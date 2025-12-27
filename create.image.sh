#!/bin/bash

docker build -t "rafaelrpsantos/megsi-iti-autoscale:latest" .

docker login

docker push rafaelrpsantos/megsi-iti-autoscale:latest

docker rmi -f rafaelrpsantos/megsi-iti-autoscale