import XCTest
import SwiftData
@testable import InfraStorage

/// ModelContainerConfiguration のテスト
final class ModelContainerConfigurationTests: XCTestCase {

    // MARK: - ModelContainer 生成テスト

    func test_create_inMemory_succeeds() throws {
        let container = try ModelContainerConfiguration.create(inMemory: true)
        XCTAssertNotNil(container)
    }

    @MainActor
    func test_create_inMemory_canInsertAndFetch() throws {
        let container = try ModelContainerConfiguration.create(inMemory: true)
        let context = container.mainContext

        let memo = VoiceMemoModel(audioFilePath: "Audio/test.m4a")
        context.insert(memo)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<VoiceMemoModel>())
        XCTAssertEqual(fetched.count, 1)
    }

    @MainActor
    func test_schema_includesAllModels() throws {
        let container = try ModelContainerConfiguration.create(inMemory: true)
        let context = container.mainContext

        // 全モデルに対して空のフェッチが実行できることでスキーマの正しさを検証
        _ = try context.fetch(FetchDescriptor<VoiceMemoModel>())
        _ = try context.fetch(FetchDescriptor<TranscriptionModel>())
        _ = try context.fetch(FetchDescriptor<AISummaryModel>())
        _ = try context.fetch(FetchDescriptor<TagModel>())
        _ = try context.fetch(FetchDescriptor<EmotionAnalysisModel>())
        _ = try context.fetch(FetchDescriptor<UserSettingsModel>())
    }
}
