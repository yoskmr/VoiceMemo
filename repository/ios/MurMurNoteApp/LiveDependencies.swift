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
            // Documents/Audio/ 配下のファイルのみ削除を許可
            guard fullURL.path.hasPrefix(audioDir.path) else {
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
            // TODO: SwiftData のネイティブページネーション（FetchDescriptor の fetchOffset/fetchLimit）に移行する
            // 現在は fetchAll() で全件取得後にメモリ上でスライスしているため、データ量増加時にパフォーマンス劣化の可能性あり
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
                    if var transcription = memo.transcription {
                        transcription.fullText = text
                        memo.transcription = transcription
                    } else if !text.isEmpty {
                        // transcription が nil の場合、新規作成して fullText を設定
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

// MARK: AudioPlayerClient → AVAudioPlayer 実装

/// AVAudioPlayer をラップする MainActor 隔離クラス
/// すべての操作を MainActor 上で実行し、AVAudioPlayer のスレッドセーフティを保証する
private final class LiveAudioPlayer: Sendable {
    /// AVAudioPlayer はメインスレッドでのみ操作する
    /// nonisolated(unsafe) で Sendable 準拠しつつ、実際のアクセスは全て MainActor 経由
    nonisolated(unsafe) private var player: AVAudioPlayer?

    /// 音声ファイルをロードし duration を返す
    @MainActor
    func loadAudio(path: String) throws -> TimeInterval {
        let url = Self.resolveFileURL(path: path)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioPlayerError.fileNotFound(path)
        }

        let newPlayer = try AVAudioPlayer(contentsOf: url)
        newPlayer.prepareToPlay()
        self.player = newPlayer
        return newPlayer.duration
    }

    /// 指定位置から再生開始
    @MainActor
    func play(from time: TimeInterval) throws {
        guard let player else { throw AudioPlayerError.notLoaded }
        player.currentTime = time
        guard player.play() else { throw AudioPlayerError.playbackFailed }
    }

    /// 一時停止
    @MainActor
    func pause() {
        player?.pause()
    }

    /// 停止（先頭に戻す）
    @MainActor
    func stop() {
        player?.stop()
        player?.currentTime = 0
    }

    /// 指定時間へシーク
    @MainActor
    func seek(to time: TimeInterval) throws {
        guard let player else { throw AudioPlayerError.notLoaded }
        let clampedTime = min(max(time, 0), player.duration)
        player.currentTime = clampedTime
    }

    /// 現在の再生位置を取得
    @MainActor
    func currentTime() -> TimeInterval {
        player?.currentTime ?? 0
    }

    // MARK: - Helpers

    /// 相対パス（"Audio/xxx.m4a"）を Documents ディレクトリ基準で解決する
    private static func resolveFileURL(path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docsDir.appendingPathComponent(path)
    }
}

/// AudioPlayer で発生するエラー
private enum AudioPlayerError: LocalizedError {
    case fileNotFound(String)
    case notLoaded
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "音声ファイルが見つかりません: \(path)"
        case .notLoaded:
            return "音声ファイルが読み込まれていません"
        case .playbackFailed:
            return "音声の再生に失敗しました"
        }
    }
}

extension AudioPlayerClient: DependencyKey {
    public static let liveValue: AudioPlayerClient = {
        let player = LiveAudioPlayer()
        return AudioPlayerClient(
            loadAudio: { path in
                try await player.loadAudio(path: path)
            },
            play: { from in
                try await player.play(from: from)
            },
            pause: {
                await player.pause()
            },
            stop: {
                await player.stop()
            },
            seek: { to in
                try await player.seek(to: to)
            },
            currentTime: {
                await player.currentTime()
            }
        )
    }()
}

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
