import Domain
import Foundation
import SwiftData
import ZIPFoundation

/// バックアップインポートエラー
public enum BackupImportError: Error, Equatable, Sendable, LocalizedError {
    case zipExtractionFailed
    case metadataNotFound
    case jsonDecodeFailed(String)
    case unsupportedVersion(Int)
    case diskSpaceInsufficient

    public var errorDescription: String? {
        switch self {
        case .zipExtractionFailed:
            return "ファイルが破損しています"
        case .metadataNotFound:
            return "対応していないバックアップ形式です"
        case .jsonDecodeFailed(let detail):
            return "対応していないバックアップ形式です: \(detail)"
        case .unsupportedVersion(let version):
            return "新しいバージョンのアプリが必要です（バックアップ v\(version)）"
        case .diskSpaceInsufficient:
            return "ストレージの空き容量が不足しています"
        }
    }
}

/// バックアップインポート処理
/// 設計書 2026-03-26-backup-restore-design.md インポートフロー準拠
public final class BackupImporter: @unchecked Sendable {

    private let modelContainer: ModelContainer
    /// FTS5 インデックス更新用（オプショナル: テスト時は nil 可）
    private let fts5Upsert: ((_ memoID: String, _ title: String, _ text: String, _ summary: String, _ tags: String) throws -> Void)?

    public init(
        modelContainer: ModelContainer,
        fts5Upsert: ((_ memoID: String, _ title: String, _ text: String, _ summary: String, _ tags: String) throws -> Void)? = nil
    ) {
        self.modelContainer = modelContainer
        self.fts5Upsert = fts5Upsert
    }

    // MARK: - Public API

    @MainActor
    public func importBackup(fileURL: URL) async throws -> BackupResult {
        // セキュリティスコープのアクセス開始（ファイルピッカー経由の場合に必要）
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { fileURL.stopAccessingSecurityScopedResource() }
        }

        // 一時ディレクトリに展開
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try FileManager.default.unzipItem(at: fileURL, to: tempDir)
        } catch {
            throw BackupImportError.zipExtractionFailed
        }

        // metadata.json を読み取り
        // ZIP 展開時にルートディレクトリが含まれる場合を考慮
        let metadataURL = findMetadataJSON(in: tempDir)
        guard let metadataURL else {
            throw BackupImportError.metadataNotFound
        }

        let payload: BackupPayload
        do {
            let data = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            payload = try decoder.decode(BackupPayload.self, from: data)
        } catch {
            throw BackupImportError.jsonDecodeFailed(error.localizedDescription)
        }

        // バージョンチェック
        if payload.version > BackupPayload.currentSupportedVersion {
            throw BackupImportError.unsupportedVersion(payload.version)
        }

        // タグのインポート + ルックアップテーブル構築
        let tagLookup = try buildTagLookup(from: payload.tags)

        // メモのインポート
        let audioBaseDir = metadataURL.deletingLastPathComponent().appendingPathComponent("audio")
        var importedCount = 0
        var skippedCount = 0
        var audioMissingCount = 0

        let context = modelContainer.mainContext

        for backupMemo in payload.memos {
            // UUID で既存データを検索
            let memoID = backupMemo.id
            let descriptor = FetchDescriptor<VoiceMemoModel>(
                predicate: #Predicate { $0.id == memoID }
            )
            let existing = try context.fetch(descriptor)
            if !existing.isEmpty {
                skippedCount += 1
                continue
            }

            // 音声ファイルのコピー
            var audioMissing = false
            if let audioFileName = backupMemo.audioFileName {
                let sourceAudioURL = audioBaseDir.appendingPathComponent(audioFileName)
                if FileManager.default.fileExists(atPath: sourceAudioURL.path) {
                    let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let destAudioDir = documentsDir.appendingPathComponent("Audio", isDirectory: true)
                    if !FileManager.default.fileExists(atPath: destAudioDir.path) {
                        try FileManager.default.createDirectory(at: destAudioDir, withIntermediateDirectories: true)
                    }
                    let destURL = destAudioDir.appendingPathComponent(audioFileName)
                    if !FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.copyItem(at: sourceAudioURL, to: destURL)
                    }
                } else {
                    audioMissing = true
                }
            }

            if audioMissing {
                audioMissingCount += 1
            }

            // SwiftData にメモを書き込み
            let audioFilePath = backupMemo.audioFileName.map { "Audio/\($0)" } ?? ""
            let memoModel = VoiceMemoModel(
                id: backupMemo.id,
                title: backupMemo.title,
                createdAt: backupMemo.createdAt,
                durationSeconds: backupMemo.durationSeconds,
                audioFilePath: audioFilePath,
                audioFormat: AudioFormat(rawValue: backupMemo.audioFormat) ?? .m4a,
                status: MemoStatus(rawValue: backupMemo.status) ?? .completed,
                isFavorite: backupMemo.isFavorite
            )
            memoModel.updatedAt = backupMemo.updatedAt
            context.insert(memoModel)

            // Transcription
            if let t = backupMemo.transcription {
                let model = TranscriptionModel(
                    id: t.id,
                    fullText: t.fullText,
                    language: t.language,
                    engineType: STTEngineType(rawValue: t.engineType) ?? .whisperKit,
                    confidence: t.confidence,
                    processedAt: t.processedAt
                )
                model.memo = memoModel
                context.insert(model)
            }

            // AISummary
            if let s = backupMemo.aiSummary {
                let model = AISummaryModel(
                    id: s.id,
                    title: s.title,
                    summaryText: s.summaryText,
                    keyPoints: s.keyPoints ?? [],
                    providerType: LLMProviderType(rawValue: s.providerType) ?? .onDeviceLlamaCpp,
                    isOnDevice: s.isOnDevice,
                    generatedAt: s.generatedAt
                )
                model.memo = memoModel
                context.insert(model)
            }

            // EmotionAnalysis
            if let e = backupMemo.emotionAnalysis {
                let evidence: [[String: String]] = (e.evidence ?? []).map { ev in
                    ["text": ev.text, "emotion": ev.emotion]
                }
                let model = EmotionAnalysisModel(
                    id: e.id,
                    primaryEmotion: EmotionCategory(rawValue: e.primaryEmotion) ?? .neutral,
                    confidence: e.confidence,
                    emotionScores: e.emotionScores,
                    evidence: evidence,
                    analyzedAt: e.analyzedAt
                )
                model.memo = memoModel
                context.insert(model)
            }

            // タグのリレーション設定
            for tagName in backupMemo.tagNames {
                if let tagModel = tagLookup[tagName] {
                    memoModel.tags.append(tagModel)
                }
            }

            // FTS5 インデックス更新
            if let fts5Upsert {
                try? fts5Upsert(
                    backupMemo.id.uuidString,
                    backupMemo.title,
                    backupMemo.transcription?.fullText ?? "",
                    backupMemo.aiSummary?.summaryText ?? "",
                    backupMemo.tagNames.joined(separator: " ")
                )
            }

            importedCount += 1
        }

        try context.save()

        return BackupResult(
            importedCount: importedCount,
            skippedCount: skippedCount,
            audioMissingCount: audioMissingCount
        )
    }

    // MARK: - Private

    /// ZIP 展開後のディレクトリから metadata.json を探す
    /// ZIPFoundation が中間ディレクトリを作る場合を考慮して再帰的に検索
    private func findMetadataJSON(in directory: URL) -> URL? {
        let directPath = directory.appendingPathComponent("metadata.json")
        if FileManager.default.fileExists(atPath: directPath.path) {
            return directPath
        }
        // 1階層下を検索（ZIP がルートフォルダを含む場合）
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) {
            for item in contents {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    let nested = item.appendingPathComponent("metadata.json")
                    if FileManager.default.fileExists(atPath: nested.path) {
                        return nested
                    }
                }
            }
        }
        return nil
    }

    /// タグのインポート: 名前ベースのマージ戦略
    /// 同名タグは既存 UUID を採用、新規タグはバックアップの UUID で作成
    @MainActor
    private func buildTagLookup(from backupTags: [BackupTag]) throws -> [String: TagModel] {
        let context = modelContainer.mainContext
        var lookup: [String: TagModel] = [:]

        // 既存タグを全件取得してルックアップテーブルに
        let existingDescriptor = FetchDescriptor<TagModel>()
        let existingTags = try context.fetch(existingDescriptor)
        for tag in existingTags {
            lookup[tag.name] = tag
        }

        // バックアップのタグを処理
        for backupTag in backupTags {
            if lookup[backupTag.name] != nil {
                // 同名タグが既存にある → 既存を採用（バックアップ UUID は破棄）
                continue
            }
            // 新規タグとして作成
            let newTag = TagModel(
                id: backupTag.id,
                name: backupTag.name,
                colorHex: backupTag.colorHex,
                source: TagSource(rawValue: backupTag.source) ?? .ai,
                createdAt: backupTag.createdAt
            )
            context.insert(newTag)
            lookup[backupTag.name] = newTag
        }

        return lookup
    }
}
