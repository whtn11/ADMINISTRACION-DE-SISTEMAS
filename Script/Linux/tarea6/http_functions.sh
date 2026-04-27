#!/bin/bash
# ==============================================================================
# http_functions.sh - Biblioteca de funciones para servidores HTTP (Linux)
# Tarea 6 - Administración de Sistemas
# Grupo: 3-02 | Alumno: eromero
# Distribución: AlmaLinux 9 (dnf / firewall-cmd / systemd)
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

# ==============================================================================
# UTILIDADES
# ==============================================================================

verificar_root() {
    if [[ $EUID -ne 0 ]]; then
        msg_err "Este script debe ejecutarse como root (sudo)."
        exit 1
    fi
}

instalar_paquete() {
    local PKG="$1"
    if rpm -q "$PKG" &>/dev/null; then
        msg_warn "El paquete '$PKG' ya está instalado."
    else
        msg_info "Instalando paquete: $PKG"
        dnf install -y "$PKG" -q
        msg_ok "Paquete '$PKG' instalado."
    fi
}

# ==============================================================================
# VALIDACIONES DE PUERTO
# ==============================================================================

validar_puerto() {
    local PUERTO="$1"
    if ! [[ "$PUERTO" =~ ^[0-9]+$ ]]; then
        msg_err "El puerto debe ser numérico."
        return 1
    fi
    if (( PUERTO < 1 || PUERTO > 65535 )); then
        msg_err "Puerto fuera de rango válido (1-65535)."
        return 1
    fi
    local RESERVADOS=(22 25 53 110 143 3306 5432 21 23 445 139 3389)
    for R in "${RESERVADOS[@]}"; do
        if (( PUERTO == R )); then
            msg_err "El puerto $PUERTO está reservado para otro servicio."
            return 1
        fi
    done
    return 0
}

puerto_en_uso() {
    local PUERTO="$1"
    if ss -tlnp 2>/dev/null | grep -qE ":${PUERTO} |:${PUERTO}$"; then
        return 0
    fi
    return 1
}

pedir_puerto() {
    local PUERTO=""
    while true; do
        read -rp "Ingrese el puerto de escucha [ej: 80, 8080, 8888]: " PUERTO
        PUERTO="${PUERTO//[^0-9]/}"
        if [[ -z "$PUERTO" ]]; then
            msg_err "El puerto no puede estar vacío."
            continue
        fi
        if ! validar_puerto "$PUERTO"; then
            continue
        fi
        if puerto_en_uso "$PUERTO"; then
            msg_err "El puerto $PUERTO ya está en uso:"
            ss -tlnp | grep -E ":${PUERTO} |:${PUERTO}$"
            continue
        fi
        break
    done
    echo "$PUERTO"
}

# ==============================================================================
# VERSIONES DINÁMICAS (dnf)
# ==============================================================================

obtener_versiones() {
    local PAQUETE="$1"
    dnf list --available "$PAQUETE" 2>/dev/null \
        | awk 'NR>1 {print $2}' \
        | sort -Vr \
        | head -5
}

seleccionar_version() {
    local PAQUETE="$1"
    msg_info "Consultando versiones disponibles de '$PAQUETE'..."

    mapfile -t VERSIONES < <(obtener_versiones "$PAQUETE")

    if [[ ${#VERSIONES[@]} -eq 0 ]]; then
        msg_warn "No se encontraron versiones específicas. Se usará la versión por defecto."
        echo ""
        return
    fi

    echo ""
    echo -e "  ${CIAN}Versiones disponibles para '$PAQUETE':${NC}"
    for i in "${!VERSIONES[@]}"; do
        local ETIQUETA=""
        if [[ $i -eq 0 ]];                            then ETIQUETA="(Latest)"; fi
        if [[ $i -eq $(( ${#VERSIONES[@]} - 1 )) ]];  then ETIQUETA="(LTS/Estable)"; fi
        echo "  [$((i+1))] ${VERSIONES[$i]} $ETIQUETA"
    done
    echo ""

    local SEL=""
    while true; do
        read -rp "  Seleccione una versión [1-${#VERSIONES[@]}]: " SEL
        SEL="${SEL//[^0-9]/}"
        if [[ -n "$SEL" ]] && (( SEL >= 1 && SEL <= ${#VERSIONES[@]} )); then
            echo "${VERSIONES[$((SEL-1))]}"
            return
        fi
        msg_err "Selección inválida."
    done
}

# ==============================================================================
# USUARIO DEDICADO
# ==============================================================================

crear_usuario_dedicado() {
    local USUARIO="$1"
    local DIRECTORIO="$2"

    if id "$USUARIO" &>/dev/null; then
        msg_warn "El usuario '$USUARIO' ya existe."
    else
        useradd -r -s /sbin/nologin -d "$DIRECTORIO" "$USUARIO"
        msg_ok "Usuario dedicado '$USUARIO' creado (sin shell, sin login)."
    fi

    if [[ -d "$DIRECTORIO" ]]; then
        chown -R "${USUARIO}:${USUARIO}" "$DIRECTORIO"
        chmod 750 "$DIRECTORIO"
        msg_ok "Permisos asignados: $DIRECTORIO -> $USUARIO (chmod 750)."
    fi
}

# ==============================================================================
# FIREWALL (firewall-cmd - AlmaLinux)
# ==============================================================================

configurar_firewall() {
    local PUERTO="$1"
    local PUERTO_ANTERIOR="${2:-}"

    if ! systemctl is-active firewalld &>/dev/null; then
        systemctl start firewalld
        systemctl enable firewalld &>/dev/null
        msg_ok "firewalld iniciado."
    fi

    # Cerrar puerto anterior
    if [[ -n "$PUERTO_ANTERIOR" && "$PUERTO_ANTERIOR" != "$PUERTO" ]]; then
        firewall-cmd --permanent --remove-port="${PUERTO_ANTERIOR}/tcp" &>/dev/null
        msg_info "Puerto $PUERTO_ANTERIOR cerrado en firewall."
    fi

    # Abrir nuevo puerto
    firewall-cmd --permanent --add-port="${PUERTO}/tcp" &>/dev/null
    firewall-cmd --reload &>/dev/null
    msg_ok "Puerto $PUERTO abierto en firewall-cmd."
}

# ==============================================================================
# APACHE HTTPD (AlmaLinux: paquete 'httpd')
# ==============================================================================

instalar_configurar_apache() {
    msg_info "=== Instalacion de Apache HTTPD ==="

    local VERSION
    VERSION=$(seleccionar_version "httpd")
    local PUERTO
    PUERTO=$(pedir_puerto)

    # Instalar
    if [[ -z "$VERSION" ]]; then
        instalar_paquete httpd
    else
        dnf install -y "httpd-${VERSION}" -q 2>/dev/null || instalar_paquete httpd
    fi

    # Cambiar puerto en httpd.conf
    local HTTPD_CONF="/etc/httpd/conf/httpd.conf"
    sed -i "s/^Listen [0-9]*/Listen $PUERTO/" "$HTTPD_CONF"
    msg_ok "Puerto configurado en $PUERTO (httpd.conf)."

    # Seguridad: ocultar versión
    local SEC_CONF="/etc/httpd/conf.d/security.conf"
    cat > "$SEC_CONF" << EOF
ServerTokens Prod
ServerSignature Off
TraceEnable Off
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
EOF
    # Habilitar módulo headers
    if ! httpd -M 2>/dev/null | grep -q headers_module; then
        echo "LoadModule headers_module modules/mod_headers.so" >> "$HTTPD_CONF"
    fi
    msg_ok "ServerTokens Prod, ServerSignature Off, TRACE Off y security headers aplicados."

    # SELinux: permitir puerto personalizado
    if command -v semanage &>/dev/null && (( PUERTO != 80 && PUERTO != 443 )); then
        semanage port -a -t http_port_t -p tcp "$PUERTO" &>/dev/null \
            || semanage port -m -t http_port_t -p tcp "$PUERTO" &>/dev/null
        msg_ok "SELinux: puerto $PUERTO habilitado para http_port_t."
    fi

    # Página index.html
    local VER_REAL
    VER_REAL=$(httpd -v 2>/dev/null | grep "Server version" | awk '{print $3}' | cut -d/ -f2)
    [[ -z "$VER_REAL" ]] && VER_REAL="${VERSION:-desconocida}"
    mkdir -p /var/www/html
    cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Apache HTTPD - Tarea 6</title></head>
<body style="font-family:Arial;background:#cc0000;color:white;padding:40px;text-align:center">
  <h1>Servidor: Apache HTTPD</h1>
  <p><strong>Version:</strong> ${VER_REAL}</p>
  <p><strong>Puerto:</strong> ${PUERTO}</p>
  <p><em>Tarea 6 - Administracion de Sistemas - Grupo 3-02</em></p>
</body>
</html>
EOF
    msg_ok "Pagina index.html creada en /var/www/html/"

    # Usuario dedicado
    crear_usuario_dedicado "apache" "/var/www/html"

    # Firewall
    configurar_firewall "$PUERTO" "80"

    # Iniciar servicio (AlmaLinux: httpd)
    systemctl restart httpd
    systemctl enable httpd &>/dev/null
    msg_ok "Apache HTTPD corriendo en puerto $PUERTO."

    echo ""
    msg_info "Verificando encabezados:"
    curl -sI "http://localhost:${PUERTO}" | grep -E "HTTP|Server|X-Frame|X-Content"
}

# ==============================================================================
# NGINX (AlmaLinux)
# ==============================================================================

instalar_configurar_nginx() {
    msg_info "=== Instalacion de Nginx ==="

    # Habilitar repositorio nginx si no está
    if ! rpm -q nginx &>/dev/null && ! dnf list --available nginx &>/dev/null 2>&1 | grep -q nginx; then
        dnf install -y epel-release -q 2>/dev/null
    fi

    local VERSION
    VERSION=$(seleccionar_version "nginx")
    local PUERTO
    PUERTO=$(pedir_puerto)

    # Instalar
    if [[ -z "$VERSION" ]]; then
        instalar_paquete nginx
    else
        dnf install -y "nginx-${VERSION}" -q 2>/dev/null || instalar_paquete nginx
    fi

    # Cambiar puerto en nginx.conf
    local NGINX_CONF="/etc/nginx/nginx.conf"
    sed -i "s/listen\s\+80\b/listen $PUERTO/g"     "$NGINX_CONF"
    sed -i "s/listen\s\+\[::\]:80\b/listen [::]:$PUERTO/g" "$NGINX_CONF"
    msg_ok "Puerto configurado en $PUERTO (nginx.conf)."

    # Seguridad: server_tokens off
    if grep -q "server_tokens" "$NGINX_CONF"; then
        sed -i "s/.*server_tokens.*/    server_tokens off;/" "$NGINX_CONF"
    else
        sed -i "s/http {/http {\n    server_tokens off;/" "$NGINX_CONF"
    fi
    msg_ok "server_tokens off aplicado."

    # Security headers en el server block
    local DEF_CONF="/etc/nginx/conf.d/default.conf"
    if [[ -f "$DEF_CONF" ]]; then
        sed -i "s/listen\s\+80\b/listen $PUERTO/g" "$DEF_CONF"
        if ! grep -q "X-Frame-Options" "$DEF_CONF"; then
            sed -i "/server_name/a\\
    add_header X-Frame-Options \"SAMEORIGIN\";\\
    add_header X-Content-Type-Options \"nosniff\";\\
    if (\$request_method = TRACE) { return 405; }" "$DEF_CONF"
        fi
        msg_ok "Security headers y bloqueo de TRACE aplicados."
    fi

    # SELinux: permitir puerto personalizado
    if command -v semanage &>/dev/null && (( PUERTO != 80 && PUERTO != 443 )); then
        semanage port -a -t http_port_t -p tcp "$PUERTO" &>/dev/null \
            || semanage port -m -t http_port_t -p tcp "$PUERTO" &>/dev/null
        msg_ok "SELinux: puerto $PUERTO habilitado para http_port_t."
    fi

    # Página index.html
    local VER_REAL
    VER_REAL=$(nginx -v 2>&1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+')
    [[ -z "$VER_REAL" ]] && VER_REAL="${VERSION:-desconocida}"
    mkdir -p /usr/share/nginx/html
    cat > /usr/share/nginx/html/index.html << EOF
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Nginx - Tarea 6</title></head>
<body style="font-family:Arial;background:#009900;color:white;padding:40px;text-align:center">
  <h1>Servidor: Nginx</h1>
  <p><strong>Version:</strong> ${VER_REAL}</p>
  <p><strong>Puerto:</strong> ${PUERTO}</p>
  <p><em>Tarea 6 - Administracion de Sistemas - Grupo 3-02</em></p>
</body>
</html>
EOF
    msg_ok "Pagina index.html creada."

    # Usuario dedicado
    crear_usuario_dedicado "nginx" "/usr/share/nginx/html"

    # Firewall
    configurar_firewall "$PUERTO" "80"

    # Reiniciar
    nginx -t &>/dev/null && systemctl restart nginx
    systemctl enable nginx &>/dev/null
    msg_ok "Nginx corriendo en puerto $PUERTO."

    echo ""
    msg_info "Verificando encabezados:"
    curl -sI "http://localhost:${PUERTO}" | grep -E "HTTP|Server|X-Frame|X-Content"
}

# ==============================================================================
# TOMCAT (AlmaLinux)
# ==============================================================================

instalar_configurar_tomcat() {
    msg_info "=== Instalacion de Apache Tomcat ==="

    # Java
    if ! command -v java &>/dev/null; then
        msg_info "Instalando Java 17..."
        instalar_paquete java-17-openjdk-headless
    fi
    msg_ok "Java: $(java -version 2>&1 | head -1)"

    # Tomcat en AlmaLinux: paquete 'tomcat'
    local PAQUETE="tomcat"
    local VERSION
    VERSION=$(seleccionar_version "$PAQUETE")
    local PUERTO
    PUERTO=$(pedir_puerto)

    # Instalar
    if [[ -z "$VERSION" ]]; then
        instalar_paquete "$PAQUETE"
    else
        dnf install -y "${PAQUETE}-${VERSION}" -q 2>/dev/null || instalar_paquete "$PAQUETE"
    fi

    # Cambiar puerto en server.xml
    local SERVER_XML=""
    for RUTA in /etc/tomcat/server.xml /usr/share/tomcat/conf/server.xml; do
        [[ -f "$RUTA" ]] && SERVER_XML="$RUTA" && break
    done

    if [[ -n "$SERVER_XML" ]]; then
        sed -i "s/port=\"8080\"/port=\"${PUERTO}\"/" "$SERVER_XML"
        msg_ok "Puerto configurado en $PUERTO (server.xml)."
    else
        msg_warn "No se encontro server.xml. Puerto no modificado."
    fi

    # Página index.html en webapps ROOT
    local WEBAPPS=""
    for DIR in /var/lib/tomcat/webapps/ROOT /usr/share/tomcat/webapps/ROOT; do
        [[ -d "$DIR" ]] && WEBAPPS="$DIR" && break
    done

    if [[ -z "$WEBAPPS" ]]; then
        WEBAPPS="/var/lib/tomcat/webapps/ROOT"
        mkdir -p "$WEBAPPS"
    fi

    cat > "${WEBAPPS}/index.html" << EOF
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Tomcat - Tarea 6</title></head>
<body style="font-family:Arial;background:#f5a623;color:#333;padding:40px;text-align:center">
  <h1>Servidor: Apache Tomcat</h1>
  <p><strong>Version:</strong> ${VERSION:-instalada}</p>
  <p><strong>Puerto:</strong> ${PUERTO}</p>
  <p><em>Tarea 6 - Administracion de Sistemas - Grupo 3-02</em></p>
</body>
</html>
EOF
    msg_ok "Pagina index.html creada en $WEBAPPS"

    # Usuario dedicado (tomcat crea el suyo)
    if id "tomcat" &>/dev/null; then
        msg_ok "Usuario 'tomcat' ya existe."
        for DIR in /var/lib/tomcat /usr/share/tomcat; do
            [[ -d "$DIR" ]] && chown -R tomcat:tomcat "$DIR" && chmod 750 "$DIR"
        done
        msg_ok "Permisos asignados a directorios de tomcat (chmod 750)."
    fi

    # SELinux
    if command -v semanage &>/dev/null && (( PUERTO != 8080 && PUERTO != 8443 )); then
        semanage port -a -t http_port_t -p tcp "$PUERTO" &>/dev/null \
            || semanage port -m -t http_port_t -p tcp "$PUERTO" &>/dev/null
        msg_ok "SELinux: puerto $PUERTO habilitado."
    fi

    # Firewall
    configurar_firewall "$PUERTO" "8080"

    # Reiniciar
    systemctl restart tomcat
    systemctl enable tomcat &>/dev/null
    msg_ok "Tomcat corriendo en puerto $PUERTO."

    echo ""
    msg_info "Verificando encabezados (espere 5s):"
    sleep 5
    curl -sI "http://localhost:${PUERTO}" | grep -E "HTTP|Server|X-Frame|X-Content"
}

# ==============================================================================
# ESTADO DE SERVICIOS
# ==============================================================================

mostrar_estado() {
    echo ""
    echo -e "${CIAN}=========================================${NC}"
    echo -e "${CIAN}   ESTADO DE SERVIDORES HTTP             ${NC}"
    echo -e "${CIAN}=========================================${NC}"

    for SVC in httpd nginx tomcat; do
        if systemctl list-units --type=service --all 2>/dev/null | grep -q "${SVC}.service"; then
            local ESTADO
            ESTADO=$(systemctl is-active "$SVC" 2>/dev/null)
            if [[ "$ESTADO" == "active" ]]; then
                echo -e "  ${VERDE}[CORRIENDO]${NC} $SVC"
            else
                echo -e "  ${ROJO}[DETENIDO]${NC}  $SVC"
            fi
        else
            echo -e "  ${AMARILLO}[NO INSTALADO]${NC} $SVC"
        fi
    done

    echo ""
    msg_info "Puertos en escucha:"
    ss -tlnp | grep -E ":80 |:443 |:8080 |:8888 " || echo "  (Ninguno en puertos comunes)"
    echo ""
}
