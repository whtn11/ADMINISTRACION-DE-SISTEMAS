#!/bin/bash
# ==============================================================================
# http_main.sh - Script principal - Servidores HTTP Linux
# Tarea 6 - Administración de Sistemas
# Grupo: 3-02 | Alumno: eromero
# Uso: sudo bash http_main.sh
# ==============================================================================

# Cargar funciones
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/http_functions.sh"

# ==============================================================================
# MAIN - Solo llamadas a funciones
# ==============================================================================

mostrar_banner() {
    clear
    echo -e "${CIAN}============================================================${NC}"
    echo -e "${CIAN}   TAREA 6 - APROVISIONAMIENTO DE SERVIDORES HTTP          ${NC}"
    echo -e "${CIAN}   Administracion de Sistemas | Grupo 3-02                 ${NC}"
    echo -e "${CIAN}============================================================${NC}"
    echo ""
}

mostrar_menu() {
    echo -e "  ${AMARILLO}Seleccione una opcion:${NC}"
    echo ""
    echo "  [1] Instalar y Configurar Apache2"
    echo "  [2] Instalar y Configurar Nginx"
    echo "  [3] Instalar y Configurar Apache Tomcat"
    echo "  [4] Ver estado de todos los servidores HTTP"
    echo "  [5] Salir"
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
                mostrar_estado
                read -rp "Presione ENTER para continuar..."
                ;;
            5)
                msg_info "Saliendo..."
                exit 0
                ;;
            *)
                msg_err "Opcion invalida. Seleccione entre 1 y 5."
                sleep 1
                ;;
        esac
    done
}

main
