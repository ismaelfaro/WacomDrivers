import XCTest
@testable import BambooKit

/// Keeps the documentation honest: the machine-readable device table and the links in the docs
/// must agree with the code and the files on disk.
final class DocsTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testDevicesJSONMatchesModelTable() throws {
        struct Device: Decodable {
            let productID: Int
            let name: String
            let penMaxX: Int
            let penMaxY: Int
            let widthMM: Double
            let heightMM: Double
        }
        struct Table: Decodable {
            let vendorID: Int
            let penMaxPressure: Int
            let touchMax: Int
            let models: [Device]
        }
        let data = try Data(contentsOf: root.appendingPathComponent("docs/devices.json"))
        let table = try JSONDecoder().decode(Table.self, from: data)

        XCTAssertEqual(table.vendorID, wacomVendorID)
        XCTAssertEqual(table.penMaxPressure, penMaxPressure)
        XCTAssertEqual(table.touchMax, touchMax)
        XCTAssertEqual(table.models.count, TabletModel.all.count, "docs/devices.json and TabletModel.all differ in size")
        for entry in table.models {
            let model = try XCTUnwrap(TabletModel.find(productID: entry.productID),
                                      "product \(entry.productID) is in docs/devices.json but not in TabletModel.all")
            XCTAssertEqual(model.name, entry.name)
            XCTAssertEqual(model.penMaxX, entry.penMaxX)
            XCTAssertEqual(model.penMaxY, entry.penMaxY)
            XCTAssertEqual(model.widthMM, entry.widthMM, accuracy: 0.001)
            XCTAssertEqual(model.heightMM, entry.heightMM, accuracy: 0.001)
        }
    }

    func testRelativeMarkdownLinksPointToExistingFiles() throws {
        let docs = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("docs").path)
            .filter { $0.hasSuffix(".md") }.map { "docs/\($0)" }
        let files = ["README.md", "AGENTS.md", "CLAUDE.md", "llms.txt"] + docs
        let link = try NSRegularExpression(pattern: #"\]\(([^)\s]+)\)"#)

        for file in files {
            let url = root.appendingPathComponent(file)
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in link.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let target = String(text[Range(match.range(at: 1), in: text)!])
                if target.contains(":") || target.hasPrefix("#") { continue } // URLs and in-page anchors
                let path = target.split(separator: "#").first.map(String.init) ?? target
                let resolved = url.deletingLastPathComponent().appendingPathComponent(path)
                XCTAssertTrue(FileManager.default.fileExists(atPath: resolved.path),
                              "\(file) links to missing \(target)")
            }
        }
    }
}
