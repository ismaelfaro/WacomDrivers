# Protocol: Wacom Bamboo (3rd generation) over USB HID

Everything here was observed on one **CTH-670** (USB `056a:00df`) unless marked *(Linux)*, meaning it
comes from the layout used by the Linux kernel driver (`drivers/hid/wacom_wac.c`, `wacom_bpt_pen` and
`wacom_bpt3_touch`) and was only partly re-checked on hardware. See [STATUS.md](STATUS.md).

## Device

| Property | Value |
|---|---|
| USB vendor / product | `0x056A` / `0x00DF` (CTH-670); `0xDD` CTL-470 and `0xDE` CTH-470 *(Linux, untested)* |
| Strings | manufacturer "Wacom Co.,Ltd.", product "CTH-670", HID name "Bamboo Create CTH-670" |
| bcdDevice | `0x0100` |
| Interfaces | two HID interfaces (pen, touch) |

On macOS they appear as two `IOHIDDevice`s with the same vendor/product IDs.

## Interface 1: pen (and legacy mouse)

IOHID properties: `MaxInputReportSize` 10, `MaxFeatureReportSize` 32, primary usage page 1 usage 2 (mouse).

Report descriptor (hex, from `ioreg`):

```
05010902a10185010901a100050919012905150025019505750181029501750381010501093009311581257f750895028106c0c0
050d0901a1018502a1000600ff0901150026ff00750895098102c0
090185029501b102 090185039501b102 090185049501b102 090185059501b102 090185109502b102
090185119510b102 090185139501b102 090185209501b102 09018514951fb102 09018530951fb102
090185319504b11f
85c0 0900 9509 8102 c0
```

Meaning:

- Report ID 1: boot-style relative mouse (3 buttons, X/Y). This is what macOS would use by default.
- **Report ID 2: pen, 9 data bytes → 10 bytes with the ID.** This is the one the driver uses.
- Feature reports IDs 2, 3, 4, 5, 0x10, 0x11, 0x13, 0x14, 0x20, 0x21, 0x30, 0x31 (vendor).
- Report ID 0xC0, 9 bytes: seen once at startup (`c0 00 .. 00 01`); ignored.

### Switching to tablet mode

The driver sends feature report **ID 2 with payload `02 02`** (`penModeReport` in `Protocol.swift`) when
the pen interface attaches. After that, ID 2 packets stream. Whether the OS already streams ID 2 without
this request was **not isolated**; it is sent as a precaution matching the Linux driver *(Linux)*.

### Pen input report (ID 2), 10 bytes

```
byte  0     0x02          report ID
byte  1     flags
byte  2-3   X, little endian
byte  4-5   Y, little endian
byte  6-7   pressure, little endian
byte  8     unknown (values 0x0a, 0x1a, 0x1f seen; tilt/distance, not decoded)
byte  9     0x00
```

Flags (byte 1), as parsed by `parsePen`:

| Bit | Meaning | Evidence |
|---|---|---|
| `0x20` | pen in range (proximity) | parsed; hover packets are `0xE0`, so `0x20` is set while hovering |
| `0x01` | tip touching | `0xE1` packets dominate while drawing |
| `0x08` | eraser end | *(Linux)*, not verified |
| `0x02` / `0x04` | side button 1 / 2 | *(Linux)*, not verified which is physically lower/upper |
| `0x80`, `0x40` | always set while in range in captures | meaning unknown |

Real captured packets:

```
02 e1 cb 0e dc 13 3f 03 1f 00     tip down  x=0x0ecb(3787) y=0x13dc(5084) pressure=0x033f(831)
02 e1 21 0f 04 13 48 03 1a 00     tip down
```

Ranges seen in a short capture: X up to 11544, Y up to 9517, pressure up to 949 (of 1023). That capture
did not reach the corners, so the **real maximum X/Y of the CTH-670 is not calibrated**. The driver uses
21648 × 13700 from the Linux table; if the pointer does not reach the display edges, measure the corners
with `--dump` and fix `TabletModel.all` and `docs/devices.json`.

## Interface 2: touch and express keys

IOHID: `MaxInputReportSize` 64, `MaxFeatureReportSize` 1, usage page `0xFF00` usage `0x80` (vendor).

Report descriptor: `0600ff0980a10285027508953f1500260010810185037508953f8101c0`

- Report IDs 2 and 3, 63 data bytes each, logical maximum `0x1000` (4096).
- The driver only parses ID 2.

### Touch input report (ID 2), 64 bytes

```
byte 0     0x02            report ID
byte 1     message count (low 3 bits), up to 7
byte 2+    count × 8-byte messages
```

Message layout (`parseTouch`):

| Message id (byte 0) | Meaning |
|---|---|
| `2`–`17` | finger slot; byte 1 bit `0x80` = finger down; X = `b2<<4 \| b4>>4`, Y = `b3<<4 \| b4&0x0F` (12 bits each, 0–4095) |
| `128` (`0x80`) | express keys, bits `b1 & 0x0F` *(Linux)*; **no key press captured on hardware yet** |
| `0x81` | seen continuously (~100/s) as `02 01 81 00 00 00 00 00 00 00` while idle; treated as no-op |

Real captured finger packets (message = 8 bytes after count):

```
02 01 02 c0 d9 cc a6 0d 32 51     one finger, slot 2, flags 0xC0, x=0xd9a y=0xcc6
02 02 02 90 db c6 36 14 3e 71 03 c0 ad a5 51 03 1b 00     two fingers: slots 2 and 3
02 01 80 00 80 00 00 00 00 00     id 0x80 with other bytes, seen near finger lifts (meaning unknown)
```

Observed behaviour that shaped the driver:

- Finger-up packets are not reliably delivered, so `Driver` drops a finger after 0.15 s without update.
- Finger slot numbers are reused, so two-finger gestures use the two lowest slot numbers present.
- Active area maps to 4096 × 4096 logical units regardless of the physical aspect ratio; the driver
  scales by physical size (`widthMM`/`heightMM`) so motion is isotropic.

## Checking for a new unit

```bash
ioreg -l -w 0 | grep -c '"idVendor" = 1386'       # 1386 = 0x056A; 0 means not on USB
.build/release/wacom-bamboo --dump                # raw reports; touch lines are 64 bytes, pen lines 10
```
