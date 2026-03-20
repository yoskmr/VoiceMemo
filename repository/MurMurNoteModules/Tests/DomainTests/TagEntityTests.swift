import XCTest
@testable import Domain

final class TagEntityTests: XCTestCase {

    func test_tagEntity_creation_withDefaults() {
        let tag = TagEntity(name: "仕事")

        XCTAssertEqual(tag.name, "仕事")
        XCTAssertEqual(tag.colorHex, "#FF9500")
        XCTAssertEqual(tag.source, .ai)
    }

    func test_tagEntity_manualSource() {
        let tag = TagEntity(name: "個人", source: .manual)
        XCTAssertEqual(tag.source, .manual)
    }

    func test_tagEntity_customColor() {
        let tag = TagEntity(name: "重要", colorHex: "#FF0000")
        XCTAssertEqual(tag.colorHex, "#FF0000")
    }

    func test_tagSource_rawValues() {
        XCTAssertEqual(TagSource.ai.rawValue, "ai")
        XCTAssertEqual(TagSource.manual.rawValue, "manual")
    }
}
