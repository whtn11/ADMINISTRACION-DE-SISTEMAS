# ============================================================
# TAREA 2 - DHCP Server Windows
# Archivo: dhcp_main.ps1
# ============================================================

. "$PSScriptRoot\dhcp_functions.ps1"

Verificar-Admin

while ($true) {
    Write-Host "=========================="
    Write-Host "  SERVIDOR DHCP - WINDOWS"
    Write-Host "=========================="
    Write-Host "1. Instalar y configurar DHCP"
    Write-Host "2. Ver estado del servicio"
    Write-Host "3. Ver leases activos"
    Write-Host "4. Salir"
    Write-Host "=========================="
    $opcion = Read-Host "Opcion [1-4]"

    switch ($opcion) {
        "1" { Instalar-DHCP; Capturar-Parametros; Configurar-DHCP }
        "2" { Get-Service -Name DHCPServer; Get-DhcpServerv4Scope }
        "3" {
            $scopes = Get-DhcpServerv4Scope
            foreach ($scope in $scopes) {
                Write-Host "Scope: $($scope.Name)"
                Get-DhcpServerv4Lease -ScopeId $scope.ScopeId
            }
        }
        "4" { exit 0 }
        default { Write-Host "Opcion invalida" }
    }
}
