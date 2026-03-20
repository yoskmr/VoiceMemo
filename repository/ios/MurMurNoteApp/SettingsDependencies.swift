import Dependencies
import Domain
import Foundation

// MARK: - Settings Dependencies
// AI処理キュー・カスタム辞書のDependency実装（Phase 3で実体実装予定）

// MARK: AIProcessingQueueClient → スタブ実装（Phase 3で実体実装予定）

extension AIProcessingQueueClient: DependencyKey {
    public static let liveValue = AIProcessingQueueClient(
        enqueueProcessing: { _ in },
        observeStatus: { _ in AsyncStream { $0.finish() } },
        cancelProcessing: { _ in }
    )
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
