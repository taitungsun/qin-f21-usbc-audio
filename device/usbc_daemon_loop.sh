#!/system/bin/sh
REQ=/data/data/com.termux/files/home/.usbc_toggle_req
RES=/data/data/com.termux/files/home/.usbc_toggle_result
TUID=10199
TCTX=u:object_r:app_data_file:s0:c199,c256,c512,c768
LOG=/data/local/tmp/usbc_daemon.log
PIDF=/data/local/tmp/usbc_daemon.pid

# --- duplicate guard: only ever one daemon instance, no matter how many
# launchers (service.d, a PC re-arm, the connect-watcher) fire ---
if [ -f "$PIDF" ]; then
    op=$(cat "$PIDF" 2>/dev/null)
    if [ -n "$op" ] && [ "$op" != "$$" ] && [ -d "/proc/$op" ] && \
       tr '\0' ' ' < "/proc/$op/cmdline" 2>/dev/null | grep -q usbc_daemon_loop; then
        echo "$(date) duplicate start, $op already running; exiting $$" >> "$LOG"
        exit 0
    fi
fi
echo $$ > "$PIDF"

echo "$(date) started pid=$$" >> "$LOG"
while [ ! -d /data/data/com.termux/files/home ]; do sleep 5; done
while true; do
    if [ -f "$REQ" ]; then
        rm -f "$REQ"
        out=$(/system/bin/sh /data/adb/usbc_audio_toggle.sh 2>&1)
        echo "$out" > "$RES"
        chown "$TUID:$TUID" "$RES" 2>/dev/null
        chcon "$TCTX" "$RES" 2>/dev/null
        echo "$(date) processed: $out" >> "$LOG"
    fi
    sleep 1
done
