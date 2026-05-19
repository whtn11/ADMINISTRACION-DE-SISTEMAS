# ==============================================================================
# ssl_main.ps1 - Script principal - Orquestador SSL/TLS Windows
# Práctica 7 - Administración de Sistemas
# Grupo: 3-02 | Alumno: eromero
# Uso: Ejecutar como Administrador
# ==============================================================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\ssl_functions.ps1"

function Mostrar-Banner {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   PRACTICA 7 - ORQUESTADOR SSL/TLS + FTP HIBRIDO          " -ForegroundColor Cyan
    Write-Host "   Administracion de Sistemas | Grupo 3-02                 " -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Mostrar-Menu {
    Write-Host "  Seleccione una opcion:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1] Configurar SSL en IIS"
    Write-Host "  [2] Instalar y Configurar SSL en Apache Windows"
    Write-Host "  [3] Instalar y Configurar SSL en Nginx Windows"
    Write-Host "  [4] Configurar SSL en IIS-FTP (FTPS)"
    Write-Host "  [5] Ver resumen de instalaciones"
    Write-Host "  [6] Salir"
    Write-Host ""
}

function Main {
    Verificar-Administrador

    while ($true) {
        Mostrar-Banner
        Mostrar-Menu

        $opcion = Read-Host "  Ingrese su opcion"
        $opcion = $opcion.Trim()

        switch ($opcion) {
            "1" {
                Write-Host ""
                Configurar-SSL-IIS
                Write-Host ""
                Read-Host "Presione ENTER para continuar"
            }
            "2" {
                Write-Host ""
                Configurar-SSL-Apache
                Write-Host ""
                Read-Host "Presione ENTER para continuar"
            }
            "3" {
                Write-Host ""
                Configurar-SSL-Nginx
                Write-Host ""
                Read-Host "Presione ENTER para continuar"
            }
            "4" {
                Write-Host ""
                Configurar-SSL-IISFTP
                Write-Host ""
                Read-Host "Presione ENTER para continuar"
            }
            "5" {
                Write-Host ""
                Mostrar-Resumen
                Read-Host "Presione ENTER para continuar"
            }
            "6" {
                Msg-Info "Saliendo..."
                exit 0
            }
            default {
                Msg-Err "Opcion invalida. Seleccione entre 1 y 6."
                Start-Sleep -Seconds 1
            }
        }
    }
}

Main
