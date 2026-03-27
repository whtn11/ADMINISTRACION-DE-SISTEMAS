# ============================================================
# TAREA 1 - Funciones de diagnóstico
# Archivo: tarea1_functions.ps1
# ============================================================

function Obtener-Hostname {
    return $env:COMPUTERNAME
}

function Obtener-IP {
    return (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -ne '127.0.0.1'} | Select-Object -First 1).IPAddress
}

function Obtener-Disco {
    Get-PSDrive C | Select-Object @{N='Total(GB)';E={[math]::Round(($_.Used+$_.Free)/1GB,2)}}, @{N='Usado(GB)';E={[math]::Round($_.Used/1GB,2)}}, @{N='Libre(GB)';E={[math]::Round($_.Free/1GB,2)}}
}

function Mostrar-Diagnostico {
    Write-Host "============================="
    Write-Host " NOMBRE DEL EQUIPO: $(Obtener-Hostname)"
    Write-Host " IP ACTUAL: $(Obtener-IP)"
    Write-Host " ESPACIO EN DISCO:"
    Obtener-Disco
    Write-Host "============================="
}
