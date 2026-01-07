#!/bin/sh

LOCK="/tmp/autoscaler.lock"
exec 9>$LOCK || exit 1
flock -n 9 || exit 0

SERVICE="megsi-iti-service-files"
IMAGE="rafaelrpsantos/megsi-iti-service-files:latest"

APP_NETWORK="megsi-net"
PROXY_NETWORK="traefik-net"

MIN=${MIN:-1}
MAX=${MAX:-2}

CPU_UP=${CPU_UP:-70}
CPU_DOWN=${CPU_DOWN:-30}

RPS_UP=${RPS_UP:-20}
RPS_DOWN=${RPS_DOWN:-5}

SLEEP=${SLEEP:-15}

PROM_URL=${PROM_URL:-"http://prometheus:9090/api/v1/query"}
CONFIG_SERVER_URL="http://megsi-config-server-fs:8888/actuator/health"

echo "[autoscaler] config: MIN=$MIN MAX=$MAX CPU_UP=$CPU_UP CPU_DOWN=$CPU_DOWN RPS_UP=$RPS_UP RPS_DOWN=$RPS_DOWN SLEEP=$SLEEP"

ENV_VARS="
-e SPRING_CLOUD_CONFIG_URI=http://megsi-config-server:8888
-e MARIADB_SERVER_URI=mariadb
-e MYSQL_ROOT_PASSWORD=uminho
-e KAFKA_SERVER_URI=kafka:29092
"

VOLUMES="
-v /mnt/NAS:/mnt/NAS
"

TRAEFIK_LABELS="
--label traefik.enable=true
--label traefik.http.routers.files.rule=Host(\`files.localhost\`)
--label traefik.http.routers.files.entrypoints=web
--label traefik.http.services.files.loadbalancer.server.port=8081
"

config_server_ready() {
  STATUS=$(wget -q --server-response --spider "$CONFIG_SERVER_URL" 2>&1 \
    | awk '/HTTP\/[0-9.]+/ {print $2}' | tail -n 1)

  [ "$STATUS" = "200" ]
}

while true; do
  if ! config_server_ready; then
    echo "[autoscaler] aguardando megsi-config-server-fs (health != 200)"
    sleep "$SLEEP"
    continue
  fi

  CURRENT=$(docker ps \
    --filter "name=${SERVICE}-" \
    --format "{{.Names}}" | wc -l)

  if [ "$CURRENT" -lt "$MIN" ]; then
    echo "[autoscaler] bootstrap -> criando instância inicial"

    LAST=$(docker ps --filter "name=${SERVICE}-" --format "{{.Names}}" \
      | sed "s/${SERVICE}-//" | sort -n | tail -n 1)

    [ -z "$LAST" ] && LAST=0
    NEXT=$((LAST + 1))

    docker run -d \
      --name "${SERVICE}-${NEXT}" \
      --network "$APP_NETWORK" \
      --network "$PROXY_NETWORK" \
      $TRAEFIK_LABELS \
      $ENV_VARS \
      $VOLUMES \
      "$IMAGE"

    sleep "$SLEEP"
    continue
  fi

  CPU=$(wget -qO- \
    "$PROM_URL?query=avg(rate(container_cpu_usage_seconds_total{container=~\"${SERVICE}.*\"}[30s]))*100" \
    | jq -r '.data.result[0].value[1] // 0')

  RPS=$(wget -qO- \
    "$PROM_URL?query=sum(rate(traefik_service_requests_total{service=\"files@docker\"}[30s]))" \
    | jq -r '.data.result[0].value[1] // 0')

  echo "[autoscaler] cpu=${CPU}% rps=${RPS} replicas=${CURRENT}"

  if { [ "$(echo "$CPU > $CPU_UP" | bc)" -eq 1 ] || \
       [ "$(echo "$RPS > $RPS_UP" | bc)" -eq 1 ]; } && \
       [ "$CURRENT" -lt "$MAX" ]; then

    LAST=$(docker ps --filter "name=${SERVICE}-" --format "{{.Names}}" \
      | sed "s/${SERVICE}-//" | sort -n | tail -n 1)

    [ -z "$LAST" ] && LAST=0
    NEXT=$((LAST + 1))

    echo "[autoscaler] scale UP -> ${SERVICE}-${NEXT}"

    docker run -d \
      --name "${SERVICE}-${NEXT}" \
      --network "$APP_NETWORK" \
      --network "$PROXY_NETWORK" \
      $TRAEFIK_LABELS \
      $ENV_VARS \
      $VOLUMES \
      "$IMAGE"
  fi

  if [ "$(echo "$CPU < $CPU_DOWN" | bc)" -eq 1 ] && \
     [ "$(echo "$RPS < $RPS_DOWN" | bc)" -eq 1 ] && \
     [ "$CURRENT" -gt "$MIN" ]; then

    TARGET=$(docker ps --filter "name=${SERVICE}-" --format "{{.Names}}" \
      | sort | tail -n 1)

    echo "[autoscaler] scale DOWN -> removendo ${TARGET}"
    docker rm -f "$TARGET"
  fi

  sleep "$SLEEP"
done
