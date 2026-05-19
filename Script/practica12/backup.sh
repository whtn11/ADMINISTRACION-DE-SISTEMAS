#!/bin/bash
mkdir -p ./backups
docker exec mailserver tar -czf - /var/mail > ./backups/mail_backup_$(date +%F).tar.gz
echo "Respaldo creado: ./backups/mail_backup_$(date +%F).tar.gz"
