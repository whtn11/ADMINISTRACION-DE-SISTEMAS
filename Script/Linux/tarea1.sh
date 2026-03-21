#!/bin/bash
# ============================================================
#  TAREA 1 - Script de Diagnóstico del Sistema
#  Materia: Sistemas
#  Servidor: Srv-Linux-Sistemas | IP: 192.168.10.20
# ============================================================

# Colores para output
VERDE='\033[0;32m'
AZUL='\033[0;34m'
AMARILLO='\033[1;33m'
RESET='\033[0m'
LINEA="============================================================"

echo -e "${AZUL}${LINEA}${RESET}"
echo -e "${VERDE}       DIAGNÓSTICO DEL SISTEMA - TAREA 1${RESET}"
echo -e "${AZUL}${LINEA}${RESET}"

# 1. Nombre del equipo
echo -e "\n${AMARILLO}[1] NOMBRE DEL EQUIPO:${RESET}"
echo "    $(hostname)"

# 2. IP actual (red interna - adaptador 2)
echo -e "\n${AMARILLO}[2] DIRECCIÓN IP ACTUAL:${RESET}"
ip -4 addr show | grep -v "127.0.0.1" | grep "inet" | awk '{print "    " $2}'

# 3. Espacio en disco
echo -e "\n${AMARILLO}[3] ESPACIO EN DISCO:${RESET}"
df -h --output=source,size,used,avail,pcent,target | grep -v "tmpfs\|devtmpfs" | \
    awk 'NR==1{print "    "$0} NR>1{print "    "$0}'

# 4. Memoria RAM
echo -e "\n${AMARILLO}[4] MEMORIA RAM:${RESET}"
free -h | awk 'NR==1{print "    "$0} NR==2{print "    "$0}'

# 5. Estado del sistema operativo
echo -e "\n${AMARILLO}[5] SISTEMA OPERATIVO:${RESET}"
cat /etc/os-release | grep "PRETTY_NAME" | cut -d= -f2 | tr -d '"' | awk '{print "    "$0}'

# 6. Uptime
echo -e "\n${AMARILLO}[6] TIEMPO EN LÍNEA:${RESET}"
echo "    $(uptime -p)"

# 7. Prueba de conectividad a los otros nodos
echo -e "\n${AMARILLO}[7] PRUEBA DE CONECTIVIDAD (PING):${RESET}"

NODOS=("192.168.10.15:Srv-Win-Sistemas" "192.168.10.30:Cliente-Sistemas")

for NODO in "${NODOS[@]}"; do
    IP=$(echo $NODO | cut -d: -f1)
    NOMBRE=$(echo $NODO | cut -d: -f2)
    if ping -c 2 -W 2 "$IP" &>/dev/null; then
        echo -e "    ${VERDE}[OK]${RESET}  $NOMBRE ($IP) - Alcanzable"
    else
        echo -e "    \033[0;31m[FAIL]\033[0m $NOMBRE ($IP) - Sin respuesta"
    fi
done

echo -e "\n${AZUL}${LINEA}${RESET}"
echo -e "${VERDE}        FIN DEL DIAGNÓSTICO${RESET}"
echo -e "${AZUL}${LINEA}${RESET}\n"
