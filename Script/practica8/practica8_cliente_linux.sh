#!/bin/bash
# Practica 8 — Cliente Linux
# Une el equipo al dominio empresa.local mediante realmd/sssd/adcli

set -euo pipefail

DOMINIO="empresa.local"
IP_SERVIDOR="192.168.10.150"
ADMIN_USER="eromero"

# -----------------------------------------------
# COLORES
# -----------------------------------------------
ok()   { echo -e "\e[32m[OK]   $1\e[0m"; }
info() { echo -e "\e[36m[INFO] $1\e[0m"; }
warn() { echo -e "\e[33m[WARN] $1\e[0m"; }
err()  { echo -e "\e[31m[ERR]  $1\e[0m"; }


# -----------------------------------------------
# 1. VERIFICAR ROOT
# -----------------------------------------------
if [[ $EUID -ne 0 ]]; then
    err "Este script debe ejecutarse como root (sudo ./practica8_cliente_linux.sh)"
    exit 1
fi


# -----------------------------------------------
# 2. CONFIGURAR IP ESTATICA
# -----------------------------------------------
configurar_red() {
    info "Interfaces de red disponibles:"
    IFACES=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo))

    for i in "${!IFACES[@]}"; do
        IP_ACTUAL=$(ip -4 addr show "${IFACES[$i]}" 2>/dev/null | grep -oP '(?<=inet )\S+' || echo "sin IP")
        echo "  [$((i+1))] ${IFACES[$i]}  —  $IP_ACTUAL"
    done

    read -rp "Selecciona interfaz de red interna [1]: " SEL
    SEL=${SEL:-1}
    IFACE="${IFACES[$((SEL-1))]}"

    read -rp "IP estatica para este cliente [192.168.10.202]: " IP_CLIENTE
    IP_CLIENTE=${IP_CLIENTE:-192.168.10.202}

    info "Configurando $IFACE con IP $IP_CLIENTE..."

    # Detectar si usa NetworkManager o netplan
    if command -v nmcli &>/dev/null; then
        CON=$(nmcli -t -f NAME,DEVICE con show --active | grep "$IFACE" | cut -d: -f1 | head -1)
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
    elif [[ -d /etc/netplan ]]; then
        NETPLAN_FILE="/etc/netplan/01-dominio.yaml"
        cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  ethernets:
    ${IFACE}:
      addresses: [${IP_CLIENTE}/24]
      routes:
        - to: default
          via: 192.168.10.1
      nameservers:
        addresses: [${IP_SERVIDOR}]
EOF
        netplan apply
    else
        ip addr flush dev "$IFACE"
        ip addr add "$IP_CLIENTE/24" dev "$IFACE"
        ip route add default via 192.168.10.1 dev "$IFACE"
        echo "nameserver $IP_SERVIDOR" > /etc/resolv.conf
        warn "Configuracion temporal (no persiste al reinicio). Configura netplan o NetworkManager manualmente."
    fi

    ok "Red configurada: $IP_CLIENTE | Gateway: 192.168.10.1 | DNS: $IP_SERVIDOR"
}


# -----------------------------------------------
# 3. PROBAR CONECTIVIDAD
# -----------------------------------------------
probar_conectividad() {
    info "Probando conectividad con el servidor ($IP_SERVIDOR)..."
    if ping -c 2 -W 2 "$IP_SERVIDOR" &>/dev/null; then
        ok "Servidor alcanzable."
    else
        err "No se puede alcanzar el servidor en $IP_SERVIDOR."
        err "Verifica que el servidor este encendido y en la misma red."
        exit 1
    fi

    info "Verificando resolucion DNS de $DOMINIO..."
    if host "$DOMINIO" "$IP_SERVIDOR" &>/dev/null; then
        ok "DNS resuelve $DOMINIO correctamente."
    else
        err "No se pudo resolver $DOMINIO. Verifica que el servidor sea el DC y el DNS."
        exit 1
    fi
}


# -----------------------------------------------
# 4. INSTALAR PAQUETES
# -----------------------------------------------
instalar_paquetes() {
    info "Actualizando repositorios..."
    apt-get update -q

    info "Instalando realmd, sssd, adcli y dependencias..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        realmd \
        sssd \
        sssd-tools \
        sssd-ad \
        adcli \
        samba-common-bin \
        oddjob \
        oddjob-mkhomedir \
        packagekit \
        krb5-user \
        2>/dev/null

    ok "Paquetes instalados."
}


# -----------------------------------------------
# 5. UNIRSE AL DOMINIO
# -----------------------------------------------
unir_dominio() {
    info "Descubriendo dominio $DOMINIO..."
    if ! realm discover "$DOMINIO"; then
        err "No se pudo descubrir el dominio. Verifica red y DNS."
        exit 1
    fi

    echo ""
    info "Uniendo equipo al dominio $DOMINIO con el usuario $ADMIN_USER..."
    info "Se pedira la contrasena del usuario $ADMIN_USER@$DOMINIO"
    echo ""

    realm join -U "$ADMIN_USER" "$DOMINIO"
    ok "Equipo unido al dominio $DOMINIO."
}


# -----------------------------------------------
# 6. CONFIGURAR SSSD
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
    ok "sssd.conf configurado (fallback_homedir = /home/%u@%d, nombres sin sufijo de dominio)."

    systemctl restart sssd
    systemctl enable sssd
    ok "sssd reiniciado y habilitado."
}


# -----------------------------------------------
# 7. HABILITAR CREACION AUTOMATICA DE HOME
# -----------------------------------------------
configurar_home() {
    info "Habilitando creacion automatica de directorio home..."
    pam-auth-update --enable mkhomedir
    ok "mkhomedir habilitado."
}


# -----------------------------------------------
# 8. CONFIGURAR SUDO PARA USUARIOS AD
# -----------------------------------------------
configurar_sudo() {
    info "Configurando sudo para el usuario administrador AD ($ADMIN_USER)..."

    SUDOERS_FILE="/etc/sudoers.d/ad-admins"

    cat > "$SUDOERS_FILE" <<EOF
# Permisos sudo para administrador del dominio ${DOMINIO}
${ADMIN_USER}@${DOMINIO} ALL=(ALL) ALL
${ADMIN_USER}           ALL=(ALL) ALL
EOF

    chmod 440 "$SUDOERS_FILE"
    ok "sudo configurado para $ADMIN_USER en $SUDOERS_FILE"
}


# -----------------------------------------------
# 9. VERIFICAR UNION
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
        ok "Usuario $ADMIN_USER resuelto correctamente:"
        id "$ADMIN_USER"
    else
        warn "No se pudo resolver $ADMIN_USER. Puede tardar unos segundos en propagar."
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
# MENU PRINCIPAL
# -----------------------------------------------
menu() {
    while true; do
        clear
        echo "========================================"
        echo "   Practica 8 — Cliente Linux           "
        echo "   Dominio: $DOMINIO                    "
        echo "========================================"
        echo "  [1] Configurar red"
        echo "  [2] Probar conectividad"
        echo "  [3] Instalar paquetes"
        echo "  [4] Unirse al dominio"
        echo "  [5] Configurar sssd"
        echo "  [6] Habilitar home automatico + sudo"
        echo "  [7] Verificar union al dominio"
        echo "  [8] Unirse al dominio (todo en uno)"
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
