import XCTest
@testable import Domain

final class TranscriptionSegmentTests: XCTestCase {

    // MARK: - 初期化テスト

    func test_init_setsAllProperties() {
        let segment = TranscriptionSegment(
            text: "こんにちは",
            startTime: 1.0,
            endTime: 2.5,
            confidence: 0.95
        )

        XCTAssertEqual(segment.text, "こんにちは")
        XCTAssertEqual(segment.startTime, 1.0)
        XCTAssertEqual(segment.endTime, 2.5)
        XCTAssertEqual(segment.confidence, 0.95)
    }

    // MARK: - Equatable テスト

    func test_equatable_sameValuesAreEqual() {
        let segment1 = TranscriptionSegment(
            text: "テスト",
            startTime: 0.0,
            endTime: 1.0,
            confidence: 0.8
        )
        let segment2 = TranscriptionSegment(
            text: "テスト",
            startTime: 0.0,
            endTime: 1.0,
            confidence: 0.8
        )
        XCTAssertEqual(segment1, segment2)
    }

    func test_equatable_differentValuesAreNotEqual() {
        let segment1 = TranscriptionSegment(
            text: "テスト",
            startTime: 0.0,
            endTime: 1.0,
            confidence: 0.8
        )
        let segment2 = TranscriptionSegment(
            text: "別のテスト",
            startTime: 0.0,
            endTime: 1.0,
            confidence: 0.8
        )
        XCTAssertNotEqual(segment1, segment2)
    }

    // MARK: - Sendable テスト

    func test_isSendable() {
        let segment = TranscriptionSegment(
            text: "テスト",
            startTime: 0.0,
            endTime: 1.0,
            confidence: 0.8
        )
        let _: any Sendable = segment
    }

    // MARK: - タイムスタンプの整合性テスト

    func test_duration_isPositive() {
        let segment = TranscriptionSegment(
            text: "テスト",
            startTime: 1.0,
            endTime: 3.5,
            confidence: 0.9
        )
        XCTAssertGreaterThan(segment.endTime, segment.startTime)
    }

    func test_confidence_withinValidRange() {
        let segment = TranscriptionSegment(
            text: "テスト",
            startTime: 0.0,
            endTime: 1.0,
            confidence: 0.85
        )
        XCTAssertGreaterThanOrEqual(segment.confidence, 0.0)
        XCTAssertLessThanOrEqual(segment.confidence, 1.0)
    }
}
