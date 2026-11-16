# Architecture

```
USB tablet
  └─ two HID interfaces (pen, touch)
       └─ IOHIDManager (seize open, falls back to shared) ── Driver.attached / report callbacks
            ├─ parsePen   (BambooKit) ─ Driver.handlePen   ─┐
            └─ parseTouch (BambooKit) ─ Driver.handleTouch ─┤  Pref (UserDefaults) read on every event
                  ├─ one finger  → pointer move              │
                  ├─ tap         → click                     │
                  ├─ two fingers → pan | zoom | rotate       │
                  └─ express keys → Action                   ▼
                                                    Pointer (CGEvent.post → .cghidEventTap)
```

Threading: everything runs on the main run loop (`IOHIDManagerScheduleWithRunLoop` with the main loop),
so `Driver`, `Pointer` and the SwiftUI settings share one thread and need no locking.

## Files

| File | Responsibility |
|---|---|
| `BambooKit/Protocol.swift` | `TabletModel` table, `parsePen`, `parseTouch`, `ExpressKeys`, constants. No I/O. |
| `wacom-bamboo/Driver.swift` | Device lifecycle, pen mapping, touch/gesture recognition, `runAction`. |
| `wacom-bamboo/Pointer.swift` | Posting mouse (with tablet fields), proximity, scroll, pinch, rotate, key events. Tracks held buttons and click count. |
| `wacom-bamboo/Preferences.swift` | `Pref` enum (keys, defaults, typed accessors) and `Action` enum. |
| `wacom-bamboo/SettingsView.swift` | Settings UI bound to `Pref` via `@AppStorage(store: Pref.store)`; `TabletStatus` for the header. |
| `wacom-bamboo/App.swift` | `NSStatusItem` menu, settings window, permission polling every 2 s. |
| `wacom-bamboo/main.swift` | CLI flags (`--dump --verbose --background --check`), app bootstrap. |

## Pen path

1. `parsePen` → `PenReport` (in range, tip, eraser, two buttons, x, y, pressure).
2. First in-range packet posts a **tablet proximity** event (vendor 0x056A, pointer type pen/eraser).
3. Position: normalised x/y (`/penMaxX`, `/penMaxY`), optionally flipped (left-handed), mapped to the
   chosen display, optionally letter-boxed to the tablet's aspect ratio.
4. Pressure: `pow(pressure/1023, Pref.pressureCurve)`; below 1 = softer, above 1 = firmer.
5. Mouse event with tablet subtype 1 carries pressure and absolute point; left button follows the tip.
6. Side buttons run their configured `Action` (default lower = right click, upper = middle click).
7. Leaving range releases everything and posts proximity-out.

## Touch path

Per report: drop stale fingers (> 0.15 s), update finger positions, average finger motion in millimetres
(`dx`, `dy`), then:

- 1 finger and never more than 1 in this gesture → move pointer by `dx*cursorSpeed`, `dy*cursorSpeed` pixels
  once total travel exceeds the 0.3 mm dead zone.
- ≥ 2 fingers → `handleTwoFingers`:
  - Vector between the two lowest slots gives **spread** (length) and **angle**.
  - While `undecided`, accumulate spread change, twist arc (`Δangle × spread`) and pan travel.
    Decide once `relative > 3 mm` or `pan travel > 1.5 mm`:
    pan if `pan travel > 0.8 × relative`, else zoom if `|spread| ≥ |twist|`, else rotate.
  - Locked until fingers lift; phases `began/changed/ended` are posted.
- All fingers up: if the gesture lasted < 0.25 s and moved < 2 mm and tap-to-click is on, click
  (left; right if two fingers were used). Recognised pan/zoom/rotate never tap.
- Pen in range disables touch (palm rejection).

## Constants (`Driver`)

| Constant | Value | Meaning |
|---|---|---|
| `tapMaxSeconds` | 0.25 | longest tap |
| `tapMaxTravelMM` | 2.0 | most movement still a tap |
| `moveDeadzoneMM` | 0.3 | ignore tiny finger jitter |
| `fingerStaleSeconds` | 0.15 | finger without update counts as lifted |
| `relativeStartMM` | 3.0 | pinch/twist threshold |
| `panStartMM` | 1.5 | pan threshold |
| `zoomMMPerUnit` | 50 | 50 mm of spread change = 1.0 magnification |

User-adjustable (see `Pref`): pointer speed (default 10 px/mm, 3–25), scroll speed (6, 2–15),
natural scrolling, zoom/rotate/tap toggles, display, keep proportions, left-handed, pressure curve
(1.0, 0.4–2.5), pen buttons and four express keys.

## Settings storage

`UserDefaults(suiteName: "local.wacom-bamboo")`. The suite name must differ from the bundle identifier
(`local.wacom-bamboo.app`). `Pref.registerDefaults()` runs at launch; `Pref.reset()` clears all keys.
Express key slots map bit→pref: `right`→key1, `back`→key2, `forward`→key3, `left`→key4. Held-action
slots: pen side buttons use 100 and 101, express keys use their bit value (1, 2, 4, 8).
