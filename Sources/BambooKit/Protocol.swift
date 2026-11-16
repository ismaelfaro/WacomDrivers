// Wire protocol of the third-generation Wacom Bamboo tablets (CTL-470, CTH-470, CTH-670).
// Layout follows the Linux kernel driver (drivers/hid/wacom_wac.c: wacom_bpt_pen, wacom_bpt3_touch).

public let wacomVendorID = 0x056A

public struct TabletModel: Equatable {
    public let productID: Int
    public let name: String
    public let penMaxX: Int
    public let penMaxY: Int
    /// Physical size of the active area in millimetres (used to scale touch motion).
    public let widthMM: Double
    public let heightMM: Double

    public static let all: [TabletModel] = [
        TabletModel(productID: 0xDD, name: "Bamboo Connect CTL-470", penMaxX: 14720, penMaxY: 9200, widthMM: 147.2, heightMM: 92.0),
        TabletModel(productID: 0xDE, name: "Bamboo Capture CTH-470", penMaxX: 14720, penMaxY: 9200, widthMM: 147.2, heightMM: 92.0),
        TabletModel(productID: 0xDF, name: "Bamboo Create CTH-670", penMaxX: 21648, penMaxY: 13700, widthMM: 216.48, heightMM: 137.0),
    ]

    public static func find(productID: Int) -> TabletModel? {
        all.first { $0.productID == productID }
    }
}

public let penMaxPressure = 1023
public let touchMax = 4096

/// Feature report that switches the pen interface from boot-mouse mode to Wacom mode.
public let penModeReportID = 2
public let penModeReport: [UInt8] = [2, 2]

public struct PenReport: Equatable {
    public var inRange: Bool
    public var tip: Bool
    public var eraser: Bool
    public var button1: Bool
    public var button2: Bool
    public var x: Int
    public var y: Int
    public var pressure: Int
}

/// Parses a pen-interface input report (report ID 2, 9 bytes, report ID included as byte 0).
public func parsePen(_ d: [UInt8]) -> PenReport? {
    guard d.count >= 9, d[0] == 0x02 else { return nil }
    let inRange = d[1] & 0x20 != 0
    guard inRange else {
        return PenReport(inRange: false, tip: false, eraser: false, button1: false, button2: false, x: 0, y: 0, pressure: 0)
    }
    return PenReport(
        inRange: true,
        tip: d[1] & 0x01 != 0,
        eraser: d[1] & 0x08 != 0,
        button1: d[1] & 0x02 != 0,
        button2: d[1] & 0x04 != 0,
        x: Int(d[2]) | Int(d[3]) << 8,
        y: Int(d[4]) | Int(d[5]) << 8,
        pressure: Int(d[6]) | Int(d[7]) << 8
    )
}

public struct ExpressKeys: OptionSet, Equatable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    // Names match the Linux driver's BTN_* assignment.
    public static let right = ExpressKeys(rawValue: 0x01)
    public static let back = ExpressKeys(rawValue: 0x02)
    public static let forward = ExpressKeys(rawValue: 0x04)
    public static let left = ExpressKeys(rawValue: 0x08)
}

public enum TouchMessage: Equatable {
    case finger(id: Int, down: Bool, x: Int, y: Int)
    case keys(ExpressKeys)
}

/// Parses a touch-interface input report (report ID 2, 64 bytes): up to seven 8-byte messages.
public func parseTouch(_ d: [UInt8]) -> [TouchMessage] {
    guard d.count >= 2, d[0] == 0x02 else { return [] }
    var out: [TouchMessage] = []
    for i in 0..<Int(d[1] & 0x07) {
        let o = 2 + i * 8
        guard o + 8 <= d.count else { break }
        let id = Int(d[o])
        if (2...17).contains(id) {
            out.append(.finger(
                id: id,
                down: d[o + 1] & 0x80 != 0,
                x: Int(d[o + 2]) << 4 | Int(d[o + 4]) >> 4,
                y: Int(d[o + 3]) << 4 | Int(d[o + 4] & 0x0F)
            ))
        } else if id == 128 {
            out.append(.keys(ExpressKeys(rawValue: d[o + 1] & 0x0F)))
        }
    }
    return out
}
