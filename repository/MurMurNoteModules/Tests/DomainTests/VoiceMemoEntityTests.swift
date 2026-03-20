import XCTest
@testable import Domain

final class VoiceMemoEntityTests: XCTestCase {

    // MARK: - 生成テスト

    func test_voiceMemoEntity_creation_withDefaults() {
        let memo = VoiceMemoEntity(audioFilePath: "Audio/test.m4a")

        XCTAssertFalse(memo.id.uuidString.isEmpty)
        XCTAssertEqual(memo.title, "")
        XCTAssertEqual(memo.durationSeconds, 0)
        XCTAssertEqual(memo.audioFilePath, "Audio/test.m4a")
        XCTAssertEqual(memo.audioFormat, .m4a)
        XCTAssertEqual(memo.status, .completed)
        XCTAssertFalse(memo.isFavorite)
        XCTAssertNil(memo.transcription)
        XCTAssertNil(memo.aiSummary)
        XCTAssertNil(memo.emotionAnalysis)
        XCTAssertTrue(memo.tags.isEmpty)
    }

    func test_voiceMemoEntity_creation_withAllProperties() {
        let id = UUID()
        let date = Date()
        let transcription = TranscriptionEntity(fullText: "テスト文字起こし")
        let summary = AISummaryEntity(summaryText: "要約テスト")
        let emotion = EmotionAnalysisEntity(primaryEmotion: .joy, confidence: 0.9)
        let tag = TagEntity(name: "テスト")

        let memo = VoiceMemoEntity(
            id: id,
            title: "テストメモ",
            createdAt: date,
            updatedAt: date,
            durationSeconds: 60.0,
            audioFilePath: "Audio/test.m4a",
            audioFormat: .m4a,
            status: .completed,
            isFavorite: true,
            transcription: transcription,
            aiSummary: summary,
            emotionAnalysis: emotion,
            tags: [tag]
        )

        XCTAssertEqual(memo.id, id)
        XCTAssertEqual(memo.title, "テストメモ")
        XCTAssertEqual(memo.durationSeconds, 60.0)
        XCTAssertTrue(memo.isFavorite)
        XCTAssertNotNil(memo.transcription)
        XCTAssertNotNil(memo.aiSummary)
        XCTAssertNotNil(memo.emotionAnalysis)
        XCTAssertEqual(memo.tags.count, 1)
    }

    func test_voiceMemoEntity_updatedAt_defaultsToCreatedAt() {
        let date = Date()
        let memo = VoiceMemoEntity(createdAt: date, audioFilePath: "Audio/test.m4a")
        XCTAssertEqual(memo.updatedAt, date)
    }

    // MARK: - Equatable

    func test_voiceMemoEntity_equality() {
        let id = UUID()
        let date = Date()
        let memo1 = VoiceMemoEntity(id: id, createdAt: date, audioFilePath: "Audio/a.m4a")
        let memo2 = VoiceMemoEntity(id: id, createdAt: date, audioFilePath: "Audio/a.m4a")
        XCTAssertEqual(memo1, memo2)
    }

    func test_voiceMemoEntity_inequality() {
        let memo1 = VoiceMemoEntity(audioFilePath: "Audio/a.m4a")
        let memo2 = VoiceMemoEntity(audioFilePath: "Audio/b.m4a")
        XCTAssertNotEqual(memo1, memo2)
    }
}
