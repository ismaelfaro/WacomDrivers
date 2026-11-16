# Wacom Bamboo for macOS

An unofficial macOS driver for Wacom Bamboo tablets that Apple and Wacom no longer support:
**CTH-670** (tested), and CTH-470 / CTL-470 (same protocol, untested).

A small menu-bar app reads the tablet over USB and turns it into pointer, pen pressure,
gestures and shortcuts. No kernel extension and no system changes.

## Features

- **Pen:** absolute mapping to a chosen display, pressure curve, eraser, and tablet
  proximity events so drawing apps see a real pen. Side buttons are configurable.
- **Touch:** one finger moves the pointer, tap to click, two-finger tap for right click,
  two-finger pan, pinch to zoom, two-finger rotate.
- **Express keys:** each of the four can be set to a click, a shortcut (back, forward, undo, redo) or nothing.
- **Settings window** (Pen, Touch, Keys tabs), opened from the menu-bar icon.

## Install

Download `Wacom Bamboo.zip` from the [latest release](../../releases), unzip it, and move
`Wacom Bamboo.app` to `/Applications`.

The app is not notarized by Apple, so macOS blocks it the first time. Either:

- right-click the app, choose **Open**, then **Open** again; or
- run once in Terminal:

  ```bash
  xattr -dr com.apple.quarantine "/Applications/Wacom Bamboo.app"
  ```

Then grant the two permissions it asks for in **System Settings > Privacy & Security**:

- **Accessibility** (moves the pointer)
- **Input Monitoring** (reads the tablet)

Restart the app after granting them.

## Build from source

Requires macOS 13 or later and Xcode command line tools.

```bash
./scripts/make-app.sh          # builds dist/Wacom Bamboo.app and dist/Wacom Bamboo.zip
swift test                     # protocol parser tests
```

Diagnostics:

```bash
.build/release/wacom-bamboo --dump      # print raw HID reports
.build/release/wacom-bamboo --verbose   # also log raw touch packets
```

## How it works

- `Sources/BambooKit/Protocol.swift` parses the pen and touch HID reports. The layout follows
  the Linux kernel driver (`drivers/hid/wacom_wac.c`).
- `Sources/wacom-bamboo/Driver.swift` reads reports via IOHIDManager and runs the gesture logic.
- `Sources/wacom-bamboo/Pointer.swift` posts events with CoreGraphics.
- Pinch and rotate use gesture event types that have no public API. They are checked against
  AppKit's decoding but could change in a future macOS.

## Known limits

- Tested on one tablet only. Other models share the protocol but are unverified.
- Pen maps to one display at a time. Pen buttons and express keys are numbered as the tablet reports them.
- The app is unsigned by an Apple Developer ID, so each rebuild needs the permissions granted again.

## License

Apache License 2.0. See [LICENSE](LICENSE).
This project is not affiliated with or endorsed by Wacom. "Wacom" and "Bamboo" are trademarks of Wacom Co., Ltd.
