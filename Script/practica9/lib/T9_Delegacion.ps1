$ROLES_VALIDOS = @("identidad", "storage", "politicas", "auditoria")

$GRUPOS_ROLES = @{
    "identidad" = "RolIdentidad"
    "storage"   = "RolStorage"
    "politicas" = "RolPoliticas"
    "auditoria" = "RolAuditoria"
}


function Crear-GruposRoles {
    foreach ($grupo in $GRUPOS_ROLES.Values) {
        $existe = Get-ADGroup -Filter "Name -eq '$grupo'" -ErrorAction SilentlyContinue
        if (-not $existe) {
            New-ADGroup -Name $grupo -GroupScope Global -GroupCategory Security -Path $DC_PATH | Out-Null
            Print-Ok "Grupo de rol creado: $grupo"
        }
    }
}


function Obtener-Rol {
    param([string]$Sam)
    foreach ($rol in $ROLES_VALIDOS) {
        $grupo = $GRUPOS_ROLES[$rol]
        $miembros = Get-ADGroupMember -Identity $grupo -ErrorAction SilentlyContinue
        if ($miembros | Where-Object { $_.SamAccountName -eq $Sam }) {
            return $rol
        }
    }
    return $null
}


function Aplicar-Permisos {
    param([string]$Sam, [string]$Rol)

    switch ($Rol) {
        "identidad" {
            foreach ($ou in @("Cuates", "NoCuates")) {
                $path = "OU=$ou,$DC_PATH"
                dsacls $path /G "EMPRESA\${Sam}:CC;user"                        | Out-Null
                dsacls $path /G "EMPRESA\${Sam}:DC;user"                        | Out-Null
                dsacls $path /G "EMPRESA\${Sam}:WP"                    /I:S     | Out-Null
                dsacls $path /G "EMPRESA\${Sam}:CA;Reset Password;user" /I:S    | Out-Null
                dsacls $path /G "EMPRESA\${Sam}:WP;lockoutTime;user"    /I:S    | Out-Null
            }
        }
        "storage" {
            foreach ($ou in @("Cuates", "NoCuates")) {
                $path = "OU=$ou,$DC_PATH"
                dsacls $path /D "EMPRESA\${Sam}:CA;Reset Password;user" /I:S    | Out-Null
            }
            dsacls $DC_PATH /G "EMPRESA\${Sam}:GR" /I:S | Out-Null
            net localgroup "Administradores" "EMPRESA\$Sam" /add 2>$null | Out-Null
        }
        "politicas" {
            dsacls $DC_PATH /G "EMPRESA\${Sam}:GR" /I:S | Out-Null
            foreach ($ou in @("Cuates", "NoCuates")) {
                $path = "OU=$ou,$DC_PATH"
                dsacls $path /D "EMPRESA\${Sam}:WP;;user" /I:S | Out-Null
            }
        }
        "auditoria" {
            dsacls $DC_PATH /G "EMPRESA\${Sam}:GR" /I:S | Out-Null
            foreach ($ou in @("Cuates", "NoCuates")) {
                $path = "OU=$ou,$DC_PATH"
                dsacls $path /D "EMPRESA\${Sam}:WP;;user" /I:S | Out-Null
            }
            net localgroup "Lectores del registro de eventos" "EMPRESA\$Sam" /add 2>$null | Out-Null
        }
    }
}


function Revocar-Permisos {
    param([string]$Sam, [string]$Rol)

    switch ($Rol) {
        "identidad" {
            foreach ($ou in @("Cuates", "NoCuates")) {
                $path = "OU=$ou,$DC_PATH"
                dsacls $path /R "EMPRESA\$Sam" | Out-Null
            }
        }
        "storage" {
            foreach ($ou in @("Cuates", "NoCuates")) {
                $path = "OU=$ou,$DC_PATH"
                dsacls $path /R "EMPRESA\$Sam" | Out-Null
            }
            dsacls $DC_PATH /R "EMPRESA\$Sam" | Out-Null
            net localgroup "Administradores" "EMPRESA\$Sam" /delete 2>$null | Out-Null
        }
        "politicas" {
            dsacls $DC_PATH /R "EMPRESA\$Sam" | Out-Null
            foreach ($ou in @("Cuates", "NoCuates")) {
                $path = "OU=$ou,$DC_PATH"
                dsacls $path /R "EMPRESA\$Sam" | Out-Null
            }
        }
        "auditoria" {
            dsacls $DC_PATH /R "EMPRESA\$Sam" | Out-Null
            foreach ($ou in @("Cuates", "NoCuates")) {
                $path = "OU=$ou,$DC_PATH"
                dsacls $path /R "EMPRESA\$Sam" | Out-Null
            }
            net localgroup "Lectores del registro de eventos" "EMPRESA\$Sam" /delete 2>$null | Out-Null
        }
    }
}


function Asignar-Rol {
    param([string]$Sam, [string]$Rol)

    $rolActual = Obtener-Rol -Sam $Sam
    if ($rolActual) {
        Print-Err "$Sam ya tiene el rol '$rolActual'. Usa cambiar rol."
        return
    }

    $grupo = $GRUPOS_ROLES[$Rol]
    Add-ADGroupMember -Identity $grupo -Members $Sam -ErrorAction SilentlyContinue
    Add-ADGroupMember -Identity "GrupoAdmins" -Members $Sam -ErrorAction SilentlyContinue
    Aplicar-Permisos -Sam $Sam -Rol $Rol

    Print-Ok "$Sam - Rol '$Rol' asignado."
    Print-Warn "El usuario debe cerrar sesion y volver a entrar para que los cambios apliquen."
}


function Eliminar-Rol {
    param([string]$Sam)

    $rolActual = Obtener-Rol -Sam $Sam
    if (-not $rolActual) {
        Print-Warn "$Sam no tiene ningun rol asignado."
        return
    }

    $grupo = $GRUPOS_ROLES[$rolActual]
    Remove-ADGroupMember -Identity $grupo -Members $Sam -Confirm:$false -ErrorAction SilentlyContinue
    Remove-ADGroupMember -Identity "GrupoAdmins" -Members $Sam -Confirm:$false -ErrorAction SilentlyContinue
    Revocar-Permisos -Sam $Sam -Rol $rolActual

    Print-Ok "$Sam - Rol '$rolActual' eliminado."
    Print-Warn "El usuario debe cerrar sesion y volver a entrar para que los cambios apliquen."
}


function Cambiar-Rol {
    param([string]$Sam, [string]$NuevoRol)

    $rolActual = Obtener-Rol -Sam $Sam
    if (-not $rolActual) {
        Print-Warn "$Sam no tiene rol. Usa asignar rol."
        return
    }

    if ($rolActual -eq $NuevoRol) {
        Print-Warn "$Sam ya tiene el rol '$NuevoRol'."
        return
    }

    $grupoActual = $GRUPOS_ROLES[$rolActual]
    Remove-ADGroupMember -Identity $grupoActual -Members $Sam -Confirm:$false -ErrorAction SilentlyContinue
    Revocar-Permisos -Sam $Sam -Rol $rolActual

    $grupoNuevo = $GRUPOS_ROLES[$NuevoRol]
    Add-ADGroupMember -Identity $grupoNuevo -Members $Sam -ErrorAction SilentlyContinue
    Aplicar-Permisos -Sam $Sam -Rol $NuevoRol

    Print-Ok "$Sam - Rol cambiado de '$rolActual' a '$NuevoRol'."
    Print-Warn "El usuario debe cerrar sesion y volver a entrar para que los cambios apliquen."
}


function Configurar-FSRM-Base {
    Print-Info "Creando estructura FSRM base..."

    if (-not (Test-Path "C:\Perfiles")) {
        New-Item -Path "C:\Perfiles" -ItemType Directory -Force | Out-Null
        Print-Ok "Carpeta C:\Perfiles creada."
    }

    if (-not (Get-FsrmQuotaTemplate -Name "Cuota-100MB" -ErrorAction SilentlyContinue)) {
        New-FsrmQuotaTemplate -Name "Cuota-100MB" -Size 100MB | Out-Null
        Print-Ok "Plantilla Cuota-100MB creada."
    }

    if (-not (Get-FsrmQuota -Path "C:\Perfiles" -ErrorAction SilentlyContinue)) {
        New-FsrmQuota -Path "C:\Perfiles" -Size 100MB | Out-Null
        Print-Ok "Cuota 100MB aplicada en C:\Perfiles."
    }

    if (-not (Get-FsrmFileGroup -Name "Archivos-Prohibidos" -ErrorAction SilentlyContinue)) {
        New-FsrmFileGroup -Name "Archivos-Prohibidos" -IncludePattern @("*.mp3","*.mp4","*.exe","*.avi","*.mkv") | Out-Null
        Print-Ok "Grupo Archivos-Prohibidos creado."
    }

    if (-not (Get-FsrmFileScreenTemplate -Name "Pantalla-Prohibidos" -ErrorAction SilentlyContinue)) {
        New-FsrmFileScreenTemplate -Name "Pantalla-Prohibidos" -Active -IncludeGroup @("Archivos-Prohibidos") | Out-Null
        Print-Ok "Plantilla Pantalla-Prohibidos creada."
    }

    if (-not (Get-FsrmFileScreen -Path "C:\Perfiles" -ErrorAction SilentlyContinue)) {
        New-FsrmFileScreen -Path "C:\Perfiles" -Template "Pantalla-Prohibidos" | Out-Null
        Print-Ok "Apantallamiento aplicado en C:\Perfiles."
    }
}


function Configurar-RDP-Admins {
    Print-Info "Configurando permisos RDP para usuarios con rol..."

    try {
        Add-ADGroupMember -Identity "Usuarios de escritorio remoto" -Members "GrupoAdmins" -ErrorAction Stop
    } catch {}

    $secpolPath = "C:\secpol_admins.txt"
    $sdbPath    = "C:\secpol_admins.sdb"
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
    Print-Ok "Permisos RDP configurados."
}


function Configurar-Delegacion {
    Clear-Host
    Write-Host "========== Configuracion de Delegacion RBAC =========="
    Write-Host ""

    Crear-GruposRoles
    Write-Host ""
    Configurar-FSRM-Base
    Write-Host ""
    Configurar-RDP-Admins

    Write-Host ""
    Print-Ok "Delegacion configurada."
    Print-Info "Usa la opcion 6 para asignar roles a los usuarios."
    Write-Host ""
}
