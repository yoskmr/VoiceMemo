import Data
import Dependencies
import Domain
import FeatureSubscription
import Foundation
import InfraLLM
import InfraNetwork
import InfraStorage
import SwiftData

// MARK: - Settings Dependencies
// AI処理キュー・LLMプロバイダ・AIクォータ・カスタム辞書のDependency実装

// MARK: - Shared ModelContainer
// StorageDependencies.swift で定義された sharedModelContainer をアプリ全体で共有する

// MARK: BackendProxyClient → Live実装（Backend Proxy 経由クラウドAI）

/// Backend Proxy Base URL（Phase 3b: 環境変数 or Info.plist から取得予定）
private let backendProxyBaseURL: URL = {
    #if DEBUG
    // デバッグメニュー: Backend URL 切替
    if let debugURL = UserDefaults.standard.string(forKey: "debug_backendURL") {
        switch debugURL {
        case "staging":
            return URL(string: "https://staging-api.soyoka.app")!
        case "custom":
            // カスタムURLは将来的にユーザー入力に対応予定
            // 現時点では localhost を使用
            return URL(string: "http://localhost:8080")!
        default:
            // "dev" またはその他 → デフォルト
            break
        }
    }
    #endif
    return URL(string: "https://api.soyoka.app")!
}()

extension BackendProxyClient: DependencyKey {
    public static let liveValue: BackendProxyClient = .live(baseURL: backendProxyBaseURL)
}

// MARK: LLMProviderClient → HybridLLMRouter Live実装（オンデバイス優先 → クラウドフォールバック）

/// Phase 3b: HybridLLMRouter でオンデバイス（Apple Intelligence）優先、
/// クラウド（GPT-4o mini via Backend Proxy）フォールバック構成に切替
private let sharedOnDeviceLLMProvider = OnDeviceLLMProvider()
private let sharedCloudLLMProvider = CloudLLMProvider(proxyClient: BackendProxyClient.liveValue)
private let sharedHybridLLMRouter = HybridLLMRouter(
    onDeviceProvider: sharedOnDeviceLLMProvider,
    cloudProvider: sharedCloudLLMProvider
)

extension LLMProviderClient: DependencyKey {
    public static let liveValue: LLMProviderClient = sharedHybridLLMRouter.asClient()
}

// MARK: AIQuotaClient → AIQuotaRepository Live実装（SwiftData永続化）

private let sharedAIQuotaRepository = AIQuotaRepository(
    modelContainer: sharedModelContainer
)

extension AIQuotaClient: DependencyKey {
    public static let liveValue: AIQuotaClient = sharedAIQuotaRepository.toClient()
}

// MARK: AIProcessingQueueClient → AIProcessingQueueLive Live実装

extension AIProcessingQueueClient: DependencyKey {
    public static let liveValue: AIProcessingQueueClient = {
        let queue = AIProcessingQueueLive(
            modelContainer: sharedModelContainer,
            llmProvider: LLMProviderClient.liveValue,
            aiQuota: AIQuotaClient.liveValue,
            voiceMemoRepository: VoiceMemoRepositoryClient.liveValue,
            customDictionaryClient: CustomDictionaryClient.liveValue,
            fts5IndexManager: FTS5IndexManagerClient.liveValue,
            subscriptionClient: SubscriptionClient.liveValue
        )
        return queue.toClient()
    }()
}

// MARK: CustomDictionaryClient → SwiftData永続化実装

extension CustomDictionaryClient: DependencyKey {
    public static let liveValue: CustomDictionaryClient = {
        let container = sharedModelContainer

        return CustomDictionaryClient(
            loadEntries: {
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<CustomDictionaryEntryModel>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
                let models = try context.fetch(descriptor)
                return models.map { model in
                    DictionaryEntry(id: model.id, reading: model.reading, display: model.display)
                }
            },
            addEntry: { entry in
                let context = ModelContext(container)
                let model = CustomDictionaryEntryModel(
                    id: entry.id,
                    reading: entry.reading,
                    display: entry.display
                )
                context.insert(model)
                try context.save()
            },
            deleteEntry: { id in
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<CustomDictionaryEntryModel>(
                    predicate: #Predicate { $0.id == id }
                )
                let models = try context.fetch(descriptor)
                for model in models {
                    context.delete(model)
                }
                try context.save()
            },
            getContextualStrings: {
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<CustomDictionaryEntryModel>()
                let models = try context.fetch(descriptor)
                return models.map(\.display)
            },
            getDictionaryPairs: {
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<CustomDictionaryEntryModel>()
                let models = try context.fetch(descriptor)
                return models.map { (reading: $0.reading, display: $0.display) }
            }
        )
    }()
}
