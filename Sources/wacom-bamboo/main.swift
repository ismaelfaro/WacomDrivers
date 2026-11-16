// Wacom Bamboo driver for macOS: menu-bar app with a settings window.
//
//   Wacom Bamboo                  open the menu-bar app with the settings window
//   Wacom Bamboo --background     start in the menu bar only
//   Wacom Bamboo --dump           print raw HID reports, no pointer control (diagnostics)
//   Wacom Bamboo --verbose        also print raw touch packets while running
//   Wacom Bamboo --check          print whether the two required permissions are granted

import AppKit
import Foundation
import IOKit.hid

setvbuf(stdout, nil, _IOLBF, 0)

Pref.registerDefaults()

let arguments = Set(CommandLine.arguments.dropFirst())
let known: Set<String> = ["--dump", "--verbose", "--background", "--check"]
if !arguments.isSubset(of: known) {
    print("Usage: wacom-bamboo [--dump] [--verbose] [--background] [--check]")
    exit(2)
}

if arguments.contains("--check") {
    let input = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    print("Accessibility (move pointer): \(CGPreflightPostEventAccess() ? "granted" : "NOT granted")")
    print("Input Monitoring (read tablet): \(input == kIOHIDAccessTypeGranted ? "granted" : "NOT granted")")
    exit(0)
}

if arguments.contains("--dump") {
    let driver = Driver(dump: true, verbose: false)
    driver.start()
    CFRunLoopRun()
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
// Kept in a global so the delegate outlives the run loop setup (NSApplication holds it weakly).
let delegate = AppDelegate(
    driver: Driver(dump: false, verbose: arguments.contains("--verbose")),
    showSettingsAtLaunch: !arguments.contains("--background")
)
app.delegate = delegate
app.run()
