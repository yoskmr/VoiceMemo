import XCTest
@testable import Domain

final class ConfidenceLevelTests: XCTestCase {

    // MARK: - 正常系: 信頼度しきい値による3段階判定

    func test_confidence_0_8_returns_high() {
        let level = ConfidenceLevel(confidence: 0.8)
        XCTAssertEqual(level, .high)
    }

    func test_confidence_0_7_returns_high() {
        // 境界値: 0.7 は高信頼に含まれる（>= 0.7）
        let level = ConfidenceLevel(confidence: 0.7)
        XCTAssertEqual(level, .high)
    }

    func test_confidence_1_0_returns_high() {
        let level = ConfidenceLevel(confidence: 1.0)
        XCTAssertEqual(level, .high)
    }

    func test_confidence_0_5_returns_medium() {
        let level = ConfidenceLevel(confidence: 0.5)
        XCTAssertEqual(level, .medium)
    }

    func test_confidence_0_4_returns_medium() {
        // 境界値: 0.4 は中信頼に含まれる（>= 0.4）
        let level = ConfidenceLevel(confidence: 0.4)
        XCTAssertEqual(level, .medium)
    }

    func test_confidence_0_699_returns_medium() {
        // 境界値: 0.7未満は中信頼
        let level = ConfidenceLevel(confidence: 0.699)
        XCTAssertEqual(level, .medium)
    }

    func test_confidence_0_2_returns_low() {
        let level = ConfidenceLevel(confidence: 0.2)
        XCTAssertEqual(level, .low)
    }

    func test_confidence_0_399_returns_low() {
        // 境界値: 0.4未満は低信頼
        let level = ConfidenceLevel(confidence: 0.399)
        XCTAssertEqual(level, .low)
    }

    func test_confidence_0_0_returns_low() {
        let level = ConfidenceLevel(confidence: 0.0)
        XCTAssertEqual(level, .low)
    }

    func test_confidence_negative_returns_low() {
        let level = ConfidenceLevel(confidence: -0.5)
        XCTAssertEqual(level, .low)
    }

    // MARK: - インジケーターカラー

    func test_high_indicatorColor_is_green() {
        XCTAssertEqual(ConfidenceLevel.high.indicatorColor, "green")
    }

    func test_medium_indicatorColor_is_yellow() {
        XCTAssertEqual(ConfidenceLevel.medium.indicatorColor, "yellow")
    }

    func test_low_indicatorColor_is_red() {
        XCTAssertEqual(ConfidenceLevel.low.indicatorColor, "red")
    }
}
