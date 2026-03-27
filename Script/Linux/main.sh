#!/bin/bash
# ============================================================
# TAREA 4 - Menú Principal / SSH
# Archivo: main.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function verificar_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Ejecuta el script como root (sudo)"
        exit 1
    fi
}

function instalar_ssh() {
    if rpm -q openssh-server &>/dev/null; then
        echo "OpenSSH ya esta instalado."
    else
        echo "Instalando OpenSSH..."
        dnf install -y openssh-server
        echo "Instalacion completada."
    fi
    systemctl enable sshd
    systemctl start sshd
    systemctl is-active --quiet sshd && echo "Servicio SSH activo." || echo "Error al iniciar SSH."
    firewall-cmd --add-service=ssh --permanent &>/dev/null
    firewall-cmd --reload &>/dev/null
    echo "Puerto 22 abierto en firewall."
    echo "Conexion: ssh $(whoami)@$(hostname -I | awk '{print $1}')"
}

function ver_estado_ssh() {
    systemctl status sshd --no-pager
}

while true; do
    echo "=========================="
    echo "    MENU PRINCIPAL"
    echo "=========================="
    echo "1. Instalar/verificar SSH"
    echo "2. Estado de SSH"
    echo "3. Menu DHCP (Tarea 2)"
    echo "4. Menu DNS (Tarea 3)"
    echo "5. Diagnostico del sistema (Tarea 1)"
    echo "6. Salir"
    echo "=========================="
    read -p "Opcion [1-6]: " OPCION

    case $OPCION in
        1) verificar_root; instalar_ssh ;;
        2) ver_estado_ssh ;;
        3) bash "$SCRIPT_DIR/tarea2/dhcp_main.sh" ;;
        4) bash "$SCRIPT_DIR/tarea3/dns_main.sh" ;;
        5) bash "$SCRIPT_DIR/tarea1/tarea1_main.sh" ;;
        6) exit 0 ;;
        *) echo "Opcion invalida" ;;
    esac
done
