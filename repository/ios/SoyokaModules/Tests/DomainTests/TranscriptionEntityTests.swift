import XCTest
@testable import Domain

final class TranscriptionEntityTests: XCTestCase {

    func test_transcriptionEntity_creation_withDefaults() {
        let transcription = TranscriptionEntity(fullText: "テスト文字起こし")

        XCTAssertFalse(transcription.id.uuidString.isEmpty)
        XCTAssertEqual(transcription.fullText, "テスト文字起こし")
        XCTAssertEqual(transcription.language, "ja-JP")
        XCTAssertEqual(transcription.engineType, .whisperKit)
        XCTAssertEqual(transcription.confidence, 0.0)
    }

    func test_transcriptionEntity_creation_withCustomValues() {
        let transcription = TranscriptionEntity(
            fullText: "Custom text",
            language: "en-US",
            engineType: .speechAnalyzer,
            confidence: 0.95
        )

        XCTAssertEqual(transcription.fullText, "Custom text")
        XCTAssertEqual(transcription.language, "en-US")
        XCTAssertEqual(transcription.engineType, .speechAnalyzer)
        XCTAssertEqual(transcription.confidence, 0.95)
    }

    func test_transcriptionEntity_equality() {
        let id = UUID()
        let date = Date()
        let t1 = TranscriptionEntity(id: id, fullText: "same", processedAt: date)
        let t2 = TranscriptionEntity(id: id, fullText: "same", processedAt: date)
        XCTAssertEqual(t1, t2)
    }
}
