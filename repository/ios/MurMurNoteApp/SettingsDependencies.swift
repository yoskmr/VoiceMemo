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

// MARK: CustomDictionaryClient → MVPスタブ実装（カスタム辞書は後で実装）

extension CustomDictionaryClient: DependencyKey {
    public static let liveValue = CustomDictionaryClient(
        loadEntries: { [] },
        addEntry: { _ in },
        deleteEntry: { _ in },
        getContextualStrings: { [] }
    )
}
