#!/bin/bash
# ssh.sh - Automatización y gestión del servidor SSH (OpenSSH)
# Tarea 4 - Adaptado para AlmaLinux 8/9
# Requiere ejecutarse como root o con sudo

# ---------- Cargar librerías ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/validaciones.sh"

# ---------- Verificar root ----------
verificar_root() {
    if [[ "$EUID" -ne 0 ]]; then
        print_warning "Este script debe ejecutarse como root o con sudo."
        print_info    "Ejecuta: sudo $0 $*"
        exit 1
    fi
}

# ---------- Funciones ----------

ayuda() {
    echo "Uso del script: $0 [opcion]"
    echo "Opciones:"
    echo -e "  ${azul}-v, --verify       ${nc}Verifica si esta instalado SSH"
    echo -e "  ${azul}-i, --install      ${nc}Instala y configura SSH"
    echo -e "  ${azul}-r, --restart      ${nc}Reiniciar servidor SSH"
    echo -e "  ${azul}-s, --status       ${nc}Verificar estado del servidor SSH"
    echo -e "  ${azul}-?, --help         ${nc}Muestra esta ayuda"
}

# ──────────────────────────────────────────────
# Verificar instalación de OpenSSH
# ──────────────────────────────────────────────
verificar_Instalacion() {
    print_info "Verificando instalación de SSH..."

    if rpm -q openssh-server &>/dev/null; then
        local version
        version=$(rpm -q openssh-server --queryformat '%{VERSION}')
        print_success "SSH ya está instalado (versión: $version)"
        return 0
    fi

    if command -v sshd &>/dev/null; then
        local version
        version=$(sshd -V 2>&1 | head -1)
        print_success "SSH encontrado: $version"
        return 0
    fi

    print_warning "SSH no está instalado"
    return 1
}

# ──────────────────────────────────────────────
# Instalar y configurar SSH
# ──────────────────────────────────────────────
instalar_SSH() {
    print_menu "=== Instalación y Configuración de SSH ==="
    echo ""

    # 1. Verificar si ya está instalado
    if verificar_Instalacion; then
        echo -ne "${amarillo}¿Desea reconfigurar el servidor SSH? [s/N]: ${nc}"
        read -r reconf
        if [[ ! "$reconf" =~ ^[Ss]$ ]]; then
            print_info "Operación cancelada"
            return 0
        fi
    else
        print_info "Instalando OpenSSH Server..."

        if dnf install -y openssh-server &>/dev/null; then
            print_success "SSH instalado correctamente"
        else
            print_warning "Error en la instalación de SSH"
            return 1
        fi
    fi

    echo ""

    # 2. Habilitar e iniciar el servicio
    print_info "Habilitando servicio SSH en el arranque..."
    if systemctl enable sshd &>/dev/null; then
        print_success "Servicio sshd configurado para arranque automático"
    else
        print_warning "No se pudo habilitar el servicio sshd"
        return 1
    fi

    print_info "Iniciando servicio SSH..."
    if systemctl is-active --quiet sshd; then
        print_info "Servicio ya estaba activo, reiniciando..."
        if systemctl restart sshd &>/dev/null; then
            print_success "Servicio sshd reiniciado"
        else
            print_warning "Error al reiniciar el servicio sshd"
            return 1
        fi
    else
        if systemctl start sshd &>/dev/null; then
            print_success "Servicio sshd iniciado"
        else
            print_warning "Error al iniciar el servicio sshd"
            print_warning "Revise los logs: journalctl -u sshd"
            return 1
        fi
    fi

    # 3. Obtener el puerto configurado
    local ssh_conf="/etc/ssh/sshd_config"
    local puerto=22

    if [[ -f "$ssh_conf" ]]; then
        local linea_puerto
        linea_puerto=$(grep -E "^Port\s+[0-9]+" "$ssh_conf" | head -1 | awk '{print $2}')
        [[ -n "$linea_puerto" ]] && puerto="$linea_puerto"
    fi

    print_info "Puerto SSH configurado: $puerto"

    # 4. Configurar SELinux si el puerto no es el 22
    if [[ "$puerto" -ne 22 ]]; then
        print_info "Puerto no estándar detectado, configurando SELinux..."
        if command -v semanage &>/dev/null; then
            semanage port -a -t ssh_port_t -p tcp "$puerto" &>/dev/null || \
            semanage port -m -t ssh_port_t -p tcp "$puerto" &>/dev/null
            print_success "Puerto $puerto habilitado en SELinux"
        else
            print_warning "semanage no encontrado"
            print_warning "Instala: dnf install policycoreutils-python-utils"
        fi
    fi

    # 5. Abrir puerto en firewalld
    print_info "Configurando firewall para SSH (puerto $puerto)..."

    if command -v firewall-cmd &>/dev/null; then
        if [[ "$puerto" -eq 22 ]]; then
            if firewall-cmd --query-service=ssh --permanent &>/dev/null; then
                print_success "Regla SSH ya existe en el firewall"
            else
                firewall-cmd --add-service=ssh --permanent &>/dev/null && \
                    print_success "Servicio SSH habilitado en el firewall" || \
                    print_warning "No se pudo configurar el firewall"
            fi
        else
            if firewall-cmd --query-port="$puerto/tcp" --permanent &>/dev/null; then
                print_success "Puerto $puerto/TCP ya está abierto en el firewall"
            else
                firewall-cmd --add-port="$puerto/tcp" --permanent &>/dev/null && \
                    print_success "Puerto $puerto/TCP abierto en el firewall" || \
                    print_warning "No se pudo abrir el puerto $puerto en el firewall"
            fi
        fi

        firewall-cmd --reload &>/dev/null && \
            print_success "Firewall recargado" || \
            print_warning "No se pudo recargar el firewall"
    else
        print_warning "firewalld no encontrado, configure el firewall manualmente"
        print_warning "Abra el puerto $puerto/TCP"
    fi

    # 6. Verificación final
    echo ""
    print_info "Verificando estado del servidor SSH..."
    echo ""

    systemctl is-active --quiet sshd && \
        print_success "Servicio sshd: activo y corriendo" || \
        print_warning "Servicio sshd: NO está corriendo"

    ss -tulnp 2>/dev/null | grep -q ":$puerto " && \
        print_success "Puerto $puerto: escuchando" || \
        print_warning "Puerto $puerto: NO está escuchando"

    # 7. Resumen final
    local interfaz
    interfaz=$(ip route | grep default | awk '{print $5}' | head -1)
    local ip
    ip=$(ip addr show "$interfaz" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)

    echo ""
    print_success "======================================"
    print_success "  SSH listo para conexiones remotas"
    print_success "======================================"
    print_info    "  IP del servidor : $ip"
    print_info    "  Puerto          : $puerto"
    print_info    "  Comando SSH     : ssh usuario@$ip -p $puerto"
    print_success "======================================"
}

# ──────────────────────────────────────────────
# Reiniciar SSH
# ──────────────────────────────────────────────
reiniciar_SSH() {
    print_info "Reiniciando servidor SSH..."

    if ! systemctl list-unit-files 2>/dev/null | grep -q "^sshd.service"; then
        print_warning "El servicio sshd no existe. Instale SSH primero con --install"
        return 1
    fi

    if ! systemctl is-active --quiet sshd; then
        print_warning "El servicio SSH no está activo"
        echo -ne "${amarillo}¿Desea iniciarlo en lugar de reiniciarlo? [s/N]: ${nc}"
        read -r opc
        if [[ "$opc" =~ ^[Ss]$ ]]; then
            systemctl start sshd
        else
            return 0
        fi
    else
        systemctl restart sshd
    fi

    if systemctl is-active --quiet sshd; then
        print_success "Servidor SSH reiniciado correctamente"
        echo ""
        systemctl status sshd --no-pager -l
    else
        print_warning "Error al reiniciar el servidor SSH"
        print_info    "Revise los logs: journalctl -u sshd"
    fi
}

# ──────────────────────────────────────────────
# Ver estado del servidor SSH
# ──────────────────────────────────────────────
ver_Estado() {
    print_menu "=== ESTADO DEL SERVIDOR SSH ==="

    if ! systemctl list-unit-files 2>/dev/null | grep -q "^sshd.service"; then
        print_warning "El servicio sshd no existe. SSH no está instalado."
        return 1
    fi

    echo ""
    systemctl status sshd --no-pager -l
    echo ""

    local tipo_inicio
    tipo_inicio=$(systemctl is-enabled sshd 2>/dev/null)
    print_info "Tipo de inicio: $tipo_inicio"

    # Leer puerto desde sshd_config
    local ssh_conf="/etc/ssh/sshd_config"
    local puerto=22
    if [[ -f "$ssh_conf" ]]; then
        local linea_puerto
        linea_puerto=$(grep -E "^Port\s+[0-9]+" "$ssh_conf" | head -1 | awk '{print $2}')
        [[ -n "$linea_puerto" ]] && puerto="$linea_puerto"
    fi

    # Detectar IP
    local interfaz
    interfaz=$(ip route | grep default | awk '{print $5}' | head -1)
    local ip
    ip=$(ip addr show "$interfaz" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)

    print_info "IP del servidor : $ip"
    print_info "Puerto          : $puerto"
}

# ---------- Main ----------
verificar_root "$@"

case $1 in
    -v | --verify)  verificar_Instalacion ;;
    -i | --install) instalar_SSH ;;
    -r | --restart) reiniciar_SSH ;;
    -s | --status)  ver_Estado ;;
    -? | --help)    ayuda ;;
    *)              ayuda ;;
esac