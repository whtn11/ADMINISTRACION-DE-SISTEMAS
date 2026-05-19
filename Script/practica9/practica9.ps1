#Requires -RunAsAdministrator

. "$PSScriptRoot\lib\helpers.ps1"

$rutaLib = "$PSScriptRoot\lib"

. "$rutaLib\T9_AD.ps1"
. "$rutaLib\T9_Delegacion.ps1"
. "$rutaLib\T9_Politicas.ps1"
. "$rutaLib\T9_MFA.ps1"

function Ver-Usuarios-Roles {
    Clear-Host
    Write-Host "========== Usuarios y Roles Actuales =========="
    Write-Host ""

    $usuarios = @()
    $usuarios += Get-ADUser -Filter * -SearchBase "OU=Cuates,$DC_PATH" -ErrorAction SilentlyContinue
    $usuarios += Get-ADUser -Filter * -SearchBase "OU=NoCuates,$DC_PATH" -ErrorAction SilentlyContinue

    $ou_map = @{}
    foreach ($u in (Get-ADUser -Filter * -SearchBase "OU=Cuates,$DC_PATH" -ErrorAction SilentlyContinue)) {
        $ou_map[$u.SamAccountName] = "Cuates"
    }
    foreach ($u in (Get-ADUser -Filter * -SearchBase "OU=NoCuates,$DC_PATH" -ErrorAction SilentlyContinue)) {
        $ou_map[$u.SamAccountName] = "NoCuates"
    }

    $formato = "{0,-20} {1,-12} {2}"
    Write-Host ($formato -f "Usuario", "OU", "Rol actual")
    Write-Host ($formato -f "-------", "--", "----------")

    foreach ($u in $usuarios) {
        $rol = Obtener-Rol -Sam $u.SamAccountName
        $rolTexto = if ($rol) { $rol } else { "(sin rol)" }
        $ou = $ou_map[$u.SamAccountName]
        Write-Host ($formato -f $u.SamAccountName, $ou, $rolTexto)
    }

    Write-Host ""
}

function Seleccionar-Usuario {
    $usuarios = @()
    $usuarios += Get-ADUser -Filter * -SearchBase "OU=Cuates,$DC_PATH" -ErrorAction SilentlyContinue
    $usuarios += Get-ADUser -Filter * -SearchBase "OU=NoCuates,$DC_PATH" -ErrorAction SilentlyContinue

    if ($usuarios.Count -eq 0) {
        Print-Err "No hay usuarios en Cuates ni NoCuates."
        return $null
    }

    Write-Host ""
    Write-Host "Usuarios disponibles:"
    for ($i = 0; $i -lt $usuarios.Count; $i++) {
        $rol = Obtener-Rol -Sam $usuarios[$i].SamAccountName
        $rolTexto = if ($rol) { "[$rol]" } else { "[sin rol]" }
        Write-Host "  [$($i+1)] $($usuarios[$i].SamAccountName) $rolTexto"
    }

    Write-Host ""
    $sel = Read-Host "Selecciona usuario (numero)"

    if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $usuarios.Count) {
        return $usuarios[[int]$sel - 1].SamAccountName
    }

    Print-Err "Seleccion invalida."
    return $null
}

function Seleccionar-Rol {
    Write-Host ""
    Write-Host "Roles disponibles:"
    Write-Host "  [1] identidad  - Crear/Eliminar/Modificar/Reset usuarios en Cuates y NoCuates"
    Write-Host "  [2] storage    - Gestionar cuotas y apantallamiento FSRM"
    Write-Host "  [3] politicas  - Lectura en todo el dominio + GPOs"
    Write-Host "  [4] auditoria  - Lectura en todo el dominio + logs de seguridad"
    Write-Host ""

    $sel = Read-Host "Selecciona rol (numero)"

    switch ($sel) {
        "1" { return "identidad" }
        "2" { return "storage"   }
        "3" { return "politicas" }
        "4" { return "auditoria" }
        default {
            Print-Err "Seleccion invalida."
            return $null
        }
    }
}

function Habilitar-Vista-Perfiles {
    Print-Info "Forzando acceso de administrador a perfiles moviles..."

    if (-not (Test-Path "C:\Perfiles")) {
        Print-Warn "La carpeta C:\Perfiles no existe."
        return
    }

    icacls "C:\Perfiles" /grant "Administradores:(OI)(CI)R" /T | Out-Null
    Print-Ok "Acceso de lectura para administrador habilitado en C:\Perfiles."

    Write-Host ""
    Print-Info "Perfiles encontrados:"
    Get-ChildItem "C:\Perfiles" | ForEach-Object { Write-Host "  $($_.Name)" }
}


function Administrar-Usuarios {
    do {
        Clear-Host
        Write-Host "========== Administrar Usuarios =========="
        Write-Host ""
        Write-Host "  [1] Ver usuarios y sus roles actuales"
        Write-Host "  [2] Asignar rol a usuario"
        Write-Host "  [3] Eliminar rol de usuario"
        Write-Host "  [4] Cambiar rol de usuario"
        Write-Host "  [5] Habilitar vista de perfiles moviles"
        Write-Host "  [6] Volver"
        Write-Host ""

        $op = Read-Host "Selecciona una opcion"

        switch ($op) {
            "1" {
                Ver-Usuarios-Roles
                Read-Host "`nEnter para continuar"
            }
            "2" {
                Clear-Host
                Write-Host "========== Asignar Rol =========="
                $sam = Seleccionar-Usuario
                if (-not $sam) { Read-Host "`nEnter para continuar"; break }
                $rol = Seleccionar-Rol
                if (-not $rol) { Read-Host "`nEnter para continuar"; break }
                Write-Host ""
                Asignar-Rol -Sam $sam -Rol $rol
                Read-Host "`nEnter para continuar"
            }
            "3" {
                Clear-Host
                Write-Host "========== Eliminar Rol =========="
                $sam = Seleccionar-Usuario
                if (-not $sam) { Read-Host "`nEnter para continuar"; break }
                Write-Host ""
                Eliminar-Rol -Sam $sam
                Read-Host "`nEnter para continuar"
            }
            "4" {
                Clear-Host
                Write-Host "========== Cambiar Rol =========="
                $sam = Seleccionar-Usuario
                if (-not $sam) { Read-Host "`nEnter para continuar"; break }
                $rol = Seleccionar-Rol
                if (-not $rol) { Read-Host "`nEnter para continuar"; break }
                Write-Host ""
                Cambiar-Rol -Sam $sam -NuevoRol $rol
                Read-Host "`nEnter para continuar"
            }
            "5" {
                Clear-Host
                Habilitar-Vista-Perfiles
                Read-Host "`nEnter para continuar"
            }
            "6" { return }
            default { Print-Warn "Opcion no valida."; Start-Sleep -Seconds 1 }
        }
    } while ($true)
}

function Crear-Usuario-Completo {
    Clear-Host
    Write-Host "========== Crear Nuevo Usuario =========="
    Write-Host ""

    $nombre   = Read-Host "Nombre"
    $apellido = Read-Host "Apellido"
    $usuario  = Read-Host "Nombre de usuario (SamAccountName)"

    Write-Host ""
    Write-Host "  [1] Cuates"
    Write-Host "  [2] NoCuates"
    $ouSel = Read-Host "OU"
    $ou = switch ($ouSel) {
        "1" { "Cuates"   }
        "2" { "NoCuates" }
        default { $null  }
    }
    if (-not $ou) { Print-Err "OU invalida."; return }

    $pass = Read-Host "Contrasena" -AsSecureString

    $existe = Get-ADUser -Filter "SamAccountName -eq '$usuario'" -ErrorAction SilentlyContinue
    if ($existe) { Print-Err "El usuario '$usuario' ya existe en AD."; return }

    Print-Info "Creando usuario en AD..."
    try {
        New-ADUser `
            -Name              "$nombre $apellido" `
            -GivenName         $nombre `
            -Surname           $apellido `
            -SamAccountName    $usuario `
            -UserPrincipalName "$usuario@$DOMINIO" `
            -AccountPassword   $pass `
            -Path              "OU=$ou,$DC_PATH" `
            -Enabled           $true `
            -ProfilePath       "\\$env:COMPUTERNAME\Perfiles\$usuario"
        Print-Ok "Usuario '$usuario' creado en OU=$ou."
    } catch {
        Print-Err "Error al crear usuario: $_"
        return
    }

    $carpetaPerfil = "C:\Perfiles\$usuario"
    if (-not (Test-Path $carpetaPerfil)) {
        New-Item -Path $carpetaPerfil -ItemType Directory -Force | Out-Null
    }
    icacls $carpetaPerfil /grant "${usuario}:(OI)(CI)F"      | Out-Null
    icacls $carpetaPerfil /grant "Administradores:(OI)(CI)R" | Out-Null
    Print-Ok "Carpeta de perfil creada con permisos: $carpetaPerfil"

    if (-not (Test-Path $MULTIOTP_EXE)) {
        Print-Warn "multiOTP no encontrado. El usuario fue creado en AD pero sin token OTP."
        return
    }

    Print-Info "Generando token OTP..."
    $clave = Generar-ClaveTOTP
    & $MULTIOTP_EXE -createga $usuario $clave | Out-Null

    if ($LASTEXITCODE -eq 11) {
        & $MULTIOTP_EXE -set $usuario prefix-pin=0 | Out-Null

        ""                                       | Out-File $RUTA_CLAVES -Append -Encoding UTF8
        "Usuario: $usuario"                      | Out-File $RUTA_CLAVES -Append -Encoding UTF8
        "  Nombre en GA: $usuario@$DOMINIO_MFA" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
        "  Clave:        $clave"                 | Out-File $RUTA_CLAVES -Append -Encoding UTF8

        Write-Host ""
        Write-Host "========== Token para Google Authenticator ==========" -ForegroundColor Yellow
        Write-Host "  Usuario : $usuario"
        Write-Host "  Clave   : " -NoNewline
        Write-Host $clave -ForegroundColor Green
        Write-Host "  Tipo    : Basada en tiempo (TOTP)"
        Write-Host "=====================================================" -ForegroundColor Yellow
        Print-Ok "Token guardado en: $RUTA_CLAVES"
    } else {
        Print-Err "Error al registrar token OTP (codigo: $LASTEXITCODE)."
    }
}


function Mostrar-Menu {
    do {
        Clear-Host
        Write-Host "========== Practica 09: Seguridad, Delegacion y MFA =========="
        Write-Host ""
        Write-Host "  [1] Inicializar entorno"
        Write-Host "  [2] Configurar Active Directory"
        Write-Host "  [3] Configurar Delegacion RBAC"
        Write-Host "  [4] Configurar Politicas y Auditoria"
        Write-Host "  [5] Configurar MFA"
        Write-Host "  [6] Generar Reporte de Auditoria"
        Write-Host "  [7] Administrar Usuarios"
        Write-Host "  [8] Crear nuevo usuario"
        Write-Host "  [9] Salir"
        Write-Host ""

        $op = Read-Host "Selecciona una opcion"

        switch ($op) {
            "1" { Clear-Host; Inicializar-Entorno;    Read-Host "`nEnter para continuar" }
            "2" { Clear-Host; Configurar-AD;          Read-Host "`nEnter para continuar" }
            "3" { Clear-Host; Configurar-Delegacion;  Read-Host "`nEnter para continuar" }
            "4" { Clear-Host; Configurar-Politicas;   Read-Host "`nEnter para continuar" }
            "5" { Clear-Host; Configurar-MFA;         Read-Host "`nEnter para continuar" }
            "6" { Clear-Host; Generar-Reporte;        Read-Host "`nEnter para continuar" }
            "7" { Administrar-Usuarios }
            "8" { Crear-Usuario-Completo;             Read-Host "`nEnter para continuar" }
            "9" { Clear-Host; Write-Host "Saliendo..."; return }
            default { Print-Warn "Opcion no valida."; Start-Sleep -Seconds 1 }
        }
    } while ($true)
}

Mostrar-Menu
