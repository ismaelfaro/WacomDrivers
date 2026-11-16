import Foundation

/// What a pen side button or tablet express key does.
enum Action: String, CaseIterable, Identifiable {
    case none, leftClick, rightClick, middleClick, back, forward, undo, redo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Nothing"
        case .leftClick: return "Click"
        case .rightClick: return "Right click"
        case .middleClick: return "Middle click"
        case .back: return "Back (⌘[)"
        case .forward: return "Forward (⌘])"
        case .undo: return "Undo (⌘Z)"
        case .redo: return "Redo (⇧⌘Z)"
        }
    }
}

/// User settings. The settings window writes them through @AppStorage and the driver reads them
/// on every event, so changes apply immediately.
enum Pref: String, CaseIterable {
    case displayID, keepProportions, leftHanded, pressureCurve, penButton1, penButton2
    case touchEnabled, tapToClick, cursorSpeed, scrollSpeed, naturalScroll, zoomEnabled, rotateEnabled
    case key1, key2, key3, key4

    // Must differ from the app bundle identifier (local.wacom-bamboo.app), which cannot be used as a suite name.
    static let store = UserDefaults(suiteName: "local.wacom-bamboo")!

    static let defaults: [Pref: Any] = [
        .displayID: 0, // 0 follows the main display
        .keepProportions: false,
        .leftHanded: false,
        .pressureCurve: 1.0,
        .penButton1: Action.rightClick.rawValue,
        .penButton2: Action.middleClick.rawValue,
        .touchEnabled: true,
        .tapToClick: true,
        .cursorSpeed: 10.0, // pixels per millimetre of finger travel
        .scrollSpeed: 6.0,
        .naturalScroll: true,
        .zoomEnabled: true,
        .rotateEnabled: true,
        .key1: Action.rightClick.rawValue,
        .key2: Action.back.rawValue,
        .key3: Action.forward.rawValue,
        .key4: Action.leftClick.rawValue,
    ]

    static func registerDefaults() {
        store.register(defaults: Dictionary(uniqueKeysWithValues: defaults.map { ($0.key.rawValue, $0.value) }))
    }

    static func reset() {
        for pref in allCases { store.removeObject(forKey: pref.rawValue) }
    }

    var bool: Bool { Pref.store.bool(forKey: rawValue) }
    var double: Double { Pref.store.double(forKey: rawValue) }
    var int: Int { Pref.store.integer(forKey: rawValue) }
    var action: Action { Action(rawValue: Pref.store.string(forKey: rawValue) ?? "") ?? .none }
}
