import AppKit
import CoreGraphics
import IOKit.hid
import SwiftUI

/// Menu-bar presence: tablet status, the settings window and Quit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let driver: Driver
    private let showSettingsAtLaunch: Bool
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Tablet not connected", action: nil, keyEquivalent: "")
    private let status = TabletStatus()
    private var window: NSWindow?

    init(driver: Driver, showSettingsAtLaunch: Bool) {
        self.driver = driver
        self.showSettingsAtLaunch = showSettingsAtLaunch
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "scribble", accessibilityDescription: "Wacom Bamboo")

        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Wacom Bamboo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        driver.onConnectionChange = { [weak self] name in
            self?.statusLine.title = name.map { "\($0) connected" } ?? "Tablet not connected"
            self?.status.name = name
        }
        requestPermissions()
        driver.start()
        if showSettingsAtLaunch { openSettings() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        driver.stop()
    }

    /// Accessibility lets the driver move the pointer; Input Monitoring lets it read the tablet.
    private func requestPermissions() {
        if !CGPreflightPostEventAccess() { CGRequestPostEventAccess() }
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }

    @objc func openSettings() {
        if window == nil {
            let created = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(status: status)))
            created.title = "Wacom Bamboo"
            created.styleMask = [.titled, .closable, .miniaturizable]
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
