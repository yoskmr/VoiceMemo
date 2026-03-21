import Data
import Dependencies
import Domain
import Foundation
import InfraLLM
import InfraStorage
import SwiftData

// MARK: - Settings Dependencies
// AI処理キュー・LLMプロバイダ・AIクォータ・カスタム辞書のDependency実装

// MARK: - Shared ModelContainer

/// AI関連モジュールで共有する ModelContainer
/// SwiftData の ModelContainer は複数インスタンスを持つと競合するため、
/// シングルトンで共有する。
private let sharedAIModelContainer: ModelContainer = {
    do {
        return try ModelContainerConfiguration.create(inMemory: false)
    } catch {
        #if DEBUG
        fatalError("SwiftData ModelContainer の初期化に失敗 (AI): \(error)")
        #else
        fatalError("データベース初期化エラー")
        #endif
    }
}()

// MARK: LLMProviderClient → OnDeviceLLMProvider Live実装

/// Phase 3a: OnDeviceLLMProvider を使用（内部的に MockLLMProvider に委譲）
/// 将来: llama.cpp 実統合時に OnDeviceLLMProvider の内部実装を差し替える
private let sharedOnDeviceLLMProvider = OnDeviceLLMProvider()

extension LLMProviderClient: DependencyKey {
    public static let liveValue: LLMProviderClient = sharedOnDeviceLLMProvider.asClient()
}

// MARK: AIQuotaClient → AIQuotaRepository Live実装（SwiftData永続化）

private let sharedAIQuotaRepository = AIQuotaRepository(
    modelContainer: sharedAIModelContainer
)

extension AIQuotaClient: DependencyKey {
    public static let liveValue: AIQuotaClient = sharedAIQuotaRepository.toClient()
}

// MARK: AIProcessingQueueClient → AIProcessingQueueLive Live実装

extension AIProcessingQueueClient: DependencyKey {
    public static let liveValue: AIProcessingQueueClient = {
        let queue = AIProcessingQueueLive(
            modelContainer: sharedAIModelContainer,
            llmProvider: LLMProviderClient.liveValue,
            aiQuota: AIQuotaClient.liveValue,
            voiceMemoRepository: VoiceMemoRepositoryClient.liveValue
        )
        return queue.toClient()
    }()
}

// MARK: CustomDictionaryClient → UserDefaults永続化実装

/// カスタム辞書エントリの UserDefaults 永続化キー
private let customDictionaryUserDefaultsKey = "com.murmurnote.customDictionary.entries"

/// UserDefaults に保存するためのCodable中間構造体
private struct CodableDictionaryEntry: Codable {
    let id: String
    let reading: String
    let display: String

    init(from entry: DictionaryEntry) {
        self.id = entry.id.uuidString
        self.reading = entry.reading
        self.display = entry.display
    }

    func toDomainEntry() -> DictionaryEntry? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return DictionaryEntry(id: uuid, reading: reading, display: display)
    }
}

extension CustomDictionaryClient: DependencyKey {
    public static let liveValue: CustomDictionaryClient = {
        let defaults = UserDefaults.standard

        /// UserDefaults からエントリ一覧をデコードする
        func loadEntriesFromDefaults() -> [DictionaryEntry] {
            guard let data = defaults.data(forKey: customDictionaryUserDefaultsKey) else {
                return []
            }
            let decoder = JSONDecoder()
            guard let codableEntries = try? decoder.decode([CodableDictionaryEntry].self, from: data) else {
                return []
            }
            return codableEntries.compactMap { $0.toDomainEntry() }
        }

        /// エントリ一覧を UserDefaults にエンコードして保存する
        func saveEntriesToDefaults(_ entries: [DictionaryEntry]) throws {
            let codableEntries = entries.map { CodableDictionaryEntry(from: $0) }
            let encoder = JSONEncoder()
            let data = try encoder.encode(codableEntries)
            defaults.set(data, forKey: customDictionaryUserDefaultsKey)
        }

        return CustomDictionaryClient(
            loadEntries: {
                loadEntriesFromDefaults()
            },
            addEntry: { entry in
                var entries = loadEntriesFromDefaults()
                entries.append(entry)
                try saveEntriesToDefaults(entries)
            },
            deleteEntry: { id in
                var entries = loadEntriesFromDefaults()
                entries.removeAll { $0.id == id }
                try saveEntriesToDefaults(entries)
            },
            getContextualStrings: {
                loadEntriesFromDefaults().map(\.display)
            }
        )
    }()
}
