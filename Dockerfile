FROM alpine:3.19

RUN apk add --no-cache docker-cli curl jq bc util-linux

WORKDIR /autoscale

COPY autoscale.sh .
RUN chmod +x autoscale.sh

CMD ["./autoscale.sh"]