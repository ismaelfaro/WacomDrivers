# macOS integration notes

Knowledge that is expensive to rediscover.

## Permissions (TCC)

| Permission | Why | Checked with |
|---|---|---|
| Accessibility | post pointer, scroll, key and gesture events | `CGPreflightPostEventAccess()` / `CGRequestPostEventAccess()` |
| Input Monitoring | open the tablet HID device and read reports | `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` / `IOHIDRequestAccess` |

Both are needed. Without Accessibility the app runs and reads the tablet, but the pointer does not move.

### Why permissions "disappear" after a rebuild

macOS ties each grant to the app's **code identity**. An **ad-hoc signature** (`codesign --sign -`) has a
designated requirement of `cdhash H"..."`, and the hash changes on every build. The old entry then stays in
System Settings **with its toggle ON but no longer matches the new binary**, so the app is denied silently.

Symptoms: app shows "Permissions missing"; `open -n App --args --check` prints `NOT granted` while the
toggle looks ON.

Fixes:

1. **Stable signature** (done in this repo): `./scripts/make-signing-cert.sh` creates a self-signed
   code-signing certificate "Wacom Bamboo Local Signing" in the login keychain; `make-app.sh` signs with it.
   The requirement becomes `identifier "local.wacom-bamboo.app" and certificate leaf = H"<cert hash>"`,
   identical across rebuilds (verified by comparing `codesign -dr -` over two builds).
2. **Re-grant once** after switching signature (the user must do this; do not change TCC yourself):

   ```bash
   tccutil reset Accessibility local.wacom-bamboo.app
   tccutil reset ListenEvent   local.wacom-bamboo.app
   ```

   Then open the app, use the header buttons "Accessibility…" / "Input Monitoring…", enable it, quit and reopen.

The certificate shows `CSSMERR_TP_NOT_TRUSTED` in `security find-identity`; that is normal for self-signed
and does not prevent signing. The first `codesign` use may show a keychain dialog: choose **Always Allow**.
Over a non-GUI session `codesign` can fail with `errSecInternalComponent`; `make-app.sh` then falls back to
an ad-hoc signature.

`security import` rejected a PKCS#12 made by Homebrew OpenSSL 3 ("MAC verification failed"); the script uses
the system `/usr/bin/openssl` (LibreSSL), which works.

### Whose permissions does a process use?

A process started from a terminal (or from Claude Code's shell) is attributed to the **responsible
parent app** and inherits its grants. So running the binary from a shell can work while the same app
opened from Finder is denied. Launch through LaunchServices to test the app's own state:

```bash
open -n "dist/Wacom Bamboo.app" --stdout out.txt --stderr out.txt --args --check
```

`Input Monitoring` changes only apply after the app restarts.

## Reading the tablet

- `IOHIDManager` with a matching dictionary for vendor `0x056A` and each product ID.
- Opened with `kIOHIDOptionsTypeSeizeDevice` first so macOS stops also treating the tablet as a mouse;
  falls back to `kIOHIDOptionsTypeNone`. `--dump` never seizes.
- Reports arrive via `IOHIDDeviceRegisterInputReportCallback` on the main run loop.
- Report ID byte is included in the buffer (byte 0).

## Injecting events

All events are posted with `CGEvent.post(tap: .cghidEventTap)` from a `.hidSystemState` source.

- **Pen:** mouse events with `mouseEventSubtype = 1` (tablet point), plus `mouseEventPressure`,
  `tabletEventPointX/Y/Pressure`, and a separate `tabletProximity` event on enter/leave. A listen-only event
  tap confirmed proximity events with vendor ID 1386 and pressure values reach the session.
- **Clicks:** `Pointer` tracks held buttons (`.left`, `.right`, `.center`), turns moves into drags while a
  button is held, and counts clicks (same button, < 0.4 s, < 6 px) for double/triple click.
- **Scroll:** `scrollWheelEvent2` in pixel units with `scrollWheelEventScrollPhase` set, so apps treat it as
  trackpad-style pan.
- **Pinch / rotate:** no public API. Built by creating a `CGEvent`, setting `type` to raw `29`
  (NSEvent gesture type), field `110` = gesture kind (**8 = zoom/magnify, 5 = rotate**), field `113` = value
  (magnification delta; rotation in degrees, counterclockwise positive), field `132` = phase
  (1 began, 2 changed, 4 ended). Verified by round-trip through `NSEvent(cgEvent:)`, which yields
  `.magnify` / `.rotate` with the right values and phases. These are undocumented and may change.
- **Shortcuts:** key events with virtual keys `33` (`[`), `30` (`]`), `6` (`Z`) and modifier flags.

## Packaging

- `./scripts/make-app.sh` builds `--arch arm64 --arch x86_64` (SwiftPM prints a deprecation warning for
  x86_64 on newer deployment targets; harmless), assembles `Wacom Bamboo.app` from
  `Resources/Info.plist` and `Resources/AppIcon.icns`, signs, and zips with `ditto`.
- `LSUIElement` is true and the activation policy is `.accessory`: menu-bar only, no Dock icon.
- Bundle identifier `local.wacom-bamboo.app`. "Start at login" uses `SMAppService.mainApp` (macOS 13+) and
  only works from a real app bundle.
- **Gatekeeper:** the app is not notarized (no Apple Developer ID). On another Mac, right-click → Open, or
  `xattr -dr com.apple.quarantine "/Applications/Wacom Bamboo.app"`. The other Mac does not have the local
  certificate, so the permission prompts happen there once per installed build identity.
