import AppKit
import BambooKit
import CoreGraphics

/// Position and pressure of a pen, passed along so apps see tablet data rather than a plain mouse.
struct TabletPoint {
    var x: Int
    var y: Int
    var pressure: Double
}

/// Injects pointer, scroll, key and gesture events into the system.
final class Pointer {
    /// Gesture phases as CGEvent encodes them.
    enum Phase: Int64 {
        case began = 1, changed = 2, ended = 4
    }

    private let source = CGEventSource(stateID: .hidSystemState)
    private var held: Set<CGMouseButton> = []
    private var lastPosition: CGPoint?
    private var lastDown: (button: CGMouseButton, time: TimeInterval, position: CGPoint)?
    private var clickCount: Int64 = 1

    var location: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    func move(to position: CGPoint, tablet: TabletPoint? = nil) {
        let type: CGEventType
        let button: CGMouseButton
        if held.contains(.left) {
            (type, button) = (.leftMouseDragged, .left)
        } else if held.contains(.right) {
            (type, button) = (.rightMouseDragged, .right)
        } else if held.contains(.center) {
            (type, button) = (.otherMouseDragged, .center)
        } else {
            (type, button) = (.mouseMoved, .left)
        }
        post(type, position, button, tablet)
    }

    func button(_ button: CGMouseButton, down: Bool, at position: CGPoint, tablet: TabletPoint? = nil) {
        guard down != held.contains(button) else { return }
        if down {
            held.insert(button)
            let now = ProcessInfo.processInfo.systemUptime
            if let last = lastDown, last.button == button, now - last.time < 0.4,
               hypot(position.x - last.position.x, position.y - last.position.y) < 6 {
                clickCount += 1
            } else {
                clickCount = 1
            }
            lastDown = (button, now, position)
        } else {
            held.remove(button)
        }
        let type: CGEventType
        switch button {
        case .left: type = down ? .leftMouseDown : .leftMouseUp
        case .right: type = down ? .rightMouseDown : .rightMouseUp
        default: type = down ? .otherMouseDown : .otherMouseUp
        }
        post(type, position, button, tablet)
    }

    func click(_ button: CGMouseButton) {
        let position = location
        self.button(button, down: true, at: position)
        self.button(button, down: false, at: position)
    }

    func releaseAll() {
        let position = location
        for b in held { button(b, down: false, at: position) }
    }

    /// Trackpad-style scroll: pixel deltas plus a gesture phase, so apps treat it as a pan.
    func scroll(dx: Int32, dy: Int32, phase: Phase) {
        guard let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        else { return }
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase.rawValue)
        e.post(tap: .cghidEventTap)
    }

    /// Pinch and rotate gestures. CGEvent has no public API for these; the type and field numbers
    /// below are the ones AppKit decodes into NSEvent magnify and rotate events.
    func magnify(_ amount: Double, phase: Phase) { gesture(kind: 8, value: amount, phase: phase) }

    /// Degrees, counterclockwise positive.
    func rotate(_ degrees: Double, phase: Phase) { gesture(kind: 5, value: degrees, phase: phase) }

    private func gesture(kind: Int64, value: Double, phase: Phase) {
        guard let e = CGEvent(source: source), let type = CGEventType(rawValue: 29),
              let kindField = CGEventField(rawValue: 110), let valueField = CGEventField(rawValue: 113),
              let phaseField = CGEventField(rawValue: 132) else { return }
        e.type = type
        e.setIntegerValueField(kindField, value: kind)
        e.setDoubleValueField(valueField, value: value)
        e.setIntegerValueField(phaseField, value: phase.rawValue)
        e.post(tap: .cghidEventTap)
    }

    func key(_ code: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    func proximity(entering: Bool, eraser: Bool, productID: Int) {
        guard let e = CGEvent(source: source) else { return }
        e.type = .tabletProximity
        e.setIntegerValueField(.tabletProximityEventVendorID, value: Int64(wacomVendorID))
        e.setIntegerValueField(.tabletProximityEventTabletID, value: Int64(productID))
        e.setIntegerValueField(.tabletProximityEventDeviceID, value: 1)
        e.setIntegerValueField(.tabletProximityEventSystemTabletID, value: 1)
        e.setIntegerValueField(.tabletProximityEventPointerID, value: eraser ? 2 : 1)
        e.setIntegerValueField(.tabletProximityEventVendorPointerType, value: eraser ? 0x82A : 0x822)
        e.setIntegerValueField(.tabletProximityEventPointerType, value: eraser ? 3 : 1)
        // device ID | abs X | abs Y | buttons | pressure
        e.setIntegerValueField(.tabletProximityEventCapabilityMask, value: 0x0447)
        e.setIntegerValueField(.tabletProximityEventEnterProximity, value: entering ? 1 : 0)
        e.post(tap: .cghidEventTap)
    }

    private func post(_ type: CGEventType, _ position: CGPoint, _ button: CGMouseButton, _ tablet: TabletPoint?) {
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: position, mouseButton: button)
        else { return }
        if let last = lastPosition {
            e.setIntegerValueField(.mouseEventDeltaX, value: Int64((position.x - last.x).rounded()))
            e.setIntegerValueField(.mouseEventDeltaY, value: Int64((position.y - last.y).rounded()))
        }
        lastPosition = position
        if type != .mouseMoved {
            e.setIntegerValueField(.mouseEventClickState, value: clickCount)
        }
        if let t = tablet {
            e.setIntegerValueField(.mouseEventSubtype, value: 1) // tablet point
            e.setDoubleValueField(.mouseEventPressure, value: t.pressure)
            e.setIntegerValueField(.tabletEventPointX, value: Int64(t.x))
            e.setIntegerValueField(.tabletEventPointY, value: Int64(t.y))
            e.setDoubleValueField(.tabletEventPointPressure, value: t.pressure)
            e.setIntegerValueField(.tabletEventDeviceID, value: 1)
        }
        e.post(tap: .cghidEventTap)
    }
}
