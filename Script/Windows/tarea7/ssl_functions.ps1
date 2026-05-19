# ==============================================================================
# ssl_functions.ps1 - Biblioteca de funciones para SSL/TLS y orquestador híbrido
# Práctica 7 - Administración de Sistemas
# Grupo: 3-02 | Alumno: eromero
# ==============================================================================

# Forzar encoding UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

# ---- Mensajes ----
function Msg-Ok($msg)   { Write-Host "[OK]    $msg" -ForegroundColor Green }
function Msg-Err($msg)  { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Msg-Info($msg) { Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Msg-Warn($msg) { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }

# ---- Configuración global ----
$FTP_SERVER = "192.168.10.20"
$FTP_USER   = "juan"
$FTP_PASS   = "ervg2005"
$FTP_BASE   = "/http/Windows"
$DOMINIO    = "reprobados.com"
$SSL_DIR    = "C:\ssl\practica7"
$RESUMEN    = @()

# ==============================================================================
# UTILIDADES
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
        Msg-Info "Instalando Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Msg-Ok "Chocolatey instalado."
    }
}

function Preguntar-SSL($servicio) {
    while ($true) {
        $resp = Read-Host "¿Desea activar SSL en $servicio? [S/N]"
        $resp = $resp.Trim().ToUpper()
        if ($resp -eq "S" -or $resp -eq "N") { return $resp }
        Msg-Err "Respuesta invalida. Ingrese S o N."
    }
}

function Elegir-Fuente {
    Write-Host ""
    Write-Host "  Fuente de instalacion:" -ForegroundColor Cyan
    Write-Host "  [1] WEB (Chocolatey)"
    Write-Host "  [2] FTP (repositorio privado 192.168.10.20)"
    Write-Host ""
    while ($true) {
        $opc = Read-Host "  Seleccione [1-2]"
        $opc = $opc.Trim()
        if ($opc -eq "1" -or $opc -eq "2") { return $opc }
        Msg-Err "Opcion invalida."
    }
}

# ==============================================================================
# CLIENTE FTP DINÁMICO
# ==============================================================================

function Listar-FTP($ruta) {
    $cred = New-Object System.Net.NetworkCredential($FTP_USER, $FTP_PASS)
    try {
        $request = [System.Net.FtpWebRequest]::Create("ftp://${FTP_SERVER}${ruta}")
        $request.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $request.Credentials = $cred
        $request.UsePassive = $true
        $request.UseBinary = $true
        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        $content = $reader.ReadToEnd()
        $reader.Close()
        $response.Close()
        return $content.Split("`n") | Where-Object { $_.Trim() -ne "" }
    } catch {
        Msg-Err "Error al conectar al FTP: $_"
        return @()
    }
}

function Navegar-FTP($servicio) {
    $ruta = "${FTP_BASE}/${servicio}"
    Msg-Info "Conectando al FTP: ftp://${FTP_SERVER}${ruta}"

    $archivos = Listar-FTP $ruta | Where-Object { $_ -notlike "*.sha256" }

    if ($archivos.Count -eq 0) {
        Msg-Err "No se encontraron archivos en $ruta"
        return $null
    }

    Write-Host ""
    Write-Host "  Archivos disponibles en FTP:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $archivos.Count; $i++) {
        Write-Host "  [$($i+1)] $($archivos[$i].Trim())"
    }
    Write-Host ""

    while ($true) {
        $sel = Read-Host "  Seleccione archivo [1-$($archivos.Count)]"
        if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $archivos.Count) {
            return $archivos[[int]$sel - 1].Trim()
        }
        Msg-Err "Seleccion invalida."
    }
}

function Descargar-FTP($servicio, $archivo, $destino) {
    $ruta = "${FTP_BASE}/${servicio}/${archivo}"
    $url  = "ftp://${FTP_SERVER}${ruta}"
    Msg-Info "Descargando $archivo desde FTP..."

    $cred = New-Object System.Net.NetworkCredential($FTP_USER, $FTP_PASS)
    try {
        $request = [System.Net.FtpWebRequest]::Create($url)
        $request.Method = [System.Net.WebRequestMethods+Ftp]::DownloadFile
        $request.Credentials = $cred
        $request.UsePassive = $true
        $request.UseBinary = $true
        $response = $request.GetResponse()
        $stream = $response.GetResponseStream()
        $fileStream = [System.IO.File]::Create("$destino\$archivo")
        $stream.CopyTo($fileStream)
        $fileStream.Close()
        $stream.Close()
        $response.Close()
        Msg-Ok "Archivo descargado: $destino\$archivo"
        return $true
    } catch {
        Msg-Err "Error al descargar: $_"
        return $false
    }
}

function Verificar-Hash($servicio, $archivo, $destino) {
    $ruta = "${FTP_BASE}/${servicio}"
    $shaArchivos = Listar-FTP $ruta | Where-Object { $_ -like "*.sha256" }

    if ($shaArchivos.Count -eq 0) {
        Msg-Warn "No se encontro archivo .sha256 en el servidor FTP."
        return $true
    }

    $shaFile = $shaArchivos[0].Trim()
    Msg-Info "Descargando hash: $shaFile"
    Descargar-FTP $servicio $shaFile $destino | Out-Null

    # Leer hash esperado
    $hashEsperado = (Get-Content "$destino\$shaFile" -ErrorAction SilentlyContinue).Split(" ")[0].Trim()

    # Calcular hash local
    $hashLocal = (Get-FileHash "$destino\$archivo" -Algorithm SHA256).Hash.ToLower()

    Msg-Info "Verificando integridad..."
    if ($hashEsperado -eq $hashLocal) {
        Msg-Ok "Integridad verificada correctamente."
        return $true
    } else {
        Msg-Err "El hash no coincide. Archivo posiblemente corrupto."
        return $false
    }
}

function Instalar-DesdeFTP($servicio) {
    $destino = "C:\ftp_install"
    New-Item -ItemType Directory -Force -Path $destino | Out-Null

    $archivo = Navegar-FTP $servicio
    if (-not $archivo) { return $false }

    $ok = Descargar-FTP $servicio $archivo $destino
    if (-not $ok) { return $false }

    $ok = Verificar-Hash $servicio $archivo $destino
    if (-not $ok) { return $false }

    return "$destino\$archivo"
}

# ==============================================================================
# CERTIFICADOS SSL (Windows)
# ==============================================================================

function Generar-Certificado($servicio) {
    $certDir = "$SSL_DIR\$servicio"
    New-Item -ItemType Directory -Force -Path $certDir | Out-Null

    Msg-Info "Generando certificado SSL para $DOMINIO ($servicio)..."
    $cert = New-SelfSignedCertificate -DnsName $DOMINIO -CertStoreLocation "Cert:\LocalMachine\My" `
        -NotAfter (Get-Date).AddDays(365) -KeyAlgorithm RSA -KeyLength 2048

    # Exportar certificado
    $certPath = "$certDir\cert.pfx"
    $pwd = ConvertTo-SecureString -String "practica7" -Force -AsPlainText
    Export-PfxCertificate -Cert $cert -FilePath $certPath -Password $pwd | Out-Null

    Msg-Ok "Certificado generado: $certPath (thumbprint: $($cert.Thumbprint))"
    return $cert.Thumbprint
}

# ==============================================================================
# IIS (HTTPS)
# ==============================================================================

function Configurar-SSL-IIS {
    Msg-Info "=== IIS (HTTPS) ==="
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $ssl = Preguntar-SSL "IIS"
    if ($ssl -eq "S") {
        $thumb = Generar-Certificado "IIS"

        # Agregar binding HTTPS
        $existente = Get-WebBinding -Name "Default Web Site" | Where-Object { $_.bindingInformation -match ":443:" }
        if (-not $existente) {
            New-WebBinding -Name "Default Web Site" -Protocol https -Port 443 -IPAddress "*"
        }

        # Asignar certificado al binding
        $binding = Get-WebBinding -Name "Default Web Site" -Protocol https
        $binding.AddSslCertificate($thumb, "My")

        # Redirección HTTP → HTTPS via web.config
        $webConfig = "C:\inetpub\wwwroot\web.config"
        [xml]$wc = Get-Content $webConfig -ErrorAction SilentlyContinue
        if ($null -eq $wc) {
            $wc = [xml]'<?xml version="1.0"?><configuration><system.webServer></system.webServer></configuration>'
        }
        # Agregar rewrite rule
        $rewrite = @"
<rewrite>
  <rules>
    <rule name="HTTP to HTTPS" stopProcessing="true">
      <match url="(.*)" />
      <conditions><add input="{HTTPS}" pattern="^OFF$" /></conditions>
      <action type="Redirect" url="https://{HTTP_HOST}/{R:1}" redirectType="Permanent" />
    </rule>
  </rules>
</rewrite>
"@
        Add-Content $webConfig $rewrite -ErrorAction SilentlyContinue

        # Firewall
        Remove-NetFirewallRule -DisplayName "HTTPS-IIS-443" -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName "HTTPS-IIS-443" -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow | Out-Null

        Restart-Service W3SVC
        Msg-Ok "IIS HTTPS configurado en puerto 443."
        $script:RESUMEN += "IIS: HTTPS (puerto 443)"
    } else {
        Msg-Ok "IIS sin SSL."
        $script:RESUMEN += "IIS: HTTP sin SSL"
    }
}

# ==============================================================================
# APACHE WINDOWS (HTTPS)
# ==============================================================================

function Configurar-SSL-Apache {
    Msg-Info "=== Apache Windows ==="
    $fuente = Elegir-Fuente

    $apacheDir = "C:\Users\Administrador\AppData\Roaming\Apache24"
    if (-not (Test-Path "$apacheDir\bin\httpd.exe")) {
        if ($fuente -eq "1") {
            Verificar-Chocolatey
            choco install apache-httpd -y --no-progress 2>&1 | Out-Null
        } else {
            $archivo = Instalar-DesdeFTP "Apache"
            if ($archivo) {
                Expand-Archive $archivo -DestinationPath "C:\Apache24" -Force
                $apacheDir = "C:\Apache24\Apache24"
            }
        }
    }

    $ssl = Preguntar-SSL "Apache Windows"
    if ($ssl -eq "S") {
        $certDir = "$SSL_DIR\Apache"
        New-Item -ItemType Directory -Force -Path $certDir | Out-Null

        # Generar certificado con openssl si está disponible
        if (Get-Command openssl -ErrorAction SilentlyContinue) {
            & openssl req -x509 -nodes -days 365 -newkey rsa:2048 `
                -keyout "$certDir\privkey.pem" `
                -out "$certDir\cert.pem" `
                -subj "/C=MX/ST=Sinaloa/L=LMochis/O=UAS/CN=$DOMINIO" 2>$null
            Msg-Ok "Certificado generado en $certDir"
        } else {
            Msg-Warn "openssl no encontrado. Usando certificado autofirmado de Windows."
            Generar-Certificado "Apache" | Out-Null
        }

        # Agregar configuración SSL al httpd.conf
        $httpdConf = "$apacheDir\conf\httpd.conf"
        if (Test-Path $httpdConf) {
            $sslConfig = @"

Listen 9443
LoadModule ssl_module modules/mod_ssl.so
<VirtualHost *:9443>
    ServerName $DOMINIO
    SSLEngine on
    SSLCertificateFile "$certDir/cert.pem"
    SSLCertificateKeyFile "$certDir/privkey.pem"
    DocumentRoot "$apacheDir/htdocs"
</VirtualHost>
<VirtualHost *:9090>
    ServerName $DOMINIO
    Redirect permanent / https://$DOMINIO:9443/
</VirtualHost>
"@
            Add-Content $httpdConf $sslConfig
            Msg-Ok "SSL configurado en Apache puerto 9443."
        }

        # Firewall
        Remove-NetFirewallRule -DisplayName "HTTPS-Apache-9443" -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName "HTTPS-Apache-9443" -Direction Inbound -LocalPort 9443 -Protocol TCP -Action Allow | Out-Null

        & "$apacheDir\bin\httpd.exe" -k restart 2>$null
        Msg-Ok "Apache HTTPS configurado en puerto 9443."
        $script:RESUMEN += "Apache: HTTPS (puerto 9443)"
    } else {
        Msg-Ok "Apache sin SSL."
        $script:RESUMEN += "Apache: HTTP sin SSL"
    }
}

# ==============================================================================
# NGINX WINDOWS (HTTPS)
# ==============================================================================

function Configurar-SSL-Nginx {
    Msg-Info "=== Nginx Windows ==="
    $fuente = Elegir-Fuente

    $nginxDir = (Get-ChildItem "C:\tools" -Filter "nginx*" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName

    if (-not $nginxDir) {
        if ($fuente -eq "1") {
            Verificar-Chocolatey
            choco install nginx -y --no-progress 2>&1 | Out-Null
            $nginxDir = (Get-ChildItem "C:\tools" -Filter "nginx*" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
        } else {
            $archivo = Instalar-DesdeFTP "Nginx"
            if ($archivo) {
                Expand-Archive $archivo -DestinationPath "C:\tools\nginx-ftp" -Force
                $nginxDir = "C:\tools\nginx-ftp"
            }
        }
    }

    $ssl = Preguntar-SSL "Nginx Windows"
    if ($ssl -eq "S") {
        $certDir = "$SSL_DIR\Nginx"
        New-Item -ItemType Directory -Force -Path $certDir | Out-Null

        if (Get-Command openssl -ErrorAction SilentlyContinue) {
            & openssl req -x509 -nodes -days 365 -newkey rsa:2048 `
                -keyout "$certDir\privkey.pem" `
                -out "$certDir\cert.pem" `
                -subj "/C=MX/ST=Sinaloa/L=LMochis/O=UAS/CN=$DOMINIO" 2>$null
            Msg-Ok "Certificado generado en $certDir"
        } else {
            Generar-Certificado "Nginx" | Out-Null
        }

        # Agregar server block HTTPS en nginx.conf
        $nginxConf = "$nginxDir\conf\nginx.conf"
        if (Test-Path $nginxConf) {
            $sslBlock = @"

    server {
        listen 8443 ssl;
        server_name $DOMINIO;
        ssl_certificate     $($certDir -replace '\\','/')/cert.pem;
        ssl_certificate_key $($certDir -replace '\\','/')/privkey.pem;
        root html;
        index index.html;
    }
    server {
        listen 8080;
        server_name $DOMINIO;
        return 301 https://`$host:8443`$request_uri;
    }
"@
            # Insertar antes del cierre del bloque http
            $content = Get-Content $nginxConf -Raw
            $content = $content -replace '(#.+\n)*\}(\s*)$', "$sslBlock`n}`$2"
            Set-Content $nginxConf $content
            Msg-Ok "SSL configurado en Nginx puerto 8443."
        }

        # Firewall
        Remove-NetFirewallRule -DisplayName "HTTPS-Nginx-8443" -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName "HTTPS-Nginx-8443" -Direction Inbound -LocalPort 8443 -Protocol TCP -Action Allow | Out-Null

        # Reiniciar Nginx
        Stop-Process -Name nginx -Force -ErrorAction SilentlyContinue
        Start-Process "$nginxDir\nginx.exe" -WorkingDirectory $nginxDir
        Msg-Ok "Nginx HTTPS configurado en puerto 8443."
        $script:RESUMEN += "Nginx: HTTPS (puerto 8443)"
    } else {
        Msg-Ok "Nginx sin SSL."
        $script:RESUMEN += "Nginx: HTTP sin SSL"
    }
}

# ==============================================================================
# IIS-FTP (FTPS)
# ==============================================================================

function Configurar-SSL-IISFTP {
    Msg-Info "=== IIS-FTP (FTPS) ==="
    $ssl = Preguntar-SSL "IIS-FTP"

    if ($ssl -eq "S") {
        Import-Module WebAdministration -ErrorAction SilentlyContinue

        # Instalar FTP si no está
        $ftpFeature = Get-WindowsFeature -Name Web-Ftp-Server -ErrorAction SilentlyContinue
        if ($ftpFeature -and -not $ftpFeature.Installed) {
            Msg-Info "Instalando IIS-FTP..."
            Install-WindowsFeature -Name Web-Ftp-Server -IncludeManagementTools | Out-Null
            Msg-Ok "IIS-FTP instalado."
        }

        $thumb = Generar-Certificado "IIS-FTP"

        # Configurar SSL en sitio FTP
        Set-WebConfigurationProperty -PSPath "IIS:\" `
            -Filter "system.applicationHost/sites/site[@name='Default FTP Site']/ftpServer/security/ssl" `
            -Name "serverCertHash" -Value $thumb -ErrorAction SilentlyContinue

        Set-WebConfigurationProperty -PSPath "IIS:\" `
            -Filter "system.applicationHost/sites/site[@name='Default FTP Site']/ftpServer/security/ssl" `
            -Name "controlChannelPolicy" -Value "SslRequire" -ErrorAction SilentlyContinue

        Set-WebConfigurationProperty -PSPath "IIS:\" `
            -Filter "system.applicationHost/sites/site[@name='Default FTP Site']/ftpServer/security/ssl" `
            -Name "dataChannelPolicy" -Value "SslRequire" -ErrorAction SilentlyContinue

        # Firewall
        Remove-NetFirewallRule -DisplayName "FTPS-IIS-990" -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName "FTPS-IIS-990" -Direction Inbound -LocalPort 990 -Protocol TCP -Action Allow | Out-Null

        Restart-Service W3SVC -ErrorAction SilentlyContinue
        Msg-Ok "IIS-FTP FTPS configurado."
        $script:RESUMEN += "IIS-FTP: FTPS (SSL requerido)"
    } else {
        Msg-Ok "IIS-FTP sin SSL."
        $script:RESUMEN += "IIS-FTP: FTP sin SSL"
    }
}

# ==============================================================================
# RESUMEN FINAL
# ==============================================================================

function Mostrar-Resumen {
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "   RESUMEN DE INSTALACIONES              " -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan

    foreach ($item in $script:RESUMEN) {
        Write-Host "  * $item" -ForegroundColor Green
    }

    Write-Host ""
    Msg-Info "Verificando servicios activos:"

    $servicios = @{
        "W3SVC"   = "IIS"
        "Apache2.4" = "Apache"
    }
    foreach ($svc in $servicios.Keys) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) {
            $estado = if ($s.Status -eq "Running") { "[ACTIVO]" } else { "[INACTIVO]" }
            $color  = if ($s.Status -eq "Running") { "Green" } else { "Red" }
            Write-Host "  $estado $($servicios[$svc])" -ForegroundColor $color
        }
    }

    # Nginx
    $nginx = Get-Process -Name nginx -ErrorAction SilentlyContinue
    if ($nginx) { Write-Host "  [ACTIVO]   Nginx" -ForegroundColor Green }
    else         { Write-Host "  [INACTIVO] Nginx" -ForegroundColor Red }

    Write-Host ""
    Msg-Info "Certificados generados:"
    Get-ChildItem "$SSL_DIR" -Recurse -Filter "*.pfx" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  * $($_.FullName)" -ForegroundColor Green
    }
    Get-ChildItem "$SSL_DIR" -Recurse -Filter "cert.pem" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  * $($_.FullName)" -ForegroundColor Green
    }
    Write-Host ""
}
