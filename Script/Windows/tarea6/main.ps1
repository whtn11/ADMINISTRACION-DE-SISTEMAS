# ============================================================
# TAREA 4 - Menú Principal / SSH
# Archivo: main.ps1
# ============================================================

function Verificar-Admin {
    $esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $esAdmin) {
        Write-Host "Ejecuta el script como Administrador."
        exit 1
    }
}

function Instalar-SSH {
    $ssh = Get-WindowsCapability -Online | Where-Object { $_.Name -like "OpenSSH.Server*" }
    if ($ssh.State -eq "Installed") {
        Write-Host "OpenSSH ya esta instalado." -ForegroundColor Green
    } else {
        Write-Host "Instalando OpenSSH Server..." -ForegroundColor Yellow
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
        Write-Host "Instalacion completada." -ForegroundColor Green
    }
    Start-Service sshd
    Set-Service -Name sshd -StartupType Automatic
    New-NetFirewallRule -Name "OpenSSH" -DisplayName "OpenSSH Server" -Protocol TCP -LocalPort 22 -Action Allow -Direction Inbound -ErrorAction SilentlyContinue
    Write-Host "SSH activo. Conexion: ssh Administrador@$((Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -ne '127.0.0.1'} | Select-Object -First 1).IPAddress)" -ForegroundColor Green
}

function Ver-Estado-SSH {
    Get-Service sshd | Select-Object Name, Status, StartType
}

Verificar-Admin

while ($true) {
    Write-Host "=========================="
    Write-Host "    MENU PRINCIPAL"
    Write-Host "=========================="
    Write-Host "1. Instalar/verificar SSH"
    Write-Host "2. Estado de SSH"
    Write-Host "3. Menu DHCP (Tarea 2)"
    Write-Host "4. Menu DNS (Tarea 3)"
    Write-Host "5. Diagnostico del sistema (Tarea 1)"
    Write-Host "6. Salir"
    Write-Host "=========================="
    $opcion = Read-Host "Opcion [1-6]"

    switch ($opcion) {
        "1" { Instalar-SSH }
        "2" { Ver-Estado-SSH }
        "3" { & "$PSScriptRoot\..\tarea2\dhcp_main.ps1" }
        "4" { & "$PSScriptRoot\..\tarea3\dns_main.ps1" }
        "5" { & "$PSScriptRoot\..\tarea1\tarea1_main.ps1" }
        "6" { exit 0 }
        default { Write-Host "Opcion invalida" }
    }
}
