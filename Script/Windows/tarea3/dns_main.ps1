# ============================================================
# TAREA 3 - Script principal DNS Windows
# Archivo: dns_main.ps1
# ============================================================

. "$PSScriptRoot\dns_functions.ps1"

Verificar-Admin

while ($true) {
    Write-Host "=========================="
    Write-Host "  SERVIDOR DNS - WINDOWS"
    Write-Host "=========================="
    Write-Host "1. Instalar y configurar DNS"
    Write-Host "2. Ver estado del servicio"
    Write-Host "3. Probar resolucion DNS"
    Write-Host "4. Salir"
    Write-Host "=========================="
    $opcion = Read-Host "Opcion [1-4]"

    switch ($opcion) {
        "1" {
            Verificar-IPFija
            Instalar-DNS
            Configurar-Zona
            Crear-Registros
            Restart-Service DNS
            Write-Host "DNS configurado correctamente." -ForegroundColor Green
        }
        "2" { Ver-Estado-DNS }
        "3" { Probar-DNS }
        "4" { exit 0 }
        default { Write-Host "Opcion invalida" }
    }
}
