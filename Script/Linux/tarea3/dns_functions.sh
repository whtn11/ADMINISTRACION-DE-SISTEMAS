#!/bin/bash
# ============================================================
# TAREA 3 - Funciones DNS Linux (BIND9)
# Archivo: dns_functions.sh
# ============================================================

NAMED_CONF="/etc/named.conf"
ZONES_DIR="/var/named"

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

function verificar_ip_estatica() {
    local METODO
    METODO=$(nmcli -g ipv4.method con show enp0s8 2>/dev/null)
    if [[ "$METODO" == "manual" ]]; then
        echo "IP estatica ya configurada."
    else
        echo "No tiene IP estatica. Configurando..."
        read -p "IP estatica: " IP
        read -p "Mascara (ej: 24): " PREFIX
        read -p "Gateway: " GW
        nmcli con mod enp0s8 ipv4.method manual ipv4.addresses "$IP/$PREFIX" ipv4.gateway "$GW"
        nmcli con up enp0s8
        echo "IP estatica configurada: $IP"
    fi
}

function instalar_dns() {
    if rpm -q bind &>/dev/null; then
        echo "BIND9 ya esta instalado."
    else
        echo "Instalando BIND9..."
        dnf install -y bind bind-utils
        echo "Instalacion completada."
    fi
}

function configurar_dns() {
    read -p "Dominio (ej: reprobados.com): " DOMINIO
    while true; do
        read -p "IP para el dominio: " IP_DOMINIO
        validar_ip "$IP_DOMINIO" && break
        echo "IP invalida."
    done

    local ZONE_FILE="$ZONES_DIR/${DOMINIO}.zone"
    local SERIAL
    SERIAL=$(date +%Y%m%d01)

    cat > "$NAMED_CONF" <<EOF
options {
    listen-on port 53 { any; };
    directory "$ZONES_DIR";
    allow-query { any; };
    recursion no;
    dnssec-validation yes;
};

zone "$DOMINIO" IN {
    type master;
    file "$ZONE_FILE";
    allow-update { none; };
};
EOF

    cat > "$ZONE_FILE" <<EOF
\$TTL 86400
@   IN  SOA ns1.$DOMINIO. admin.$DOMINIO. (
            $SERIAL
            3600
            1800
            604800
            86400 )

@       IN  NS      ns1.$DOMINIO.
@       IN  A       $IP_DOMINIO
ns1     IN  A       $IP_DOMINIO
www     IN  CNAME   $DOMINIO.
EOF

    chown named:named "$ZONE_FILE"

    echo "Validando configuracion..."
    named-checkconf "$NAMED_CONF" && echo "named.conf correcto." || { echo "Error en named.conf"; return 1; }
    named-checkzone "$DOMINIO" "$ZONE_FILE" && echo "Zona correcta." || { echo "Error en zona"; return 1; }
}

function iniciar_dns() {
    systemctl enable named
    systemctl restart named
    systemctl is-active --quiet named && echo "Servicio DNS activo." || echo "Error al iniciar el servicio."

    firewall-cmd --add-service=dns --permanent &>/dev/null
    firewall-cmd --reload &>/dev/null
    echo "Puerto 53 abierto en firewall."
}

function ver_estado_dns() {
    systemctl status named --no-pager
}

function probar_dns() {
    read -p "Dominio a resolver: " DOMINIO
    echo "--- nslookup ---"
    nslookup "$DOMINIO" 127.0.0.1
    echo "--- ping ---"
    ping -c 2 "$DOMINIO"
}
