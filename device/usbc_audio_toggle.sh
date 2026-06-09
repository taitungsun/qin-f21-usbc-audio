#!/system/bin/sh
#
# Toggle USB-C audio (host mode) on Qin F21 Pro / DumberOS.
#
# The wusb3801 Type-C controller never asserts its INT for audio accessories, so
# MUSB never enters host mode and a plugged USB-C earphone is never enumerated.
# Writing 1 to usb20_host's "option" forces host mode + VBUS (issue_host_work);
# writing 2 tears it back down so the port can charge / idle normally.
#
# There is a VBUS race: host-connect turns VBUS on, but a competing disconnect
# work item can kill it ~130 ms later, before the earphone enumerates. So when
# turning ON we re-assert option=1 repeatedly until card2 appears (or we give up).
#
# Run as root. Self-correcting: if enabling never enumerates it reverts to OFF,
# so VBUS is never left on with nothing attached (that costs ~100 mA).

OPT=/sys/module/usb20_host/parameters/option

if [ -d /proc/asound/card2 ]; then
    # Currently ON -> turn OFF
    echo 2 > "$OPT"
    state="USB-C audio OFF"
else
    # Currently OFF -> turn ON, beating the VBUS race with rapid re-asserts
    i=0
    while [ "$i" -lt 15 ]; do
        [ -d /proc/asound/card2 ] && break
        echo 1 > "$OPT"
        sleep 0.4
        i=$((i + 1))
    done
    [ -d /proc/asound/card2 ] || sleep 1   # final settle
    if [ -d /proc/asound/card2 ]; then
        # ensure the USB-headset streams are audible (Android keeps a separate,
        # often-low volume per output device; rescue it so there's actual sound)
        cmd media_session volume --stream 0 --set 8  >/dev/null 2>&1   # voice call
        cmd media_session volume --stream 3 --set 11 >/dev/null 2>&1   # music
        state="USB-C audio ON"
    else
        echo 2 > "$OPT"                    # revert, no drain
        state="USB-C audio: no earphone detected"
    fi
fi

cmd vibrator vibrate 150 >/dev/null 2>&1   # best-effort haptic feedback
log -t usbc_audio "$state"
echo "$state"
