#!/system/bin/sh
# install-autostart.sh — make the USB-C audio daemon start itself on every boot,
# on-device, with NO PC. Qin F21 Pro / DumberOS. Run as root:
#
#   adb root
#   adb push device/usbc_daemon_loop.sh   /data/adb/ && adb shell chmod 755 /data/adb/usbc_daemon_loop.sh
#   adb push device/install-autostart.sh  /data/adb/ && adb shell sh /data/adb/install-autostart.sh
#   adb reboot
#
# It registers an init service that starts /data/adb/usbc_daemon_loop.sh at
# boot_completed, labelled into the permissive + init-launchable `phhsu_daemon` domain
# (present thanks to the build's phh/AOSP-GSI lineage) — so no Magisk and no sepolicy
# patch. init then supervises the daemon and respawns it if it dies.
set -u

RC_DIR=/vendor/etc/init
STANDALONE="$RC_DIR/usbc-audio-autostart.rc"
LABEL=u:object_r:vendor_configs_file:s0

# Service block. Leading newline so that an *append* can't fuse onto a host file's
# last line if that file doesn't end in a newline.
BLOCK='
# --- USB-C audio daemon autostart (install-autostart.sh) ---
service usbc_audio_daemon /system/bin/sh /data/adb/usbc_daemon_loop.sh
    user root
    group root system
    seclabel u:r:phhsu_daemon:s0
    disabled

on property:sys.boot_completed=1
    start usbc_audio_daemon'

[ "$(id -u)" = 0 ] || { echo "ERROR: run me as root (adb root)"; exit 1; }

VDEV=$(awk '$2=="/vendor"{print $1}' /proc/mounts)
blockdev --setrw "$VDEV" 2>/dev/null
mount -o remount,rw /vendor 2>/dev/null || { echo "ERROR: cannot remount /vendor rw"; exit 1; }

installed=""
# 1) Preferred: a clean standalone .rc (works if /vendor has a free block).
if printf '%s\n' "$BLOCK" > "$STANDALONE" 2>/dev/null && [ -s "$STANDALONE" ]; then
    chown root:root "$STANDALONE" 2>/dev/null
    chmod 0644      "$STANDALONE" 2>/dev/null
    chcon "$LABEL"  "$STANDALONE" 2>/dev/null
    installed="standalone file: $STANDALONE"
else
    # 2) Fallback: /vendor is full — a new file can't be allocated (df's "free" space
    #    is unusable reserve). Append the block into the last-block slack of an existing
    #    .rc: an in-place grow that needs no new block. NEVER cp/rewrite on a full
    #    /vendor — truncating frees the block irrecoverably. Append only.
    rm -f "$STANDALONE" 2>/dev/null
    host=""
    for f in "$RC_DIR"/*.rc; do
        [ "$f" = "$STANDALONE" ] && continue
        sz=$(stat -c%s "$f" 2>/dev/null) || continue
        slack=$(( 4096 - (sz % 4096) ))
        if [ "$slack" -gt 500 ]; then host="$f"; break; fi
    done
    [ -n "$host" ] || { echo "ERROR: /vendor full and no .rc has enough slack to append into"; mount -o remount,ro /vendor 2>/dev/null; exit 1; }
    before=$(stat -c%s "$host")
    printf '%s\n' "$BLOCK" >> "$host" 2>/dev/null
    after=$(stat -c%s "$host")
    [ "$after" -gt "$before" ] || { echo "ERROR: append to $host failed (out of space)"; mount -o remount,ro /vendor 2>/dev/null; exit 1; }
    installed="appended into: $host"
fi

sync
mount -o remount,ro /vendor 2>/dev/null
echo "OK: autostart installed ($installed)"
echo "Reboot, then verify:  getprop init.svc.usbc_audio_daemon   # -> running"
