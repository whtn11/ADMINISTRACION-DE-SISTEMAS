#!/bin/bash

source ./docker_functions.sh

echo "=== Práctica 10 - Despliegue de contenedores ==="

echo "[1/5] Creando red infra_red..."
crear_red

echo "[2/5] Creando volúmenes..."
crear_volumenes

echo "[3/5] Construyendo imagen web Apache..."
construir_web

echo "[4/5] Iniciando contenedores..."
iniciar_web
iniciar_db
iniciar_ftp

echo "[5/5] Listo. Contenedores corriendo:"
docker ps

