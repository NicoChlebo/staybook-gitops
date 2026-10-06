#!/bin/bash
# Construit les 5 images StayBook et les charge dans le cluster kind (pas de registre nécessaire).
# Usage : ./build-images.sh <chemin-vers-staybook-src> [tag]   (tag par défaut : v1)
set -e
SRC=${1:?"chemin vers les sources StayBook (dossier contenant front/, gateway/, ...)"}
TAG=${2:-v1}
for s in front gateway hotels-service reservations-service rag-service; do
  echo "== build staybook-$s:$TAG"
  docker build -q -t staybook-$s:$TAG "$SRC/$s"
done
echo "== chargement dans kind (cluster argocd-tp)"
kind load docker-image --name argocd-tp \
  staybook-front:$TAG staybook-gateway:$TAG staybook-hotels-service:$TAG \
  staybook-reservations-service:$TAG staybook-rag-service:$TAG
echo "OK — images disponibles dans le cluster :"
docker exec argocd-tp-control-plane crictl images | grep staybook
