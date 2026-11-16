import AppKit
import ServiceManagement
import SwiftUI

/// Live connection state, updated from the driver's connection callback on the main run loop.
final class TabletStatus: ObservableObject {
    @Published var name: String?
}

struct SettingsView: View {
    @ObservedObject var status: TabletStatus

    var body: some View {
        VStack(spacing: 0) {
            HeaderCard(status: status)
            TabView {
                PenSettings().tabItem { Label("Pen", systemImage: "pencil.tip") }
                TouchSettings().tabItem { Label("Touch", systemImage: "hand.point.up.left") }
                KeySettings().tabItem { Label("Keys", systemImage: "square.grid.2x2") }
            }
        }
        .frame(width: 520, height: 780)
    }
}

// MARK: - Header

private struct HeaderCard: View {
    @ObservedObject var status: TabletStatus

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text("Wacom Bamboo").font(.title3.bold())
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.name == nil ? Color.secondary : Color.green)
                        .frame(width: 8, height: 8)
                    Text(status.name.map { "\($0) connected" } ?? "Tablet not connected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.quaternary)
    }
}

// MARK: - Pen

private struct PenSettings: View {
    @AppStorage(Pref.displayID.rawValue, store: Pref.store) var displayID = 0
    @AppStorage(Pref.keepProportions.rawValue, store: Pref.store) var keepProportions = false
    @AppStorage(Pref.leftHanded.rawValue, store: Pref.store) var leftHanded = false
    @AppStorage(Pref.pressureCurve.rawValue, store: Pref.store) var pressureCurve = 1.0
    @AppStorage(Pref.penButton1.rawValue, store: Pref.store) var button1 = Action.rightClick
    @AppStorage(Pref.penButton2.rawValue, store: Pref.store) var button2 = Action.middleClick

    var body: some View {
        Form {
            Section {
                Picker("Display", selection: $displayID) {
                    Text("Main display").tag(0)
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        Text(screen.localizedName).tag(screenNumber(screen))
                    }
                }
                Toggle("Keep proportions", isOn: $keepProportions)
                Toggle("Left-handed (tablet rotated 180°)", isOn: $leftHanded)
            } header: {
                Label("Display", systemImage: "display")
            }

            Section {
                PressureCurveView(curve: pressureCurve)
                Slider(value: $pressureCurve, in: 0.4...2.5) {
                    Text("Tip feel")
                } minimumValueLabel: {
                    Text("Soft")
                } maximumValueLabel: {
                    Text("Firm")
                }
            } header: {
                Label("Pressure", systemImage: "chart.line.uptrend.xyaxis")
            }

            Section {
                ActionPicker(title: "Lower side button", selection: $button1)
                ActionPicker(title: "Upper side button", selection: $button2)
            } header: {
                Label("Side buttons", systemImage: "button.horizontal")
            }

            GeneralSection()
        }
        .formStyle(.grouped)
    }

    private func screenNumber(_ screen: NSScreen) -> Int {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }
}

/// Graph of pen pressure in (across) against pressure out (up), with the straight line for reference.
private struct PressureCurveView: View {
    let curve: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    p.addLine(to: CGPoint(x: w, y: 0))
                }
                .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    for i in 0...60 {
                        let t = Double(i) / 60
                        p.addLine(to: CGPoint(x: CGFloat(t) * w, y: h - CGFloat(pow(t, curve)) * h))
                    }
                }
                .stroke(Color.accentColor, lineWidth: 2.5)
            }
        }
        .frame(height: 90)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.08)))
    }
}

// MARK: - Touch

private struct TouchSettings: View {
    @AppStorage(Pref.touchEnabled.rawValue, store: Pref.store) var touchEnabled = true
    @AppStorage(Pref.tapToClick.rawValue, store: Pref.store) var tapToClick = true
    @AppStorage(Pref.cursorSpeed.rawValue, store: Pref.store) var cursorSpeed = 10.0
    @AppStorage(Pref.scrollSpeed.rawValue, store: Pref.store) var scrollSpeed = 6.0
    @AppStorage(Pref.naturalScroll.rawValue, store: Pref.store) var naturalScroll = true
    @AppStorage(Pref.zoomEnabled.rawValue, store: Pref.store) var zoomEnabled = true
    @AppStorage(Pref.rotateEnabled.rawValue, store: Pref.store) var rotateEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Finger touch", isOn: $touchEnabled)
                HStack(spacing: 10) {
                    GestureChip(title: "Move", symbol: "cursorarrow.motionlines", enabled: touchEnabled)
                    GestureChip(title: "Tap", symbol: "hand.tap", enabled: touchEnabled && tapToClick)
                    GestureChip(title: "Pan", symbol: "hand.draw", enabled: touchEnabled)
                    GestureChip(title: "Pinch", symbol: "arrow.up.left.and.arrow.down.right",
                                enabled: touchEnabled && zoomEnabled)
                    GestureChip(title: "Rotate", symbol: "arrow.triangle.2.circlepath",
                                enabled: touchEnabled && rotateEnabled)
                }
                .frame(maxWidth: .infinity)
            } header: {
                Label("Touch", systemImage: "hand.point.up.left")
            }

            Section {
                Slider(value: $cursorSpeed, in: 3...25) {
                    Text("Pointer speed")
                } minimumValueLabel: {
                    Text("Slow")
                } maximumValueLabel: {
                    Text("Fast")
                }
                Toggle("Tap to click (two fingers for right click)", isOn: $tapToClick)
            } header: {
                Label("Pointer", systemImage: "cursorarrow.motionlines")
            }
            .disabled(!touchEnabled)

            Section {
                Slider(value: $scrollSpeed, in: 2...15) {
                    Text("Scroll speed")
                } minimumValueLabel: {
                    Text("Slow")
                } maximumValueLabel: {
                    Text("Fast")
                }
                Toggle("Natural scrolling", isOn: $naturalScroll)
                Toggle("Pinch to zoom", isOn: $zoomEnabled)
                Toggle("Rotate", isOn: $rotateEnabled)
            } header: {
                Label("Two-finger gestures", systemImage: "hand.draw")
            }
            .disabled(!touchEnabled)
        }
        .formStyle(.grouped)
    }
}

/// One gesture the tablet understands; dimmed while its setting is off.
private struct GestureChip: View {
    let title: String
    let symbol: String
    let enabled: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title2)
            Text(title).font(.caption)
        }
        .frame(width: 76, height: 64)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.14)))
        .opacity(enabled ? 1 : 0.35)
    }
}

// MARK: - Keys

private struct KeySettings: View {
    @AppStorage(Pref.key1.rawValue, store: Pref.store) var key1 = Action.rightClick
    @AppStorage(Pref.key2.rawValue, store: Pref.store) var key2 = Action.back
    @AppStorage(Pref.key3.rawValue, store: Pref.store) var key3 = Action.forward
    @AppStorage(Pref.key4.rawValue, store: Pref.store) var key4 = Action.leftClick

    var body: some View {
        Form {
            Section {
                ExpressKeyDiagram(actions: [key1, key2, key3, key4])
            }
            Section {
                ActionPicker(title: "Key 1", selection: $key1)
                ActionPicker(title: "Key 2", selection: $key2)
                ActionPicker(title: "Key 3", selection: $key3)
                ActionPicker(title: "Key 4", selection: $key4)
            } header: {
                Label("Express keys", systemImage: "square.grid.2x2")
            } footer: {
                Text("Keys are numbered as the tablet reports them, which may not match their order on the tablet.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

/// The four keys beside a tablet outline, each labelled with what it does now.
private struct ExpressKeyDiagram: View {
    let actions: [Action]

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(spacing: 8) {
                ForEach(actions.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        Text("\(i + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.accentColor))
                        Text(actions[i].title).font(.callout).lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(width: 180, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.14)))
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.5), lineWidth: 2)
                Image(systemName: "pencil.and.scribble").font(.system(size: 38)).foregroundStyle(.secondary)
            }
            .frame(width: 150, height: 150)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

// MARK: - Shared

private struct GeneralSection: View {
    @State private var startAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Section {
            // Login items only work for a real app bundle, not the bare command-line binary.
            if Bundle.main.bundleIdentifier != nil {
                Toggle("Start at login", isOn: $startAtLogin)
                    .onChange(of: startAtLogin) { enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            startAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            Button("Reset all settings") { Pref.reset() }
        } header: {
            Label("App", systemImage: "gearshape")
        }
    }
}

private struct ActionPicker: View {
    let title: String
    @Binding var selection: Action

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(Action.allCases) { Text($0.title).tag($0) }
        }
    }
}
