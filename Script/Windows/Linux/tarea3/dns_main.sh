#!/bin/bash
# ============================================================
# TAREA 3 - Script principal DNS Linux
# Archivo: dns_main.sh
# ============================================================

source "$(dirname "$0")/dns_functions.sh"

verificar_root

while true; do
    echo "=========================="
    echo "   SERVIDOR DNS - LINUX"
    echo "=========================="
    echo "1. Instalar y configurar DNS"
    echo "2. Ver estado del servicio"
    echo "3. Probar resolucion DNS"
    echo "4. Salir"
    echo "=========================="
    read -p "Opcion [1-4]: " OPCION

    case $OPCION in
        1)
            verificar_ip_estatica
            instalar_dns
            configurar_dns
            iniciar_dns
            ;;
        2) ver_estado_dns ;;
        3) probar_dns ;;
        4) exit 0 ;;
        *) echo "Opcion invalida" ;;
    esac
done
