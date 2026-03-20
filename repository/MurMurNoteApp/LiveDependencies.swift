import Dependencies
import Domain
import InfraSTT
import InfraStorage
import Foundation
import AVFoundation
import SwiftData

// MARK: - Live Dependencies Registration
// アプリ実行時に実際のハードウェア/APIに接続するDependency実装

// MARK: AudioRecorderClient → AVAudioEngineRecorder

extension AudioRecorderClient: DependencyKey {
    public static let liveValue: AudioRecorderClient = {
        let recorder = AVAudioEngineRecorder()
        return AudioRecorderClient(
            startRecording: { try await recorder.startRecording() },
            pauseRecording: { try await recorder.pauseRecording() },
            resumeRecording: { try await recorder.resumeRecording() },
            stopRecording: { try await recorder.stopRecording() },
            isRecording: { recorder.isRecording },
            isPaused: { recorder.isPaused },
            requestPermission: {
                await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }
        )
    }()
}

// MARK: STTEngineClient → AppleSpeechEngine

extension STTEngineClient: DependencyKey {
    public static let liveValue: STTEngineClient = {
        let engine = AppleSpeechEngine()
        return STTEngineClient(
            startTranscription: { audioStream, language in
                engine.startTranscription(audioStream: audioStream, language: language)
            },
            finishTranscription: { try await engine.finishTranscription() },
            stopTranscription: { await engine.stopTranscription() },
            isAvailable: { await engine.isAvailable() }
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
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fullURL = docsDir.appendingPathComponent(relativePath)
            try FileManager.default.removeItem(at: fullURL)
        }
    )
}

// MARK: VoiceMemoRepositoryClient → SwiftData永続化

extension VoiceMemoRepositoryClient: DependencyKey {
    public static let liveValue: VoiceMemoRepositoryClient = {
        // SwiftData ModelContainer（設計書準拠: 永続ローカルストレージ）
        let container: ModelContainer = {
            do {
                return try ModelContainerConfiguration.create(inMemory: false)
            } catch {
                fatalError("SwiftData ModelContainer の初期化に失敗: \(error)")
            }
        }()

        let repo = SwiftDataVoiceMemoRepository(modelContainer: container)

        return VoiceMemoRepositoryClient(
            save: { memo in try await repo.save(memo) },
            fetchByID: { id in try await repo.fetchByID(id) },
            fetchAll: { try await repo.fetchAll() },
            delete: { id in try await repo.delete(id) },
            fetchMemos: { page, pageSize in
                let all = try await repo.fetchAll()
                let start = page * pageSize
                guard start < all.count else { return [] }
                let end = min(start + pageSize, all.count)
                return Array(all[start..<end])
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
        try? manager.createIndex()

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

// MARK: AudioPlayerClient → MVPスタブ実装（音声再生は後で実装）

extension AudioPlayerClient: DependencyKey {
    public static let liveValue = AudioPlayerClient(
        loadAudio: { _ in 0 },
        play: { _ in },
        pause: { },
        stop: { },
        seek: { _ in },
        currentTime: { 0 }
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

// MARK: TemporaryRecordingStoreClient → 一時ファイル削除

extension TemporaryRecordingStoreClient: DependencyKey {
    public static let liveValue = TemporaryRecordingStoreClient(
        cleanup: { recordingID in
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("Recording", isDirectory: true)
            let fm = FileManager.default

            guard fm.fileExists(atPath: tmpDir.path),
                  let files = try? fm.contentsOfDirectory(atPath: tmpDir.path) else {
                return
            }

            let prefix = recordingID.uuidString
            for file in files where file.hasPrefix(prefix) {
                try? fm.removeItem(at: tmpDir.appendingPathComponent(file))
            }
        }
    )
}
