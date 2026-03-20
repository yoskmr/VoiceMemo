import Dependencies
import Foundation

/// カスタム辞書エントリ
/// TASK-0018: カスタム辞書（STT精度向上）
public struct DictionaryEntry: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var reading: String   // 読み（ひらがな/カタカナ）
    public var display: String   // 表記（漢字/英語等）

    public init(id: UUID = UUID(), reading: String, display: String) {
        self.id = id
        self.reading = reading
        self.display = display
    }
}

/// カスタム辞書管理の TCA Dependency ラッパー
/// @Dependency(\.customDictionaryClient) でReducerから注入可能にする
/// REQ-025: SFSpeechRecognizerのcontextualStrings連携
public struct CustomDictionaryClient: Sendable {
    /// 辞書エントリの読み込み
    public var loadEntries: @Sendable () async throws -> [DictionaryEntry]
    /// 辞書エントリの追加
    public var addEntry: @Sendable (DictionaryEntry) async throws -> Void
    /// 辞書エントリの削除
    public var deleteEntry: @Sendable (UUID) async throws -> Void
    /// STTエンジンに渡す contextualStrings を生成
    public var getContextualStrings: @Sendable () async throws -> [String]

    public init(
        loadEntries: @escaping @Sendable () async throws -> [DictionaryEntry],
        addEntry: @escaping @Sendable (DictionaryEntry) async throws -> Void,
        deleteEntry: @escaping @Sendable (UUID) async throws -> Void,
        getContextualStrings: @escaping @Sendable () async throws -> [String]
    ) {
        self.loadEntries = loadEntries
        self.addEntry = addEntry
        self.deleteEntry = deleteEntry
        self.getContextualStrings = getContextualStrings
    }
}

// MARK: - DependencyKey

extension CustomDictionaryClient: TestDependencyKey {
    public static let testValue = CustomDictionaryClient(
        loadEntries: unimplemented("CustomDictionaryClient.loadEntries"),
        addEntry: unimplemented("CustomDictionaryClient.addEntry"),
        deleteEntry: unimplemented("CustomDictionaryClient.deleteEntry"),
        getContextualStrings: unimplemented("CustomDictionaryClient.getContextualStrings")
    )
}

extension DependencyValues {
    public var customDictionaryClient: CustomDictionaryClient {
        get { self[CustomDictionaryClient.self] }
        set { self[CustomDictionaryClient.self] = newValue }
    }
}
