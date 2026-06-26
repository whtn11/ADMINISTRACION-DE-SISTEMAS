#Requires -RunAsAdministrator

$multiotp = "C:\Program Files\multiOTP\multiotp.exe"
$claves   = "C:\Users\Administrador\claves_mfa.txt"
$usuarios = @("Administrador","eromero","nuzumaki","khatake","suchiha","iuchiha","mnamikaze","kuzumaki","asarutobi","hsenju","muchiha","tsenju")

"========== Claves MFA - empresa.local ==========" | Out-File $claves -Encoding UTF8
"Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $claves -Append -Encoding UTF8
"Instrucciones: Abre Google Authenticator -> + -> Ingresar clave -> Tipo: Basada en tiempo" | Out-File $claves -Append -Encoding UTF8
"" | Out-File $claves -Append -Encoding UTF8

$base32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
foreach ($u in $usuarios) {
    $clave = -join (1..20 | ForEach-Object { $base32[(Get-Random -Maximum 32)] })
    & $multiotp -createga $u $clave 2>$null | Out-Null
    if ($LASTEXITCODE -eq 11 -or $LASTEXITCODE -eq 22) {
        & $multiotp -set $u prefix-pin=0 2>$null | Out-Null
        Write-Host "[OK] $u registrado" -ForegroundColor Green
    } else {
        Write-Host "[WARN] $u - codigo: $LASTEXITCODE" -ForegroundColor Yellow
    }
    "Usuario: $u"      | Out-File $claves -Append -Encoding UTF8
    "  Clave: $clave"  | Out-File $claves -Append -Encoding UTF8
    ""                 | Out-File $claves -Append -Encoding UTF8
}

Write-Host ""
Write-Host "Claves guardadas en: $claves" -ForegroundColor Cyan
Write-Host ""
Get-Content $claves
