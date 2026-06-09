#!/system/bin/sh
REQ=/data/data/com.termux/files/home/.usbc_toggle_req
RES=/data/data/com.termux/files/home/.usbc_toggle_result
TUID=10199
TCTX=u:object_r:app_data_file:s0:c199,c256,c512,c768
echo "$(date) started pid=$$" >> /data/local/tmp/usbc_daemon.log
while [ ! -d /data/data/com.termux/files/home ]; do sleep 5; done
while true; do
    if [ -f "$REQ" ]; then
        rm -f "$REQ"
        out=$(/system/bin/sh /data/adb/usbc_audio_toggle.sh 2>&1)
        echo "$out" > "$RES"
        chown "$TUID:$TUID" "$RES" 2>/dev/null
        chcon "$TCTX" "$RES" 2>/dev/null
        echo "$(date) processed: $out" >> /data/local/tmp/usbc_daemon.log
    fi
    sleep 1
done
