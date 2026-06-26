#Requires -RunAsAdministrator

. "$PSScriptRoot\lib\helpers.ps1"

$DOMINIO       = "empresa.local"
$IP_SERVIDOR   = "192.168.10.150"
$MULTIOTP_EXE  = "C:\Program Files\multiOTP\multiotp.exe"
$MULTIOTP_MSI  = "$PSScriptRoot\lib\multiOTP.msi"
$VCREDIST_EXE  = "$PSScriptRoot\lib\VC_redist.x64.exe"
$MULTIOTP_REG  = "Registry::HKEY_CLASSES_ROOT\CLSID\{FCEFDFAB-B0A1-4C4D-8B2B-4FF4E0A3D978}"


function Configurar-Timezone-Cliente {
    if ((Get-TimeZone).Id -ne "US Mountain Standard Time") {
        Set-TimeZone -Id "US Mountain Standard Time"
        Print-Ok "Zona horaria configurada: US Mountain Standard Time (UTC-7, Sinaloa)."
    } else {
        Print-Warn "Zona horaria ya configurada (se omite)."
    }
    w32tm /resync /force 2>&1 | Out-Null
    Print-Ok "Hora sincronizada."
}


function Unir-Dominio {
    Print-Info "Verificando estado del dominio..."

    Configurar-Timezone-Cliente
    Write-Host ""

    $equipo = Get-WmiObject Win32_ComputerSystem

    if ($equipo.PartOfDomain) {
        Write-Host ""
        if ($equipo.Domain -eq $DOMINIO) {
            Print-Warn "Este equipo ya esta en el dominio $DOMINIO."
        } else {
            Print-Warn "Este equipo esta en el dominio: $($equipo.Domain)"
        }
        Write-Host ""
        Write-Host "  [1] Salir del dominio actual y unirse a $DOMINIO"
        Write-Host "  [2] Cancelar"
        Write-Host ""
        $opDom = Read-Host "Selecciona una opcion"

        if ($opDom -ne "1") {
            Print-Warn "Operacion cancelada."
            return
        }

        Print-Info "Introduce las credenciales de administrador del dominio actual."
        $dominioNetbios = $equipo.Domain.Split(".")[0].ToUpper()
        $credActual = Get-Credential -UserName "$dominioNetbios\eromero" -Message "Credenciales para salir de $($equipo.Domain)"

        Print-Info "Saliendo del dominio $($equipo.Domain)..."
        try {
            Remove-Computer -UnjoinDomainCredential $credActual -WorkgroupName "WORKGROUP" -Force -ErrorAction Stop
            Print-Ok "Salido del dominio correctamente."
        } catch {
            Print-Err "No se pudo salir del dominio: $_"
            Print-Info "Asegurate de ingresar el usuario como DOMINIO\usuario (ej: EMPRESA\eromero)"
            return
        }
        Write-Host ""
    }

    Write-Host ""
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
    $sel  = Read-Host "Selecciona el adaptador de red interna (red_sistemas)$hint"

    if ([string]::IsNullOrWhiteSpace($sel) -and $defaultIdx) {
        $sel = "$defaultIdx"
    }

    if ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $adaptadores.Count) {
        Print-Err "Seleccion invalida."
        return
    }

    $adaptador = $adaptadores[[int]$sel - 1]
    Print-Ok "Adaptador seleccionado: $($adaptador.Name)"

    Write-Host ""
    $ipCliente = Read-Host "IP estatica para este cliente (Enter para usar 192.168.10.200)"
    if ([string]::IsNullOrWhiteSpace($ipCliente)) { $ipCliente = "192.168.10.200" }

    Print-Info "Configurando IP estatica $ipCliente en $($adaptador.Name)..."
    $ipActual = Get-NetIPAddress -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($ipActual) {
        Remove-NetIPAddress -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    }
    Remove-NetRoute -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 `
        -IPAddress $ipCliente -PrefixLength 24 -DefaultGateway "192.168.10.1" | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $adaptador.ifIndex -ServerAddresses $IP_SERVIDOR
    Print-Ok "IP: $ipCliente  |  Gateway: 192.168.10.1  |  DNS: $IP_SERVIDOR"

    Write-Host ""
    Print-Info "Probando conectividad con el servidor..."
    if (Test-Connection -ComputerName $IP_SERVIDOR -Count 1 -Quiet) {
        Print-Ok "Servidor accesible."
    } else {
        Print-Err "No se puede alcanzar el servidor en $IP_SERVIDOR."
        Print-Info "Verifica que el servidor este encendido y en la misma red interna."
        return
    }

    Write-Host ""
    Print-Info "Introduce las credenciales de administrador del dominio."
    $credencial = Get-Credential -Message "Credenciales para unirse a $DOMINIO (ej: EMPRESA\eromero)"

    Print-Info "Uniendo equipo al dominio $DOMINIO..."
    try {
        Add-Computer -DomainName $DOMINIO -Credential $credencial -Force -ErrorAction Stop
        Print-Ok "Equipo unido correctamente a $DOMINIO."
        Print-Warn "El equipo se reiniciara para aplicar los cambios."
        Read-Host "`nEnter para reiniciar"
        Restart-Computer -Force
    } catch {
        Print-Err "No se pudo unir al dominio: $_"
        Print-Info "Verifica que el servidor este encendido y accesible en $IP_SERVIDOR."
    }
}


function Instalar-RSAT {
    Print-Info "Verificando instalacion de RSAT (herramientas AD)..."
    $rsat = Get-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0 -ErrorAction SilentlyContinue
    if ($rsat -and $rsat.State -eq "Installed") {
        Print-Warn "RSAT ya instalado (se omite)."
        return
    }
    Print-Info "Instalando RSAT..."
    Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0 | Out-Null
    Print-Ok "RSAT instalado."
}


function Instalar-MultiOTP {
    Print-Info "Verificando instalacion de multiOTP..."

    $instalado = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" |
                 Where-Object { $_.DisplayName -like "*multiOTP*" } |
                 Select-Object -First 1

    if ($instalado) {
        Print-Warn "multiOTP ya instalado: $($instalado.DisplayVersion) (se omite)"
        return
    }

    if (-not (Test-Path $VCREDIST_EXE)) {
        Print-Err "No se encontro: $VCREDIST_EXE"
        Print-Info "Verifica que VC_redist.x64.exe y multiOTP.msi esten en practica9\lib\"
        return
    }

    if (-not (Test-Path $MULTIOTP_MSI)) {
        Print-Err "No se encontro: $MULTIOTP_MSI"
        return
    }

    Print-Info "Instalando Visual C++ Redistributable..."
    Start-Process $VCREDIST_EXE -ArgumentList "/quiet /norestart" -Wait
    Print-Ok "Visual C++ instalado."

    Print-Info "Instalando multiOTP Credential Provider..."
    Start-Process "msiexec.exe" -ArgumentList "/i `"$MULTIOTP_MSI`" /quiet /norestart" -Wait
    Print-Ok "multiOTP instalado."
}


function Configurar-CredentialProvider {
    Print-Info "Configurando Credential Provider..."

    if (-not (Test-Path $MULTIOTP_EXE)) {
        Print-Err "multiotp.exe no encontrado. Ejecuta primero la opcion 2."
        return
    }

    & $MULTIOTP_EXE -config max-block-failures=3      | Out-Null
    & $MULTIOTP_EXE -config failure-delayed-time=1800 | Out-Null
    Print-Ok "Lockout: 3 intentos fallidos, bloqueo 30 minutos."

    try {
        Set-ItemProperty -Path $MULTIOTP_REG -Name "cpus_logon"        -Value "0e" -ErrorAction Stop
        Set-ItemProperty -Path $MULTIOTP_REG -Name "cpus_unlock"       -Value "0e" -ErrorAction Stop
        Set-ItemProperty -Path $MULTIOTP_REG -Name "two_step_hide_otp" -Value 1    -ErrorAction Stop
        Set-ItemProperty -Path $MULTIOTP_REG -Name "multiOTPUPNFormat" -Value 0    -ErrorAction Stop
        Print-Ok "Credential Provider configurado en registro."
    } catch {
        Print-Err "Error al escribir en registro: $_"
        Print-Warn "Verifica que multiOTP este correctamente instalado."
    }
}


function Importar-Tokens-Servidor {
    if (-not (Test-Path $MULTIOTP_EXE)) {
        Print-Err "multiotp.exe no encontrado. Ejecuta primero la opcion 2."
        return
    }

    $ip = Read-Host "IP del servidor (Enter para usar $IP_SERVIDOR)"
    if ([string]::IsNullOrWhiteSpace($ip)) { $ip = $IP_SERVIDOR }

    if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
        Print-Err "IP no valida: $ip"
        return
    }

    Print-Info "Introduce las credenciales de administrador del servidor."
    $usuarioRed = Read-Host "Usuario (ej: EMPRESA\eromero)"
    $passseg    = Read-Host "Contrasena" -AsSecureString
    $passTxt    = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                      [Runtime.InteropServices.Marshal]::SecureStringToBSTR($passseg))

    Print-Info "Estableciendo conexion con el servidor..."
    net use "\\$ip\c$" $passTxt /user:$usuarioRed 2>&1 | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Print-Err "No se pudo conectar a \\$ip\c$"
        Print-Info "Verifica la IP y las credenciales."
        return
    }
    Print-Ok "Conexion establecida."

    $rutaRemota = "\\$ip\c$\Users\Administrador\claves_mfa.txt"

    if (-not (Test-Path $rutaRemota)) {
        Print-Err "No se encontro el archivo en: $rutaRemota"
        Print-Info "Verifica que la opcion 5 del servidor se haya ejecutado."
        net use "\\$ip\c$" /delete 2>&1 | Out-Null
        return
    }

    & $MULTIOTP_EXE -config server-url="" | Out-Null
    Print-Ok "Modo local activado (sin servidor remoto)."

    $lineas      = Get-Content $rutaRemota
    $usuarioMFA  = $null
    $registrados = 0
    $omitidos    = 0

    Write-Host ""
    Print-Info "Registrando tokens..."
    Write-Host ""

    foreach ($linea in $lineas) {
        if ($linea -match '^Usuario:\s+(.+)$') {
            $usuarioMFA = $matches[1].Trim()
        }

        if ($linea -match '^\s+Clave:\s+(.+)$' -and $usuarioMFA) {
            $clave = $matches[1].Trim()

            & $MULTIOTP_EXE -createga $usuarioMFA $clave | Out-Null

            if ($LASTEXITCODE -eq 11) {
                & $MULTIOTP_EXE -set $usuarioMFA prefix-pin=0 | Out-Null
                Print-Ok "  $usuarioMFA - token registrado"
                $registrados++
            } elseif ($LASTEXITCODE -eq 22) {
                Print-Warn "  $usuarioMFA - ya registrado (se omite)"
                $omitidos++
            } else {
                Print-Err "  $usuarioMFA - error (codigo: $LASTEXITCODE)"
            }

            $usuarioMFA = $null
        }
    }

    net use "\\$ip\c$" /delete 2>&1 | Out-Null

    Write-Host ""
    Print-Info "Resumen: $registrados registrado(s), $omitidos omitido(s)."
    Print-Warn "Reinicia el cliente para que los cambios apliquen."
}


function Mostrar-Instrucciones {
    Clear-Host
    Write-Host "========== Instrucciones de uso ==========" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "ORDEN de ejecucion (primera vez):"
    Write-Host "  1) Unir al dominio  ->  el equipo se reinicia"
    Write-Host "  2) Instalar multiOTP"
    Write-Host "  3) Configurar Credential Provider"
    Write-Host "  4) Importar tokens del servidor"
    Write-Host "  5) Reiniciar"
    Write-Host ""
    Write-Host "La opcion 1 configura el DNS hacia $IP_SERVIDOR y une"
    Write-Host "el equipo al dominio $DOMINIO."
    Write-Host ""
    Write-Host "La opcion 4 se conecta al servidor, lee las claves MFA"
    Write-Host "y las registra localmente. Solo necesitas la IP del servidor"
    Write-Host "y credenciales de administrador de dominio."
    Write-Host ""
    Write-Host "Al iniciar sesion usa: EMPRESA\eromero"
    Write-Host "Se pedira contrasena y luego el codigo de Google Authenticator."
    Write-Host ""
}


function Limpiar-Usuarios-MultiOTP {
    if (-not (Test-Path $MULTIOTP_EXE)) {
        Print-Err "multiotp.exe no encontrado."
        return
    }

    $usersDir = "C:\Program Files\multiOTP\users"

    if (-not (Test-Path $usersDir)) {
        Print-Warn "No se encontro la carpeta de usuarios de multiOTP."
        return
    }

    $archivos = Get-ChildItem $usersDir -File -ErrorAction SilentlyContinue

    if (-not $archivos -or $archivos.Count -eq 0) {
        Print-Warn "No hay usuarios registrados en multiOTP."
        return
    }

    Write-Host ""
    Print-Info "Usuarios registrados en multiOTP:"
    foreach ($f in $archivos) { Write-Host "  - $($f.BaseName)" }

    Write-Host ""
    $confirm = Read-Host "Confirmar eliminacion de todos los usuarios (s/n)"
    if ($confirm -ne "s") {
        Print-Warn "Operacion cancelada."
        return
    }

    Write-Host ""
    $eliminados = 0
    foreach ($f in $archivos) {
        $sam = $f.BaseName
        & $MULTIOTP_EXE -delete $sam | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Print-Ok "  $sam - eliminado"
            $eliminados++
        } else {
            Print-Err "  $sam - error al eliminar (codigo: $LASTEXITCODE)"
        }
    }

    Write-Host ""
    Print-Info "Resumen: $eliminados usuario(s) eliminado(s)."
    Print-Warn "Vuelve a ejecutar la opcion 4 para reimportar los tokens del servidor."
}


function Salir-Dominio {
    $equipo = Get-WmiObject Win32_ComputerSystem

    if (-not $equipo.PartOfDomain) {
        Print-Warn "Este equipo no esta en ningun dominio."
        return
    }

    Print-Info "Dominio actual: $($equipo.Domain)"
    Write-Host ""
    Write-Host "  [1] Salir normalmente (servidor disponible)"
    Write-Host "  [2] Forzar salida (servidor apagado o no disponible)"
    Write-Host "  [3] Cancelar"
    Write-Host ""
    $modo = Read-Host "Selecciona una opcion"

    if ($modo -eq "3" -or [string]::IsNullOrWhiteSpace($modo)) {
        Print-Warn "Operacion cancelada."
        return
    }

    Print-Info "Saliendo del dominio $($equipo.Domain)..."

    if ($modo -eq "1") {
        $dominioNetbios = $equipo.Domain.Split(".")[0].ToUpper()
        $cred = Get-Credential -UserName "$dominioNetbios\eromero" -Message "Credenciales para salir de $($equipo.Domain)"
        $pass = $cred.GetNetworkCredential().Password
        $result = $equipo.UnjoinDomainOrWorkgroup($pass, $cred.UserName, 0)
    } else {
        $result = $equipo.UnjoinDomainOrWorkgroup($null, $null, 0)
    }

    if ($result.ReturnValue -eq 0) {
        Print-Ok "Salido del dominio correctamente."
        Print-Warn "Reinicia el equipo para aplicar los cambios."
        Read-Host "`nEnter para reiniciar"
        Restart-Computer -Force
    } else {
        Print-Err "Error al salir del dominio (codigo: $($result.ReturnValue))."
    }
}


function Mostrar-Menu {
    do {
        Clear-Host
        Write-Host "========== Practica 09: Configuracion MFA - Cliente =========="
        Write-Host ""
        Write-Host "  [1] Unir al dominio empresa.local"
        Write-Host "  [2] Instalar multiOTP Credential Provider"
        Write-Host "  [3] Configurar Credential Provider"
        Write-Host "  [4] Importar tokens del servidor"
        Write-Host "  [5] Ver instrucciones"
        Write-Host "  [6] Limpiar usuarios multiOTP"
        Write-Host "  [7] Salir del dominio actual"
        Write-Host "  [8] Salir"
        Write-Host ""

        $op = Read-Host "Selecciona una opcion"

        switch ($op) {
            "1" { Clear-Host; Unir-Dominio;                  Read-Host "`nEnter para continuar" }
            "2" { Clear-Host; Instalar-RSAT; Write-Host ""; Instalar-MultiOTP; Read-Host "`nEnter para continuar" }
            "3" { Clear-Host; Configurar-CredentialProvider; Read-Host "`nEnter para continuar" }
            "4" { Clear-Host; Importar-Tokens-Servidor;      Read-Host "`nEnter para continuar" }
            "5" { Mostrar-Instrucciones;                     Read-Host "`nEnter para continuar" }
            "6" { Clear-Host; Limpiar-Usuarios-MultiOTP;     Read-Host "`nEnter para continuar" }
            "7" { Clear-Host; Salir-Dominio;                 Read-Host "`nEnter para continuar" }
            "8" { Clear-Host; Write-Host "Saliendo..."; return }
            default { Print-Warn "Opcion no valida."; Start-Sleep -Seconds 1 }
        }
    } while ($true)
}

Mostrar-Menu
