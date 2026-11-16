# Troubleshooting

Check top to bottom; each row names the test that separates the causes.

| Symptom | Likely cause | Check | Fix |
|---|---|---|---|
| Header says "Tablet not connected" | tablet not on USB (charge-only cable, bad port/hub) | `ioreg -l -w 0 \| grep -c '"idVendor" = 1386'` prints `0` | use a data cable; plug directly into the Mac; tablet's white light on is not proof of data |
| Tablet connected but pointer never moves | Accessibility not granted to **this build** | orange banner in the header, or `open -n "App" --stdout o.txt --stderr o.txt --args --check` | re-grant: `tccutil reset Accessibility local.wacom-bamboo.app`, reopen app, enable it |
| Banner shows but System Settings toggle is ON | stale entry from an older signature | same as above | `tccutil reset` both services, then enable again; keep a stable signature ([MACOS-INTEGRATION.md](MACOS-INTEGRATION.md)) |
| No reports at all in `--dump` | Input Monitoring missing, or another process seized the device | `pgrep -lf "Wacom Bamboo\|wacom-bamboo"` | grant Input Monitoring, restart app; `pkill -x "Wacom Bamboo"` for extra instances |
| Worked from a terminal, not from Finder | terminal's permissions were used | run via `open -n` | grant permissions to the app itself |
| Worked until I rebuilt | ad-hoc signature changed | `codesign -dr - "dist/Wacom Bamboo.app"` shows `cdhash` | `./scripts/make-signing-cert.sh`, then re-grant once |
| `codesign` fails with `errSecInternalComponent` | no GUI keychain prompt available | run `./scripts/make-app.sh` in a normal Terminal window | approve the keychain dialog: Always Allow |
| `security import` says "MAC verification failed" | PKCS#12 made by OpenSSL 3 | `which -a openssl` | script already uses `/usr/bin/openssl` |
| Logs are empty when redirected | stdout buffering | — | `main.swift` sets line buffering; keep it |
| Pen moves but no pressure in a drawing app | app ignores tablet events, or tip pressure is 0 | event tap should show `tx` and pressure on mouse events | check app's tablet settings; pen must touch the tablet |
| Pointer does not reach screen corners | pen range in `TabletModel` is wrong for this unit | `--dump`, drag the pen to each corner, read max X/Y | correct `TabletModel.all` and `docs/devices.json` |
| One finger moves nothing, two fingers scroll | stale finger stuck | `--verbose` shows finger packets | expiry exists (0.15 s); report packets via a hardware-report issue |
| Settings window cut off | window smaller than content | — | window is 520×780; the permission banner adds height on the Pen tab |
| App blocked on another Mac | Gatekeeper | — | right-click → Open, or `xattr -dr com.apple.quarantine "/Applications/Wacom Bamboo.app"` |
| Pinch/rotate do nothing in an app | the app does not handle these gestures | event tap shows gesture type 29 events | try Preview or Maps; behaviour is per app |

## Useful commands

```bash
ioreg -r -c IOUSBHostDevice -w 0 | grep -E 'CTH|Wacom'                 # on USB?
ioreg -r -c IOHIDDevice -l -w 0 | grep -A12 '"VendorID" = 1386'        # HID interfaces and descriptors
codesign -dr - "dist/Wacom Bamboo.app"                                  # code requirement
security find-identity -p codesigning                                   # signing identities
```
