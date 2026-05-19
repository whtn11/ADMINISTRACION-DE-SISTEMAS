$DOMINIO      = "empresa.local"
$DC_PATH      = "DC=empresa,DC=local"
$CSV_USUARIOS = "$PSScriptRoot\usuarios.csv"


function Configurar-IP-Servidor {
    Print-Info "Verificando IP estatica en Ethernet 2..."

    $adaptador = Get-NetAdapter | Where-Object { $_.Name -eq "Ethernet 2" -and $_.Status -eq "Up" }
    if (-not $adaptador) {
        Print-Warn "Adaptador 'Ethernet 2' no encontrado o no activo."
        return
    }

    $ipActual = Get-NetIPAddress -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($ipActual -and $ipActual.IPAddress -eq "192.168.10.150") {
        Print-Warn "IP 192.168.10.150 ya configurada en Ethernet 2 (se omite)."
        return
    }

    if ($ipActual) {
        Remove-NetIPAddress -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    }
    Remove-NetRoute -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 `
        -IPAddress "192.168.10.150" -PrefixLength 24 -DefaultGateway "192.168.10.1" | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $adaptador.ifIndex -ServerAddresses "127.0.0.1"
    Print-Ok "IP: 192.168.10.150  |  Gateway: 192.168.10.1  |  DNS: 127.0.0.1"
}


function Configurar-Timezone-Servidor {
    Print-Info "Verificando zona horaria..."

    if ((Get-TimeZone).Id -ne "US Mountain Standard Time") {
        Set-TimeZone -Id "US Mountain Standard Time"
        Print-Ok "Zona horaria configurada: US Mountain Standard Time (UTC-7, Sinaloa)."
    } else {
        Print-Warn "Zona horaria ya configurada (se omite)."
    }

    w32tm /resync /force 2>&1 | Out-Null
    Print-Ok "Hora sincronizada."
}


function Inicializar-Entorno {
    Write-Host ""
    Write-Host "========== Inicializar Entorno =========="

    Configurar-IP-Servidor
    Write-Host ""
    Configurar-Timezone-Servidor
    Write-Host ""

    $rol = Get-WindowsFeature -Name AD-Domain-Services
    if ($rol.InstallState -ne "Installed") {
        Print-Info "Instalando rol AD-Domain-Services..."
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
        Print-Ok "Rol AD instalado."
    } else {
        Print-Warn "AD-Domain-Services ya instalado (se omite)."
    }

    $fsrm = Get-WindowsFeature -Name FS-Resource-Manager
    if ($fsrm.InstallState -ne "Installed") {
        Print-Info "Instalando FSRM..."
        Install-WindowsFeature -Name FS-Resource-Manager -IncludeManagementTools
        Print-Ok "FSRM instalado."
    } else {
        Print-Warn "FSRM ya instalado (se omite)."
    }

    $domainRole = (Get-WmiObject Win32_ComputerSystem).DomainRole
    if ($domainRole -ge 4) {
        Print-Warn "Ya es Controlador de Dominio (se omite promocion)."
        return
    }

    Print-Info "Promoviendo a Controlador de Dominio..."
    $safePass = ConvertTo-SecureString "SafeMode@Pass123!" -AsPlainText -Force

    Install-ADDSForest `
        -DomainName                    $DOMINIO `
        -DomainNetBiosName             "EMPRESA" `
        -InstallDns `
        -SafeModeAdministratorPassword $safePass `
        -Force

    Print-Warn "El servidor se reiniciara. Ejecuta el script de nuevo y elige opcion 2."
}


function Crear-OUs {
    Print-Info "Verificando Unidades Organizativas..."
    foreach ($ou in @("Cuates", "NoCuates")) {
        $existe = Get-ADOrganizationalUnit -Filter "Name -eq '$ou'" -ErrorAction SilentlyContinue
        if (-not $existe) {
            New-ADOrganizationalUnit -Name $ou -Path $DC_PATH
            Print-Ok "OU creada: $ou"
        } else {
            Print-Warn "OU ya existe: $ou (se omite)"
        }
    }
}


function Crear-UsuariosCSV {
    if (-not (Test-Path $CSV_USUARIOS)) {
        Print-Err "No se encontro el CSV: $CSV_USUARIOS"
        return
    }

    $usuarios = Import-Csv $CSV_USUARIOS
    $creados  = 0
    $omitidos = 0

    Print-Info "Leyendo CSV: $($usuarios.Count) usuario(s)..."
    Write-Host ""

    foreach ($u in $usuarios) {
        if ($u.OU -notin @("Cuates", "NoCuates")) {
            Print-Warn "OU invalida '$($u.OU)' para '$($u.Usuario)'. Solo Cuates o NoCuates."
            $omitidos++
            continue
        }

        $existe = Get-ADUser -Filter "SamAccountName -eq '$($u.Usuario)'" -ErrorAction SilentlyContinue
        if (-not $existe) {
            $pass = ConvertTo-SecureString $u.Contrasena -AsPlainText -Force
            New-ADUser `
                -Name              "$($u.Nombre) $($u.Apellido)" `
                -GivenName         $u.Nombre `
                -Surname           $u.Apellido `
                -SamAccountName    $u.Usuario `
                -UserPrincipalName "$($u.Usuario)@$DOMINIO" `
                -AccountPassword   $pass `
                -Path              "OU=$($u.OU),$DC_PATH" `
                -Enabled           $true
            Print-Ok "Creado: $($u.Usuario) - $($u.OU)"
            $creados++
        } else {
            Print-Warn "Ya existe: $($u.Usuario) (se omite)"
            $omitidos++
        }
    }

    Write-Host ""
    Print-Info "Resumen: $creados creado(s), $omitidos omitido(s)."
}


function Habilitar-RDP-Usuarios {
    Print-Info "Habilitando RDP para todos los usuarios..."

    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
        -Name "fDenyTSConnections" -Value 0
    Enable-NetFirewallRule -DisplayGroup "Escritorio remoto" -ErrorAction SilentlyContinue

    $usuarios = @()
    $usuarios += Get-ADUser -Filter * -SearchBase "OU=Cuates,$DC_PATH" -ErrorAction SilentlyContinue
    $usuarios += Get-ADUser -Filter * -SearchBase "OU=NoCuates,$DC_PATH" -ErrorAction SilentlyContinue

    foreach ($u in $usuarios) {
        try {
            Add-ADGroupMember -Identity "Usuarios de escritorio remoto" -Members $u.SamAccountName -ErrorAction Stop
        } catch {}
        net localgroup "Usuarios de escritorio remoto" "EMPRESA\$($u.SamAccountName)" /add 2>$null | Out-Null
    }

    $secpolPath = "C:\secpol_rdp.txt"
    $sdbPath    = "C:\secpol_rdp.sdb"
    secedit /export /cfg $secpolPath | Out-Null

    $content = Get-Content $secpolPath
    if (-not ($content -like "*S-1-5-32-555*")) {
        $content = $content -replace `
            "SeRemoteInteractiveLogonRight = \*S-1-5-32-544", `
            "SeRemoteInteractiveLogonRight = *S-1-5-32-544,*S-1-5-32-555"
        $content | Set-Content $secpolPath
        secedit /configure /db $sdbPath /cfg $secpolPath /quiet | Out-Null
    }

    Remove-Item $secpolPath -ErrorAction SilentlyContinue
    Remove-Item $sdbPath    -ErrorAction SilentlyContinue

    Print-Ok "RDP habilitado para todos los usuarios."
}


function Crear-AdminDleyva {
    Print-Info "Verificando usuario administrador eromero..."

    $existe = Get-ADUser -Filter "SamAccountName -eq 'eromero'" -ErrorAction SilentlyContinue
    if (-not $existe) {
        $pass = Read-Host "Contrasena para eromero" -AsSecureString
        New-ADUser `
            -Name              "eromero" `
            -SamAccountName    "eromero" `
            -UserPrincipalName "eromero@$DOMINIO" `
            -AccountPassword   $pass `
            -Enabled           $true
        Print-Ok "eromero creado."
    } else {
        Print-Warn "eromero ya existe en AD."
    }

    $enDomainAdmins = Get-ADGroupMember "Admins. del dominio" -ErrorAction SilentlyContinue |
                      Where-Object { $_.SamAccountName -eq "eromero" }
    if (-not $enDomainAdmins) {
        Add-ADGroupMember -Identity "Admins. del dominio" -Members "eromero"
        Print-Ok "eromero agregado a Admins. del dominio."
    } else {
        Print-Warn "eromero ya es miembro de Admins. del dominio (se omite)."
    }
}


function Configurar-PerfilesMoviles {
    Print-Info "Configurando perfiles moviles..."

    if (-not (Test-Path "C:\Perfiles")) {
        New-Item -Path "C:\Perfiles" -ItemType Directory -Force | Out-Null
        Print-Ok "Carpeta C:\Perfiles creada."
    }

    icacls "C:\Perfiles" /grant "Usuarios del dominio:(OI)(CI)F" /T | Out-Null
    icacls "C:\Perfiles" /grant "Administradores:(OI)(CI)R" /T | Out-Null
    Print-Ok "Permisos NTFS configurados en C:\Perfiles."

    $share = Get-SmbShare -Name "Perfiles" -ErrorAction SilentlyContinue
    if (-not $share) {
        New-SmbShare -Name "Perfiles" -Path "C:\Perfiles" -FullAccess "Todos" | Out-Null
        Print-Ok "Carpeta compartida como \\$env:COMPUTERNAME\Perfiles"
    } else {
        Print-Warn "Compartido 'Perfiles' ya existe (se omite)."
    }

    $usuarios = @("eromero")
    if (Test-Path $CSV_USUARIOS) {
        $usuarios += (Import-Csv $CSV_USUARIOS).Usuario
    }

    foreach ($sam in $usuarios) {
        $existe = Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue
        if ($existe) {
            Set-ADUser -Identity $sam -ProfilePath "\\$env:COMPUTERNAME\Perfiles\$sam"
            Print-Ok "  $sam - perfil movil asignado."
        }
    }
}


function Configurar-AD {
    Clear-Host
    Write-Host "========== Configuracion de Active Directory =========="
    Write-Host ""

    Crear-AdminDleyva
    Write-Host ""
    Crear-OUs
    Write-Host ""
    Crear-UsuariosCSV
    Write-Host ""
    Habilitar-RDP-Usuarios
    Write-Host ""
    Configurar-PerfilesMoviles

    Write-Host ""
    Print-Ok "Active Directory configurado correctamente."
    Write-Host ""
}
