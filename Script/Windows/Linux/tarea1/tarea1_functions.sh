#!/bin/bash
# ============================================================
# TAREA 1 - Funciones de diagnóstico
# Archivo: tarea1_functions.sh
# ============================================================

function obtener_hostname() {
    hostname
}

function obtener_ip() {
    hostname -I | awk '{print $1}'
}

function obtener_disco() {
    df -h /
}

function mostrar_diagnostico() {
    echo "============================="
    echo " NOMBRE DEL EQUIPO: $(obtener_hostname)"
    echo " IP ACTUAL: $(obtener_ip)"
    echo " ESPACIO EN DISCO:"
    obtener_disco
    echo "============================="
}
