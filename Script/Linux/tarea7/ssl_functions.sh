#!/bin/bash
# ==============================================================================
# ssl_functions.sh - Biblioteca de funciones para SSL/TLS y orquestador híbrido
# Práctica 7 - Administración de Sistemas
# Grupo: 3-02 | Alumno: eromero
# Distribución: AlmaLinux 9
# ==============================================================================

# ---- Colores ----
ROJO='\033[0;31m'
VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
CIAN='\033[0;36m'
NC='\033[0m'

msg_ok()   { echo -e "${VERDE}[OK]${NC}    $1"; }
msg_err()  { echo -e "${ROJO}[ERROR]${NC} $1"; }
msg_info() { echo -e "${CIAN}[INFO]${NC}  $1"; }
msg_warn() { echo -e "${AMARILLO}[WARN]${NC}  $1"; }

# ---- Configuración global ----
FTP_SERVER="192.168.10.20"
FTP_USER="juan"
FTP_PASS="ervg2005"
FTP_BASE="/http/Linux"
DOMINIO="reprobados.com"
SSL_DIR="/etc/ssl/practica7"
RESUMEN=()

# ==============================================================================
# UTILIDADES
# ==============================================================================

verificar_root() {
    if [[ $EUID -ne 0 ]]; then
        msg_err "Este script debe ejecutarse como root."
        exit 1
    fi
}

instalar_paquete() {
    local PKG="$1"
    if rpm -q "$PKG" &>/dev/null; then
        msg_warn "'$PKG' ya está instalado."
    else
        msg_info "Instalando $PKG..."
        dnf install -y "$PKG" -q
        msg_ok "$PKG instalado."
    fi
}

preguntar_ssl() {
    local SERVICIO="$1"
    local RESP=""
    while true; do
        read -rp "¿Desea activar SSL en $SERVICIO? [S/N]: " RESP
        RESP="${RESP^^}"
        if [[ "$RESP" == "S" || "$RESP" == "N" ]]; then
            echo "$RESP"
            return
        fi
        msg_err "Respuesta inválida. Ingrese S o N."
    done
}

# ==============================================================================
# FUENTE DE INSTALACIÓN
# ==============================================================================

elegir_fuente() {
    echo ""
    echo -e "  ${CIAN}Fuente de instalación:${NC}"
    echo "  [1] WEB (repositorio dnf)"
    echo "  [2] FTP (repositorio privado 192.168.10.20)"
    echo ""
    local OPC=""
    while true; do
        read -rp "  Seleccione [1-2]: " OPC
        OPC="${OPC//[^0-9]/}"
        if [[ "$OPC" == "1" || "$OPC" == "2" ]]; then
            echo "$OPC"
            return
        fi
        msg_err "Opción inválida."
    done
}

# ==============================================================================
# CLIENTE FTP DINÁMICO
# ==============================================================================

listar_ftp() {
    local RUTA="$1"
    curl -s --list-only "ftp://${FTP_SERVER}${RUTA}" -u "${FTP_USER}:${FTP_PASS}" 2>/dev/null
}

navegar_ftp() {
    local SERVICIO="$1"
    local RUTA="${FTP_BASE}/${SERVICIO}"

    msg_info "Conectando al FTP: ftp://${FTP_SERVER}${RUTA}"
    local ARCHIVOS
    mapfile -t ARCHIVOS < <(listar_ftp "$RUTA" | grep -v "^d")

    if [[ ${#ARCHIVOS[@]} -eq 0 ]]; then
        msg_err "No se encontraron archivos en $RUTA"
        return 1
    fi

    echo ""
    echo -e "  ${CIAN}Archivos disponibles en FTP:${NC}"
    for i in "${!ARCHIVOS[@]}"; do
        local F="${ARCHIVOS[$i]}"
        # Filtrar hashes, mostrar solo instaladores
        if [[ "$F" != *.sha256 ]]; then
            echo "  [$((i+1))] $F"
        fi
    done
    echo ""

    # Filtrar solo instaladores
    local INSTALADORES=()
    for F in "${ARCHIVOS[@]}"; do
        [[ "$F" != *.sha256 ]] && INSTALADORES+=("$F")
    done

    local SEL=""
    while true; do
        read -rp "  Seleccione archivo [1-${#INSTALADORES[@]}]: " SEL
        SEL="${SEL//[^0-9]/}"
        if [[ -n "$SEL" ]] && (( SEL >= 1 && SEL <= ${#INSTALADORES[@]} )); then
            echo "${INSTALADORES[$((SEL-1))]}"
            return 0
        fi
        msg_err "Selección inválida."
    done
}

descargar_ftp() {
    local SERVICIO="$1"
    local ARCHIVO="$2"
    local DESTINO="$3"
    local RUTA="${FTP_BASE}/${SERVICIO}/${ARCHIVO}"

    msg_info "Descargando $ARCHIVO desde FTP..."
    curl -s "ftp://${FTP_SERVER}${RUTA}" -u "${FTP_USER}:${FTP_PASS}" -o "${DESTINO}/${ARCHIVO}"

    if [[ $? -ne 0 ]]; then
        msg_err "Error al descargar $ARCHIVO"
        return 1
    fi
    msg_ok "Archivo descargado: ${DESTINO}/${ARCHIVO}"
}

verificar_hash() {
    local SERVICIO="$1"
    local ARCHIVO="$2"
    local DESTINO="$3"
    local RUTA="${FTP_BASE}/${SERVICIO}"

    # Buscar archivo .sha256 correspondiente
    local SHA_FILE
    SHA_FILE=$(listar_ftp "$RUTA" | grep ".sha256" | head -1)

    if [[ -z "$SHA_FILE" ]]; then
        msg_warn "No se encontró archivo .sha256 en el servidor FTP."
        return 0
    fi

    msg_info "Descargando hash: $SHA_FILE"
    curl -s "ftp://${FTP_SERVER}${RUTA}/${SHA_FILE}" -u "${FTP_USER}:${FTP_PASS}" -o "/tmp/${SHA_FILE}"

    # Ajustar el nombre del archivo en el .sha256
    sed -i "s|.*/||" "/tmp/${SHA_FILE}"
    echo "$(cat /tmp/${SHA_FILE} | awk '{print $1}')  ${DESTINO}/${ARCHIVO}" > /tmp/check.sha256

    msg_info "Verificando integridad del archivo..."
    if sha256sum -c /tmp/check.sha256 &>/dev/null; then
        msg_ok "Integridad verificada correctamente."
        return 0
    else
        msg_err "¡El hash no coincide! El archivo puede estar corrupto."
        return 1
    fi
}

instalar_desde_ftp() {
    local SERVICIO="$1"
    local DESTINO="/tmp/ftp_install"
    mkdir -p "$DESTINO"

    local ARCHIVO
    ARCHIVO=$(navegar_ftp "$SERVICIO")
    [[ $? -ne 0 ]] && return 1

    descargar_ftp "$SERVICIO" "$ARCHIVO" "$DESTINO"
    [[ $? -ne 0 ]] && return 1

    verificar_hash "$SERVICIO" "$ARCHIVO" "$DESTINO"
    [[ $? -ne 0 ]] && return 1

    msg_info "Instalando $ARCHIVO..."
    dnf install -y "${DESTINO}/${ARCHIVO}" -q 2>/dev/null || \
    rpm -ivh "${DESTINO}/${ARCHIVO}" 2>/dev/null
    msg_ok "$SERVICIO instalado desde FTP."
}

# ==============================================================================
# GENERACIÓN DE CERTIFICADOS SSL
# ==============================================================================

generar_certificado() {
    local SERVICIO="$1"
    local CERT_DIR="${SSL_DIR}/${SERVICIO}"
    mkdir -p "$CERT_DIR"

    msg_info "Generando certificado SSL para $DOMINIO ($SERVICIO)..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "${CERT_DIR}/privkey.pem" \
        -out "${CERT_DIR}/cert.pem" \
        -subj "/C=MX/ST=Sinaloa/L=LMochis/O=UAS/CN=${DOMINIO}" \
        2>/dev/null

    if [[ $? -eq 0 ]]; then
        msg_ok "Certificado generado en ${CERT_DIR}/"
        chmod 600 "${CERT_DIR}/privkey.pem"
    else
        msg_err "Error al generar certificado SSL."
        return 1
    fi
}

# ==============================================================================
# APACHE HTTPD
# ==============================================================================

instalar_configurar_apache() {
    msg_info "=== Apache HTTPD ==="
    local FUENTE
    FUENTE=$(elegir_fuente)

    if [[ "$FUENTE" == "1" ]]; then
        instalar_paquete httpd
    else
        instalar_desde_ftp "Apache"
    fi

    # Configurar SSL si se desea
    local SSL
    SSL=$(preguntar_ssl "Apache HTTPD")

    if [[ "$SSL" == "S" ]]; then
        instalar_paquete mod_ssl
        instalar_paquete openssl
        generar_certificado "apache"

        local CERT_DIR="${SSL_DIR}/apache"
        local SSL_CONF="/etc/httpd/conf.d/ssl.conf"

        # Configurar VirtualHost HTTPS
        cat > "$SSL_CONF" << EOF
Listen 443 https
SSLPassPhraseDialog exec:/usr/libexec/httpd-ssl-pass-dialog
SSLSessionCache         shmcb:/run/httpd/sslcache(512000)
SSLSessionCacheTimeout  300
SSLRandomSeed startup file:/dev/urandom  256
SSLRandomSeed connect builtin
SSLCryptoDevice builtin

<VirtualHost *:443>
    ServerName ${DOMINIO}
    SSLEngine on
    SSLCertificateFile ${CERT_DIR}/cert.pem
    SSLCertificateKeyFile ${CERT_DIR}/privkey.pem
    DocumentRoot /var/www/html
    ErrorLog /var/log/httpd/ssl_error.log
</VirtualHost>
EOF

        # Redirección HTTP → HTTPS
        local REDIR_CONF="/etc/httpd/conf.d/redirect.conf"
        cat > "$REDIR_CONF" << EOF
<VirtualHost *:80>
    ServerName ${DOMINIO}
    RewriteEngine On
    RewriteRule ^(.*)$ https://%{HTTP_HOST}\$1 [R=301,L]
</VirtualHost>
EOF
        # Habilitar mod_rewrite
        echo "LoadModule rewrite_module modules/mod_rewrite.so" >> /etc/httpd/conf/httpd.conf 2>/dev/null

        # SELinux
        semanage port -a -t http_port_t -p tcp 443 &>/dev/null || \
        semanage port -m -t http_port_t -p tcp 443 &>/dev/null
        firewall-cmd --permanent --add-port=443/tcp &>/dev/null
        firewall-cmd --reload &>/dev/null

        systemctl restart httpd
        msg_ok "Apache HTTPS configurado en puerto 443."
        RESUMEN+=("Apache HTTPD: HTTPS ✓ (puerto 443)")
    else
        systemctl restart httpd
        msg_ok "Apache HTTP sin SSL."
        RESUMEN+=("Apache HTTPD: HTTP sin SSL")
    fi
}

# ==============================================================================
# NGINX
# ==============================================================================

instalar_configurar_nginx() {
    msg_info "=== Nginx ==="
    local FUENTE
    FUENTE=$(elegir_fuente)

    if [[ "$FUENTE" == "1" ]]; then
        dnf install -y epel-release -q 2>/dev/null
        instalar_paquete nginx
    else
        instalar_desde_ftp "Nginx"
    fi

    local SSL
    SSL=$(preguntar_ssl "Nginx")

    if [[ "$SSL" == "S" ]]; then
        instalar_paquete openssl
        generar_certificado "nginx"

        local CERT_DIR="${SSL_DIR}/nginx"
        local NGINX_SSL="/etc/nginx/conf.d/ssl.conf"

        cat > "$NGINX_SSL" << EOF
server {
    listen 443 ssl;
    server_name ${DOMINIO};

    ssl_certificate     ${CERT_DIR}/cert.pem;
    ssl_certificate_key ${CERT_DIR}/privkey.pem;

    root /usr/share/nginx/html;
    index index.html;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
}

server {
    listen 80;
    server_name ${DOMINIO};
    return 301 https://\$host\$request_uri;
}
EOF

        semanage port -a -t http_port_t -p tcp 443 &>/dev/null || \
        semanage port -m -t http_port_t -p tcp 443 &>/dev/null
        firewall-cmd --permanent --add-port=443/tcp &>/dev/null
        firewall-cmd --reload &>/dev/null

        nginx -t &>/dev/null && systemctl restart nginx
        msg_ok "Nginx HTTPS configurado en puerto 443."
        RESUMEN+=("Nginx: HTTPS ✓ (puerto 443)")
    else
        systemctl restart nginx
        msg_ok "Nginx HTTP sin SSL."
        RESUMEN+=("Nginx: HTTP sin SSL")
    fi
}

# ==============================================================================
# TOMCAT
# ==============================================================================

instalar_configurar_tomcat() {
    msg_info "=== Apache Tomcat ==="
    local FUENTE
    FUENTE=$(elegir_fuente)

    if [[ "$FUENTE" == "1" ]]; then
        instalar_paquete java-17-openjdk-headless
        instalar_paquete tomcat
    else
        instalar_paquete java-17-openjdk-headless
        instalar_desde_ftp "Tomcat"
    fi

    local SSL
    SSL=$(preguntar_ssl "Tomcat")

    if [[ "$SSL" == "S" ]]; then
        instalar_paquete openssl
        generar_certificado "tomcat"

        local CERT_DIR="${SSL_DIR}/tomcat"
        local SERVER_XML="/etc/tomcat/server.xml"

        if [[ -f "$SERVER_XML" ]]; then
            # Agregar conector HTTPS si no existe
            if ! grep -q "8443" "$SERVER_XML"; then
                sed -i "s|</Service>|<Connector port=\"8443\" protocol=\"org.apache.coyote.http11.Http11NioProtocol\" SSLEnabled=\"true\" maxThreads=\"150\" scheme=\"https\" secure=\"true\" keystoreFile=\"${CERT_DIR}/cert.pem\" keystorePass=\"\" clientAuth=\"false\" sslProtocol=\"TLS\"/>\n</Service>|" "$SERVER_XML"
            fi
            msg_ok "Conector HTTPS agregado en puerto 8443."
        fi

        firewall-cmd --permanent --add-port=8443/tcp &>/dev/null
        firewall-cmd --reload &>/dev/null
        systemctl restart tomcat
        msg_ok "Tomcat HTTPS configurado en puerto 8443."
        RESUMEN+=("Tomcat: HTTPS ✓ (puerto 8443)")
    else
        systemctl restart tomcat
        msg_ok "Tomcat sin SSL."
        RESUMEN+=("Tomcat: HTTP sin SSL")
    fi
}

# ==============================================================================
# VSFTPD (FTPS)
# ==============================================================================

configurar_ssl_vsftpd() {
    msg_info "=== vsftpd (FTPS) ==="
    local SSL
    SSL=$(preguntar_ssl "vsftpd")

    if [[ "$SSL" == "S" ]]; then
        instalar_paquete openssl
        generar_certificado "vsftpd"

        local CERT_DIR="${SSL_DIR}/vsftpd"
        local CONF="/etc/vsftpd/vsftpd.conf"

        # Agregar configuración SSL
        cat >> "$CONF" << EOF

# SSL/TLS
ssl_enable=YES
allow_anon_ssl=NO
force_local_data_ssl=YES
force_local_logins_ssl=YES
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
rsa_cert_file=${CERT_DIR}/cert.pem
rsa_private_key_file=${CERT_DIR}/privkey.pem
EOF

        systemctl restart vsftpd
        msg_ok "vsftpd FTPS configurado."
        RESUMEN+=("vsftpd: FTPS ✓")
    else
        msg_ok "vsftpd sin SSL."
        RESUMEN+=("vsftpd: FTP sin SSL")
    fi
}

# ==============================================================================
# RESUMEN FINAL
# ==============================================================================

mostrar_resumen() {
    echo ""
    echo -e "${CIAN}=========================================${NC}"
    echo -e "${CIAN}   RESUMEN DE INSTALACIONES              ${NC}"
    echo -e "${CIAN}=========================================${NC}"
    for ITEM in "${RESUMEN[@]}"; do
        echo -e "  ${VERDE}•${NC} $ITEM"
    done
    echo ""
    msg_info "Verificando servicios activos:"
    for SVC in httpd nginx tomcat vsftpd; do
        if systemctl is-active "$SVC" &>/dev/null; then
            echo -e "  ${VERDE}[ACTIVO]${NC}   $SVC"
        else
            echo -e "  ${ROJO}[INACTIVO]${NC} $SVC"
        fi
    done
    echo ""
    msg_info "Certificados generados:"
    find "${SSL_DIR}" -name "cert.pem" 2>/dev/null | while read -r CERT; do
        echo -e "  ${VERDE}•${NC} $CERT"
        openssl x509 -in "$CERT" -noout -subject -dates 2>/dev/null | sed 's/^/    /'
    done
    echo ""
}
