$RUTA_REPORTE = "$env:USERPROFILE\reporte_accesos.txt"


function Crear-Grupos {
    Print-Info "Verificando grupos de seguridad..."

    $existe = Get-ADGroup -Filter "Name -eq 'GrupoAdmins'" -ErrorAction SilentlyContinue
    if (-not $existe) {
        New-ADGroup -Name "GrupoAdmins" `
            -GroupScope    Global `
            -GroupCategory Security `
            -Path          $DC_PATH
        Print-Ok "Grupo creado: GrupoAdmins"
    } else {
        Print-Warn "Grupo ya existe: GrupoAdmins (se omite)"
    }

    $existe = Get-ADGroup -Filter "Name -eq 'GrupoUsuarios'" -ErrorAction SilentlyContinue
    if (-not $existe) {
        New-ADGroup -Name "GrupoUsuarios" `
            -GroupScope    Global `
            -GroupCategory Security `
            -Path          $DC_PATH
        Print-Ok "Grupo creado: GrupoUsuarios"
    } else {
        Print-Warn "Grupo ya existe: GrupoUsuarios (se omite)"
    }
}


function Poblar-Grupos {
    Print-Info "Agregando usuarios a GrupoUsuarios..."

    $usuarios = @()
    $usuarios += Get-ADUser -Filter * -SearchBase "OU=Cuates,$DC_PATH" -ErrorAction SilentlyContinue
    $usuarios += Get-ADUser -Filter * -SearchBase "OU=NoCuates,$DC_PATH" -ErrorAction SilentlyContinue

    foreach ($u in $usuarios) {
        try {
            Add-ADGroupMember -Identity "GrupoUsuarios" -Members $u.SamAccountName -ErrorAction Stop
            Print-Ok "  $($u.SamAccountName) - GrupoUsuarios"
        } catch {
            Print-Warn "  $($u.SamAccountName) ya es miembro (se omite)"
        }
    }
}


function Configurar-FGPP {
    Print-Info "Configurando politicas de contrasena (FGPP)..."

    $existe = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq 'FGPP-Admins'" -ErrorAction SilentlyContinue
    if (-not $existe) {
        New-ADFineGrainedPasswordPolicy `
            -Name                        "FGPP-Admins" `
            -Precedence                  10 `
            -MinPasswordLength           12 `
            -ComplexityEnabled           $true `
            -ReversibleEncryptionEnabled $false `
            -PasswordHistoryCount        5 `
            -MaxPasswordAge              "60.00:00:00" `
            -MinPasswordAge              "1.00:00:00" `
            -LockoutThreshold            3 `
            -LockoutDuration             "00:30:00" `
            -LockoutObservationWindow    "00:30:00"
        Print-Ok "FGPP-Admins creada (minimo 12 chars)"
    } else {
        Print-Warn "FGPP-Admins ya existe (se omite)"
    }

    $existe = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq 'FGPP-Usuarios'" -ErrorAction SilentlyContinue
    if (-not $existe) {
        New-ADFineGrainedPasswordPolicy `
            -Name                        "FGPP-Usuarios" `
            -Precedence                  20 `
            -MinPasswordLength           8 `
            -ComplexityEnabled           $true `
            -ReversibleEncryptionEnabled $false `
            -PasswordHistoryCount        3 `
            -MaxPasswordAge              "90.00:00:00" `
            -MinPasswordAge              "1.00:00:00" `
            -LockoutThreshold            3 `
            -LockoutDuration             "00:30:00" `
            -LockoutObservationWindow    "00:30:00"
        Print-Ok "FGPP-Usuarios creada (minimo 8 chars)"
    } else {
        Print-Warn "FGPP-Usuarios ya existe (se omite)"
    }

    Print-Info "Asignando politicas a grupos..."

    try {
        Add-ADFineGrainedPasswordPolicySubject -Identity "FGPP-Admins" -Subjects "GrupoAdmins" -ErrorAction Stop
        Print-Ok "FGPP-Admins asignada a GrupoAdmins"
    } catch {
        Print-Warn "FGPP-Admins ya estaba asignada (se omite)"
    }

    try {
        Add-ADFineGrainedPasswordPolicySubject -Identity "FGPP-Usuarios" -Subjects "GrupoUsuarios" -ErrorAction Stop
        Print-Ok "FGPP-Usuarios asignada a GrupoUsuarios"
    } catch {
        Print-Warn "FGPP-Usuarios ya estaba asignada (se omite)"
    }
}


function Configurar-Auditoria {
    Print-Info "Activando auditoria de eventos..."

    auditpol /set /subcategory:"Inicio de sesión" /success:enable /failure:enable | Out-Null
    Print-Ok "Auditoria activada: Inicio de sesion (aciertos y errores)"

    auditpol /set /subcategory:"Sistema de archivos" /success:enable /failure:enable | Out-Null
    Print-Ok "Auditoria activada: Sistema de archivos (aciertos y errores)"
}


function Generar-Reporte {
    Print-Info "Generando reporte de accesos denegados..."
    Print-Info "Buscando eventos ID 4625 en el log de seguridad..."

    $eventos = Get-WinEvent -LogName Security `
        -FilterXPath "*[System[EventID=4625]]" `
        -MaxEvents 10 `
        -ErrorAction SilentlyContinue

    if (-not $eventos) {
        Print-Warn "No se encontraron eventos de acceso denegado (ID 4625)."
        return
    }

    $eventos |
    Select-Object TimeCreated, Id, Message |
    ForEach-Object {
        [PSCustomObject]@{
            Fecha   = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
            EventID = $_.Id
            Mensaje = $_.Message.Split("`n")[0]
        }
    } |
    Format-Table -AutoSize |
    Out-File $RUTA_REPORTE -Encoding UTF8

    Print-Ok "Reporte generado en: $RUTA_REPORTE"
    Write-Host ""
    Get-Content $RUTA_REPORTE
}


function Configurar-Politicas {
    Clear-Host
    Write-Host "========== Configuracion de Politicas y Auditoria =========="
    Write-Host ""

    Crear-Grupos
    Write-Host ""
    Poblar-Grupos
    Write-Host ""
    Configurar-FGPP
    Write-Host ""
    Configurar-Auditoria

    Write-Host ""
    Print-Ok "Politicas y auditoria configuradas correctamente."
    Write-Host ""
}
