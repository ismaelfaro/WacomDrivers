import XCTest
@testable import BambooKit

final class ProtocolTests: XCTestCase {
    func testPenInRangeWithTip() {
        let r = parsePen([0x02, 0x21, 0x34, 0x12, 0x56, 0x04, 0xFF, 0x01, 0x0A])
        XCTAssertEqual(r, PenReport(inRange: true, tip: true, eraser: false, button1: false, button2: false,
                                    x: 0x1234, y: 0x0456, pressure: 0x01FF))
    }

    func testPenEraserAndButtons() {
        let r = parsePen([0x02, 0x2E, 0, 0, 0, 0, 0, 0, 0])!
        XCTAssertTrue(r.eraser && r.button1 && r.button2)
        XCTAssertFalse(r.tip)
    }

    func testPenOutOfRange() {
        XCTAssertEqual(parsePen([0x02, 0x00, 1, 1, 1, 1, 1, 1, 1])?.inRange, false)
    }

    func testPenRejectsOtherReports() {
        XCTAssertNil(parsePen([0x01, 0x21, 0, 0, 0, 0, 0, 0, 0]))
        XCTAssertNil(parsePen([0x02, 0x21]))
    }

    func testTouchFingerAndKeys() {
        var d = [UInt8](repeating: 0, count: 64)
        d[0] = 0x02
        d[1] = 0x02
        d[2...6] = [2, 0x80, 0x12, 0x45, 0x36]
        d[10...11] = [128, 0x08]
        XCTAssertEqual(parseTouch(d), [
            .finger(id: 2, down: true, x: 0x123, y: 0x456),
            .keys(.left),
        ])
    }

    func testTouchFingerUp() {
        var d = [UInt8](repeating: 0, count: 64)
        d[0] = 0x02
        d[1] = 0x01
        d[2] = 3
        XCTAssertEqual(parseTouch(d), [.finger(id: 3, down: false, x: 0, y: 0)])
    }

    func testModelLookup() {
        XCTAssertEqual(TabletModel.find(productID: 0xDF)?.penMaxX, 21648)
        XCTAssertNil(TabletModel.find(productID: 0x1234))
    }
}
