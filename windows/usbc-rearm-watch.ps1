# usbc-rearm-watch.ps1 - auto-arm the USB-C audio daemon whenever the phone connects.
# Leave running (or launch hidden at login via usbc-rearm-watch.vbs). Ctrl-C to stop.

$adb = if ($env:ADB) { $env:ADB } else { 'adb' }
$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$rearm = Join-Path $here 'usbc-rearm.ps1'

function Log($m) { Write-Host ("{0} {1}" -f (Get-Date -Format HH:mm:ss), $m) }
Log 'watching for device - will re-arm USB-C daemon on each connect (Ctrl-C to stop)'

$armed = ''
while ($true) {
    & $adb wait-for-device 2>$null | Out-Null
    $serial = (& $adb get-serialno) 2>$null
    if ($serial) { $serial = $serial.Trim() }
    if ($serial -and $serial -ne 'unknown' -and $serial -ne $armed) {
        Log "device $serial connected -> arming"
        & powershell -NoProfile -ExecutionPolicy Bypass -File $rearm
        if ($LASTEXITCODE -eq 0) { $armed = $serial }
    }
    # debounce: wait until this device disconnects before looking again
    while (((& $adb get-state) 2>$null) -match 'device') { Start-Sleep -Seconds 3 }
    if ($serial -eq $armed) { Log "device $serial disconnected"; $armed = '' }
    Start-Sleep -Seconds 1
}
