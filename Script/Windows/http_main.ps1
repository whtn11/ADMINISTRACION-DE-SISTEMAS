# ==============================================================================
# http_main.ps1 - Script principal - Servidores HTTP Windows
# Tarea 6 - Administración de Sistemas
# Grupo: 3-02 | Alumno: eromero
# Uso: Ejecutar como Administrador via SSH/PowerShell remoto
# ==============================================================================

# Forzar encoding UTF-8 para caracteres en español
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

# Cargar funciones desde el archivo de biblioteca
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\http_functions.ps1"

# ==============================================================================
# MAIN - Solo llamadas a funciones
# ==============================================================================

function Mostrar-Banner {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   TAREA 6 - APROVISIONAMIENTO DE SERVIDORES HTTP          " -ForegroundColor Cyan
    Write-Host "   Administración de Sistemas | Grupo 3-02                 " -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Mostrar-Menu {
    Write-Host "  Seleccione una opción:" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1] Instalar y Configurar IIS (Internet Information Services)" -ForegroundColor Yellow
    Write-Host "  [2] Instalar y Configurar Apache para Windows (Chocolatey)"    -ForegroundColor Yellow
    Write-Host "  [3] Instalar y Configurar Nginx para Windows (Chocolatey)"     -ForegroundColor Yellow
    Write-Host "  [4] Ver estado de todos los servidores HTTP"                   -ForegroundColor Yellow
    Write-Host "  [5] Salir"                                                     -ForegroundColor Yellow
    Write-Host ""
}

function Main {
    Verificar-Administrador

    while ($true) {
        Mostrar-Banner
        Mostrar-Menu

        $opcion = Read-Host "  Ingrese su opción"
        $opcion = $opcion.Trim()

        switch ($opcion) {
            "1" {
                Write-Host ""
                Msg-Info "--- IIS (Internet Information Services) ---"
                Instalar-Configurar-IIS
                Write-Host ""
                Read-Host "Presione ENTER para continuar"
            }
            "2" {
                Write-Host ""
                Msg-Info "--- Apache HTTP Server para Windows ---"
                Instalar-Configurar-Apache
                Write-Host ""
                Read-Host "Presione ENTER para continuar"
            }
            "3" {
                Write-Host ""
                Msg-Info "--- Nginx para Windows ---"
                Instalar-Configurar-Nginx
                Write-Host ""
                Read-Host "Presione ENTER para continuar"
            }
            "4" {
                Write-Host ""
                Mostrar-Estado-Servicios
                Read-Host "Presione ENTER para continuar"
            }
            "5" {
                Msg-Info "Saliendo..."
                exit 0
            }
            default {
                Msg-Err "Opción inválida. Seleccione entre 1 y 5."
                Start-Sleep -Seconds 1
            }
        }
    }
}

Main
