#!/bin/bash
# check_status.sh - Tarea 1

echo "============================="
echo " NOMBRE DEL EQUIPO: $(hostname)"
echo " IP ACTUAL: $(hostname -I | awk '{print $1}')"
echo " ESPACIO EN DISCO:"
df -h /
echo "============================="