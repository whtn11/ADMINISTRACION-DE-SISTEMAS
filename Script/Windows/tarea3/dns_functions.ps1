# ============================================================
# TAREA 3 - Funciones DNS Windows
# Archivo: dns_functions.ps1
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

function Verificar-IPFija {
    $interfaz = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    $ipActual = Get-NetIPAddress -InterfaceAlias $interfaz.Name -AddressFamily IPv4 | Select-Object -First 1

    if ($ipActual.PrefixOrigin -eq "Dhcp" -or $ipActual.IPAddress -like "169.254.*") {
        Write-Host "IP dinamica detectada." -ForegroundColor Yellow
        $confirmar = Read-Host "Deseas configurar IP fija? (S/N)"
        if ($confirmar -match '^[Ss]$') {
            $nuevaIP = Read-Host "IP Estatica"
            $prefijo = Read-Host "Prefijo (ej: 24)"
            $gateway = Read-Host "Gateway"
            New-NetIPAddress -InterfaceAlias $interfaz.Name -IPAddress $nuevaIP -PrefixLength $prefijo -DefaultGateway $gateway
            Write-Host "IP configurada: $nuevaIP" -ForegroundColor Green
        }
    } else {
        Write-Host "IP fija ya configurada: $($ipActual.IPAddress)" -ForegroundColor Green
    }
}

function Instalar-DNS {
    $dns = Get-WindowsFeature -Name DNS
    if ($dns.InstallState -eq "Installed") {
        Write-Host "DNS ya esta instalado." -ForegroundColor Green
    } else {
        Write-Host "Instalando DNS..." -ForegroundColor Yellow
        Install-WindowsFeature -Name DNS -IncludeManagementTools
        Write-Host "DNS instalado correctamente." -ForegroundColor Green
    }
}

function Configurar-Zona {
    $zona = "reprobados.com"
    $zonaExiste = Get-DnsServerZone -Name $zona -ErrorAction SilentlyContinue
    if ($zonaExiste) {
        Write-Host "La zona $zona ya existe." -ForegroundColor Green
    } else {
        Add-DnsServerPrimaryZone -Name $zona -ZoneFile "$zona.dns"
        Write-Host "Zona $zona creada." -ForegroundColor Green
    }
}

function Crear-Registros {
    $zona = "reprobados.com"
    $ipCliente = Read-Host "IP del cliente para $zona"
    while (-not (Validar-IP $ipCliente)) {
        Write-Host "IP invalida." -ForegroundColor Red
        $ipCliente = Read-Host "IP del cliente"
    }

    try { Add-DnsServerResourceRecordA -Name "@" -ZoneName $zona -IPv4Address $ipCliente -ErrorAction Stop } catch {}
    try { Add-DnsServerResourceRecordA -Name "www" -ZoneName $zona -IPv4Address $ipCliente -ErrorAction Stop } catch {}

    Write-Host "Registros A creados: $zona -> $ipCliente" -ForegroundColor Green
    Write-Host "Registros A creados: www.$zona -> $ipCliente" -ForegroundColor Green
}

function Ver-Estado-DNS {
    Get-Service -Name DNS | Select-Object Name, Status
    Get-DnsServerZone | Select-Object ZoneName, ZoneType, IsAutoCreated
}

function Probar-DNS {
    Write-Host "--- nslookup reprobados.com ---"
    nslookup reprobados.com 127.0.0.1
    Write-Host "--- ping www.reprobados.com ---"
    ping www.reprobados.com -n 2
}
