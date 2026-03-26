import Foundation
import Testing
@testable import Domain

@Suite("BackupPayload Codable テスト")
struct BackupPayloadTests {

    // MARK: - ヘルパー

    private func makeTestPayload() -> BackupPayload {
        let transcription = BackupTranscription(
            id: UUID(),
            fullText: "今日は天気が良くて散歩した",
            language: "ja-JP",
            engineType: STTEngineType.speechAnalyzer.rawValue,
            confidence: 0.85,
            processedAt: Date()
        )
        let aiSummary = BackupAISummary(
            id: UUID(),
            title: "散歩中の気づき",
            summaryText: "天気の良い日に散歩",
            keyPoints: ["ポイント1", "ポイント2"],
            providerType: LLMProviderType.onDeviceAppleIntelligence.rawValue,
            isOnDevice: true,
            generatedAt: Date()
        )
        let emotionAnalysis = BackupEmotionAnalysis(
            id: UUID(),
            primaryEmotion: EmotionCategory.joy.rawValue,
            confidence: 0.72,
            emotionScores: [
                EmotionCategory.joy.rawValue: 0.72,
                EmotionCategory.calm.rawValue: 0.20,
                EmotionCategory.surprise.rawValue: 0.08,
            ],
            evidence: [
                BackupSentimentEvidence(
                    text: "天気が良くて",
                    emotion: EmotionCategory.joy.rawValue
                )
            ],
            analyzedAt: Date()
        )
        let memo = BackupMemo(
            id: UUID(),
            title: "テストメモ",
            createdAt: Date(),
            updatedAt: Date(),
            durationSeconds: 45.2,
            audioFileName: "test-uuid.m4a",
            audioFormat: AudioFormat.m4a.rawValue,
            status: MemoStatus.completed.rawValue,
            isFavorite: false,
            transcription: transcription,
            aiSummary: aiSummary,
            emotionAnalysis: emotionAnalysis,
            tagNames: ["アイデア", "散歩"]
        )
        let tag = BackupTag(
            id: UUID(),
            name: "アイデア",
            colorHex: "#FF9500",
            source: TagSource.ai.rawValue,
            createdAt: Date()
        )
        return BackupPayload(
            version: 1,
            memos: [memo],
            tags: [tag]
        )
    }

    @Test("Codable ラウンドトリップ: エンコード → デコードで同一データを復元できる")
    func test_codableRoundTrip_同一データを復元() throws {
        let original = makeTestPayload()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupPayload.self, from: data)
        #expect(decoded.version == original.version)
        #expect(decoded.memos.count == original.memos.count)
        #expect(decoded.tags.count == original.tags.count)
        #expect(decoded.memos.first?.title == "テストメモ")
        #expect(decoded.memos.first?.tagNames == ["アイデア", "散歩"])
    }

    @Test("emotionScores が [String: Double] 形式で正しくシリアライズされる")
    func test_emotionScores_stringDoubleFormat() throws {
        let payload = makeTestPayload()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let memos = json["memos"] as! [[String: Any]]
        let emotion = memos[0]["emotionAnalysis"] as! [String: Any]
        let scores = emotion["emotionScores"] as! [String: Double]
        #expect(scores["joy"] == 0.72)
        #expect(scores["calm"] == 0.20)
    }

    @Test("未知フィールドが含まれるJSONでもデコード成功する（前方互換性）")
    func test_unknownFields_デコード成功() throws {
        let json = """
        {
            "version": 1,
            "exportedAt": "2026-03-26T12:00:00Z",
            "sourceApp": "Soyoka",
            "sourceBundleId": "app.soyoka",
            "memos": [],
            "tags": [],
            "futureField": "should be ignored"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: json)
        #expect(payload.version == 1)
        #expect(payload.memos.isEmpty)
    }

    @Test("バージョンチェック: currentSupportedVersion は 1")
    func test_currentSupportedVersion() {
        #expect(BackupPayload.currentSupportedVersion == 1)
    }

    @Test("BackupResult: totalCount は importedCount + skippedCount")
    func test_backupResult_totalCount() {
        let result = BackupResult(importedCount: 5, skippedCount: 3, audioMissingCount: 1)
        #expect(result.totalCount == 8)
        #expect(result.audioMissingCount == 1)
    }
}
