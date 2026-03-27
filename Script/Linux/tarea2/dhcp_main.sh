#!/bin/bash
# ============================================================
# TAREA 2 - DHCP Server Linux
# Archivo: dhcp_main.sh
# ============================================================

source "$(dirname "$0")/dhcp_functions.sh"

verificar_root

while true; do
    echo "=========================="
    echo "  SERVIDOR DHCP - LINUX"
    echo "=========================="
    echo "1. Instalar y configurar DHCP"
    echo "2. Ver estado del servicio"
    echo "3. Ver leases activos"
    echo "4. Salir"
    echo "=========================="
    read -p "Opcion [1-4]: " OPCION

    case $OPCION in
        1) instalar_dhcp; capturar_parametros; configurar_dhcp; iniciar_servicio ;;
        2) systemctl status dhcpd --no-pager ;;
        3) cat /var/lib/dhcpd/dhcpd.leases ;;
        4) exit 0 ;;
        *) echo "Opcion invalida" ;;
    esac
done
