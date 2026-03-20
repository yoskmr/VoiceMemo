import XCTest
@testable import Domain

final class TranscriptionResultTests: XCTestCase {

    // MARK: - 初期化テスト

    func test_init_setsAllProperties() {
        let segments = [
            TranscriptionSegment(
                text: "こんにちは",
                startTime: 0.0,
                endTime: 1.5,
                confidence: 0.95
            ),
        ]
        let result = TranscriptionResult(
            text: "こんにちは世界",
            confidence: 0.92,
            isFinal: true,
            language: "ja-JP",
            segments: segments
        )

        XCTAssertEqual(result.text, "こんにちは世界")
        XCTAssertEqual(result.confidence, 0.92)
        XCTAssertTrue(result.isFinal)
        XCTAssertEqual(result.language, "ja-JP")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments.first?.text, "こんにちは")
    }

    func test_init_defaultSegmentsIsEmpty() {
        let result = TranscriptionResult(
            text: "テスト",
            confidence: 0.5,
            isFinal: false,
            language: "ja-JP"
        )
        XCTAssertTrue(result.segments.isEmpty)
    }

    // MARK: - ファクトリメソッドテスト

    func test_empty_returnsEmptyResult() {
        let result = TranscriptionResult.empty()

        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.confidence, 0.0)
        XCTAssertTrue(result.isFinal)
        XCTAssertEqual(result.language, "ja-JP")
        XCTAssertTrue(result.segments.isEmpty)
    }

    func test_empty_withCustomLanguage() {
        let result = TranscriptionResult.empty(language: "en-US")
        XCTAssertEqual(result.language, "en-US")
    }

    // MARK: - Equatable テスト

    func test_equatable_sameValuesAreEqual() {
        let result1 = TranscriptionResult(
            text: "テスト",
            confidence: 0.8,
            isFinal: true,
            language: "ja-JP"
        )
        let result2 = TranscriptionResult(
            text: "テスト",
            confidence: 0.8,
            isFinal: true,
            language: "ja-JP"
        )
        XCTAssertEqual(result1, result2)
    }

    func test_equatable_differentTextAreNotEqual() {
        let result1 = TranscriptionResult(
            text: "テスト1",
            confidence: 0.8,
            isFinal: true,
            language: "ja-JP"
        )
        let result2 = TranscriptionResult(
            text: "テスト2",
            confidence: 0.8,
            isFinal: true,
            language: "ja-JP"
        )
        XCTAssertNotEqual(result1, result2)
    }

    func test_equatable_differentIsFinalAreNotEqual() {
        let result1 = TranscriptionResult(
            text: "テスト",
            confidence: 0.8,
            isFinal: false,
            language: "ja-JP"
        )
        let result2 = TranscriptionResult(
            text: "テスト",
            confidence: 0.8,
            isFinal: true,
            language: "ja-JP"
        )
        XCTAssertNotEqual(result1, result2)
    }

    // MARK: - Sendable テスト（コンパイル時チェック）

    func test_isSendable() {
        let result = TranscriptionResult.empty()
        let _: any Sendable = result
        // コンパイルが通れば Sendable 適合OK
    }

    // MARK: - 部分結果と最終結果の区別

    func test_partialResult_isFinalIsFalse() {
        let result = TranscriptionResult(
            text: "こんに",
            confidence: 0.6,
            isFinal: false,
            language: "ja-JP"
        )
        XCTAssertFalse(result.isFinal)
    }

    func test_finalResult_isFinalIsTrue() {
        let result = TranscriptionResult(
            text: "こんにちは",
            confidence: 0.95,
            isFinal: true,
            language: "ja-JP"
        )
        XCTAssertTrue(result.isFinal)
    }
}
