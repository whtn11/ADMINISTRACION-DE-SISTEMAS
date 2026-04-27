# ==============================================================================
# http_functions.ps1 - Biblioteca de funciones para servidores HTTP (Windows)
# Tarea 6 - Administración de Sistemas
# Grupo: 3-02 | Alumno: eromero
# ==============================================================================

# Forzar encoding UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

# ---- Colores / Mensajes ----
function Msg-Ok($msg)   { Write-Host "[OK]    $msg" -ForegroundColor Green }
function Msg-Err($msg)  { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Msg-Info($msg) { Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Msg-Warn($msg) { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }

# ==============================================================================
# UTILIDADES GENERALES
# ==============================================================================

function Verificar-Administrador {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Msg-Err "Este script debe ejecutarse como Administrador."
        exit 1
    }
}

function Verificar-Chocolatey {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Msg-Info "Chocolatey no encontrado. Instalando..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Msg-Ok "Chocolatey instalado correctamente."
    } else {
        Msg-Ok "Chocolatey ya está disponible."
    }
}

# ==============================================================================
# VALIDACIONES
# ==============================================================================

function Validar-Puerto($puerto) {
    if ($puerto -notmatch '^\d+$') {
        Msg-Err "El puerto debe ser numérico."
        return $false
    }
    $p = [int]$puerto
    if ($p -lt 1 -or $p -gt 65535) {
        Msg-Err "Puerto fuera de rango válido (1-65535)."
        return $false
    }
    $reservados = @(22, 25, 53, 110, 143, 3306, 5432, 3389, 445, 139)
    if ($reservados -contains $p) {
        Msg-Err "El puerto $p está reservado para otro servicio del sistema."
        return $false
    }
    return $true
}

function Puerto-EnUso($puerto) {
    $resultado = Test-NetConnection -ComputerName localhost -Port $puerto -WarningAction SilentlyContinue
    return $resultado.TcpTestSucceeded
}

function Pedir-Puerto {
    while ($true) {
        $puerto = Read-Host "Ingrese el puerto de escucha [ej: 80, 8080, 8888]"
        $puerto = $puerto.Trim()
        if ([string]::IsNullOrWhiteSpace($puerto)) {
            Msg-Err "El puerto no puede estar vacío."
            continue
        }
        if (-not (Validar-Puerto $puerto)) { continue }
        if (Puerto-EnUso $puerto) {
            Msg-Err "El puerto $puerto ya está en uso."
            netstat -ano | Select-String ":$puerto "
            continue
        }
        return [int]$puerto
    }
}

# ==============================================================================
# VERSIONES DINÁMICAS
# ==============================================================================

function Obtener-Versiones-Choco($paquete) {
    Msg-Info "Consultando versiones disponibles de '$paquete' en Chocolatey..."
    $info = choco info $paquete --all 2>&1 | Where-Object { $_ -match '^\s[\d]' }
    if ($info.Count -eq 0) {
        Msg-Warn "No se encontraron versiones para '$paquete'."
        return @()
    }
    $versiones = $info | ForEach-Object { ($_ -split '\s+')[1] } | Select-Object -Unique | Select-Object -First 5
    return $versiones
}

function Seleccionar-Version($paquete) {
    $versiones = Obtener-Versiones-Choco $paquete
    if ($versiones.Count -eq 0) {
        Msg-Warn "Se usará la versión más reciente disponible (latest)."
        return "latest"
    }
    Write-Host ""
    Write-Host "  Versiones disponibles para '$paquete':" -ForegroundColor Cyan
    for ($i = 0; $i -lt $versiones.Count; $i++) {
        $etiqueta = if ($i -eq 0) { "(Latest)" } elseif ($i -eq $versiones.Count - 1) { "(LTS/Más antigua)" } else { "" }
        Write-Host "  [$($i+1)] $($versiones[$i]) $etiqueta"
    }
    Write-Host ""
    while ($true) {
        $sel = Read-Host "Seleccione una versión [1-$($versiones.Count)]"
        if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $versiones.Count) {
            return $versiones[[int]$sel - 1]
        }
        Msg-Err "Selección inválida."
    }
}

# ==============================================================================
# IIS (OBLIGATORIO)
# ==============================================================================

function Instalar-IIS {
    Msg-Info "Verificando instalación de IIS..."
    $feature = Get-WindowsFeature -Name Web-Server
    if ($feature.Installed) {
        Msg-Warn "IIS ya está instalado."
    } else {
        Msg-Info "Instalando IIS y herramientas de administración..."
        Install-WindowsFeature -Name Web-Server, Web-Mgmt-Tools, Web-Mgmt-Console -IncludeManagementTools | Out-Null
        Msg-Ok "IIS instalado correctamente."
    }
    # Asegurar que el servicio esté corriendo
    Start-Service -Name W3SVC -ErrorAction SilentlyContinue
    Set-Service  -Name W3SVC -StartupType Automatic
}

function Configurar-Puerto-IIS($puerto) {
    Msg-Info "Configurando IIS en puerto $puerto..."
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Eliminar binding anterior en puerto 80 si se cambia
    $bindingActual = Get-WebBinding -Name "Default Web Site" | Where-Object { $_.bindingInformation -match ":80:" }
    if ($bindingActual -and $puerto -ne 80) {
        Remove-WebBinding -Name "Default Web Site" -BindingInformation "*:80:" -Protocol http
        Msg-Info "Binding anterior en puerto 80 eliminado."
    }

    # Agregar nuevo binding
    $existente = Get-WebBinding -Name "Default Web Site" | Where-Object { $_.bindingInformation -match ":${puerto}:" }
    if (-not $existente) {
        New-WebBinding -Name "Default Web Site" -Protocol http -Port $puerto -IPAddress "*"
        Msg-Ok "IIS configurado en puerto $puerto."
    } else {
        Msg-Warn "IIS ya tiene binding en puerto $puerto."
    }
}

function Aplicar-Seguridad-IIS {
    Msg-Info "Aplicando configuraciones de seguridad en IIS..."
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Eliminar encabezado X-Powered-By
    try {
        Remove-WebConfigurationProperty -PSPath "IIS:\" -Filter "system.webServer/httpProtocol/customHeaders" `
            -Name "." -AtElement @{name="X-Powered-By"} -ErrorAction SilentlyContinue
        Msg-Ok "Encabezado X-Powered-By eliminado."
    } catch { Msg-Warn "No se pudo eliminar X-Powered-By (puede no existir)." }

    # Ocultar versión del servidor (Request Filtering)
    Set-WebConfigurationProperty -PSPath "IIS:\" `
        -Filter "system.webServer/security/requestFiltering" `
        -Name "removeServerHeader" -Value $true -ErrorAction SilentlyContinue
    Msg-Ok "Encabezado Server ocultado en IIS."

    # Deshabilitar métodos peligrosos (TRACE, DELETE)
    Add-WebConfigurationProperty -PSPath "IIS:\" `
        -Filter "system.webServer/security/requestFiltering/verbs" `
        -Name "." -Value @{verb="TRACE"; allowed="false"} -ErrorAction SilentlyContinue
    Add-WebConfigurationProperty -PSPath "IIS:\" `
        -Filter "system.webServer/security/requestFiltering/verbs" `
        -Name "." -Value @{verb="DELETE"; allowed="false"} -ErrorAction SilentlyContinue
    Msg-Ok "Métodos TRACE y DELETE bloqueados."

    # Agregar security headers via web.config
    $webConfigPath = "C:\inetpub\wwwroot\web.config"

    if (-not (Test-Path $webConfigPath)) {
        $xmlBase = '<?xml version="1.0" encoding="UTF-8"?><configuration><system.webServer><httpProtocol><customHeaders /></httpProtocol></system.webServer></configuration>'
        Set-Content -Path $webConfigPath -Value $xmlBase -Encoding UTF8
    }

    [xml]$wc = Get-Content $webConfigPath -Raw
    $headersNode = $wc.SelectSingleNode("//customHeaders")

    if ($null -ne $headersNode) {
        $secHeaders = @(
            @{name="X-Frame-Options";        value="SAMEORIGIN"},
            @{name="X-Content-Type-Options"; value="nosniff"}
        )
        foreach ($h in $secHeaders) {
            $existe = $false
            foreach ($child in $headersNode.ChildNodes) {
                if ($child.GetAttribute("name") -eq $h.name) { $existe = $true; break }
            }
            if (-not $existe) {
                $el = $wc.CreateElement("add")
                $el.SetAttribute("name",  $h.name)
                $el.SetAttribute("value", $h.value)
                $headersNode.AppendChild($el) | Out-Null
            }
        }
        $wc.Save($webConfigPath)
        Msg-Ok "Security headers aplicados (X-Frame-Options, X-Content-Type-Options)."
    } else {
        Msg-Warn "No se pudo localizar customHeaders en web.config."
    }
}

function Crear-Pagina-IIS($version, $puerto) {
    $ruta = "C:\inetpub\wwwroot\index.html"
    $contenido = @"
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>IIS - Tarea 6</title></head>
<body style="font-family:Arial;background:#003366;color:white;padding:40px;text-align:center">
  <h1>Servidor: IIS (Internet Information Services)</h1>
  <p><strong>Version:</strong> $version</p>
  <p><strong>Puerto:</strong> $puerto</p>
  <p><em>Tarea 6 - Administracion de Sistemas - Grupo 3-02</em></p>
</body>
</html>
"@
    Set-Content -Path $ruta -Value $contenido -Encoding UTF8
    Msg-Ok "Página index.html creada en $ruta"
}

function Configurar-Firewall-IIS($puerto) {
    Msg-Info "Configurando firewall para IIS en puerto $puerto..."
    # Cerrar puerto 80 si se cambia
    if ($puerto -ne 80) {
        Remove-NetFirewallRule -DisplayName "HTTP-IIS-80" -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName "HTTP-IIS-80-BLOCK" -Direction Inbound `
            -LocalPort 80 -Protocol TCP -Action Block -ErrorAction SilentlyContinue | Out-Null
    }
    # Abrir puerto seleccionado
    Remove-NetFirewallRule -DisplayName "HTTP-IIS-$puerto" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "HTTP-IIS-$puerto" -Direction Inbound `
        -LocalPort $puerto -Protocol TCP -Action Allow | Out-Null
    Msg-Ok "Regla de firewall creada para puerto $puerto."
}

function Instalar-Configurar-IIS {
    Instalar-IIS
    $puerto = Pedir-Puerto
    Configurar-Puerto-IIS $puerto
    Aplicar-Seguridad-IIS
    $featureInfo = Get-WindowsFeature Web-Server; $version = if ($featureInfo.AdditionalInfo -is [string] -and $featureInfo.AdditionalInfo -ne "") { $featureInfo.AdditionalInfo.Split(" ")[0] } else { "10.0" }
    if ([string]::IsNullOrWhiteSpace($version)) { $version = "10.0" }
    Crear-Pagina-IIS $version $puerto
    Configurar-Firewall-IIS $puerto
    Restart-Service W3SVC
    Msg-Ok "IIS configurado y corriendo en puerto $puerto."
    Write-Host ""
    Msg-Info "Verificando con curl (encabezados):"
    curl.exe -I "http://localhost:$puerto" 2>&1 | Select-String "Server|Content|HTTP"
}

# ==============================================================================
# APACHE PARA WINDOWS (via Chocolatey)
# ==============================================================================

function Instalar-Configurar-Apache {
    Verificar-Chocolatey
    Msg-Info "=== Instalación de Apache para Windows ==="

    $version = Seleccionar-Version "apache-httpd"
    $puerto  = Pedir-Puerto

    Msg-Info "Instalando Apache versión $version..."
    if ($version -eq "latest") {
        choco install apache-httpd -y --no-progress 2>&1 | Out-Null
    } else {
        choco install apache-httpd --version $version -y --no-progress 2>&1 | Out-Null
    }
    Msg-Ok "Apache instalado."

    # Ruta típica de Apache instalado por Chocolatey
    $apacheConf = "C:\tools\Apache24\conf\httpd.conf"
    if (-not (Test-Path $apacheConf)) {
        $apacheConf = (Get-ChildItem "C:\*\Apache*\conf\httpd.conf" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    }

    if (Test-Path $apacheConf) {
        # Cambiar puerto
        (Get-Content $apacheConf) -replace 'Listen \d+', "Listen $puerto" | Set-Content $apacheConf
        Msg-Ok "Puerto configurado en $puerto (httpd.conf)"

        # Seguridad: ocultar versión
        $secLines = @("`nServerTokens Prod", "ServerSignature Off")
        Add-Content $apacheConf $secLines
        Msg-Ok "ServerTokens Prod y ServerSignature Off aplicados."
    } else {
        Msg-Warn "No se encontró httpd.conf. Configuración manual requerida."
    }

    # Página index
    $wwwroot = "C:\tools\Apache24\htdocs"
    if (Test-Path $wwwroot) {
        $contenido = @"
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Apache - Tarea 6</title></head>
<body style="font-family:Arial;background:#cc0000;color:white;padding:40px;text-align:center">
  <h1>Servidor: Apache HTTP Server</h1>
  <p><strong>Version:</strong> $version</p>
  <p><strong>Puerto:</strong> $puerto</p>
  <p><em>Tarea 6 - Administracion de Sistemas - Grupo 3-02</em></p>
</body>
</html>
"@
        Set-Content "$wwwroot\index.html" $contenido -Encoding UTF8
        Msg-Ok "Página index.html creada."
    }

    # Firewall
    Remove-NetFirewallRule -DisplayName "HTTP-Apache-$puerto" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "HTTP-Apache-$puerto" -Direction Inbound `
        -LocalPort $puerto -Protocol TCP -Action Allow | Out-Null
    Msg-Ok "Regla de firewall creada para Apache en puerto $puerto."

    # Iniciar servicio
    $svc = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($svc) {
        Restart-Service $svc.Name -ErrorAction SilentlyContinue
        Msg-Ok "Servicio Apache reiniciado."
    } else {
        Msg-Warn "No se encontró el servicio Apache. Iniciar manualmente si es necesario."
    }

    Msg-Ok "Apache configurado en puerto $puerto."
    Msg-Info "Prueba: curl -I http://localhost:$puerto"
}

# ==============================================================================
# NGINX PARA WINDOWS (via Chocolatey)
# ==============================================================================

function Instalar-Configurar-Nginx {
    Verificar-Chocolatey
    Msg-Info "=== Instalación de Nginx para Windows ==="

    $version = Seleccionar-Version "nginx"
    $puerto  = Pedir-Puerto

    Msg-Info "Instalando Nginx versión $version..."
    if ($version -eq "latest") {
        choco install nginx -y --no-progress 2>&1 | Out-Null
    } else {
        choco install nginx --version $version -y --no-progress 2>&1 | Out-Null
    }
    Msg-Ok "Nginx instalado."

    # Buscar nginx.conf
    $nginxConf = "C:\tools\nginx\conf\nginx.conf"
    if (-not (Test-Path $nginxConf)) {
        $nginxConf = (Get-ChildItem "C:\*\nginx*\conf\nginx.conf" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    }

    if (Test-Path $nginxConf) {
        (Get-Content $nginxConf) -replace 'listen\s+\d+', "listen $puerto" | Set-Content $nginxConf
        # Agregar server_tokens off
        $content = Get-Content $nginxConf -Raw
        if ($content -notmatch 'server_tokens') {
            $content = $content -replace 'http \{', "http {`n    server_tokens off;"
            Set-Content $nginxConf $content
        }
        Msg-Ok "Puerto $puerto y server_tokens off aplicados en nginx.conf."
    } else {
        Msg-Warn "No se encontró nginx.conf. Configuración manual requerida."
    }

    # Página index
    $nginxHtml = "C:\tools\nginx\html"
    if (Test-Path $nginxHtml) {
        $contenido = @"
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Nginx - Tarea 6</title></head>
<body style="font-family:Arial;background:#009900;color:white;padding:40px;text-align:center">
  <h1>Servidor: Nginx</h1>
  <p><strong>Version:</strong> $version</p>
  <p><strong>Puerto:</strong> $puerto</p>
  <p><em>Tarea 6 - Administracion de Sistemas - Grupo 3-02</em></p>
</body>
</html>
"@
        Set-Content "$nginxHtml\index.html" $contenido -Encoding UTF8
        Msg-Ok "Página index.html creada."
    }

    # Firewall
    Remove-NetFirewallRule -DisplayName "HTTP-Nginx-$puerto" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "HTTP-Nginx-$puerto" -Direction Inbound `
        -LocalPort $puerto -Protocol TCP -Action Allow | Out-Null
    Msg-Ok "Regla de firewall creada para Nginx en puerto $puerto."

    # Iniciar Nginx
    $nginxExe = (Get-ChildItem "C:\*\nginx*\nginx.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    if ($nginxExe) {
        Stop-Process -Name nginx -Force -ErrorAction SilentlyContinue
        Start-Process -FilePath $nginxExe -WorkingDirectory (Split-Path $nginxExe)
        Msg-Ok "Nginx iniciado."
    } else {
        Msg-Warn "No se encontró nginx.exe. Iniciar manualmente."
    }

    Msg-Ok "Nginx configurado en puerto $puerto."
    Msg-Info "Prueba: curl -I http://localhost:$puerto"
}

# ==============================================================================
# MONITOREO
# ==============================================================================

function Mostrar-Estado-Servicios {
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "   ESTADO DE SERVIDORES HTTP             " -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan

    # IIS
    $iis = Get-Service -Name W3SVC -ErrorAction SilentlyContinue
    if ($iis) {
        $estado = if ($iis.Status -eq 'Running') { "[CORRIENDO]" } else { "[DETENIDO]" }
        $color  = if ($iis.Status -eq 'Running') { "Green" } else { "Red" }
        Write-Host "  IIS (W3SVC):  $estado" -ForegroundColor $color
    }

    # Apache
    $apache = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($apache) {
        $estado = if ($apache.Status -eq 'Running') { "[CORRIENDO]" } else { "[DETENIDO]" }
        $color  = if ($apache.Status -eq 'Running') { "Green" } else { "Red" }
        Write-Host "  Apache:       $estado" -ForegroundColor $color
    } else {
        Write-Host "  Apache:       [NO INSTALADO]" -ForegroundColor Gray
    }

    # Nginx
    $nginx = Get-Process -Name nginx -ErrorAction SilentlyContinue
    if ($nginx) {
        Write-Host "  Nginx:        [CORRIENDO]" -ForegroundColor Green
    } else {
        Write-Host "  Nginx:        [NO INSTALADO/DETENIDO]" -ForegroundColor Gray
    }

    Write-Host ""
    Msg-Info "Puertos en escucha (HTTP):"
    netstat -ano | Select-String "LISTENING" | Select-String ":80 |:443 |:8080 |:8888 "
    Write-Host ""
}