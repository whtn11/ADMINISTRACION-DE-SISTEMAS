#!/bin/bash

NETWORK_NAME="infra_red"
NETWORK_SUBNET="172.20.0.0/16"
WEB_IMAGE="web_apache"
WEB_CONTAINER="contenedor_web"
DB_CONTAINER="contenedor_db"
FTP_CONTAINER="contenedor_ftp"
WEB_VOLUME="web_content"
DB_VOLUME="db_data"

crear_red() {
    docker network create --driver bridge --subnet "$NETWORK_SUBNET" "$NETWORK_NAME"
}

crear_volumenes() {
    docker volume create "$WEB_VOLUME"
    docker volume create "$DB_VOLUME"
}

construir_web() {
    docker build -t "$WEB_IMAGE" ./web
}

iniciar_web() {
    docker run -d \
        --name "$WEB_CONTAINER" \
        --network "$NETWORK_NAME" \
        --memory="512m" \
        --cpus="0.5" \
        -v "${WEB_VOLUME}:/usr/local/apache2/htdocs" \
        -p 8080:80 \
        "$WEB_IMAGE"
}

iniciar_db() {
    docker run -d \
        --name "$DB_CONTAINER" \
        --network "$NETWORK_NAME" \
        --memory="512m" \
        --cpus="0.5" \
        -v "${DB_VOLUME}:/var/lib/postgresql" \
        -e POSTGRES_PASSWORD=admin123 \
        -e POSTGRES_DB=practica10 \
        postgres:alpine
}

iniciar_ftp() {
    docker run -d \
        --name "$FTP_CONTAINER" \
        --network "$NETWORK_NAME" \
        --memory="256m" \
        --cpus="0.25" \
        -v "${WEB_VOLUME}:/home/vsftpd/webuser" \
        -p 21:21 \
        -p 21100-21110:21100-21110 \
        -e FTP_USER=webuser \
        -e FTP_PASS=ftp123 \
        -e PASV_MIN_PORT=21100 \
        -e PASV_MAX_PORT=21110 \
        -e PASV_ADDRESS=172.16.0.220 \
        bogem/ftp
}

respaldo_db() {
    mkdir -p ./backups
    docker exec "$DB_CONTAINER" pg_dump -U postgres practica10 > ./backups/backup_$(date +%F).sql
}
