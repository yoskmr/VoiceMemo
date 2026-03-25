import XCTest
import SwiftData
import Domain
@testable import InfraStorage

/// SwiftData @Model のテスト
/// インメモリの ModelContainer を使用してCRUD操作を検証する
final class SwiftDataModelTests: XCTestCase {

    var container: ModelContainer!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! ModelContainerConfiguration.create(inMemory: true)
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    // MARK: - VoiceMemoModel CRUD

    @MainActor
    func test_voiceMemoModel_create_andFetch() throws {
        let context = container.mainContext

        let memo = VoiceMemoModel(
            title: "テストメモ",
            durationSeconds: 60.0,
            audioFilePath: "Audio/test.m4a"
        )
        context.insert(memo)
        try context.save()

        let descriptor = FetchDescriptor<VoiceMemoModel>()
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "テストメモ")
        XCTAssertEqual(fetched.first?.durationSeconds, 60.0)
        XCTAssertEqual(fetched.first?.audioFilePath, "Audio/test.m4a")
        XCTAssertEqual(fetched.first?.audioFormat, .m4a)
        XCTAssertEqual(fetched.first?.status, .completed)
        XCTAssertFalse(fetched.first!.isFavorite)
    }

    @MainActor
    func test_voiceMemoModel_update() throws {
        let context = container.mainContext

        let memo = VoiceMemoModel(
            title: "初期タイトル",
            audioFilePath: "Audio/test.m4a"
        )
        context.insert(memo)
        try context.save()

        memo.title = "更新タイトル"
        memo.isFavorite = true
        try context.save()

        let descriptor = FetchDescriptor<VoiceMemoModel>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.title, "更新タイトル")
        XCTAssertTrue(fetched.first!.isFavorite)
    }

    @MainActor
    func test_voiceMemoModel_delete() throws {
        let context = container.mainContext

        let memo = VoiceMemoModel(audioFilePath: "Audio/test.m4a")
        context.insert(memo)
        try context.save()

        context.delete(memo)
        try context.save()

        let descriptor = FetchDescriptor<VoiceMemoModel>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 0)
    }

    // MARK: - Transcription リレーション

    @MainActor
    func test_transcriptionModel_linkedToMemo() throws {
        let context = container.mainContext

        let memo = VoiceMemoModel(audioFilePath: "Audio/test.m4a")
        context.insert(memo)

        let transcription = TranscriptionModel(
            fullText: "テスト文字起こし",
            engineType: .whisperKit,
            confidence: 0.95
        )
        transcription.memo = memo
        context.insert(transcription)
        try context.save()

        XCTAssertNotNil(memo.transcription)
        XCTAssertEqual(memo.transcription?.fullText, "テスト文字起こし")
        XCTAssertEqual(memo.transcription?.confidence, 0.95)
    }

    // MARK: - AISummary リレーション + keyPoints

    @MainActor
    func test_aiSummaryModel_keyPoints_persistence() throws {
        let context = container.mainContext

        let memo = VoiceMemoModel(audioFilePath: "Audio/test.m4a")
        context.insert(memo)

        let keyPoints = ["ポイント1", "ポイント2", "ポイント3"]
        let summary = AISummaryModel(
            title: "テスト要約",
            summaryText: "要約テキスト",
            keyPoints: keyPoints,
            providerType: .onDeviceLlamaCpp
        )
        summary.memo = memo
        context.insert(summary)
        try context.save()

        XCTAssertEqual(memo.aiSummary?.keyPoints, keyPoints)
        XCTAssertEqual(memo.aiSummary?.title, "テスト要約")
    }

    // MARK: - Tag 多対多リレーション

    @MainActor
    func test_tagModel_manyToMany() throws {
        let context = container.mainContext

        let memo1 = VoiceMemoModel(title: "メモ1", audioFilePath: "Audio/1.m4a")
        let memo2 = VoiceMemoModel(title: "メモ2", audioFilePath: "Audio/2.m4a")
        context.insert(memo1)
        context.insert(memo2)

        let tag = TagModel(name: "仕事")
        context.insert(tag)

        memo1.tags.append(tag)
        memo2.tags.append(tag)
        try context.save()

        XCTAssertEqual(tag.memos.count, 2)
        XCTAssertEqual(memo1.tags.count, 1)
        XCTAssertEqual(memo1.tags.first?.name, "仕事")
    }

    // MARK: - EmotionAnalysis emotionScores (Dict型)

    @MainActor
    func test_emotionAnalysisModel_emotionScores_persistence() throws {
        let context = container.mainContext

        let memo = VoiceMemoModel(audioFilePath: "Audio/test.m4a")
        context.insert(memo)

        let scores: [String: Double] = [
            "joy": 0.6,
            "calm": 0.2,
            "neutral": 0.1,
            "anticipation": 0.1,
        ]
        let evidence: [[String: String]] = [
            ["text": "楽しかった", "emotion": "joy"],
            ["text": "安心した", "emotion": "calm"],
        ]

        let analysis = EmotionAnalysisModel(
            primaryEmotion: .joy,
            confidence: 0.85,
            emotionScores: scores,
            evidence: evidence
        )
        analysis.memo = memo
        context.insert(analysis)
        try context.save()

        XCTAssertEqual(memo.emotionAnalysis?.emotionScores["joy"], 0.6)
        XCTAssertEqual(memo.emotionAnalysis?.emotionScores["calm"], 0.2)
        XCTAssertEqual(memo.emotionAnalysis?.evidence.count, 2)
    }

    // MARK: - カスケードデリート

    @MainActor
    func test_cascadeDelete_removesRelatedEntities() throws {
        let context = container.mainContext

        let memo = VoiceMemoModel(audioFilePath: "Audio/test.m4a")
        context.insert(memo)

        let transcription = TranscriptionModel(fullText: "テスト")
        transcription.memo = memo
        context.insert(transcription)

        let summary = AISummaryModel(summaryText: "要約")
        summary.memo = memo
        context.insert(summary)

        let emotion = EmotionAnalysisModel()
        emotion.memo = memo
        context.insert(emotion)

        try context.save()

        // メモを削除
        context.delete(memo)
        try context.save()

        // 関連エンティティも削除されていること
        XCTAssertEqual(try context.fetch(FetchDescriptor<VoiceMemoModel>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TranscriptionModel>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AISummaryModel>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<EmotionAnalysisModel>()).count, 0)
    }

    @MainActor
    func test_cascadeDelete_doesNotDeleteTags() throws {
        let context = container.mainContext

        let memo = VoiceMemoModel(audioFilePath: "Audio/test.m4a")
        context.insert(memo)

        let tag = TagModel(name: "仕事")
        context.insert(tag)
        memo.tags.append(tag)
        try context.save()

        context.delete(memo)
        try context.save()

        // タグは削除されないこと（nullify ルール）
        let tags = try context.fetch(FetchDescriptor<TagModel>())
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags.first?.name, "仕事")
    }

    // MARK: - UserSettings

    @MainActor
    func test_userSettingsModel_creation_withDefaults() throws {
        let context = container.mainContext

        let settings = UserSettingsModel()
        context.insert(settings)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserSettingsModel>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.theme, .system)
        XCTAssertEqual(fetched.first?.preferredSTTEngine, .whisperKit)
        XCTAssertFalse(fetched.first!.biometricAuthEnabled)
    }

    @MainActor
    func test_userSettingsModel_customDictionary_persistence() throws {
        let context = container.mainContext

        let settings = UserSettingsModel(
            customDictionary: ["AI": "エーアイ", "ML": "エムエル"]
        )
        context.insert(settings)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserSettingsModel>())
        XCTAssertEqual(fetched.first?.customDictionary["AI"], "エーアイ")
        XCTAssertEqual(fetched.first?.customDictionary["ML"], "エムエル")
    }

    // MARK: - toEntity 変換テスト

    @MainActor
    func test_voiceMemoModel_toEntity() throws {
        let context = container.mainContext

        let memo = VoiceMemoModel(
            title: "変換テスト",
            durationSeconds: 30.0,
            audioFilePath: "Audio/test.m4a",
            audioFormat: .m4a,
            status: .completed,
            isFavorite: true
        )
        context.insert(memo)
        try context.save()

        let entity = memo.toEntity()
        XCTAssertEqual(entity.title, "変換テスト")
        XCTAssertEqual(entity.durationSeconds, 30.0)
        XCTAssertEqual(entity.audioFilePath, "Audio/test.m4a")
        XCTAssertEqual(entity.audioFormat, .m4a)
        XCTAssertEqual(entity.status, .completed)
        XCTAssertTrue(entity.isFavorite)
    }

    @MainActor
    func test_emotionAnalysisModel_toEntity_convertsDictionary() throws {
        let context = container.mainContext

        let memo = VoiceMemoModel(audioFilePath: "Audio/test.m4a")
        context.insert(memo)

        let analysis = EmotionAnalysisModel(
            primaryEmotion: .joy,
            confidence: 0.9,
            emotionScores: ["joy": 0.8, "neutral": 0.2],
            evidence: [["text": "楽しい", "emotion": "joy"]]
        )
        analysis.memo = memo
        context.insert(analysis)
        try context.save()

        let entity = analysis.toEntity()
        XCTAssertEqual(entity.primaryEmotion, .joy)
        XCTAssertEqual(entity.confidence, 0.9)
        XCTAssertEqual(entity.emotionScores[.joy], 0.8)
        XCTAssertEqual(entity.emotionScores[.neutral], 0.2)
        XCTAssertEqual(entity.evidence.count, 1)
        XCTAssertEqual(entity.evidence.first?.text, "楽しい")
        XCTAssertEqual(entity.evidence.first?.emotion, .joy)
    }
}
