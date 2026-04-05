import Foundation
import Testing
import SwiftData
@testable import Domain
@testable import InfraStorage
import TestSupport

@Suite("BackupExporter テスト")
struct BackupExporterTests {

    /// テスト用のインメモリ ModelContainer を生成
    @MainActor
    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainerConfiguration.create(inMemory: true)
    }

    /// テスト用メモをSwiftDataに保存
    @MainActor
    private func insertTestMemo(
        context: ModelContext,
        id: UUID = UUID(),
        title: String = "テストきおく",
        audioFilePath: String = "Audio/test-uuid.m4a"
    ) -> VoiceMemoModel {
        let memo = VoiceMemoModel(
            id: id,
            title: title,
            durationSeconds: 45.2,
            audioFilePath: audioFilePath,
            audioFormat: .m4a,
            status: .completed,
            isFavorite: false
        )
        context.insert(memo)

        let transcription = TranscriptionModel(
            fullText: "今日は天気が良くて散歩した",
            language: "ja-JP",
            engineType: .speechAnalyzer,
            confidence: 0.85
        )
        transcription.memo = memo
        context.insert(transcription)

        let tag = TagModel(name: "アイデア", colorHex: "#FF9500", source: .ai)
        context.insert(tag)
        memo.tags.append(tag)

        try! context.save()
        return memo
    }

    @Test("エクスポート: BackupPayload が正しく生成される")
    @MainActor
    func test_export_BackupPayload生成() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let memoID = UUID()
        _ = insertTestMemo(context: context, id: memoID)

        let exporter = BackupExporter(modelContainer: container)
        let payload = try exporter.buildPayload()
        attachJSON(payload, named: "backup-payload")

        #expect(payload.version == 1)
        #expect(payload.sourceApp == "Soyoka")
        #expect(payload.memos.count == 1)
        #expect(payload.memos[0].id == memoID)
        #expect(payload.memos[0].title == "テストきおく")
        #expect(payload.memos[0].transcription?.fullText == "今日は天気が良くて散歩した")
        #expect(payload.memos[0].transcription?.engineType == "speech_analyzer")
        #expect(payload.memos[0].tagNames == ["アイデア"])
        #expect(payload.tags.count == 1)
        #expect(payload.tags[0].name == "アイデア")
        #expect(payload.tags[0].source == "ai")
    }

    @Test("エクスポート: audioFileName は UUID.m4a 形式で出力される")
    @MainActor
    func test_export_audioFileName形式() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let memoID = UUID()
        _ = insertTestMemo(
            context: context,
            id: memoID,
            audioFilePath: "Audio/\(memoID.uuidString).m4a"
        )

        let exporter = BackupExporter(modelContainer: container)
        let payload = try exporter.buildPayload()
        attachJSON(payload.memos, named: "backup-memos-audio")

        #expect(payload.memos[0].audioFileName == "\(memoID.uuidString).m4a")
    }

    @Test("エクスポート: emotionScores が [String: Double] 形式で出力される")
    @MainActor
    func test_export_emotionScores変換() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let memo = VoiceMemoModel(
            title: "感情テスト",
            durationSeconds: 10.0,
            audioFilePath: "Audio/emotion-test.m4a"
        )
        context.insert(memo)
        let emotion = EmotionAnalysisModel(
            primaryEmotion: .joy,
            confidence: 0.72,
            emotionScores: ["joy": 0.72, "calm": 0.20],
            evidence: [["text": "嬉しい", "emotion": "joy"]],
            analyzedAt: Date()
        )
        emotion.memo = memo
        context.insert(emotion)
        try context.save()

        let exporter = BackupExporter(modelContainer: container)
        let payload = try exporter.buildPayload()
        attachJSON(payload, named: "backup-payload-emotion")

        let memoPayload = payload.memos.first { $0.title == "感情テスト" }!
        #expect(memoPayload.emotionAnalysis?.emotionScores["joy"] == 0.72)
        #expect(memoPayload.emotionAnalysis?.emotionScores["calm"] == 0.20)
        #expect(memoPayload.emotionAnalysis?.primaryEmotion == "joy")
    }

    @Test("エクスポート: メモが0件でも空の payload を生成できる")
    @MainActor
    func test_export_メモ0件() throws {
        let container = try makeTestContainer()
        let exporter = BackupExporter(modelContainer: container)
        let payload = try exporter.buildPayload()

        #expect(payload.memos.isEmpty)
        #expect(payload.tags.isEmpty)
        #expect(payload.version == 1)
    }
}
