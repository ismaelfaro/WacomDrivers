// Wacom Bamboo driver for macOS: menu-bar app with a settings window.
//
//   Wacom Bamboo                  open the menu-bar app with the settings window
//   Wacom Bamboo --background     start in the menu bar only
//   Wacom Bamboo --dump           print raw HID reports, no pointer control (diagnostics)
//   Wacom Bamboo --verbose        also print raw touch packets while running

import AppKit
import Foundation

Pref.registerDefaults()

let arguments = Set(CommandLine.arguments.dropFirst())
let known: Set<String> = ["--dump", "--verbose", "--background"]
if !arguments.isSubset(of: known) {
    print("Usage: wacom-bamboo [--dump] [--verbose] [--background]")
    exit(2)
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
