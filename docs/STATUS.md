# Status: what is verified, what is not

Test setup: one Wacom Bamboo Create **CTH-670**, Apple Silicon Mac, macOS 27.2.1, Swift 6.4.2.
"Event tap" means a listen-only `CGEvent` tap recorded what the driver posted.

## Verified

| Area | Evidence |
|---|---|
| Tablet enumerates as `056a:00df`, two HID interfaces | `ioreg` (see [PROTOCOL.md](PROTOCOL.md)); needed a data-capable cable |
| Raw reports stream on both interfaces | `--dump`: 10-byte pen packets, 64-byte touch packets (~100/s idle) |
| Pen report layout (position, tip, pressure) | real packets decoded; pressure reached 949/1023 |
| Pen events reach apps | event tap: tablet proximity enter/leave with vendor 1386, mouse events with tablet subtype and pressure 0.08–0.73, down/up with click counts |
| One-finger pointer move, tap-to-click, two-finger pan | user confirmed touch works; event tap showed scroll events with began/changed/ended phases |
| Pinch events are generated | event tap: gesture events (kind 8) with phases 1/2/4 |
| Synthetic pinch/rotate decode in AppKit | `NSEvent(cgEvent:)` gives `.magnify` / `.rotate` with correct value and phase |
| Settings window: Pen, Touch, Keys tabs fit without scrolling, live status header | screenshots |
| "Permissions missing" banner appears when the app lacks a grant | screenshot; `--check` via `open -n` reported `Accessibility NOT granted` for a rebuilt app |
| Stable signing requirement across rebuilds | `codesign -dr -` identical for two builds (`identifier … and certificate leaf = H"…"`) |
| Tablet works with the app after permissions are granted | user confirmed (app started from a shell that holds the grants) |
| Unit tests pass (protocol parsing, docs in sync with code) | `swift test` |

## Not verified (do not claim as working)

| Area | State |
|---|---|
| Express keys | no key packet captured; the `0x80` message layout is from the Linux driver. Mapping of key 1–4 to physical keys unknown. |
| Pen side buttons | bit→button from Linux; which is physically lower/upper unknown |
| Eraser end | bit from Linux, never exercised |
| Pen X/Y maximum | 21648 × 13700 comes from the Linux table; a short capture only reached 11544 × 9517 |
| Rotate gesture | implemented and built; no event capture, no app test |
| Pinch / pan inside real apps | events are posted; app behaviour not confirmed |
| Natural scroll direction | default `true` keeps the originally shipped direction; not compared against trackpad |
| Display mapping options | choosing another display, keep proportions, left-handed, pressure curve: code paths exist, not exercised with the tablet |
| Finger-up packets | suspected unreliable (hence 0.15 s timeout); root cause not confirmed |
| CTL-470, CTH-470 | IDs, sizes and pen ranges are from the Linux table, no hardware |
| Intel Macs, other macOS versions | universal binary builds; never run on Intel |
| Start at login, other-Mac install, Gatekeeper flow | not tested |
| Finder-launched app with the stable signature | grant steps documented; final confirmation pending |

## Decisions and why (so nobody redoes them)

| Decision | Reason |
|---|---|
| Userspace app (IOHIDManager + CGEvent), no kext/DriverKit | works with only two TCC permissions; no entitlements or Developer ID needed |
| Reuse the Linux kernel driver's packet layout | Bamboo 3rd-gen protocol is documented there; real captures matched for pen and fingers |
| Seize the device, fall back to shared open | avoids macOS also moving the pointer from the boot-mouse report |
| Drop fingers after 0.15 s without update | one-finger movement produced no events until stale fingers were expired (two-finger scroll still worked) |
| Classify two-finger gestures once, then lock | prevents pan/zoom/rotate flipping mid-gesture |
| Pinch/rotate via private CGEvent fields | only way to synthesise magnify/rotate gestures without a private framework |
| Self-signed local certificate | ad-hoc signatures change per build and silently revoke TCC grants |
| Pen side-button slots 100/101, express keys by bit | an earlier version shared slot 1 between the upper pen button and the right express key |

## Chronology of problems solved

1. **No device on USB** → mini-USB cable was charge-only or faulty; tablet appeared after reconnecting
   with a working setup. Light on but no enumeration was the clue.
2. **Pointer did not follow one finger** → stale finger expiry.
3. **No pinch/pan** → added phased scroll and magnify events; later rotate.
4. **Permissions lost after rebuild** → diagnosed as signature change; added in-app warning, `--check`,
   stable certificate script and reset instructions.
5. **Empty logs** → stdout was fully buffered when redirected; now line-buffered.

## How to verify something new

1. Ask the user to perform the action on the tablet.
2. Read evidence from `.build/release/wacom-bamboo --dump` (raw) or `--verbose`, or record posted events
   with a listen-only `CGEvent` tap.
3. Move the row from "Not verified" to "Verified" here, with the evidence, and run
   `./scripts/make-llms-full.sh`.
