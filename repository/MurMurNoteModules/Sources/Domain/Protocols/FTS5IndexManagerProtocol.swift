import Dependencies
import Foundation

/// FTS5全文検索結果
/// TASK-0015: SQLite FTS5全文検索エンジン
public struct FTS5SearchResult: Equatable, Sendable {
    public let memoID: String
    public let snippet: String
    public let rank: Double

    public init(memoID: String, snippet: String, rank: Double) {
        self.memoID = memoID
        self.snippet = snippet
        self.rank = rank
    }
}

/// FTS5全文検索インデックスマネージャプロトコル
/// 設計書 01-system-architecture.md セクション5.3 準拠
public protocol FTS5IndexManagerProtocol: Sendable {
    /// FTS5仮想テーブルの作成
    func createIndex() throws
    /// メモのインデックス追加・更新（DELETE + INSERT方式）
    func upsertIndex(memoID: String, title: String, transcriptionText: String, summaryText: String, tags: String) throws
    /// インデックスからメモを削除
    func removeIndex(memoID: String) throws
    /// フルテキスト検索の実行
    func search(query: String) throws -> [FTS5SearchResult]
    /// スニペット付きフルテキスト検索
    func searchWithSnippets(query: String, snippetColumn: Int, maxTokens: Int) throws -> [FTS5SearchResult]
}

/// TCA Dependency ラッパー
public struct FTS5IndexManagerClient: Sendable {
    public var createIndex: @Sendable () throws -> Void
    public var upsertIndex: @Sendable (_ memoID: String, _ title: String, _ transcriptionText: String, _ summaryText: String, _ tags: String) throws -> Void
    public var removeIndex: @Sendable (_ memoID: String) throws -> Void
    public var search: @Sendable (_ query: String) throws -> [FTS5SearchResult]
    public var searchWithSnippets: @Sendable (_ query: String, _ snippetColumn: Int, _ maxTokens: Int) throws -> [FTS5SearchResult]

    public init(
        createIndex: @escaping @Sendable () throws -> Void,
        upsertIndex: @escaping @Sendable (_ memoID: String, _ title: String, _ transcriptionText: String, _ summaryText: String, _ tags: String) throws -> Void,
        removeIndex: @escaping @Sendable (_ memoID: String) throws -> Void,
        search: @escaping @Sendable (_ query: String) throws -> [FTS5SearchResult],
        searchWithSnippets: @escaping @Sendable (_ query: String, _ snippetColumn: Int, _ maxTokens: Int) throws -> [FTS5SearchResult]
    ) {
        self.createIndex = createIndex
        self.upsertIndex = upsertIndex
        self.removeIndex = removeIndex
        self.search = search
        self.searchWithSnippets = searchWithSnippets
    }
}

// MARK: - DependencyKey

extension FTS5IndexManagerClient: TestDependencyKey {
    public static let testValue = FTS5IndexManagerClient(
        createIndex: unimplemented("FTS5IndexManagerClient.createIndex"),
        upsertIndex: unimplemented("FTS5IndexManagerClient.upsertIndex"),
        removeIndex: unimplemented("FTS5IndexManagerClient.removeIndex"),
        search: unimplemented("FTS5IndexManagerClient.search"),
        searchWithSnippets: unimplemented("FTS5IndexManagerClient.searchWithSnippets")
    )
}

extension DependencyValues {
    public var fts5IndexManager: FTS5IndexManagerClient {
        get { self[FTS5IndexManagerClient.self] }
        set { self[FTS5IndexManagerClient.self] = newValue }
    }
}
