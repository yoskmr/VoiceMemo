import Domain
import Foundation
import SQLite3

/// FTS5全文検索インデックスの管理
/// TASK-0015: SQLite FTS5全文検索エンジン
/// REQ-006: フルテキスト検索
/// 設計書 01-system-architecture.md セクション5.3 準拠
public final class FTS5IndexManager: @unchecked Sendable, FTS5IndexManagerProtocol {

    private let dbPath: String
    private let useICU: Bool
    private let lock = NSLock()

    public init(dbPath: String) {
        self.dbPath = dbPath
        self.useICU = FTS5IndexManager.checkICUAvailability(dbPath: dbPath)
    }

    /// テスト用: ICU使用可否を明示的に指定
    internal init(dbPath: String, useICU: Bool) {
        self.dbPath = dbPath
        self.useICU = useICU
    }

    /// ICUトークナイザの利用可否
    public var isUsingICU: Bool { useICU }

    // MARK: - テーブル作成

    public func createIndex() throws {
        if useICU {
            try execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS memo_fts USING fts5(
                    memo_id UNINDEXED,
                    title,
                    transcription_text,
                    summary_text,
                    tags,
                    tokenize = 'icu ja_JP'
                );
            """)
        } else {
            // unicode61 フォールバック
            try execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS memo_fts USING fts5(
                    memo_id UNINDEXED,
                    title,
                    transcription_text,
                    summary_text,
                    tags,
                    tokenize = 'unicode61'
                );
            """)
            // trigram テーブル（部分一致検索用）
            try execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS memo_fts_trigram USING fts5(
                    memo_id UNINDEXED,
                    title,
                    transcription_text,
                    tokenize = 'trigram'
                );
            """)
        }
    }

    // MARK: - CRUD操作

    public func upsertIndex(
        memoID: String,
        title: String,
        transcriptionText: String,
        summaryText: String,
        tags: String
    ) throws {
        // 既存レコードを削除
        try execute(
            sql: "DELETE FROM memo_fts WHERE memo_id = ?;",
            params: [memoID]
        )

        // 新規挿入
        try execute(
            sql: """
                INSERT INTO memo_fts (memo_id, title, transcription_text, summary_text, tags)
                VALUES (?, ?, ?, ?, ?);
            """,
            params: [memoID, title, transcriptionText, summaryText, tags]
        )

        // trigram テーブルも更新（フォールバック環境のみ）
        if !useICU {
            try execute(
                sql: "DELETE FROM memo_fts_trigram WHERE memo_id = ?;",
                params: [memoID]
            )
            try execute(
                sql: """
                    INSERT INTO memo_fts_trigram (memo_id, title, transcription_text)
                    VALUES (?, ?, ?);
                """,
                params: [memoID, title, transcriptionText]
            )
        }
    }

    public func removeIndex(memoID: String) throws {
        try execute(
            sql: "DELETE FROM memo_fts WHERE memo_id = ?;",
            params: [memoID]
        )
        if !useICU {
            try execute(
                sql: "DELETE FROM memo_fts_trigram WHERE memo_id = ?;",
                params: [memoID]
            )
        }
    }

    // MARK: - 検索

    public func search(query: String) throws -> [FTS5SearchResult] {
        let sanitizedQuery = sanitizeQuery(query)
        guard !sanitizedQuery.isEmpty else { return [] }

        let results = try executeQuery(
            sql: """
                SELECT memo_id,
                       snippet(memo_fts, 2, '<mark>', '</mark>', '...', 32) AS snippet,
                       rank
                FROM memo_fts
                WHERE memo_fts MATCH ?
                ORDER BY rank;
            """,
            params: [sanitizedQuery]
        )

        // ICU非対応環境ではtrigramテーブルも検索してマージ
        if !useICU {
            let trigramResults = try executeQuery(
                sql: """
                    SELECT memo_id,
                           snippet(memo_fts_trigram, 2, '<mark>', '</mark>', '...', 32) AS snippet,
                           rank
                    FROM memo_fts_trigram
                    WHERE memo_fts_trigram MATCH ?
                    ORDER BY rank;
                """,
                params: [sanitizedQuery]
            )
            return mergeResults(primary: results, secondary: trigramResults)
        }

        return results
    }

    public func searchWithSnippets(
        query: String,
        snippetColumn: Int = 2,
        maxTokens: Int = 32
    ) throws -> [FTS5SearchResult] {
        let sanitizedQuery = sanitizeQuery(query)
        guard !sanitizedQuery.isEmpty else { return [] }

        let results = try executeQuery(
            sql: """
                SELECT memo_id,
                       snippet(memo_fts, \(snippetColumn), '<mark>', '</mark>', '...', \(maxTokens)) AS snippet,
                       rank
                FROM memo_fts
                WHERE memo_fts MATCH ?
                ORDER BY rank;
            """,
            params: [sanitizedQuery]
        )

        // ICU非対応環境ではtrigramテーブルも検索してマージ
        if !useICU {
            // trigramテーブルのsnippetColumnは最大2（memo_id, title, transcription_text）
            let trigramSnippetCol = min(snippetColumn, 2)
            let trigramResults = try executeQuery(
                sql: """
                    SELECT memo_id,
                           snippet(memo_fts_trigram, \(trigramSnippetCol), '<mark>', '</mark>', '...', \(maxTokens)) AS snippet,
                           rank
                    FROM memo_fts_trigram
                    WHERE memo_fts_trigram MATCH ?
                    ORDER BY rank;
                """,
                params: [sanitizedQuery]
            )
            return mergeResults(primary: results, secondary: trigramResults)
        }

        return results
    }

    // MARK: - ヘルパー

    /// 検索クエリのサニタイズ（FTS5構文エスケープ）
    /// unicode61テーブルとtrigramテーブルの両方で使われるため、
    /// ダブルクォートによるフレーズ検索で安全にエスケープする。
    /// trigramテーブルのフォールバックにより、unicode61で漏れたCJK部分一致もカバーされる。
    internal func sanitizeQuery(_ query: String) -> String {
        // FTS5特殊文字を除去
        let specialChars = CharacterSet(charactersIn: "\"*():-^{}")
        let escaped = query.unicodeScalars.filter { !specialChars.contains($0) }
        let cleaned = String(String.UnicodeScalarView(escaped))
            .trimmingCharacters(in: .whitespaces)

        guard !cleaned.isEmpty else { return "" }

        // 空白区切りの各語をダブルクォートで囲む（フレーズ検索 + エスケープ）
        let terms = cleaned.split(separator: " ")
            .map { "\"\($0)\"" }

        // 1語のみならそのまま、複数語なら AND 結合
        if terms.count == 1 {
            return terms[0]
        }
        return terms.joined(separator: " AND ")
    }

    /// ICUトークナイザの利用可否チェック
    static func checkICUAvailability(dbPath: String) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return false }
        defer { sqlite3_close(db) }

        let testSQL = "CREATE VIRTUAL TABLE IF NOT EXISTS _icu_test USING fts5(test_col, tokenize = 'icu ja_JP');"
        let result = sqlite3_exec(db, testSQL, nil, nil, nil)
        sqlite3_exec(db, "DROP TABLE IF EXISTS _icu_test;", nil, nil, nil)
        return result == SQLITE_OK
    }

    /// 検索結果のマージ（重複除去、ランク順維持）
    private func mergeResults(
        primary: [FTS5SearchResult],
        secondary: [FTS5SearchResult]
    ) -> [FTS5SearchResult] {
        var seen = Set(primary.map(\.memoID))
        var merged = primary
        for result in secondary where !seen.contains(result.memoID) {
            seen.insert(result.memoID)
            merged.append(result)
        }
        return merged
    }

    // MARK: - SQLite3 C API ラッパー

    private func execute(sql: String, params: [String] = []) throws {
        lock.lock()
        defer { lock.unlock() }

        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw FTS5Error.databaseOpenFailed(
                String(cString: sqlite3_errmsg(db))
            )
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw FTS5Error.prepareFailed(
                String(cString: sqlite3_errmsg(db))
            )
        }
        defer { sqlite3_finalize(stmt) }

        for (index, param) in params.enumerated() {
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, Int32(index + 1), param, -1, SQLITE_TRANSIENT)
        }

        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw FTS5Error.executionFailed(
                String(cString: sqlite3_errmsg(db))
            )
        }
    }

    private func executeQuery(sql: String, params: [String]) throws -> [FTS5SearchResult] {
        lock.lock()
        defer { lock.unlock() }

        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw FTS5Error.databaseOpenFailed(
                String(cString: sqlite3_errmsg(db))
            )
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw FTS5Error.prepareFailed(
                String(cString: sqlite3_errmsg(db))
            )
        }
        defer { sqlite3_finalize(stmt) }

        for (index, param) in params.enumerated() {
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, Int32(index + 1), param, -1, SQLITE_TRANSIENT)
        }

        var results: [FTS5SearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let memoID: String
            if let cString = sqlite3_column_text(stmt, 0) {
                memoID = String(cString: cString)
            } else {
                memoID = ""
            }

            let snippet: String
            if let cString = sqlite3_column_text(stmt, 1) {
                snippet = String(cString: cString)
            } else {
                snippet = ""
            }

            let rank = sqlite3_column_double(stmt, 2)

            results.append(FTS5SearchResult(
                memoID: memoID,
                snippet: snippet,
                rank: rank
            ))
        }

        return results
    }
}

// MARK: - FTS5Error

/// FTS5操作エラー
public enum FTS5Error: Error, LocalizedError {
    case databaseOpenFailed(String)
    case prepareFailed(String)
    case executionFailed(String)
    case queryFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .databaseOpenFailed(msg): return "FTS5: データベースを開けません: \(msg)"
        case let .prepareFailed(msg): return "FTS5: SQL準備失敗: \(msg)"
        case let .executionFailed(msg): return "FTS5: SQL実行失敗: \(msg)"
        case let .queryFailed(msg): return "FTS5: クエリ失敗: \(msg)"
        }
    }
}
