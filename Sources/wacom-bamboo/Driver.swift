import AppKit
import BambooKit
import CoreGraphics
import Foundation
import IOKit
import IOKit.hid

/// Reads raw HID reports from the tablet and turns them into pointer, gesture and key events.
final class Driver {
    // Fixed tuning. Speeds and feature toggles come from `Pref`.
    static let tapMaxSeconds = 0.25
    static let tapMaxTravelMM = 2.0
    static let moveDeadzoneMM = 0.3
    /// A finger with no update for this long is treated as lifted (guards against a missed "up").
    static let fingerStaleSeconds = 0.15
    /// Two-finger gesture is classified once the fingers move this far relative to each other
    /// (pinch or twist) or travel this far together (pan).
    static let relativeStartMM = 3.0
    static let panStartMM = 1.5
    /// Change in finger spread that doubles the zoom.
    static let zoomMMPerUnit = 50.0

    /// Express key bits and the preference that chooses what each one does.
    private static let expressKeys: [(bit: ExpressKeys, pref: Pref)] = [
        (.right, .key1), (.back, .key2), (.forward, .key3), (.left, .key4),
    ]

    enum TwoFingerGesture {
        case undecided, pan, zoom, rotate
    }

    let dump: Bool
    let verbose: Bool
    let pointer = Pointer()
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    var model = TabletModel.find(productID: 0xDF)!
    var buffers: [IOHIDDevice: UnsafeMutablePointer<UInt8>] = [:]

    /// Called on the main run loop with the tablet name when it attaches, nil when it leaves.
    var onConnectionChange: ((String?) -> Void)?

    var touchEnabled: Bool { Pref.touchEnabled.bool }

    var penInRange = false
    var penEraser = false
    /// Actions currently held down, so a release runs the same action even if the setting changed.
    /// Pen side buttons use 100 and 101; express keys use their ExpressKeys raw bit (1, 2, 4, 8).
    var heldActions: [Int: Action] = [:]
    private static let penSlotBase = 100

    var fingers: [Int: (x: Int, y: Int, time: TimeInterval)] = [:]
    var gestureStart: TimeInterval?
    var gestureMaxFingers = 0
    var gestureTravelMM = 0.0
    var scrollRemainder = CGPoint.zero
    var twoFinger: TwoFingerGesture?
    var twoFingerStarted = false
    var lastSpread: (ids: [Int], mm: Double, angle: Double)?
    var spreadChangeMM = 0.0
    var twistArcMM = 0.0
    var panTravel = CGPoint.zero

    init(dump: Bool, verbose: Bool) {
        self.dump = dump
        self.verbose = verbose
    }

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let matching = TabletModel.all.map {
            [kIOHIDVendorIDKey: wacomVendorID, kIOHIDProductIDKey: $0.productID]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<Driver>.fromOpaque(context!).takeUnretainedValue().attached(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<Driver>.fromOpaque(context!).takeUnretainedValue().removed(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        // Seizing keeps macOS from also treating the tablet as a plain mouse. Dump mode only listens.
        var result = kIOReturnError
        if !dump {
            result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        }
        if result != kIOReturnSuccess {
            result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if result != kIOReturnSuccess {
            print(String(format: "Could not open HID manager (0x%08X). Grant Input Monitoring in System Settings > Privacy & Security.", result))
        }
    }

    func stop() {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        for buffer in buffers.values { buffer.deallocate() }
        buffers.removeAll()
        releaseEverything()
    }

    func attached(_ device: IOHIDDevice) {
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let reportSize = max(IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 64, 16)
        if let found = TabletModel.find(productID: productID) { model = found }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportSize)
        buffers[device] = buffer
        IOHIDDeviceRegisterInputReportCallback(device, buffer, reportSize, { context, _, _, _, _, report, length in
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            Unmanaged<Driver>.fromOpaque(context!).takeUnretainedValue().report(bytes)
        }, Unmanaged.passUnretained(self).toOpaque())

        let isPen = reportSize < 20
        if isPen {
            let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, penModeReportID, penModeReport, penModeReport.count)
            if result != kIOReturnSuccess {
                print(String(format: "Could not switch pen to tablet mode (0x%08X)", result))
            }
        }
        print("Attached \(model.name) \(isPen ? "pen" : "touch") interface")
        onConnectionChange?(model.name)
    }

    func removed(_ device: IOHIDDevice) {
        buffers.removeValue(forKey: device)?.deallocate()
        guard buffers.isEmpty else { return }
        print("Tablet disconnected")
        releaseEverything()
        onConnectionChange?(nil)
    }

    /// Ends every held press and gesture, so nothing stays stuck when the tablet goes away.
    private func releaseEverything() {
        let position = pointer.location
        for (slot, action) in heldActions {
            runAction(action, down: false, at: position, slot: slot)
        }
        heldActions.removeAll()
        if penInRange { pointer.proximity(entering: false, eraser: penEraser, productID: model.productID) }
        penInRange = false
        fingers.removeAll()
        gestureStart = nil
        endTwoFingers()
        pointer.releaseAll()
    }

    func report(_ bytes: [UInt8]) {
        if dump {
            print(bytes.map { String(format: "%02x", $0) }.joined(separator: " "))
            return
        }
        if bytes.count >= 20 {
            if verbose {
                let used = min(bytes.count, 2 + Int(bytes[1] & 0x07) * 8)
                print("touch", bytes[..<used].map { String(format: "%02x", $0) }.joined(separator: " "))
            }
            handleTouch(parseTouch(bytes))
        } else if let pen = parsePen(bytes) {
            handlePen(pen)
        }
    }

    // MARK: Actions

    /// Runs what a button or key is set to do. `slot` identifies the physical control for release.
    func runAction(_ action: Action, down: Bool, at position: CGPoint, slot: Int) {
        if down { heldActions[slot] = action } else { heldActions.removeValue(forKey: slot) }
        switch action {
        case .none: break
        case .leftClick: pointer.button(.left, down: down, at: position)
        case .rightClick: pointer.button(.right, down: down, at: position)
        case .middleClick: pointer.button(.center, down: down, at: position)
        // Shortcuts fire once, on press. CGEvent key posting sends down and up together.
        case .back: if down { pointer.key(33, flags: .maskCommand) } // Cmd+[
        case .forward: if down { pointer.key(30, flags: .maskCommand) } // Cmd+]
        case .undo: if down { pointer.key(6, flags: .maskCommand) } // Cmd+Z
        case .redo: if down { pointer.key(6, flags: [.maskCommand, .maskShift]) } // Shift+Cmd+Z
        }
    }

    // MARK: Pen

    func handlePen(_ pen: PenReport) {
        guard pen.inRange else {
            if penInRange { leavePen() }
            return
        }
        if !penInRange {
            penInRange = true
            penEraser = pen.eraser
            fingers.removeAll()
            gestureStart = nil
            endTwoFingers()
            pointer.proximity(entering: true, eraser: penEraser, productID: model.productID)
        }

        let position = penPosition(pen)
        let curve = Pref.pressureCurve.double
        let raw = pen.tip ? min(Double(pen.pressure) / Double(penMaxPressure), 1) : 0
        // Curve below 1 makes light pressure register sooner; above 1 needs a firmer press.
        let point = TabletPoint(x: pen.x, y: pen.y, pressure: pow(raw, curve))

        pointer.move(to: position, tablet: point)
        pointer.button(.left, down: pen.tip, at: position, tablet: point)
        sideButton(0, pressed: pen.button1, action: Pref.penButton1.action, at: position)
        sideButton(1, pressed: pen.button2, action: Pref.penButton2.action, at: position)
    }

    private func sideButton(_ index: Int, pressed: Bool, action: Action, at position: CGPoint) {
        let slot = Self.penSlotBase + index
        let isDown = heldActions[slot] != nil
        guard pressed != isDown else { return }
        if pressed {
            runAction(action, down: true, at: position, slot: slot)
        } else if let held = heldActions[slot] {
            runAction(held, down: false, at: position, slot: slot)
        }
    }

    private func leavePen() {
        let position = pointer.location
        for slot in [Self.penSlotBase, Self.penSlotBase + 1] where heldActions[slot] != nil {
            runAction(heldActions[slot]!, down: false, at: position, slot: slot)
        }
        pointer.releaseAll()
        pointer.proximity(entering: false, eraser: penEraser, productID: model.productID)
        penInRange = false
    }

    /// Maps the pen onto the chosen display, optionally keeping the tablet's shape and turning it 180°.
    private func penPosition(_ pen: PenReport) -> CGPoint {
        let displayID = Pref.displayID.int == 0 ? CGMainDisplayID() : CGDirectDisplayID(Pref.displayID.int)
        let bounds = CGDisplayBounds(displayID)
        var nx = Double(pen.x) / Double(model.penMaxX)
        var ny = Double(pen.y) / Double(model.penMaxY)
        if Pref.leftHanded.bool {
            nx = 1 - nx
            ny = 1 - ny
        }
        var width = bounds.width, height = bounds.height, offsetX = 0.0, offsetY = 0.0
        if Pref.keepProportions.bool {
            let tabletAspect = model.widthMM / model.heightMM
            if width / height > tabletAspect {
                let used = height * tabletAspect
                offsetX = (width - used) / 2
                width = used
            } else {
                let used = width / tabletAspect
                offsetY = (height - used) / 2
                height = used
            }
        }
        return CGPoint(x: bounds.minX + offsetX + nx * (width - 1),
                       y: bounds.minY + offsetY + ny * (height - 1))
    }

    // MARK: Touch and express keys

    func handleTouch(_ messages: [TouchMessage]) {
        let now = ProcessInfo.processInfo.systemUptime
        fingers = fingers.filter { now - $0.value.time < Self.fingerStaleSeconds }
        var sumX = 0.0, sumY = 0.0, moved = 0.0
        for message in messages {
            switch message {
            case .keys(let pressed):
                handleKeys(pressed)
            case let .finger(id, down, x, y):
                guard touchEnabled, !penInRange else { continue }
                if down {
                    if let old = fingers[id] {
                        sumX += Double(x - old.x)
                        sumY += Double(y - old.y)
                        moved += 1
                    }
                    fingers[id] = (x, y, now)
                } else {
                    fingers[id] = nil
                }
            }
        }

        if !fingers.isEmpty, gestureStart == nil {
            gestureStart = now
            gestureMaxFingers = 0
            gestureTravelMM = 0
            scrollRemainder = .zero
        }
        gestureMaxFingers = max(gestureMaxFingers, fingers.count)

        let dx = moved > 0 ? sumX / moved * model.widthMM / Double(touchMax) : 0
        let dy = moved > 0 ? sumY / moved * model.heightMM / Double(touchMax) : 0
        gestureTravelMM += hypot(dx, dy)

        if fingers.count >= 2 {
            handleTwoFingers(dx: dx, dy: dy)
        } else {
            endTwoFingers()
            // After a two-finger gesture a leftover finger must not drag the cursor.
            if fingers.count == 1, gestureMaxFingers == 1, moved > 0, gestureTravelMM > Self.moveDeadzoneMM {
                let p = pointer.location
                let speed = Pref.cursorSpeed.double
                pointer.move(to: clampToDisplays(CGPoint(x: p.x + dx * speed, y: p.y + dy * speed)))
            }
        }

        if fingers.isEmpty, let start = gestureStart {
            gestureStart = nil
            if Pref.tapToClick.bool, now - start < Self.tapMaxSeconds, gestureTravelMM < Self.tapMaxTravelMM {
                pointer.click(gestureMaxFingers >= 2 ? .right : .left)
            }
        }
    }

    func handleTwoFingers(dx: Double, dy: Double) {
        if twoFinger == nil {
            twoFinger = .undecided
            twoFingerStarted = false
            lastSpread = nil
            spreadChangeMM = 0
            twistArcMM = 0
            panTravel = .zero
            scrollRemainder = .zero
        }

        // Vector between the two lowest-numbered fingers, in millimetres: its length changes on a
        // pinch, its direction on a twist.
        let ids = Array(fingers.keys.sorted().prefix(2))
        let a = fingers[ids[0]]!, b = fingers[ids[1]]!
        let vx = Double(b.x - a.x) * model.widthMM / Double(touchMax)
        let vy = Double(b.y - a.y) * model.heightMM / Double(touchMax)
        let spread = hypot(vx, vy), angle = atan2(vy, vx)
        var spreadDelta = 0.0, angleDelta = 0.0
        if let last = lastSpread, last.ids == ids {
            spreadDelta = spread - last.mm
            angleDelta = atan2(sin(angle - last.angle), cos(angle - last.angle))
        }
        lastSpread = (ids, spread, angle)

        if twoFinger == .undecided {
            spreadChangeMM += spreadDelta
            twistArcMM += angleDelta * spread
            panTravel.x += dx
            panTravel.y += dy
            let relative = hypot(spreadChangeMM, twistArcMM), together = hypot(panTravel.x, panTravel.y)
            if relative > Self.relativeStartMM || together > Self.panStartMM {
                // Twisting around one still finger also moves the midpoint, by half the relative motion.
                if together > 0.8 * relative {
                    twoFinger = .pan
                } else {
                    twoFinger = abs(spreadChangeMM) >= abs(twistArcMM) ? .zoom : .rotate
                }
            }
        }

        if twoFinger != .undecided {
            // A recognised pinch or pan is never also a tap.
            gestureTravelMM = max(gestureTravelMM, Self.tapMaxTravelMM)
        }

        switch twoFinger {
        case .zoom where Pref.zoomEnabled.bool:
            guard spreadDelta != 0 else { return }
            pointer.magnify(spreadDelta / Self.zoomMMPerUnit, phase: twoFingerStarted ? .changed : .began)
            twoFingerStarted = true
        case .rotate where Pref.rotateEnabled.bool:
            guard angleDelta != 0 else { return }
            // Tablet y grows downward, so a positive angle change is clockwise.
            pointer.rotate(-angleDelta * 180 / .pi, phase: twoFingerStarted ? .changed : .began)
            twoFingerStarted = true
        case .pan:
            // Natural scrolling moves content with the fingers; off, it moves the content opposite.
            let direction = Pref.naturalScroll.bool ? 1.0 : -1.0
            let speed = Pref.scrollSpeed.double
            scrollRemainder.x += dx * speed * direction
            scrollRemainder.y += dy * speed * direction
            let sx = scrollRemainder.x.rounded(.towardZero), sy = scrollRemainder.y.rounded(.towardZero)
            guard sx != 0 || sy != 0 else { return }
            scrollRemainder.x -= sx
            scrollRemainder.y -= sy
            pointer.scroll(dx: Int32(sx), dy: Int32(sy), phase: twoFingerStarted ? .changed : .began)
            twoFingerStarted = true
        default:
            break
        }
    }

    func endTwoFingers() {
        guard let gesture = twoFinger else { return }
        twoFinger = nil
        guard twoFingerStarted else { return }
        switch gesture {
        case .zoom: pointer.magnify(0, phase: .ended)
        case .rotate: pointer.rotate(0, phase: .ended)
        default: pointer.scroll(dx: 0, dy: 0, phase: .ended)
        }
    }

    func handleKeys(_ now: ExpressKeys) {
        let position = pointer.location
        for (bit, pref) in Self.expressKeys {
            let isDown = now.contains(bit), wasDown = heldActions[Int(bit.rawValue)] != nil
            if isDown, !wasDown {
                runAction(pref.action, down: true, at: position, slot: Int(bit.rawValue))
            } else if !isDown, wasDown, let held = heldActions[Int(bit.rawValue)] {
                runAction(held, down: false, at: position, slot: Int(bit.rawValue))
            }
        }
    }

    func clampToDisplays(_ p: CGPoint) -> CGPoint {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(UInt32(ids.count), &ids, &count)
        let all = ids.prefix(Int(count)).reduce(CGRect.null) { $0.union(CGDisplayBounds($1)) }
        guard !all.isNull else { return p }
        return CGPoint(x: min(max(p.x, all.minX), all.maxX - 1), y: min(max(p.y, all.minY), all.maxY - 1))
    }
}
