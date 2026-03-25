import XCTest
import SwiftData
import Domain
@testable import InfraStorage

/// SwiftDataVoiceMemoRepository の統合テスト
final class SwiftDataVoiceMemoRepositoryTests: XCTestCase {

    var container: ModelContainer!
    var repository: SwiftDataVoiceMemoRepository!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! ModelContainerConfiguration.create(inMemory: true)
        repository = SwiftDataVoiceMemoRepository(modelContainer: container)
    }

    override func tearDown() {
        repository = nil
        container = nil
        super.tearDown()
    }

    // MARK: - 保存と取得

    func test_save_andFetchByID() async throws {
        let memo = VoiceMemoEntity(
            title: "テストメモ",
            durationSeconds: 45.0,
            audioFilePath: "Audio/test.m4a"
        )

        try await repository.save(memo)
        let fetched = try await repository.fetchByID(memo.id)

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, memo.id)
        XCTAssertEqual(fetched?.title, "テストメモ")
        XCTAssertEqual(fetched?.durationSeconds, 45.0)
        XCTAssertEqual(fetched?.audioFilePath, "Audio/test.m4a")
    }

    func test_fetchByID_nonExistent_returnsNil() async throws {
        let result = try await repository.fetchByID(UUID())
        XCTAssertNil(result)
    }

    // MARK: - 全件取得

    func test_fetchAll_returnsSortedByCreatedAtDesc() async throws {
        let date1 = Date().addingTimeInterval(-100)
        let date2 = Date()

        try await repository.save(VoiceMemoEntity(title: "古いメモ", createdAt: date1, audioFilePath: "Audio/1.m4a"))
        try await repository.save(VoiceMemoEntity(title: "新しいメモ", createdAt: date2, audioFilePath: "Audio/2.m4a"))

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].title, "新しいメモ")
        XCTAssertEqual(all[1].title, "古いメモ")
    }

    // MARK: - 削除

    func test_delete() async throws {
        let memo = VoiceMemoEntity(audioFilePath: "Audio/test.m4a")
        try await repository.save(memo)

        try await repository.delete(memo.id)
        let fetched = try await repository.fetchByID(memo.id)

        XCTAssertNil(fetched)
    }

    func test_delete_nonExistent_doesNotThrow() async throws {
        try await repository.delete(UUID())
        // エラーが発生しないこと
    }

    // MARK: - お気に入り

    func test_fetchFavorites() async throws {
        try await repository.save(VoiceMemoEntity(title: "お気に入り1", audioFilePath: "Audio/1.m4a", isFavorite: true))
        try await repository.save(VoiceMemoEntity(title: "通常", audioFilePath: "Audio/2.m4a", isFavorite: false))
        try await repository.save(VoiceMemoEntity(title: "お気に入り2", audioFilePath: "Audio/3.m4a", isFavorite: true))

        let favorites = try await repository.fetchFavorites()
        XCTAssertEqual(favorites.count, 2)
        XCTAssertTrue(favorites.allSatisfy(\.isFavorite))
    }

    // MARK: - ステータスで検索

    func test_fetchByStatus() async throws {
        try await repository.save(VoiceMemoEntity(audioFilePath: "Audio/1.m4a", status: .completed))
        try await repository.save(VoiceMemoEntity(audioFilePath: "Audio/2.m4a", status: .recording))
        try await repository.save(VoiceMemoEntity(audioFilePath: "Audio/3.m4a", status: .completed))

        let completed = try await repository.fetchByStatus(.completed)
        XCTAssertEqual(completed.count, 2)

        let recording = try await repository.fetchByStatus(.recording)
        XCTAssertEqual(recording.count, 1)
    }

    // MARK: - カウント

    func test_count() async throws {
        let count0 = try await repository.count()
        XCTAssertEqual(count0, 0)

        try await repository.save(VoiceMemoEntity(audioFilePath: "Audio/1.m4a"))
        let count1 = try await repository.count()
        XCTAssertEqual(count1, 1)

        try await repository.save(VoiceMemoEntity(audioFilePath: "Audio/2.m4a"))
        let count2 = try await repository.count()
        XCTAssertEqual(count2, 2)
    }

    // MARK: - Transcription付きメモの保存

    func test_save_memoWithTranscription() async throws {
        let transcription = TranscriptionEntity(
            fullText: "テスト文字起こし",
            language: "ja-JP",
            engineType: .whisperKit,
            confidence: 0.95
        )

        let memo = VoiceMemoEntity(
            title: "文字起こし付きメモ",
            audioFilePath: "Audio/test.m4a",
            transcription: transcription
        )

        try await repository.save(memo)
        let fetched = try await repository.fetchByID(memo.id)

        XCTAssertNotNil(fetched?.transcription)
        XCTAssertEqual(fetched?.transcription?.fullText, "テスト文字起こし")
        XCTAssertEqual(fetched?.transcription?.engineType, .whisperKit)
        XCTAssertEqual(fetched?.transcription?.confidence, 0.95)
    }

    // MARK: - AISummary付きメモの保存

    func test_save_memoWithAISummary() async throws {
        let summary = AISummaryEntity(
            title: "要約タイトル",
            summaryText: "これはテストの要約です",
            keyPoints: ["ポイント1", "ポイント2"],
            providerType: .onDeviceLlamaCpp,
            isOnDevice: true
        )

        let memo = VoiceMemoEntity(
            audioFilePath: "Audio/test.m4a",
            aiSummary: summary
        )

        try await repository.save(memo)
        let fetched = try await repository.fetchByID(memo.id)

        XCTAssertNotNil(fetched?.aiSummary)
        XCTAssertEqual(fetched?.aiSummary?.title, "要約タイトル")
        XCTAssertEqual(fetched?.aiSummary?.keyPoints, ["ポイント1", "ポイント2"])
        XCTAssertEqual(fetched?.aiSummary?.providerType, .onDeviceLlamaCpp)
    }

    // MARK: - EmotionAnalysis付きメモの保存

    func test_save_memoWithEmotionAnalysis() async throws {
        let emotion = EmotionAnalysisEntity(
            primaryEmotion: .joy,
            confidence: 0.9,
            emotionScores: [.joy: 0.8, .calm: 0.2],
            evidence: [SentimentEvidence(text: "楽しかった", emotion: .joy)]
        )

        let memo = VoiceMemoEntity(
            audioFilePath: "Audio/test.m4a",
            emotionAnalysis: emotion
        )

        try await repository.save(memo)
        let fetched = try await repository.fetchByID(memo.id)

        XCTAssertNotNil(fetched?.emotionAnalysis)
        XCTAssertEqual(fetched?.emotionAnalysis?.primaryEmotion, .joy)
        XCTAssertEqual(fetched?.emotionAnalysis?.emotionScores[.joy], 0.8)
        XCTAssertEqual(fetched?.emotionAnalysis?.evidence.count, 1)
    }

    // MARK: - Tag付きメモの保存

    func test_save_memoWithTags() async throws {
        let tags = [
            TagEntity(name: "仕事", source: .ai),
            TagEntity(name: "個人", source: .manual),
        ]

        let memo = VoiceMemoEntity(
            audioFilePath: "Audio/test.m4a",
            tags: tags
        )

        try await repository.save(memo)
        let fetched = try await repository.fetchByID(memo.id)

        XCTAssertEqual(fetched?.tags.count, 2)
        let tagNames = Set(fetched?.tags.map(\.name) ?? [])
        XCTAssertTrue(tagNames.contains("仕事"))
        XCTAssertTrue(tagNames.contains("個人"))
    }

    // MARK: - タグによる検索

    func test_fetchByTag() async throws {
        let tag = TagEntity(name: "重要")

        try await repository.save(VoiceMemoEntity(title: "メモ1", audioFilePath: "Audio/1.m4a", tags: [tag]))
        try await repository.save(VoiceMemoEntity(title: "メモ2", audioFilePath: "Audio/2.m4a"))

        let tagged = try await repository.fetchByTag("重要")
        XCTAssertEqual(tagged.count, 1)
        XCTAssertEqual(tagged.first?.title, "メモ1")
    }
}
