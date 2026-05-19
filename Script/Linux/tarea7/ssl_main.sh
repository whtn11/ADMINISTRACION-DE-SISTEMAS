#!/bin/bash
# ==============================================================================
# ssl_main.sh - Script principal - Orquestador SSL/TLS Linux
# Práctica 7 - Administración de Sistemas
# Grupo: 3-02 | Alumno: eromero
# Uso: sudo bash ssl_main.sh
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ssl_functions.sh"

mostrar_banner() {
    clear
    echo -e "${CIAN}============================================================${NC}"
    echo -e "${CIAN}   PRACTICA 7 - ORQUESTADOR SSL/TLS + FTP HIBRIDO          ${NC}"
    echo -e "${CIAN}   Administracion de Sistemas | Grupo 3-02                 ${NC}"
    echo -e "${CIAN}============================================================${NC}"
    echo ""
}

mostrar_menu() {
    echo -e "  ${AMARILLO}Seleccione una opcion:${NC}"
    echo ""
    echo "  [1] Instalar y Configurar Apache HTTPD"
    echo "  [2] Instalar y Configurar Nginx"
    echo "  [3] Instalar y Configurar Tomcat"
    echo "  [4] Configurar SSL en vsftpd (FTPS)"
    echo "  [5] Ver resumen de instalaciones"
    echo "  [6] Salir"
    echo ""
}

main() {
    verificar_root

    while true; do
        mostrar_banner
        mostrar_menu

        read -rp "  Ingrese su opcion: " OPCION
        OPCION="${OPCION//[^0-9]/}"

        case "$OPCION" in
            1)
                echo ""
                instalar_configurar_apache
                echo ""
                read -rp "Presione ENTER para continuar..."
                ;;
            2)
                echo ""
                instalar_configurar_nginx
                echo ""
                read -rp "Presione ENTER para continuar..."
                ;;
            3)
                echo ""
                instalar_configurar_tomcat
                echo ""
                read -rp "Presione ENTER para continuar..."
                ;;
            4)
                echo ""
                configurar_ssl_vsftpd
                echo ""
                read -rp "Presione ENTER para continuar..."
                ;;
            5)
                echo ""
                mostrar_resumen
                read -rp "Presione ENTER para continuar..."
                ;;
            6)
                msg_info "Saliendo..."
                exit 0
                ;;
            *)
                msg_err "Opcion invalida. Seleccione entre 1 y 6."
                sleep 1
                ;;
        esac
    done
}

main
