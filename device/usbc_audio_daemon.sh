#!/system/bin/sh
#
# Root-side watcher for the USB-C audio toggle.
# Termux (no root) creates ~/.usbc_toggle_req; this daemon (root) runs the
# toggle and writes the result to ~/.usbc_toggle_result for Termux to display.
# Started at boot by Magisk service.d (and can be started manually for testing).

REQ=/data/data/com.termux/files/home/.usbc_toggle_req
RES=/data/data/com.termux/files/home/.usbc_toggle_result
TUID=10199
TCTX=u:object_r:app_data_file:s0:c199,c256,c512,c768

(
    # wait until Termux home exists
    while [ ! -d /data/data/com.termux/files/home ]; do sleep 5; done
    while true; do
        if [ -f "$REQ" ]; then
            rm -f "$REQ"
            out=$(/system/bin/sh /data/adb/usbc_audio_toggle.sh 2>&1)
            echo "$out" > "$RES"
            chown "$TUID:$TUID" "$RES" 2>/dev/null
            chcon "$TCTX" "$RES" 2>/dev/null
        fi
        sleep 1
    done
) &
