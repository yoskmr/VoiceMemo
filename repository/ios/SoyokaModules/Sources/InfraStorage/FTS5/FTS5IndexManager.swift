import Domain
import Foundation
import os.log
import SQLite3

private let logger = Logger(subsystem: "app.soyoka", category: "FTS5")

/// FTS5全文検索インデックスの管理
/// TASK-0015: SQLite FTS5全文検索エンジン
/// REQ-006: フルテキスト検索
/// 設計書 01-system-architecture.md セクション5.3 準拠
///
/// ## 日本語検索の戦略
/// unicode61 トークナイザは CJK 文字列を単一トークンとして扱うため、
/// 日本語の部分一致検索ができない。そのため trigram テーブルを常に併用し、
/// 3文字以上の日本語クエリは trigram で部分一致検索を行う。
/// 2文字以下のクエリは LIKE フォールバックで対応する。
public final class FTS5IndexManager: @unchecked Sendable, FTS5IndexManagerProtocol {

    private let dbPath: String
    private let useICU: Bool
    private let lock = NSLock()
    private var db: OpaquePointer?

    public init(dbPath: String) {
        self.dbPath = dbPath
        self.useICU = FTS5IndexManager.checkICUAvailability(dbPath: dbPath)

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            let errMsg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            logger.error("[FTS5] init: sqlite3_open 失敗: \(errMsg)")
            db = nil
        }
        logger.info("[FTS5] init: dbPath=\(dbPath, privacy: .private), useICU=\(self.useICU)")
    }

    /// テスト用: ICU使用可否を明示的に指定
    internal init(dbPath: String, useICU: Bool) {
        self.dbPath = dbPath
        self.useICU = useICU

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            db = nil
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
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
        }
        // trigram テーブルは常に作成（日本語部分一致検索の安全網）
        // unicode61 は CJK 文字列を単一トークンとして扱うため、
        // 日本語の部分一致は trigram に依存する
        try execute(sql: """
            CREATE VIRTUAL TABLE IF NOT EXISTS memo_fts_trigram USING fts5(
                memo_id UNINDEXED,
                title,
                transcription_text,
                tokenize = 'trigram'
            );
        """)
        logger.info("[FTS5] createIndex 完了 (useICU=\(self.useICU))")
    }

    // MARK: - CRUD操作

    public func upsertIndex(
        memoID: String,
        title: String,
        transcriptionText: String,
        summaryText: String,
        tags: String
    ) throws {
        logger.info("[FTS5] upsert開始: id=\(memoID.prefix(8), privacy: .private), title_len=\(title.count), text_len=\(transcriptionText.count)")

        if transcriptionText.isEmpty && title.isEmpty {
            logger.warning("[FTS5] upsert: title と transcriptionText が両方空です")
        }

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

        // trigram テーブルも常に更新（日本語部分一致の安全網）
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

        logger.info("[FTS5] upsert完了: id=\(memoID.prefix(8), privacy: .private)")
    }

    public func removeIndex(memoID: String) throws {
        try execute(
            sql: "DELETE FROM memo_fts WHERE memo_id = ?;",
            params: [memoID]
        )
        try execute(
            sql: "DELETE FROM memo_fts_trigram WHERE memo_id = ?;",
            params: [memoID]
        )
    }

    // MARK: - 検索

    public func search(query: String) throws -> [FTS5SearchResult] {
        let sanitizedQuery = sanitizeQuery(query)
        guard !sanitizedQuery.isEmpty else { return [] }

        // unicode61/ICU テーブルで検索（CJK部分一致は期待できない）
        var primaryResults: [FTS5SearchResult] = []
        do {
            primaryResults = try executeQuery(
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
        } catch {
            logger.warning("[FTS5] memo_fts検索エラー（trigramフォールバックに継続）: \(error.localizedDescription)")
        }

        // trigram テーブルで部分一致検索（日本語対応の要）
        let cleanedQuery = cleanQuery(query)
        if cleanedQuery.count >= 3 {
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
            return mergeResults(primary: primaryResults, secondary: trigramResults)
        } else if cleanedQuery.count >= 1 {
            // 2文字以下: trigram不可、LIKEフォールバック
            let likeResults = try executeLikeQuery(query: cleanedQuery)
            return mergeResults(primary: primaryResults, secondary: likeResults)
        }

        return primaryResults
    }

    public func searchWithSnippets(
        query: String,
        snippetColumn: Int = 2,
        maxTokens: Int = 32
    ) throws -> [FTS5SearchResult] {
        let sanitizedQuery = sanitizeQuery(query)
        guard !sanitizedQuery.isEmpty else { return [] }

        let cleanedQuery = cleanQuery(query)
        logger.info("[FTS5] searchWithSnippets: query_len=\(query.count), sanitized_len=\(sanitizedQuery.count), cleaned_len=\(cleanedQuery.count)")

        // unicode61/ICU テーブルで検索
        // エラーが発生してもtrigramフォールバックに進む
        var primaryResults: [FTS5SearchResult] = []
        do {
            primaryResults = try executeQuery(
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
            logger.info("[FTS5] memo_fts結果: \(primaryResults.count)件")
        } catch {
            logger.warning("[FTS5] memo_fts検索エラー（trigramフォールバックに継続）: \(error.localizedDescription)")
        }

        // trigram テーブルで部分一致検索（3文字以上）
        if cleanedQuery.count >= 3 {
            let trigramSnippetCol = min(snippetColumn, 2)
            do {
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
                logger.info("[FTS5] trigram結果: \(trigramResults.count)件")
                return mergeResults(primary: primaryResults, secondary: trigramResults)
            } catch {
                logger.warning("[FTS5] trigram検索エラー: \(error.localizedDescription)")
            }
        } else if cleanedQuery.count >= 1 {
            // 2文字以下: trigram不可、LIKEフォールバック
            do {
                let likeResults = try executeLikeQuery(query: cleanedQuery)
                logger.info("[FTS5] LIKEフォールバック結果: \(likeResults.count)件")
                return mergeResults(primary: primaryResults, secondary: likeResults)
            } catch {
                logger.warning("[FTS5] LIKEフォールバックエラー: \(error.localizedDescription)")
            }
        }

        return primaryResults
    }

    // MARK: - ヘルパー

    /// FTS5特殊文字を除去してクリーンなクエリ文字列を返す
    internal func cleanQuery(_ query: String) -> String {
        let specialChars = CharacterSet(charactersIn: "\"*():-^{}")
        let escaped = query.unicodeScalars.filter { !specialChars.contains($0) }
        return String(String.UnicodeScalarView(escaped))
            .trimmingCharacters(in: .whitespaces)
    }

    /// 検索クエリのサニタイズ（FTS5構文エスケープ）
    /// unicode61テーブルとtrigramテーブルの両方で使われるため、
    /// ダブルクォートによるフレーズ検索で安全にエスケープする。
    /// trigramテーブルのフォールバックにより、unicode61で漏れたCJK部分一致もカバーされる。
    internal func sanitizeQuery(_ query: String) -> String {
        let cleaned = cleanQuery(query)
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
        var errMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, testSQL, nil, nil, &errMsg)
        if let errMsg {
            sqlite3_free(errMsg)
        }

        var dropErrMsg: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, "DROP TABLE IF EXISTS _icu_test;", nil, nil, &dropErrMsg)
        if let dropErrMsg {
            sqlite3_free(dropErrMsg)
        }

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

        guard let db else {
            throw FTS5Error.databaseOpenFailed("コネクションが確立されていません")
        }

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

        guard let db else {
            throw FTS5Error.databaseOpenFailed("コネクションが確立されていません")
        }

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

    /// 2文字以下のクエリ用 LIKE フォールバック検索
    /// trigram は最低3文字必要なため、短いクエリにはLIKEを使う
    private func executeLikeQuery(query: String) throws -> [FTS5SearchResult] {
        lock.lock()
        defer { lock.unlock() }

        guard let db else {
            throw FTS5Error.databaseOpenFailed("コネクションが確立されていません")
        }

        // memo_fts_trigram の content テーブルから LIKE 検索
        // FTS5 shadow テーブルは直接アクセスできないため、通常テーブルへ LIKE を使う
        // ただし FTS5 テーブルは SELECT で直接読める
        let sql = """
            SELECT memo_id, title, transcription_text
            FROM memo_fts_trigram
            WHERE title LIKE ? OR transcription_text LIKE ?
            LIMIT 50;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw FTS5Error.prepareFailed(
                String(cString: sqlite3_errmsg(db))
            )
        }
        defer { sqlite3_finalize(stmt) }

        let likePattern = "%\(query)%"
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, likePattern, -1, transient)
        sqlite3_bind_text(stmt, 2, likePattern, -1, transient)

        var results: [FTS5SearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let memoID = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let text = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""

            // スニペット生成: マッチ箇所の前後を切り出す
            let snippet = generateSnippet(from: text.isEmpty ? title : text, query: query)
            results.append(FTS5SearchResult(memoID: memoID, snippet: snippet, rank: 0))
        }

        return results
    }

    /// LIKE フォールバック用のスニペット生成
    private func generateSnippet(from text: String, query: String, maxLength: Int = 80) -> String {
        guard let range = text.range(of: query, options: .caseInsensitive) else {
            let endIndex = text.index(text.startIndex, offsetBy: min(maxLength, text.count))
            return String(text[..<endIndex])
        }
        // マッチ箇所の前後を含むスニペットを生成
        let matchStart = text.distance(from: text.startIndex, to: range.lowerBound)
        let contextStart = max(0, matchStart - 20)
        let startIdx = text.index(text.startIndex, offsetBy: contextStart)
        let endIdx = text.index(startIdx, offsetBy: min(maxLength, text.distance(from: startIdx, to: text.endIndex)))
        var snippet = String(text[startIdx..<endIdx])
        if contextStart > 0 { snippet = "..." + snippet }
        if endIdx < text.endIndex { snippet = snippet + "..." }
        // マークアップ追加
        snippet = snippet.replacingOccurrences(of: query, with: "<mark>\(query)</mark>")
        return snippet
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
