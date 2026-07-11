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

- **It's a manual toggle to turn ON.** The port controller can't sense the audio accessory, so the phone can't auto‑switch — you run the toggle when you plug the DAC in. Turning **off** is now automatic (see below).
- **Power:** host mode holds VBUS at ~100 mA. Two things keep it from being left on to drain the battery (and block charging): the toggle **auto‑reverts if no DAC enumerates**, and the watcher daemon has an **auto‑off safeguard** — if host mode is on but no DAC (`card 2`) has been present for ~10 s, it reverts host mode on its own. So unplugging the DAC without toggling off can no longer leave VBUS draining. (Verified on hardware: pulling the DAC drops `card 2`, and the daemon reverts within ~10 s.)
- **⚠️ Don’t toggle while plugged into a PC or charger.** Forcing host mode then fights the incoming VBUS → contention + a USB reset. Only toggle with the **bare DAC** in the port.
- **The port toggle reverts on reboot** (it’s a runtime kernel write) — press it again after you plug the DAC back in. The *watcher daemon*, however, can be made to start itself every boot: see **[Auto‑start on boot](#auto-start-on-boot-on-device-no-pc-needed)**.

## One-tap widget (Termux:Widget)

The cleanest front-end is a **Termux:Widget** shortcut — tap the widget icon on your home
screen to toggle USB-C audio on/off. Requires Termux + Termux:Widget installed.

**1. Grant `SYSTEM_ALERT_WINDOW` to Termux** (makes the result toast persist; survives reboot):

```sh
adb shell appops set com.termux SYSTEM_ALERT_WINDOW allow
```

**2. Create the shortcut script** (inside Termux):

```sh
mkdir -p ~/.shortcuts
cat > ~/.shortcuts/USB-C\ Audio.sh << ‘EOF’
#!/data/data/com.termux/files/usr/bin/sh
touch ~/.usbc_toggle_req
EOF
chmod 755 ~/.shortcuts/USB-C\ Audio.sh
```

**3. Arm the on-device daemon** from your PC (once per boot):

```sh
# Linux
usbc-rearm          # from linux/usbc-rearm

# Windows
.\usbc-rearm.ps1    # from windows/usbc-rearm.ps1
```

The daemon (`usbc_daemon_loop.sh`) watches for `~/.usbc_toggle_req` and runs the toggle
when it appears. Tapping the widget drops the flag file; the daemon picks it up within
~1 s, runs the toggle, and the result toast pops up.

The same loop also runs the **auto‑off safeguard**: on each pass it checks whether host
mode is on (`option` = 1) while no DAC (`card 2`) is present, and after ~10 s of that
(a debounce that ignores the brief enumeration VBUS race) it writes `2` to turn host mode
back off. This means host mode can't outlive the DAC — unplug the earphone and VBUS stops
on its own, so it never sits draining ~100 mA or blocking a charge.

**Re-arm after every reboot** — `service.d` doesn’t fire on this device (Magisk boot runner
is dead), so the daemon needs to be started from a PC. The PC-side watcher scripts
(`usbc-rearm-watch` / `usbc-rearm-watch.ps1`) do this automatically on each USB connect.

## Auto-start on boot, on-device (no PC needed)

The watcher daemon has to be (re)started after every reboot. The `linux/` and `windows/`
helpers do that from a PC whenever the phone connects — fine when you’re tethered, but a
reboot away from a computer leaves the daemon dead until you next plug in.

You can make the phone arm the daemon **itself, every boot, with no PC** — and **without
Magisk and without patching SELinux policy**. Two things about this build make it clean:

1. **`/vendor` is writable at runtime with no dm‑verity** (bootloader unlocked / `orange`
   verified‑boot state), so a file added there persists across reboots.
2. Its SELinux policy keeps a **permissive, init‑launchable domain, `phhsu_daemon`**
   (inherited from the build’s phh/AOSP‑GSI lineage — you can see stock `.rc` files using
   `seclabel u:r:phhsu_daemon:s0`). A boot service labelled into that domain runs as
   unconfined root, so there’s nothing to patch. This matters because **Magisk’s
   boot‑script runner does not execute on this device**, so `service.d`/`post-fs-data.d`
   never fire — the usual root‑autostart route is a dead end here.

So we register a plain **`init` service** that starts the daemon at `boot_completed`.
`init` then owns and **supervises** it: if the daemon ever dies, init respawns it — more
robust than the PC re‑arm.

### The service (`device/usbc-audio-autostart.rc`)

```
service usbc_audio_daemon /system/bin/sh /data/adb/usbc_daemon_loop.sh
    user root
    group root system
    seclabel u:r:phhsu_daemon:s0
    disabled

on property:sys.boot_completed=1
    start usbc_audio_daemon
```

### Install

```sh
adb root
adb push device/usbc_daemon_loop.sh  /data/adb/ && adb shell chmod 755 /data/adb/usbc_daemon_loop.sh
adb push device/install-autostart.sh /data/adb/ && adb shell sh /data/adb/install-autostart.sh
adb reboot
```

`install-autostart.sh` remounts `/vendor` read‑write and drops the service into
`/vendor/etc/init/` with the correct SELinux label.

> **Heads‑up on the F21 Pro’s full `/vendor`:** the partition is 100 % used, so a brand‑new
> file can’t be allocated (the “free” space `df` reports is unusable reserve). The installer
> falls back to **appending the service block into an existing `.rc`’s last‑block slack** —
> an in‑place grow that needs no new block. Corollary: **never `cp`/rewrite a file on a full
> `/vendor`** — a truncate frees its block and you can’t get it back. Append only.

### Verify

```sh
adb shell getprop init.svc.usbc_audio_daemon   # -> running
```

Confirmed untethered: booted on battery with no cable attached, the daemon armed itself at
~40 s of uptime — minutes before USB was ever reconnected. The port `option` write is still
a runtime toggle you press when you plug the DAC in; this only makes the *daemon* survive a
reboot on its own.

## Repository layout

- **`device/`** — root scripts that live on the phone under `/data/adb/`
  - `usbc_audio_toggle.sh` — the self-correcting ON↔OFF toggle (the core tool)
  - `usbc_audio_daemon.sh` — a `service.d` watcher that runs the toggle when a flag file is tapped (front-end for a widget)
  - `usbc_daemon_loop.sh` — the watcher loop
  - `usbc-audio-autostart.rc` — `init` service that starts the daemon on boot (see “Auto‑start on boot”)
  - `install-autostart.sh` — installs that service into `/vendor/etc/init/` (on‑device, no PC)
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

## Troubleshooting

- **adb keeps dropping / `device descriptor read/64, error -32` in `dmesg`.** This is a
  marginal **USB-C cable**, not the phone — swap to a known-good cable and use a direct
  port (no hub). Verified fix; a bad cable also causes "stuck charging" symptoms.
- **adb shows the device then loses it after the toggle.** Expected if you toggled while
  on the PC — host mode fights the PC's VBUS and resets the bus (see the caveat above).
  Re-run `adb kill-server && adb start-server` to re-grab the re-enumerated device.
- **Daemon won't auto-start on a fresh boot (no PC).** Magisk's boot-script runner doesn't
  execute on this device, so `service.d` never fires on its own. The proper fix is the
  on-device **[Auto‑start on boot](#auto-start-on-boot-on-device-no-pc-needed)** `init`
  service (`install-autostart.sh`); the `linux/`/`windows/` PC helpers remain as a fallback
  for arming it while tethered. The daemon self-guards against duplicates via a pidfile, so
  arming it more than once (e.g. init + a PC re-arm) is safe.

## License

MIT © 2026 taitungsun. The kernel mechanism described here is reverse-engineered
behaviour of the device; the scripts and docs in this repo are released under MIT.
