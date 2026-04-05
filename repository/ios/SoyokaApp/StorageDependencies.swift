import Dependencies
import Domain
import Foundation
import InfraStorage
import SwiftData

// MARK: - Storage Dependencies
// SwiftData永続化・FTS5検索・音声ファイル管理のDependency実装

// MARK: - Shared ModelContainer（アプリ全体で唯一のインスタンス）

/// SwiftData ModelContainer のシングルトン
/// 複数の Dependency ファイル（Storage / Backup / Settings）から共有参照する。
/// ModelContainer を複数インスタンス生成すると SwiftData の内部状態が競合するため、
/// 必ずこの共有インスタンスを使用すること。
let sharedModelContainer: ModelContainer = {
    do {
        return try ModelContainerConfiguration.create(inMemory: false)
    } catch {
        #if DEBUG
        fatalError("SwiftData ModelContainer の初期化に失敗: \(error)")
        #else
        fatalError("データベース初期化エラー")
        #endif
    }
}()

// MARK: VoiceMemoRepositoryClient → SwiftData永続化

extension VoiceMemoRepositoryClient: DependencyKey {
    public static let liveValue: VoiceMemoRepositoryClient = {
        let repo = SwiftDataVoiceMemoRepository(modelContainer: sharedModelContainer)

        return VoiceMemoRepositoryClient(
            save: { memo in try await repo.save(memo) },
            fetchByID: { id in try await repo.fetchByID(id) },
            fetchAll: { try await repo.fetchAll() },
            delete: { id in try await repo.delete(id) },
            // SwiftData ネイティブページネーション（fetchOffset / fetchLimit）
            fetchMemos: { page, pageSize in
                try await repo.fetchPage(page: page, pageSize: pageSize)
            },
            fetchMemoDetail: { id in
                guard let memo = try await repo.fetchByID(id) else {
                    throw NSError(domain: "VoiceMemoRepository", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "メモが見つかりません"])
                }
                return memo
            },
            updateMemoText: { id, title, text in
                if var memo = try await repo.fetchByID(id) {
                    memo.title = title
                    // AI整理テキストがある場合はそちらを更新、なければ文字起こしを更新
                    if var summary = memo.aiSummary {
                        summary.summaryText = text
                        memo.aiSummary = summary
                    } else if var transcription = memo.transcription {
                        transcription.fullText = text
                        memo.transcription = transcription
                    } else if !text.isEmpty {
                        memo.transcription = TranscriptionEntity(fullText: text)
                    }
                    memo.updatedAt = Date()
                    try await repo.save(memo)
                }
            },
            getAudioFilePath: { id in
                let memo = try await repo.fetchByID(id)
                return memo?.audioFilePath ?? ""
            },
            fetchAllTags: { [] },
            fetchMemoForSearch: { id in
                guard let memo = try await repo.fetchByID(id) else { return nil }
                return SearchableMemo(
                    title: memo.title,
                    createdAt: memo.createdAt,
                    emotion: memo.emotionAnalysis?.primaryEmotion,
                    durationSeconds: memo.durationSeconds,
                    tags: memo.tags.map(\.name)
                )
            },
            fetchMemosByIDs: { ids in
                // N+1解消: 全件取得してフィルタリング（SwiftData の #Predicate は [UUID].contains 非対応のため）
                // TODO: iOS 18+ で #Predicate の IN 句対応が安定したら FetchDescriptor ベースの一括取得に移行する
                let allMemos = try await repo.fetchAll()
                let idSet = Set(ids)
                var result: [UUID: SearchableMemo] = [:]
                for memo in allMemos where idSet.contains(memo.id) {
                    result[memo.id] = SearchableMemo(
                        title: memo.title,
                        createdAt: memo.createdAt,
                        emotion: memo.emotionAnalysis?.primaryEmotion,
                        durationSeconds: memo.durationSeconds,
                        tags: memo.tags.map(\.name)
                    )
                }
                return result
            }
        )
    }()
}

// MARK: FTS5IndexManagerClient → SQLite FTS5全文検索エンジン接続

extension FTS5IndexManagerClient: DependencyKey {
    public static let liveValue: FTS5IndexManagerClient = {
        let dbPath: String = {
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dbDir = docsDir.appendingPathComponent("Database", isDirectory: true)
            if !FileManager.default.fileExists(atPath: dbDir.path) {
                try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
            }
            return dbDir.appendingPathComponent("fts5_index.sqlite3").path
        }()

        let manager = FTS5IndexManager(dbPath: dbPath)

        // 起動時にFTS5仮想テーブルを作成（既にある場合はスキップ）
        do {
            try manager.createIndex()
            print("[FTS5] createIndex 成功 (ICU=\(manager.isUsingICU), path=\(dbPath))")
        } catch {
            print("[FTS5] createIndex エラー: \(error)")
        }

        return FTS5IndexManagerClient(
            createIndex: { try manager.createIndex() },
            upsertIndex: { memoID, title, transcriptionText, summaryText, tags in
                try manager.upsertIndex(
                    memoID: memoID,
                    title: title,
                    transcriptionText: transcriptionText,
                    summaryText: summaryText,
                    tags: tags
                )
            },
            removeIndex: { memoID in try manager.removeIndex(memoID: memoID) },
            search: { query in try manager.search(query: query) },
            searchWithSnippets: { query, snippetColumn, maxTokens in
                try manager.searchWithSnippets(query: query, snippetColumn: snippetColumn, maxTokens: maxTokens)
            }
        )
    }()
}

// MARK: AudioFileStoreClient → ファイル操作の実装

extension AudioFileStoreClient: DependencyKey {
    public static let liveValue = AudioFileStoreClient(
        moveToDocuments: { tempURL, id in
            let fm = FileManager.default
            let audioDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Audio", isDirectory: true)

            if !fm.fileExists(atPath: audioDir.path) {
                try fm.createDirectory(at: audioDir, withIntermediateDirectories: true)
            }

            let destURL = audioDir.appendingPathComponent("\(id.uuidString).m4a")

            // 既に存在する場合は上書き
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }

            try fm.moveItem(at: tempURL, to: destURL)
            return destURL
        },
        setFileProtection: { url in
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
        },
        deleteAudioFile: { relativePath in
            // パストラバーサル対策: ".." を含むパスを拒否し、Audio/ 配下のみ削除を許可
            guard !relativePath.contains("..") else {
                throw NSError(
                    domain: "AudioFileStore",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "不正なファイルパスです"]
                )
            }
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let audioDir = docsDir.appendingPathComponent("Audio", isDirectory: true)
            let fullURL = docsDir.appendingPathComponent(relativePath).standardizedFileURL
            // Documents/Audio/ 配下のファイルのみ削除を許可（末尾スラッシュで "Audio_evil/" 等の誤マッチを防止）
            let audioDirPrefix = audioDir.path.hasSuffix("/") ? audioDir.path : audioDir.path + "/"
            guard fullURL.path.hasPrefix(audioDirPrefix) || fullURL.path == audioDir.path else {
                throw NSError(
                    domain: "AudioFileStore",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Audio ディレクトリ外のファイルは削除できません"]
                )
            }
            try FileManager.default.removeItem(at: fullURL)
        }
    )
}
