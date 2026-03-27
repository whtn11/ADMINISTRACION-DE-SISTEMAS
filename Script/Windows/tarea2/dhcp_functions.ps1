# ============================================================
# TAREA 2 - Funciones DHCP Windows
# Archivo: dhcp_functions.ps1
# ============================================================

function Verificar-Admin {
    $esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $esAdmin) {
        Write-Host "Ejecuta el script como Administrador."
        exit 1
    }
}

function Validar-IP {
    param([string]$IP)
    try { [System.Net.IPAddress]::Parse($IP) | Out-Null; return $true }
    catch { return $false }
}

function Instalar-DHCP {
    $instalado = (Get-WindowsFeature -Name DHCP).Installed
    if ($instalado) {
        Write-Host "El rol DHCP ya esta instalado."
    } else {
        Write-Host "Instalando rol DHCP..."
        Install-WindowsFeature -Name DHCP -IncludeManagementTools
        Write-Host "Instalacion completada."
    }
    Start-Service -Name DHCPServer -ErrorAction SilentlyContinue
    Set-Service -Name DHCPServer -StartupType Automatic
}

function Capturar-Parametros {
    Write-Host "--- Configuracion del Scope ---"

    do {
        $script:ScopeNombre = Read-Host "Nombre del scope"
    } while ([string]::IsNullOrWhiteSpace($script:ScopeNombre))

    do {
        $script:ScopeIP = Read-Host "Red del scope (ej: 192.168.100.0)"
    } while (-not (Validar-IP $script:ScopeIP))

    do {
        $script:Mascara = Read-Host "Mascara (ej: 255.255.255.0)"
    } while (-not (Validar-IP $script:Mascara))

    do {
        $script:RangoInicio = Read-Host "IP inicio del rango"
    } while (-not (Validar-IP $script:RangoInicio))

    do {
        $script:RangoFin = Read-Host "IP fin del rango"
    } while (-not (Validar-IP $script:RangoFin))

    do {
        $script:Gateway = Read-Host "Gateway"
    } while (-not (Validar-IP $script:Gateway))

    do {
        $script:DNS = Read-Host "DNS"
    } while (-not (Validar-IP $script:DNS))

    do {
        $dias = Read-Host "Lease time en dias (ej: 1)"
        $valido = $dias -match '^\d+$' -and [int]$dias -gt 0
    } while (-not $valido)
    $script:LeaseTime = [int]$dias
}

function Configurar-DHCP {
    Write-Host "Configurando scope DHCP..."

    $existe = Get-DhcpServerv4Scope | Where-Object { $_.ScopeId -eq $script:ScopeIP }
    if ($existe) {
        Remove-DhcpServerv4Scope -ScopeId $script:ScopeIP -Force
        Write-Host "Scope anterior eliminado."
    }

    Add-DhcpServerv4Scope `
        -Name $script:ScopeNombre `
        -StartRange $script:RangoInicio `
        -EndRange $script:RangoFin `
        -SubnetMask $script:Mascara `
        -LeaseDuration ([TimeSpan]::FromDays($script:LeaseTime)) `
        -State Active

    Set-DhcpServerv4OptionValue `
        -ScopeId $script:ScopeIP `
        -Router $script:Gateway `
        -DnsServer $script:DNS

    Restart-Service -Name DHCPServer
    Write-Host "DHCP configurado y servicio reiniciado."
}
