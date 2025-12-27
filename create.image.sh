#!/bin/bash


PREFIX="megsi-iti-service-files"
CONTAINERS=$(sudo docker ps -a --filter "name=^/${PREFIX}" -q)
if [ -z "$CONTAINERS" ]; then
  echo "Nenhum container encontrado com o prefixo '$PREFIX'."
  exit 0
fi
sudo docker stop $CONTAINERS
sudo docker rm $CONTAINERS

sudo docker rmi rafaelrpsantos/megsi-iti-autoscaler:latest
sudo docker build -t "rafaelrpsantos/megsi-iti-autoscaler:latest" .