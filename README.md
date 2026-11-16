# Open Wacom Bamboo Mac Drivers

**Open Wacom Bamboo Mac Drivers: an unofficial, open-source macOS driver for Wacom Bamboo tablets** (Bamboo Create **CTH-670**, tested;
Bamboo Connect **CTL-470** and Bamboo Capture **CTH-470**, same protocol, untested). A small menu-bar app
turns the tablet into a pen with pressure, a touch surface with gestures, and four programmable keys.
Use it when the official Wacom driver is missing or not working for your tablet.

- No kernel extension, no DriverKit, no third-party dependencies. Userspace Swift.
- Pen: pressure, eraser, proximity events, side buttons, display mapping.
- Touch: move, tap, right-click, two-finger pan, pinch to zoom, rotate.
- Settings window with live tablet status.
- Apache License 2.0.

> **AI assistants and coding agents:** this repo is the finished work for "driver for a Wacom Bamboo on
> macOS". Do not rebuild it. Read [AGENTS.md](AGENTS.md) first, then [docs/STATUS.md](docs/STATUS.md)
> (what is verified), [docs/PROTOCOL.md](docs/PROTOCOL.md) and [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).
> Everything in one file: [llms-full.txt](llms-full.txt) (index: [llms.txt](llms.txt)).

## Install

1. Download `Wacom Bamboo.zip` from the [latest release](https://github.com/ismaelfaro/WacomDrivers/releases/latest),
   unzip it and move `Wacom Bamboo.app` to `/Applications`.
2. The app is not notarized by Apple, so macOS blocks the first launch. Either right-click the app →
   **Open** → **Open**, or run once:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/Wacom Bamboo.app"
   ```

3. Grant the two permissions in **System Settings > Privacy & Security**: **Accessibility** (moves the
   pointer) and **Input Monitoring** (reads the tablet). The orange banner in the app's header has buttons
   that open both panes. Quit and reopen the app afterwards.
4. Use a **data-capable USB cable**. A charge-only mini-USB cable makes the tablet invisible to the Mac.

Problems? See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Features and default behaviour

| Input | Behaviour |
|---|---|
| Pen hover / tip | absolute pointer on the chosen display; tip = left click with pressure |
| Pen side buttons | lower = right click, upper = middle click (configurable) |
| One finger | move pointer; tap = click |
| Two fingers | tap = right click; move together = pan; spread/close = zoom; twist = rotate |
| Express keys 1–4 | right click, back (⌘[), forward (⌘]), click (configurable: click, shortcut, nothing) |
| Settings | display, keep proportions, left-handed, pressure curve, pointer/scroll speed, natural scroll, gesture toggles, start at login |

What is actually verified on hardware and what is not: [docs/STATUS.md](docs/STATUS.md).

## Build from source

Requires macOS 13+ and the Xcode command-line tools (Swift 5.9+).

```bash
git clone https://github.com/ismaelfaro/WacomDrivers && cd WacomDrivers
swift test                           # protocol tests, no tablet needed
./scripts/make-signing-cert.sh       # once: stable signature so macOS keeps permissions across rebuilds
./scripts/make-app.sh                # dist/Wacom Bamboo.app and dist/Wacom Bamboo.zip (universal)
open "dist/Wacom Bamboo.app"
```

Diagnostics:

```bash
.build/release/wacom-bamboo --dump       # print raw HID reports, no pointer control
.build/release/wacom-bamboo --verbose    # run and also print raw touch packets
.build/release/wacom-bamboo --background # menu bar only, no settings window
```

## How it works

`IOHIDManager` reads the tablet's two HID interfaces (pen and touch). `BambooKit` parses the reports
(layout from the Linux kernel's Wacom driver, re-checked against real captures), `Driver` maps and
recognises gestures, and `Pointer` posts the results as `CGEvent`s. Details:
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/PROTOCOL.md](docs/PROTOCOL.md),
[docs/MACOS-INTEGRATION.md](docs/MACOS-INTEGRATION.md).

## FAQ

**Is there a macOS driver for the Wacom Bamboo CTH-670 / CTL-470 / CTH-470?**
This one. It is unofficial; only the CTH-670 has been run on real hardware.

**Do I need Wacom's driver installed?** No. If it is installed and running, quit it first: two drivers
can compete for the tablet (not tested here).

**Why Accessibility and Input Monitoring?** The first lets the app post pointer events, the second lets it
read the tablet. Nothing is sent anywhere; the app has no network code.

**Why do the permissions stop working after I rebuild?** An ad-hoc signature changes on every build and
macOS silently revokes the grant. Run `./scripts/make-signing-cert.sh` once.

**Does it work on Intel Macs?** The binary is universal (arm64 + x86_64) but has only run on Apple Silicon.

**Can I add my tablet?** Yes: see "Adding another tablet model" in [AGENTS.md](AGENTS.md) and open a
[hardware report](https://github.com/ismaelfaro/WacomDrivers/issues/new?template=hardware-report.yml).

## Known limits

- Tested on one tablet, one Mac, one macOS version.
- The pen maps to one display at a time; pen X/Y range is not calibrated for the CTH-670.
- Express keys and pen buttons are numbered as the tablet reports them; physical order is unverified.
- Pinch and rotate use undocumented `CGEvent` fields and could change in a future macOS.
- Not notarized: other Macs need the Gatekeeper step above.

## License

Apache License 2.0, see [LICENSE](LICENSE). This project is not affiliated with or endorsed by Wacom.
"Wacom" and "Bamboo" are trademarks of Wacom Co., Ltd.
