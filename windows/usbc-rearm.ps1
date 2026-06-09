# usbc-rearm.ps1 - (re)start the Qin F21 Pro USB-C audio root daemon over ADB.
# Idempotent: does nothing if the daemon is already running.
# Set $env:ADB to your adb.exe path, or put adb.exe on PATH, or edit $adb below.

$adb = if ($env:ADB) { $env:ADB } else { 'adb' }
$DAEMON = '/data/adb/usbc_daemon_loop.sh'
$LAUNCH = "setsid /system/bin/sh $DAEMON </dev/null >/dev/null 2>&1 &"

function Log($m) { Write-Host ("{0} {1}" -f (Get-Date -Format HH:mm:ss), $m) }

Log 'waiting for device...'
& $adb wait-for-device
if ($LASTEXITCODE -ne 0) { Log 'ERROR: no device (check cable / driver)'; exit 1 }

& $adb root | Out-Null
Start-Sleep -Seconds 1
& $adb wait-for-device | Out-Null

$idctx = (& $adb shell id) 2>$null
if ($idctx -notmatch 'uid=0') { Log "ERROR: not root (got: $idctx)"; exit 1 }

& $adb shell "[ -f $DAEMON ]" | Out-Null
if ($LASTEXITCODE -ne 0) { Log "ERROR: $DAEMON not found on device"; exit 1 }

$running = (& $adb shell "ps -A -o PID,ARGS 2>/dev/null | grep usbc_daemon_loop | grep -v grep") 2>$null
if ($running) { Log "already running: $($running.Trim())"; exit 0 }

& $adb shell $LAUNCH | Out-Null
Start-Sleep -Seconds 2
& $adb wait-for-device | Out-Null
$running = (& $adb shell "ps -A -o PID,ARGS 2>/dev/null | grep usbc_daemon_loop | grep -v grep") 2>$null
if ($running) { Log "ARMED OK  $($running.Trim())"; exit 0 }
else { Log 'ERROR: launch did not take - retry or re-seat the cable'; exit 1 }
