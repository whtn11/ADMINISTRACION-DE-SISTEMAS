#!/bin/bash
# Practica 8 - Cliente Linux (AlmaLinux / RHEL)
# Une el equipo al dominio empresa.local mediante realmd/sssd/adcli

set -euo pipefail

DOMINIO="empresa.local"
IP_SERVIDOR="192.168.10.10"
ADMIN_USER="Administrador"

ok()   { echo -e "\e[32m[OK]   $1\e[0m"; }
info() { echo -e "\e[36m[INFO] $1\e[0m"; }
warn() { echo -e "\e[33m[WARN] $1\e[0m"; }
err()  { echo -e "\e[31m[ERR]  $1\e[0m"; }

if [[ $EUID -ne 0 ]]; then
    err "Ejecuta como root: sudo ./practica8_cliente_linux.sh"
    exit 1
fi


# -----------------------------------------------
# 1. CONFIGURAR RED
# -----------------------------------------------
configurar_red() {
    info "Interfaces de red disponibles:"
    IFACES=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo))

    for i in "${!IFACES[@]}"; do
        IP_ACTUAL=$(ip -4 addr show "${IFACES[$i]}" 2>/dev/null | grep -oP '(?<=inet )\S+' || echo "sin IP")
        echo "  [$((i+1))] ${IFACES[$i]}  -  $IP_ACTUAL"
    done

    read -rp "Selecciona interfaz de red interna [1]: " SEL
    SEL=${SEL:-1}
    IFACE="${IFACES[$((SEL-1))]}"

    read -rp "IP estatica para este cliente [192.168.10.202]: " IP_CLIENTE
    IP_CLIENTE=${IP_CLIENTE:-192.168.10.202}

    info "Configurando $IFACE con IP $IP_CLIENTE via NetworkManager..."

    CON=$(nmcli -t -f NAME,DEVICE con show | grep "$IFACE" | cut -d: -f1 | head -1)

    if [[ -n "$CON" ]]; then
        nmcli con mod "$CON" \
            ipv4.addresses "$IP_CLIENTE/24" \
            ipv4.gateway "192.168.10.1" \
            ipv4.dns "$IP_SERVIDOR" \
            ipv4.method manual
        nmcli con up "$CON"
    else
        nmcli con add type ethernet ifname "$IFACE" con-name "red-dominio" \
            ipv4.addresses "$IP_CLIENTE/24" \
            ipv4.gateway "192.168.10.1" \
            ipv4.dns "$IP_SERVIDOR" \
            ipv4.method manual
        nmcli con up "red-dominio"
    fi

    ok "Red configurada: $IP_CLIENTE | Gateway: 192.168.10.1 | DNS: $IP_SERVIDOR"
}


# -----------------------------------------------
# 2. PROBAR CONECTIVIDAD
# -----------------------------------------------
probar_conectividad() {
    info "Probando conectividad con el servidor ($IP_SERVIDOR)..."
    if ping -c 2 -W 2 "$IP_SERVIDOR" &>/dev/null; then
        ok "Servidor alcanzable."
    else
        err "No se puede alcanzar el servidor en $IP_SERVIDOR."
        exit 1
    fi

    info "Verificando resolucion DNS de $DOMINIO..."
    if host "$DOMINIO" "$IP_SERVIDOR" &>/dev/null; then
        ok "DNS resuelve $DOMINIO correctamente."
    else
        err "No se pudo resolver $DOMINIO. Verifica el servidor DNS."
        exit 1
    fi
}


# -----------------------------------------------
# 3. INSTALAR PAQUETES (AlmaLinux / RHEL)
# -----------------------------------------------
instalar_paquetes() {
    info "Instalando paquetes necesarios..."
    dnf install -y \
        realmd \
        sssd \
        sssd-ad \
        sssd-tools \
        adcli \
        samba-common \
        samba-common-tools \
        oddjob \
        oddjob-mkhomedir \
        krb5-workstation \
        openldap-clients \
        policycoreutils-python-utils

    ok "Paquetes instalados."
}


# -----------------------------------------------
# 4. UNIRSE AL DOMINIO
# -----------------------------------------------
unir_dominio() {
    info "Descubriendo dominio $DOMINIO..."
    if ! realm discover "$DOMINIO"; then
        err "No se pudo descubrir el dominio."
        exit 1
    fi

    echo ""
    info "Uniendo equipo al dominio con el usuario $ADMIN_USER..."
    info "Se pedira la contrasena de $ADMIN_USER"
    echo ""

    realm join -U "$ADMIN_USER" "$DOMINIO"
    ok "Equipo unido al dominio $DOMINIO."
}


# -----------------------------------------------
# 5. CONFIGURAR SSSD
# -----------------------------------------------
configurar_sssd() {
    info "Configurando sssd.conf..."

    cat > /etc/sssd/sssd.conf <<EOF
[sssd]
domains = ${DOMINIO}
config_file_version = 2
services = nss, pam

[domain/${DOMINIO}]
default_shell = /bin/bash
krb5_store_password_if_offline = True
cache_credentials = True
krb5_realm = $(echo "$DOMINIO" | tr '[:lower:]' '[:upper:]')
realmd_tags = manages-system joined-with-adcli
id_provider = ad
fallback_homedir = /home/%u@%d
ad_domain = ${DOMINIO}
use_fully_qualified_names = False
ldap_id_mapping = True
access_provider = ad
EOF

    chmod 600 /etc/sssd/sssd.conf
    systemctl restart sssd
    systemctl enable sssd
    ok "sssd configurado y habilitado."
}


# -----------------------------------------------
# 6. HABILITAR HOME AUTOMATICO + SUDO
# -----------------------------------------------
configurar_home() {
    info "Habilitando creacion automatica de home (authselect)..."
    authselect select sssd with-mkhomedir --force
    systemctl enable --now oddjobd
    ok "mkhomedir habilitado."
}

configurar_sudo() {
    info "Configurando sudo para $ADMIN_USER..."

    cat > /etc/sudoers.d/ad-admins <<EOF
# Permisos sudo para administrador del dominio ${DOMINIO}
${ADMIN_USER}@${DOMINIO} ALL=(ALL) ALL
${ADMIN_USER}            ALL=(ALL) ALL
EOF

    chmod 440 /etc/sudoers.d/ad-admins
    ok "sudo configurado en /etc/sudoers.d/ad-admins"
}


# -----------------------------------------------
# 7. VERIFICAR
# -----------------------------------------------
verificar() {
    echo ""
    echo "--- VERIFICACION ---"

    if realm list | grep -q "$DOMINIO"; then
        ok "Dominio activo: $DOMINIO"
        realm list
    else
        err "El equipo NO esta unido al dominio."
    fi

    echo ""
    info "Probando resolucion de usuario AD ($ADMIN_USER)..."
    if id "$ADMIN_USER" &>/dev/null; then
        ok "Usuario $ADMIN_USER resuelto:"
        id "$ADMIN_USER"
    else
        warn "No se pudo resolver $ADMIN_USER. Puede tardar unos segundos."
    fi

    echo "--- FIN VERIFICACION ---"
}


# -----------------------------------------------
# SALIR DEL DOMINIO
# -----------------------------------------------
salir_dominio() {
    if ! realm list | grep -q "$DOMINIO"; then
        warn "Este equipo no esta unido al dominio $DOMINIO."
        return
    fi
    info "Saliendo del dominio $DOMINIO..."
    realm leave "$DOMINIO"
    ok "Salido del dominio correctamente."
}


# -----------------------------------------------
# MENU
# -----------------------------------------------
menu() {
    while true; do
        clear
        echo "========================================"
        echo "   Practica 8 - Cliente Linux           "
        echo "   AlmaLinux | Dominio: $DOMINIO        "
        echo "========================================"
        echo "  [1] Configurar red"
        echo "  [2] Probar conectividad"
        echo "  [3] Instalar paquetes"
        echo "  [4] Unirse al dominio"
        echo "  [5] Configurar sssd"
        echo "  [6] Habilitar home automatico + sudo"
        echo "  [7] Verificar union al dominio"
        echo "  [8] Todo en uno"
        echo "  [9] Salir del dominio"
        echo "  [0] Salir"
        echo "========================================"
        read -rp "Selecciona una opcion: " OP

        case "$OP" in
            1) configurar_red ;;
            2) probar_conectividad ;;
            3) instalar_paquetes ;;
            4) unir_dominio ;;
            5) configurar_sssd ;;
            6) configurar_home; configurar_sudo ;;
            7) verificar ;;
            8)
                configurar_red
                probar_conectividad
                instalar_paquetes
                unir_dominio
                configurar_sssd
                configurar_home
                configurar_sudo
                verificar
                ;;
            9) salir_dominio ;;
            0) echo "Saliendo..."; exit 0 ;;
            *) warn "Opcion no valida." ;;
        esac

        echo ""
        read -rp "Enter para continuar..."
    done
}

menu
