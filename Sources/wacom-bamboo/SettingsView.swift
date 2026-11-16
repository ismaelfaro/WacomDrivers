import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            PenSettings().tabItem { Label("Pen", systemImage: "pencil.tip") }
            TouchSettings().tabItem { Label("Touch", systemImage: "hand.point.up.left") }
            KeySettings().tabItem { Label("Keys", systemImage: "square.grid.2x2") }
        }
        .frame(width: 460, height: 420)
        .padding(.top, 8)
    }
}

private struct PenSettings: View {
    @AppStorage(Pref.displayID.rawValue, store: Pref.store) var displayID = 0
    @AppStorage(Pref.keepProportions.rawValue, store: Pref.store) var keepProportions = false
    @AppStorage(Pref.leftHanded.rawValue, store: Pref.store) var leftHanded = false
    @AppStorage(Pref.pressureCurve.rawValue, store: Pref.store) var pressureCurve = 1.0
    @AppStorage(Pref.penButton1.rawValue, store: Pref.store) var button1 = Action.rightClick
    @AppStorage(Pref.penButton2.rawValue, store: Pref.store) var button2 = Action.middleClick

    var body: some View {
        Form {
            Section("Mapping") {
                Picker("Display", selection: $displayID) {
                    Text("Main display").tag(0)
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        Text(screen.localizedName).tag(screenNumber(screen))
                    }
                }
                Toggle("Keep proportions", isOn: $keepProportions)
                Toggle("Left-handed (tablet rotated 180°)", isOn: $leftHanded)
            }
            Section("Pen") {
                Slider(value: $pressureCurve, in: 0.4...2.5) {
                    Text("Tip feel")
                } minimumValueLabel: {
                    Text("Soft")
                } maximumValueLabel: {
                    Text("Firm")
                }
                ActionPicker(title: "Lower side button", selection: $button1)
                ActionPicker(title: "Upper side button", selection: $button2)
            }
            GeneralSection()
        }
        .formStyle(.grouped)
    }

    private func screenNumber(_ screen: NSScreen) -> Int {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }
}

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
            }
            Section("Pointer") {
                Slider(value: $cursorSpeed, in: 3...25) {
                    Text("Pointer speed")
                } minimumValueLabel: {
                    Text("Slow")
                } maximumValueLabel: {
                    Text("Fast")
                }
                Toggle("Tap to click (two fingers for right click)", isOn: $tapToClick)
            }
            .disabled(!touchEnabled)
            Section("Two-finger gestures") {
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
            }
            .disabled(!touchEnabled)
        }
        .formStyle(.grouped)
    }
}

private struct KeySettings: View {
    @AppStorage(Pref.key1.rawValue, store: Pref.store) var key1 = Action.rightClick
    @AppStorage(Pref.key2.rawValue, store: Pref.store) var key2 = Action.back
    @AppStorage(Pref.key3.rawValue, store: Pref.store) var key3 = Action.forward
    @AppStorage(Pref.key4.rawValue, store: Pref.store) var key4 = Action.leftClick

    var body: some View {
        Form {
            Section {
                ActionPicker(title: "Key 1", selection: $key1)
                ActionPicker(title: "Key 2", selection: $key2)
                ActionPicker(title: "Key 3", selection: $key3)
                ActionPicker(title: "Key 4", selection: $key4)
            } header: {
                Text("Express keys")
            } footer: {
                Text("Keys are numbered as the tablet reports them, which may not match their order on the tablet.")
            }
        }
        .formStyle(.grouped)
    }
}

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
