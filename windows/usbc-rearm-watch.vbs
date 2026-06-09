' usbc-rearm-watch.vbs - launch the watcher hidden (no console window) at login.
' Assumes the .ps1 scripts live in %USERPROFILE%\qin\ . Edit the path if you put
' them elsewhere. Put a shortcut to this .vbs (or this file) in the Startup folder:
'   Win+R  ->  shell:startup  ->  drop it in.
Dim sh, base, ps
Set sh = CreateObject("WScript.Shell")
base = sh.ExpandEnvironmentStrings("%USERPROFILE%") & "\qin\usbc-rearm-watch.ps1"
ps = "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & base & """"
sh.Run ps, 0, False
