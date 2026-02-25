#!/bin/bash
# dns.sh - Automatización y gestión del servidor DNS (BIND9)
# Tarea 2 - Adaptado para AlmaLinux 8/9
# Usa: dnf (gestor de paquetes), nmcli (configuración de red)

# ---------- Cargar librerías ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/validaciones.sh"

# ---------- Variables globales ----------
server_ip=""
named_conf="/etc/named.conf"
zones_dir="/var/named"          # Directorio estándar en AlmaLinux/RHEL

# ---------- Funciones ----------

ayuda() {
    echo "Uso del script: $0"
    echo "Opciones:"
    echo -e "  ${azul}-v, --verify       ${nc}Verifica si esta instalado BIND9"
    echo -e "  ${azul}-i, --install      ${nc}Instala y configura BIND9"
    echo -e "  ${azul}-m, --monitor      ${nc}Monitorear servidor DNS"
    echo -e "  ${azul}-r, --restart      ${nc}Reiniciar servidor DNS"
    echo -e "  ${azul}-?, --help         ${nc}Muestra esta ayuda"
}

# ──────────────────────────────────────────────
# Verificar instalación de BIND9
# ──────────────────────────────────────────────
verificar_Instalacion() {
    print_info "Verificando instalación de BIND9..."

    if rpm -q bind &>/dev/null; then
        local version
        version=$(rpm -q bind --queryformat '%{VERSION}')
        print_success "BIND9 ya está instalado (versión: $version)"
        return 0
    fi

    if command -v named &>/dev/null; then
        local version
        version=$(named -v 2>&1 | head -1)
        print_success "BIND9 encontrado: $version"
        return 0
    fi

    if systemctl list-unit-files 2>/dev/null | grep -q "^named.service"; then
        print_success "Servicio named encontrado en systemd"
        return 0
    fi

    print_warning "BIND9 no está instalado"
    return 1
}

# ──────────────────────────────────────────────
# Configurar IP estática con nmcli (AlmaLinux)
# ──────────────────────────────────────────────
configurar_ip_estatica() {
    print_info "═══════════════════════════════════════"
    print_info "  Verificación de IP Estática"
    print_info "═══════════════════════════════════════"

    # Detectar interfaz activa (excluye loopback)
    local interfaz
    interfaz=$(ip route | grep default | awk '{print $5}' | head -1)

    if [[ -z "$interfaz" ]]; then
        print_warning "No se pudo detectar una interfaz de red activa"
        echo -ne "${azul}Ingrese el nombre de la interfaz (ej: eth0, ens33, enp0s3): ${nc}"
        read -r interfaz

        if ! ip link show "$interfaz" &>/dev/null; then
            print_warning "La interfaz $interfaz no existe"
            return 1
        fi
    fi

    print_success "Interfaz detectada: $interfaz"

    # Obtener nombre de la conexión en NetworkManager
    local con_name
    con_name=$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | grep ":$interfaz$" | cut -d: -f1 | head -1)

    if [[ -z "$con_name" ]]; then
        con_name="$interfaz"
    fi

    # Verificar si ya tiene IP estática configurada en NetworkManager
    local metodo
    metodo=$(nmcli -g ipv4.method con show "$con_name" 2>/dev/null)

    if [[ "$metodo" == "manual" ]]; then
        local ip_raw
        ip_raw=$(nmcli -g ipv4.addresses con show "$con_name" 2>/dev/null | cut -d/ -f1)
        server_ip="$ip_raw"
        print_success "IP estática ya configurada: $server_ip"
        print_info "Interfaz: $interfaz | Conexión NM: $con_name"

        local gw
        gw=$(nmcli -g ipv4.gateway con show "$con_name" 2>/dev/null)
        [[ -n "$gw" ]] && print_info "Gateway: $gw"

        export server_ip
        return 0
    fi

    # Está en DHCP — obtener valores actuales
    print_warning "Configuración DHCP detectada en $interfaz"

    local IP_ACTUAL
    IP_ACTUAL=$(ip addr show "$interfaz" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    local GATEWAY
    GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
    local PREFIX
    PREFIX=$(ip addr show "$interfaz" | grep "inet " | awk '{print $2}' | cut -d/ -f2)
    PREFIX="${PREFIX:-24}"

    print_info "IP actual: $IP_ACTUAL/$PREFIX"
    print_info "Gateway:   $GATEWAY"

    echo -ne "${amarillo}¿Desea configurar IP estática? [S/n]: ${nc}"
    read -r respuesta
    if [[ "$respuesta" =~ ^[Nn]$ ]]; then
        print_warning "Se mantendrá la configuración DHCP"
        print_warning "ADVERTENCIA: El servidor DNS necesita IP estática para funcionar correctamente"
        server_ip="$IP_ACTUAL"
        export server_ip
        return 0
    fi

    echo -ne "${amarillo}¿Usar la IP actual como IP fija ($IP_ACTUAL)? [S/n]: ${nc}"
    read -r respuesta

    if [[ -z "$respuesta" || "$respuesta" =~ ^[Ss]$ ]]; then
        server_ip="$IP_ACTUAL"
        GW="$GATEWAY"
    else
        echo -ne "${azul}Ingrese la IP fija deseada: ${nc}"
        read -r server_ip
        validar_IP "$server_ip" || return 1

        echo -ne "${azul}Ingrese el prefijo de red (ej: 24): ${nc}"
        read -r PREFIX
        PREFIX="${PREFIX:-24}"

        echo -ne "${azul}Ingrese el Gateway: ${nc}"
        read -r GW
        validar_IP "$GW" || return 1
    fi

    # Obtener DNS actual (si hay) para no perderlo
    local DNS
    DNS=$(nmcli -g ipv4.dns con show "$con_name" 2>/dev/null)
    [[ -z "$DNS" ]] && DNS="8.8.8.8,8.8.4.4"

    print_info "Aplicando IP estática con nmcli..."

    nmcli con mod "$con_name" \
        ipv4.method manual \
        ipv4.addresses "$server_ip/$PREFIX" \
        ipv4.gateway "$GW" \
        ipv4.dns "$DNS" &>/dev/null

    nmcli con down "$con_name" &>/dev/null
    sleep 1
    nmcli con up "$con_name" &>/dev/null
    sleep 2

    if ping -c 1 "$GW" &>/dev/null; then
        print_success "Conectividad verificada con el gateway"
    else
        print_warning "No se pudo hacer ping al gateway, verifique la configuración"
    fi

    print_success "IP estática configurada: $server_ip"
    export server_ip
}

# ──────────────────────────────────────────────
# Instalar y configurar BIND9
# ──────────────────────────────────────────────
install_bind9() {
    configurar_ip_estatica || {
        print_warning "No se pudo configurar la IP estática"
        return 1
    }

    echo ""
    print_info "--- Instalación de BIND9 ---"

    if verificar_Instalacion; then
        print_info "BIND9 ya está instalado"
        echo -ne "${amarillo}¿Desea reconfigurar el servidor DNS? [y/n]: ${nc}"
        read -r reconf
        if [[ ! "$reconf" =~ ^[Yy]$ ]]; then
            print_info "Operación cancelada"
            return 0
        fi
    else
        print_info "Instalando BIND9 y utilidades..."

        # Habilitar repositorio EPEL (necesario en algunos casos para bind-utils)
        print_info "Verificando repositorios..."
        dnf install -y epel-release &>/dev/null

        print_info "Instalando paquete bind..."
        if dnf install -y bind &>/dev/null; then
            print_success "Paquete bind instalado correctamente"
        else
            print_warning "Error al instalar bind"
            return 1
        fi

        print_info "Instalando paquete bind-utils..."
        if dnf install -y bind-utils &>/dev/null; then
            print_success "Paquete bind-utils instalado correctamente"
        else
            print_warning "Error al instalar bind-utils (no crítico)"
        fi
    fi

    # Crear directorio de zonas si no existe
    if [[ ! -d "$zones_dir" ]]; then
        mkdir -p "$zones_dir"
        chown named:named "$zones_dir"
        print_success "Directorio de zonas creado: $zones_dir"
    fi

    print_info "Generando archivo de configuración $named_conf..."

    cat > "$named_conf" <<EOF
// Archivo de configuración de BIND9
// Generado automáticamente por dns.sh
// $(date)

options {
    listen-on port 53 { any; };
    listen-on-v6 port 53 { ::1; };
    directory       "$zones_dir";
    dump-file       "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";

    allow-query     { any; };
    recursion no;
    forwarders { };
    allow-transfer  { none; };

    dnssec-validation yes;
};

logging {
    channel default_debug {
        file "data/named.run";
        severity dynamic;
    };
};

zone "." IN {
    type hint;
    file "named.ca";
};

zone "localhost.localdomain" IN {
    type master;
    file "named.localhost";
    allow-update { none; };
};

zone "localhost" IN {
    type master;
    file "named.localhost";
    allow-update { none; };
};

zone "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa" IN {
    type master;
    file "named.loopback";
    allow-update { none; };
};

zone "1.0.0.127.in-addr.arpa" IN {
    type master;
    file "named.loopback";
    allow-update { none; };
};

zone "0.in-addr.arpa" IN {
    type master;
    file "named.empty";
    allow-update { none; };
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";
EOF

    if named-checkconf "$named_conf" 2>/dev/null; then
        print_success "Archivo named.conf generado correctamente"
    else
        print_warning "Error en la sintaxis de named.conf"
        named-checkconf "$named_conf"
        return 1
    fi

    # Ajustar SELinux para named
    print_info "Configurando SELinux para named..."
    if command -v setsebool &>/dev/null; then
        setsebool -P named_write_master_zones 1 &>/dev/null
        print_success "SELinux: named_write_master_zones habilitado"
    fi

    # Restaurar contextos en el directorio de zonas
    if command -v restorecon &>/dev/null; then
        restorecon -Rv "$zones_dir" &>/dev/null
        print_success "Contextos SELinux restaurados en $zones_dir"
    fi

    print_info "Habilitando servicio named en el arranque..."
    if systemctl enable named 2>/dev/null; then
        print_success "Servicio named habilitado"
    else
        print_warning "No se pudo habilitar el servicio named"
        return 1
    fi

    print_info "Iniciando servicio named..."
    if systemctl is-active --quiet named; then
        print_info "Servicio ya estaba activo, reiniciando..."
        systemctl restart named 2>/dev/null && print_success "Servicio named reiniciado" || {
            print_warning "Error al reiniciar el servicio named"
            return 1
        }
    else
        systemctl start named 2>/dev/null && print_success "Servicio named iniciado" || {
            print_warning "Error al iniciar el servicio named"
            print_warning "Revise los logs: journalctl -u named"
            return 1
        }
    fi

    # Configurar firewall (firewalld en AlmaLinux)
    print_info "Configurando firewall para DNS (puerto 53)..."
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --add-service=dns --permanent &>/dev/null && \
            print_success "Puerto 53 abierto en firewall (permanente)" || \
            print_warning "No se pudo configurar el firewall"

        firewall-cmd --reload &>/dev/null && \
            print_success "Firewall recargado" || \
            print_warning "No se pudo recargar el firewall"
    else
        print_warning "firewalld no encontrado, configure el firewall manualmente"
        print_warning "Abra el puerto 53 TCP y UDP"
    fi

    # Estado final
    print_info "Verificando estado del servidor DNS..."
    echo ""

    systemctl is-active --quiet named && \
        print_success "Servicio named: activo y corriendo" || \
        print_warning "Servicio named: NO está corriendo"

    ss -tulnp 2>/dev/null | grep -q ":53 " && \
        print_success "Puerto 53: escuchando" || \
        print_warning "Puerto 53: NO está escuchando"

    named-checkconf "$named_conf" 2>/dev/null && \
        print_success "Configuración: sintaxis correcta" || \
        print_warning "Configuración: hay errores de sintaxis"

    echo ""
    print_success "BIND9 instalado y configurado correctamente"
    echo ""
    print_info "IP del servidor DNS: $server_ip"
    print_info "Configure su DHCP con DNS: $server_ip"
    print_info "Siguiente paso: agregar dominios con $0 --monitor"
}

# ──────────────────────────────────────────────
# Reiniciar DNS
# ──────────────────────────────────────────────
reiniciar_DNS() {
    print_info "Reiniciando servidor DNS..."

    if systemctl restart named 2>/dev/null; then
        print_success "Servidor DNS reiniciado correctamente"

        systemctl is-active --quiet named && \
            print_success "Servicio named: activo" || \
            print_warning "El servicio no quedó activo después del reinicio"
    else
        print_warning "Error al reiniciar el servidor DNS"
        print_warning "Revise los logs: journalctl -u named"
        return 1
    fi
}

# ──────────────────────────────────────────────
# Agregar dominio
# ──────────────────────────────────────────────
agregar_dominio() {
    print_menu "--- Agregar Dominio ---"

    # Detectar IP del servidor automáticamente
    local interfaz
    interfaz=$(ip route | grep default | awk '{print $5}' | head -1)
    server_ip=$(ip addr show "$interfaz" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)

    echo -ne "${amarillo}Ingrese el nombre del dominio (ej: reprobados.com): ${nc}"
    read -r nuevo_dominio

    if ! validar_Dominio "$nuevo_dominio"; then
        print_warning "Dominio inválido, cancelando operación"
        return 1
    fi

    if grep -q "zone \"$nuevo_dominio\"" "$named_conf" 2>/dev/null; then
        print_warning "El dominio $nuevo_dominio ya está configurado"
        return 1
    fi

    if [[ -n "$server_ip" ]]; then
        echo -ne "${amarillo}Ingrese la IP para $nuevo_dominio [$server_ip]: ${nc}"
    else
        echo -ne "${amarillo}Ingrese la IP para $nuevo_dominio: ${nc}"
    fi
    read -r nueva_ip

    if [[ -z "$nueva_ip" && -n "$server_ip" ]]; then
        nueva_ip="$server_ip"
    fi

    if ! validar_IP "$nueva_ip"; then
        print_warning "IP inválida, cancelando operación"
        return 1
    fi

    local zone_file="$zones_dir/${nuevo_dominio}.zone"
    local serial
    serial=$(date +%Y%m%d01)

    print_info "Creando archivo de zona: $zone_file"

    cat > "$zone_file" <<EOF
\$TTL 86400
@   IN  SOA ns1.$nuevo_dominio. admin.$nuevo_dominio. (
            $serial ; Serial
            3600        ; Refresh
            1800        ; Retry
            604800      ; Expire
            86400 )     ; Minimum TTL

; Name Server
@           IN  NS      ns1.$nuevo_dominio.

; Registros A
@           IN  A       $nueva_ip
ns1         IN  A       $nueva_ip

; Registro CNAME
www         IN  CNAME   $nuevo_dominio.
EOF

    # Ajustar propietario y contexto SELinux del archivo de zona
    chown named:named "$zone_file"
    if command -v restorecon &>/dev/null; then
        restorecon "$zone_file" &>/dev/null
    fi

    if ! named-checkzone "$nuevo_dominio" "$zone_file" &>/dev/null; then
        print_warning "Error en la sintaxis del archivo de zona"
        named-checkzone "$nuevo_dominio" "$zone_file"
        rm -f "$zone_file"
        return 1
    fi

    print_success "Archivo de zona creado correctamente"
    print_info "Agregando zona a $named_conf..."

    cat >> "$named_conf" <<EOF

zone "$nuevo_dominio" IN {
    type master;
    file "$zone_file";
    allow-update { none; };
};
EOF

    if ! named-checkconf "$named_conf" &>/dev/null; then
        print_warning "Error en la sintaxis de named.conf"
        named-checkconf "$named_conf"
        return 1
    fi

    print_success "Zona agregada a named.conf correctamente"
    print_info "Recargando servicio BIND9..."

    if systemctl reload named 2>/dev/null; then
        print_success "Servicio recargado correctamente"
    else
        print_warning "reload falló, intentando restart..."
        systemctl restart named 2>/dev/null && \
            print_success "Servicio reiniciado correctamente" || \
            print_warning "No se pudo recargar el servicio"
    fi

    echo ""
    print_success "Dominio $nuevo_dominio agregado exitosamente"
    print_info "  IP configurada:  $nueva_ip"
    print_info "  Registro A:      $nuevo_dominio → $nueva_ip"
    print_info "  Registro CNAME:  www.$nuevo_dominio → $nuevo_dominio"
    print_info "  Archivo de zona: $zone_file"
}

# ──────────────────────────────────────────────
# Eliminar dominio
# ──────────────────────────────────────────────
eliminar_dominio() {
    print_info "═══ Eliminar Dominio ═══"

    listar_dominios
    echo ""

    echo -ne "${azul}Ingrese el dominio a eliminar: ${nc}"
    read -r dominio_eliminar

    if ! grep -q "zone \"$dominio_eliminar\"" "$named_conf" 2>/dev/null; then
        print_warning "El dominio $dominio_eliminar no existe en la configuración"
        return 1
    fi

    echo ""
    echo -ne "${rojo}¿Está seguro de eliminar el dominio $dominio_eliminar? [s/N]: ${nc}"
    read -r confirmacion

    if [[ ! "$confirmacion" =~ ^[Ss]$ ]]; then
        print_info "Operación cancelada por el usuario"
        return 0
    fi

    local zone_file="$zones_dir/${dominio_eliminar}.zone"

    print_info "Eliminando entrada de named.conf..."
    sed -i "/zone \"$dominio_eliminar\"/,/^};/d" "$named_conf"

    if named-checkconf "$named_conf" 2>/dev/null; then
        print_success "Entrada eliminada de named.conf"
    else
        print_warning "Error en named.conf después de eliminar"
        return 1
    fi

    if [[ -f "$zone_file" ]]; then
        print_info "Eliminando archivo de zona: $zone_file"
        rm -f "$zone_file"
        print_success "Archivo de zona eliminado"
    else
        print_warning "Archivo de zona no encontrado: $zone_file"
    fi

    print_info "Recargando servicio BIND9..."
    if systemctl reload named 2>/dev/null; then
        print_success "Servicio recargado correctamente"
    else
        print_warning "reload falló, intentando restart..."
        systemctl restart named 2>/dev/null && \
            print_success "Servicio reiniciado correctamente" || \
            print_warning "No se pudo recargar el servicio"
    fi

    print_success "Dominio $dominio_eliminar eliminado exitosamente"
}

# ──────────────────────────────────────────────
# Listar dominios configurados
# ──────────────────────────────────────────────
listar_dominios() {
    print_info "═══ Dominios Configurados ═══"

    if [[ ! -f "$named_conf" ]]; then
        print_warning "No se encontró el archivo $named_conf"
        return 1
    fi

    local dominios
    mapfile -t dominios < <(grep "^zone " "$named_conf" | awk -F'"' '{print $2}' | \
        grep -v "localhost\|0.in-addr\|127.in-addr\|1.0.0.0\|1.0.0.127\|\.$")

    if [[ ${#dominios[@]} -eq 0 ]]; then
        print_warning "No hay dominios configurados"
        return 0
    fi

    echo ""
    printf "${azul}%-30s %-20s %-15s${nc}\n" "DOMINIO" "IP CONFIGURADA" "ESTADO"
    echo "──────────────────────────────────────────────────────────────"

    for dominio in "${dominios[@]}"; do
        local zone_file="$zones_dir/${dominio}.zone"
        local ip="N/A"
        local estado="${rojo}Sin archivo${nc}"

        if [[ -f "$zone_file" ]]; then
            ip=$(grep "^@[[:space:]]*IN[[:space:]]*A" "$zone_file" 2>/dev/null | awk '{print $NF}')
            [[ -z "$ip" ]] && ip="N/A"
            estado="${verde}Activo${nc}"
        fi

        printf "%-30s %-20s " "$dominio" "$ip"
        echo -e "$estado"
    done

    echo ""
    print_info "Total de dominios: ${#dominios[@]}"
}

# ──────────────────────────────────────────────
# Menú de monitoreo
# ──────────────────────────────────────────────
monitoreo() {
    while true; do
        echo ""
        echo -e "${cyan}"
        echo "Menú de Monitoreo DNS"
        echo -e "${nc}"
        echo -e "  ${verde}1)${nc} Agregar dominio"
        echo -e "  ${rojo}2)${nc} Eliminar dominio"
        echo -e "  ${azul}3)${nc} Listar dominios"
        echo -e "  ${amarillo}0)${nc} Salir"
        echo ""
        echo -ne "Opcion: "
        read -r opcion

        case $opcion in
            1) agregar_dominio ;;
            2) eliminar_dominio ;;
            3) listar_dominios ;;
            0)
                print_info "Saliendo del menú de monitoreo"
                break
                ;;
            *)
                print_warning "Opcion inválida: $opcion"
                ;;
        esac
    done
}

# ---------- Main ----------
case $1 in
    -v | --verify)  verificar_Instalacion ;;
    -i | --install) install_bind9 ;;
    -m | --monitor) monitoreo ;;
    -r | --restart) reiniciar_DNS ;;
    -? | --help)    ayuda ;;
    *)              ayuda ;;
esac