#!/bin/bash
# ============================================================
# TAREA 2 - Funciones DHCP Linux
# Archivo: dhcp_functions.sh
# ============================================================

function verificar_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Ejecuta el script como root (sudo)"
        exit 1
    fi
}

function validar_ip() {
    local IP=$1
    local REGEX='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    if [[ $IP =~ $REGEX ]]; then
        IFS='.' read -r -a OCT <<< "$IP"
        for O in "${OCT[@]}"; do
            [[ $O -gt 255 ]] && return 1
        done
        return 0
    fi
    return 1
}

function instalar_dhcp() {
    if rpm -q dhcp-server &>/dev/null; then
        echo "dhcp-server ya esta instalado."
    else
        echo "Instalando dhcp-server..."
        dnf install -y dhcp-server
        echo "Instalacion completada."
    fi
}

function capturar_parametros() {
    echo "--- Configuracion del Scope ---"

    while true; do
        read -p "Nombre del scope: " SCOPE_NOMBRE
        [[ -n "$SCOPE_NOMBRE" ]] && break
        echo "El nombre no puede estar vacio."
    done

    while true; do
        read -p "Red (ej: 192.168.100.0): " SCOPE_RED
        validar_ip "$SCOPE_RED" && break
        echo "IP invalida, intente de nuevo."
    done

    while true; do
        read -p "Mascara (ej: 255.255.255.0): " SCOPE_MASCARA
        validar_ip "$SCOPE_MASCARA" && break
        echo "Mascara invalida."
    done

    while true; do
        read -p "IP inicio del rango: " RANGO_INICIO
        validar_ip "$RANGO_INICIO" && break
        echo "IP invalida."
    done

    while true; do
        read -p "IP fin del rango: " RANGO_FIN
        validar_ip "$RANGO_FIN" && break
        echo "IP invalida."
    done

    while true; do
        read -p "Gateway: " GATEWAY
        validar_ip "$GATEWAY" && break
        echo "IP invalida."
    done

    while true; do
        read -p "DNS: " DNS
        validar_ip "$DNS" && break
        echo "IP invalida."
    done

    while true; do
        read -p "Lease time en segundos (ej: 86400): " LEASE_TIME
        [[ "$LEASE_TIME" =~ ^[0-9]+$ && "$LEASE_TIME" -gt 0 ]] && break
        echo "Ingresa un numero valido."
    done

    export SCOPE_NOMBRE SCOPE_RED SCOPE_MASCARA RANGO_INICIO RANGO_FIN GATEWAY DNS LEASE_TIME
}

function configurar_dhcp() {
    echo "Generando configuracion DHCP..."

    cat > /etc/dhcp/dhcpd.conf <<EOF
default-lease-time $LEASE_TIME;
max-lease-time $LEASE_TIME;
authoritative;

subnet $SCOPE_RED netmask $SCOPE_MASCARA {
    range $RANGO_INICIO $RANGO_FIN;
    option routers $GATEWAY;
    option domain-name-servers $DNS;
    option subnet-mask $SCOPE_MASCARA;
}
EOF

    echo "Validando sintaxis..."
    dhcpd -t -cf /etc/dhcp/dhcpd.conf && echo "Sintaxis correcta." || { echo "Error de sintaxis."; exit 1; }
}

function iniciar_servicio() {
    systemctl enable dhcpd
    systemctl restart dhcpd
    systemctl is-active --quiet dhcpd && echo "Servicio DHCP activo." || echo "Error al iniciar el servicio."
}
