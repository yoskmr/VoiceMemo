import Foundation
import Testing
import SwiftData
import ZIPFoundation
@testable import Domain
@testable import InfraStorage

@Suite("BackupImporter テスト")
struct BackupImporterTests {

    @MainActor
    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainerConfiguration.create(inMemory: true)
    }

    /// テスト用の .soyokabackup (ZIP) ファイルを生成するヘルパー
    private func createTestBackupFile(payload: BackupPayload, audioFiles: [String: Data] = [:]) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(payload)
        try jsonData.write(to: tempDir.appendingPathComponent("metadata.json"))

        if !audioFiles.isEmpty {
            let audioDir = tempDir.appendingPathComponent("audio", isDirectory: true)
            try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
            for (name, data) in audioFiles {
                try data.write(to: audioDir.appendingPathComponent(name))
            }
        }

        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).soyokabackup")
        try FileManager.default.zipItem(at: tempDir, to: zipURL)
        try? FileManager.default.removeItem(at: tempDir)
        return zipURL
    }

    private func makeMinimalPayload(memoID: UUID = UUID()) -> BackupPayload {
        let memo = BackupMemo(
            id: memoID,
            title: "テストきおく",
            createdAt: Date(),
            updatedAt: Date(),
            durationSeconds: 30.0,
            audioFileName: "\(memoID.uuidString).m4a",
            audioFormat: "m4a",
            status: "completed",
            isFavorite: false,
            transcription: BackupTranscription(
                id: UUID(),
                fullText: "テスト文字起こし",
                language: "ja-JP",
                engineType: "speech_analyzer",
                confidence: 0.9,
                processedAt: Date()
            ),
            aiSummary: nil,
            emotionAnalysis: nil,
            tagNames: ["テストタグ"]
        )
        let tag = BackupTag(
            id: UUID(),
            name: "テストタグ",
            colorHex: "#FF0000",
            source: "ai",
            createdAt: Date()
        )
        return BackupPayload(memos: [memo], tags: [tag])
    }

    @Test("インポート: 新規メモが正しく SwiftData に保存される")
    @MainActor
    func test_import_新規メモ保存() async throws {
        let container = try makeTestContainer()
        let memoID = UUID()
        let payload = makeMinimalPayload(memoID: memoID)
        let zipURL = try createTestBackupFile(payload: payload)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let importer = BackupImporter(modelContainer: container)
        let result = try await importer.importBackup(fileURL: zipURL)

        #expect(result.importedCount == 1)
        #expect(result.skippedCount == 0)

        let descriptor = FetchDescriptor<VoiceMemoModel>(
            predicate: #Predicate { $0.id == memoID }
        )
        let memos = try container.mainContext.fetch(descriptor)
        #expect(memos.count == 1)
        #expect(memos[0].title == "テストきおく")
        #expect(memos[0].transcription?.fullText == "テスト文字起こし")
    }

    @Test("インポート: UUID 重複メモはスキップされる")
    @MainActor
    func test_import_重複スキップ() async throws {
        let container = try makeTestContainer()
        let memoID = UUID()

        // 既存メモを先に挿入
        let existingMemo = VoiceMemoModel(
            id: memoID,
            title: "既存きおく",
            durationSeconds: 10.0,
            audioFilePath: "Audio/existing.m4a"
        )
        container.mainContext.insert(existingMemo)
        try container.mainContext.save()

        let payload = makeMinimalPayload(memoID: memoID)
        let zipURL = try createTestBackupFile(payload: payload)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let importer = BackupImporter(modelContainer: container)
        let result = try await importer.importBackup(fileURL: zipURL)

        #expect(result.importedCount == 0)
        #expect(result.skippedCount == 1)

        // タイトルが上書きされていないことを確認
        let descriptor = FetchDescriptor<VoiceMemoModel>(
            predicate: #Predicate { $0.id == memoID }
        )
        let memos = try container.mainContext.fetch(descriptor)
        #expect(memos[0].title == "既存きおく")
    }

    @Test("インポート: タグマージ - 同名タグは既存UUIDを採用")
    @MainActor
    func test_import_タグマージ_同名は既存UUID採用() async throws {
        let container = try makeTestContainer()
        let existingTagID = UUID()

        // 既存タグを先に挿入
        let existingTag = TagModel(id: existingTagID, name: "テストタグ", colorHex: "#00FF00", source: .manual)
        container.mainContext.insert(existingTag)
        try container.mainContext.save()

        let payload = makeMinimalPayload()
        let zipURL = try createTestBackupFile(payload: payload)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let importer = BackupImporter(modelContainer: container)
        _ = try await importer.importBackup(fileURL: zipURL)

        // タグが重複作成されていないことを確認
        let tagDescriptor = FetchDescriptor<TagModel>(
            predicate: #Predicate { $0.name == "テストタグ" }
        )
        let tags = try container.mainContext.fetch(tagDescriptor)
        #expect(tags.count == 1)
        #expect(tags[0].id == existingTagID)
    }

    @Test("インポート: バージョンが大きい場合はエラー")
    @MainActor
    func test_import_バージョン不一致エラー() async throws {
        let container = try makeTestContainer()
        let payload = BackupPayload(
            version: 999,
            memos: [],
            tags: []
        )
        let zipURL = try createTestBackupFile(payload: payload)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let importer = BackupImporter(modelContainer: container)
        await #expect(throws: BackupImportError.self) {
            try await importer.importBackup(fileURL: zipURL)
        }
    }

    @Test("インポート: 音声ファイル欠損時はメタデータのみ復元")
    @MainActor
    func test_import_音声欠損_メタデータのみ復元() async throws {
        let container = try makeTestContainer()
        let memoID = UUID()
        let payload = makeMinimalPayload(memoID: memoID)
        // 音声ファイルを含めずに ZIP を作成
        let zipURL = try createTestBackupFile(payload: payload, audioFiles: [:])
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let importer = BackupImporter(modelContainer: container)
        let result = try await importer.importBackup(fileURL: zipURL)

        #expect(result.importedCount == 1)
        #expect(result.audioMissingCount == 1)

        let descriptor = FetchDescriptor<VoiceMemoModel>(
            predicate: #Predicate { $0.id == memoID }
        )
        let memos = try container.mainContext.fetch(descriptor)
        #expect(memos.count == 1)
    }
}
