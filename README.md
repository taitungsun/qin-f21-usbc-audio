# HOW-TO: Enable USB‑C wired audio on the Qin F21 Pro

**Tested on:** Qin F21 Pro (MediaTek MT6761) running **DumberOS** (LineageOS‑based, Android 14, kernel 4.19.127). Should apply to other AOSP/LineageOS builds on the same hardware.

## The problem

Plug a **USB‑C DAC / USB‑C wired earphone** into the F21 Pro and you get **no sound** — the dongle never even shows up. The phone simply never powers the port for an audio accessory.

## Why it happens

The Type‑C port controller (**wusb3801**) never raises its interrupt for *audio* accessories. Because of that, the MediaTek **MUSB** USB controller never switches into **host mode**, so it never turns on **VBUS** (port power), so a plugged‑in USB‑C DAC is never enumerated. It's not a hardware fault — the port just isn't being told to power up.

The fix is to **force MUSB into host mode** manually via a kernel knob. That asserts VBUS and the DAC enumerates as a normal USB sound card.

Under the hood, writing the knob triggers:
`set_option → issue_host_work → (charger) OTG‑boost VBUS on → iddig interrupt → musb_start(is_host=1)`,
after which the USB‑Audio class driver binds the DAC.

## Requirements

- **Root.** On a `-userdebug` build you can get it from a PC with `adb root` (gives uid 0 directly). On a Magisk’d build, a `su` shell works too.
- A USB‑C DAC / USB‑C‑to‑3.5mm audio dongle.

## The one knob

```
/sys/module/usb20_host/parameters/option
```

- `echo 1` → **force host mode + VBUS on** (enables the DAC)
- `echo 2` → **tear it back down** (port returns to charge/idle)

## Quick test (manual)

Plug in your USB‑C DAC, then as root:

```sh
echo 1 > /sys/module/usb20_host/parameters/option
sleep 1
cat /proc/asound/cards
```

You should now see a **third card (card 2)** appear — your DAC, e.g.:

```
 0 [mt63xxaccdet   ]: mt63xx-accdet - mt63xx-accdet
 1 [mtsndcard      ]: mt-snd-card - mt-snd-card
 2 [ATHCKD7NC      ]: USB-Audio - ATH-CKD7NC      <-- your USB-C DAC
```

Android then routes audio to `usb_headset` and you'll hear sound. To turn it off:

```sh
echo 2 > /sys/module/usb20_host/parameters/option
```

> **There's a VBUS race:** turning host mode on briefly powers VBUS, but a competing "disconnect" work item can kill it (~130 ms) before the DAC finishes enumerating. If `card 2` doesn't show on the first try, just write `1` again a few times until it appears. The toggle script below does this automatically.

## A self‑correcting toggle script

Save as `/data/adb/usbc_audio_toggle.sh`, `chmod 755`, run as root. It flips ON↔OFF, beats the VBUS race with rapid re‑asserts, **auto‑reverts to OFF if no DAC enumerates** (so VBUS is never left on with nothing attached — that wastes ~100 mA), and rescues the per‑output volume so there's actually sound.

```sh
#!/system/bin/sh
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
        cmd media_session volume --stream 0 --set 8  >/dev/null 2>&1   # voice call
        cmd media_session volume --stream 3 --set 11 >/dev/null 2>&1   # music
        state="USB-C audio ON"
    else
        echo 2 > "$OPT"                    # revert, no drain
        state="USB-C audio: no earphone detected"
    fi
fi

cmd vibrator vibrate 150 >/dev/null 2>&1   # haptic feedback
log -t usbc_audio "$state"
echo "$state"
```

Run it:

```sh
# from a PC:
adb root && adb shell sh /data/adb/usbc_audio_toggle.sh
# or in an on-device root shell:
su -c 'sh /data/adb/usbc_audio_toggle.sh'
```

## Notes & caveats

- **It's a manual toggle.** The port controller can't sense the audio accessory, so the phone can't auto‑switch — you run the toggle when you plug the DAC in (and again to turn it off).
- **Power:** host mode holds VBUS at ~100 mA. The script’s auto‑revert means it’s only on while a DAC is actually present.
- **⚠️ Don’t toggle while plugged into a PC or charger.** Forcing host mode then fights the incoming VBUS → contention + a USB reset. Only toggle with the **bare DAC** in the port.
- **Reverts on reboot** (it’s a runtime kernel write). Re‑run the toggle after a reboot, or wire it to a button/widget for convenience.

## Making it convenient (optional)

Since it’s just a root shell command, you can trigger it from anything that can run root: a Tasker/Termux:Widget button, a `service.d` watcher that runs the toggle when you tap a flag file, etc. The core mechanism is the single `option` write above — everything else is just a front‑end.

## Repository layout

- **`device/`** — root scripts that live on the phone under `/data/adb/`
  - `usbc_audio_toggle.sh` — the self-correcting ON↔OFF toggle (the core tool)
  - `usbc_audio_daemon.sh` — a `service.d` watcher that runs the toggle when a flag file is tapped (front-end for a widget)
  - `usbc_daemon_loop.sh` — the watcher loop (re-armed each boot)
- **`linux/`** — host-side helpers, run from a PC over `adb`
  - `usbc-rearm` — (re)start the on-device daemon after a reboot (idempotent)
  - `usbc-rearm-watch` — auto-arm on each USB connect
  - `usbc-rearm-watch-boot` + `autostart/` — run it at login
- **`windows/`** — PowerShell / VBS equivalents of the re-arm helpers
- **`assets/`** — widget icon

## Install (quick)

```sh
adb root
adb push device/usbc_audio_toggle.sh /data/adb/ && adb shell chmod 755 /data/adb/usbc_audio_toggle.sh
# plug in the USB-C DAC, then:
adb shell sh /data/adb/usbc_audio_toggle.sh    # -> "USB-C audio ON"
```

## License

MIT © 2026 taitungsun. The kernel mechanism described here is reverse-engineered
behaviour of the device; the scripts and docs in this repo are released under MIT.
