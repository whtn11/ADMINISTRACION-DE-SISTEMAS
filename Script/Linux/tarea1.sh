# check_status.ps1 - Tarea 1

Write-Host "============================="
Write-Host " NOMBRE DEL EQUIPO: $($env:COMPUTERNAME)"
Write-Host " IP ACTUAL: $((Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -ne '127.0.0.1'} | Select-Object -First 1).IPAddress)"
Write-Host " ESPACIO EN DISCO:"
Get-PSDrive C | Select-Object @{N='Total(GB)';E={[math]::Round(($_.Used+$_.Free)/1GB,2)}}, @{N='Usado(GB)';E={[math]::Round($_.Used/1GB,2)}}, @{N='Libre(GB)';E={[math]::Round($_.Free/1GB,2)}}
Write-Host "============================="
