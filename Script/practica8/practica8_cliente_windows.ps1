#Requires -RunAsAdministrator

. "$PSScriptRoot\lib\helpers.ps1"

$DOMINIO     = "empresa.local"
$IP_SERVIDOR = "192.168.10.10"


function Configurar-Red {
    Print-Info "Adaptadores de red disponibles:"
    $adaptadores = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }

    for ($i = 0; $i -lt $adaptadores.Count; $i++) {
        $ip = (Get-NetIPAddress -InterfaceIndex $adaptadores[$i].ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
        Write-Host "  [$($i+1)] $($adaptadores[$i].Name)  -  IP actual: $ip"
    }

    $defaultIdx = $null
    for ($i = 0; $i -lt $adaptadores.Count; $i++) {
        if ($adaptadores[$i].Name -eq "Ethernet 2") { $defaultIdx = $i + 1; break }
    }

    $hint = if ($defaultIdx) { " (Enter para Ethernet 2)" } else { "" }
    $sel  = Read-Host "Selecciona el adaptador de red interna$hint"

    if ([string]::IsNullOrWhiteSpace($sel) -and $defaultIdx) { $sel = "$defaultIdx" }

    if ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $adaptadores.Count) {
        Print-Err "Seleccion invalida."
        return $false
    }

    $adaptador = $adaptadores[[int]$sel - 1]

    $ipCliente = Read-Host "IP estatica para este cliente (Enter para 192.168.10.201)"
    if ([string]::IsNullOrWhiteSpace($ipCliente)) { $ipCliente = "192.168.10.201" }

    Print-Info "Configurando IP $ipCliente en $($adaptador.Name)..."
    $ipActual = Get-NetIPAddress -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($ipActual) {
        Remove-NetIPAddress -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    }
    Remove-NetRoute -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue

    New-NetIPAddress -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 `
        -IPAddress $ipCliente -PrefixLength 24 -DefaultGateway "192.168.10.1" | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $adaptador.ifIndex -ServerAddresses $IP_SERVIDOR
    Print-Ok "IP: $ipCliente  |  Gateway: 192.168.10.1  |  DNS: $IP_SERVIDOR"
    return $true
}


function Probar-Conectividad {
    Print-Info "Probando conectividad con el servidor ($IP_SERVIDOR)..."
    if (Test-Connection -ComputerName $IP_SERVIDOR -Count 2 -Quiet) {
        Print-Ok "Servidor alcanzable."
        return $true
    }
    Print-Err "No se puede alcanzar el servidor en $IP_SERVIDOR."
    Print-Info "Verifica que el servidor este encendido y en la misma red interna."
    return $false
}


function Unir-Dominio {
    Clear-Host
    Write-Host "========== Unir al dominio $DOMINIO ==========" -ForegroundColor Yellow
    Write-Host ""

    $equipo = Get-WmiObject Win32_ComputerSystem

    if ($equipo.PartOfDomain -and $equipo.Domain -eq $DOMINIO) {
        Print-Warn "Este equipo ya esta en el dominio $DOMINIO."
        return
    }

    if (-not (Configurar-Red))   { return }
    Write-Host ""
    if (-not (Probar-Conectividad)) { return }

    Write-Host ""
    Print-Info "Introduce las credenciales del administrador del dominio."
    $cred = Get-Credential -Message "Credenciales para unirse a $DOMINIO (ej: EMPRESA\eromero)"

    Print-Info "Uniendo equipo al dominio..."
    try {
        Add-Computer -DomainName $DOMINIO -Credential $cred -Force -ErrorAction Stop
        Print-Ok "Equipo unido a $DOMINIO correctamente."
        Print-Warn "El equipo se reiniciara ahora."
        Read-Host "`nEnter para reiniciar"
        Restart-Computer -Force
    } catch {
        Print-Err "No se pudo unir al dominio: $_"
    }
}


function Salir-Dominio {
    Clear-Host
    Write-Host "========== Salir del dominio ==========" -ForegroundColor Yellow
    Write-Host ""

    $equipo = Get-WmiObject Win32_ComputerSystem
    if (-not $equipo.PartOfDomain) {
        Print-Warn "Este equipo no esta en ningun dominio."
        return
    }

    Print-Info "Dominio actual: $($equipo.Domain)"
    Write-Host ""
    Write-Host "  [1] Salir normalmente (servidor disponible)"
    Write-Host "  [2] Forzar salida (servidor apagado)"
    Write-Host "  [3] Cancelar"
    Write-Host ""
    $modo = Read-Host "Selecciona una opcion"

    if ($modo -eq "3" -or [string]::IsNullOrWhiteSpace($modo)) {
        Print-Warn "Operacion cancelada."
        return
    }

    if ($modo -eq "1") {
        $dominioNetbios = $equipo.Domain.Split(".")[0].ToUpper()
        $cred   = Get-Credential -UserName "$dominioNetbios\eromero" -Message "Credenciales para salir del dominio"
        $pass   = $cred.GetNetworkCredential().Password
        $result = $equipo.UnjoinDomainOrWorkgroup($pass, $cred.UserName, 0)
    } else {
        $result = $equipo.UnjoinDomainOrWorkgroup($null, $null, 0)
    }

    if ($result.ReturnValue -eq 0) {
        Print-Ok "Salido del dominio correctamente."
        Read-Host "`nEnter para reiniciar"
        Restart-Computer -Force
    } else {
        Print-Err "Error al salir del dominio (codigo: $($result.ReturnValue))."
    }
}


function Ver-Estado {
    Clear-Host
    Write-Host "========== Estado del equipo ==========" -ForegroundColor Yellow
    Write-Host ""

    $equipo = Get-WmiObject Win32_ComputerSystem
    if ($equipo.PartOfDomain) {
        Print-Ok "Dominio: $($equipo.Domain)"
    } else {
        Print-Warn "No esta en ningun dominio."
    }

    $adaptadores = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    foreach ($a in $adaptadores) {
        $ip  = (Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
        $dns = (Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses -join ", "
        Print-Info "$($a.Name)  IP: $ip  DNS: $dns"
    }

    Write-Host ""
    Print-Info "Probando resolucion DNS de $DOMINIO..."
    try {
        $res = Resolve-DnsName $DOMINIO -ErrorAction Stop | Select-Object -First 1
        Print-Ok "DNS resuelve $DOMINIO -> $($res.IPAddress)"
    } catch {
        Print-Err "No se pudo resolver $DOMINIO - verifica el DNS apuntando al servidor."
    }
}


function Mostrar-Menu {
    do {
        Clear-Host
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host "   Practica 8 - Cliente Windows         " -ForegroundColor Red
        Write-Host "   Dominio: $DOMINIO                   " -ForegroundColor DarkGray
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host "  [1] Unirse al dominio"
        Write-Host "  [2] Salir del dominio"
        Write-Host "  [3] Ver estado del equipo"
        Write-Host "  [4] Salir"
        Write-Host "========================================" -ForegroundColor Yellow

        $op = Read-Host "Selecciona una opcion"

        switch ($op) {
            "1" { Unir-Dominio;    Read-Host "`nEnter para continuar" }
            "2" { Salir-Dominio;   Read-Host "`nEnter para continuar" }
            "3" { Ver-Estado;      Read-Host "`nEnter para continuar" }
            "4" { Write-Host "Saliendo..."; return }
            default { Print-Warn "Opcion no valida."; Start-Sleep -Seconds 1 }
        }
    } while ($true)
}

Mostrar-Menu
