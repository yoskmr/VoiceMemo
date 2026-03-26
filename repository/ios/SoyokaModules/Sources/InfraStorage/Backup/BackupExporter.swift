import Domain
import Foundation
import SwiftData
import ZIPFoundation

/// バックアップエクスポート処理
/// 設計書 2026-03-26-backup-restore-design.md エクスポートフロー準拠
/// SwiftData から全データを読み取り、JSON + 音声ファイルを ZIP 化する
public final class BackupExporter: @unchecked Sendable {

    private let modelContainer: ModelContainer

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Public API

    /// エクスポートを実行し、.soyokabackup ファイルの URL を返す
    /// 返却される URL は FileManager.temporaryDirectory 配下の一時ファイル
    /// 呼び出し側（ShareSheet の onDismiss 等）で削除すること
    @MainActor
    public func export() throws -> URL {
        let payload = try buildPayload()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // metadata.json を書き出し
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(payload)
        let metadataURL = tempDir.appendingPathComponent("metadata.json")
        try jsonData.write(to: metadataURL)

        // audio/ ディレクトリに音声ファイルをコピー
        let audioDir = tempDir.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        for memo in payload.memos {
            guard let audioFileName = memo.audioFileName else { continue }
            let sourceURL = documentsDir.appendingPathComponent("Audio").appendingPathComponent(audioFileName)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                let destURL = audioDir.appendingPathComponent(audioFileName)
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
            }
        }

        // ZIP 化
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let zipFileName = "\(timestamp).soyokabackup"
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(zipFileName)

        // 既存の同名ファイルがあれば削除
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }

        try FileManager.default.zipItem(at: tempDir, to: zipURL)

        // 一時展開ディレクトリを削除
        try? FileManager.default.removeItem(at: tempDir)

        return zipURL
    }

    // MARK: - Internal (テスト用に公開)

    /// SwiftData から BackupPayload を構築する
    @MainActor
    public func buildPayload() throws -> BackupPayload {
        let context = modelContainer.mainContext

        // 全メモ取得
        let memoDescriptor = FetchDescriptor<VoiceMemoModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let memoModels = try context.fetch(memoDescriptor)

        // 全タグ取得
        let tagDescriptor = FetchDescriptor<TagModel>()
        let tagModels = try context.fetch(tagDescriptor)

        // メモ → BackupMemo 変換
        let backupMemos = memoModels.map { model -> BackupMemo in
            // audioFilePath から audioFileName を抽出（"Audio/uuid.m4a" → "uuid.m4a"）
            let audioFileName: String? = {
                let path = model.audioFilePath
                guard !path.isEmpty else { return nil }
                return URL(fileURLWithPath: path).lastPathComponent
            }()

            let transcription: BackupTranscription? = model.transcription.map {
                BackupTranscription(
                    id: $0.id,
                    fullText: $0.fullText,
                    language: $0.language,
                    engineType: $0.engineType.rawValue,
                    confidence: $0.confidence,
                    processedAt: $0.processedAt
                )
            }

            let aiSummary: BackupAISummary? = model.aiSummary.map {
                BackupAISummary(
                    id: $0.id,
                    title: $0.title,
                    summaryText: $0.summaryText,
                    keyPoints: $0.keyPoints.isEmpty ? nil : $0.keyPoints,
                    providerType: $0.providerType.rawValue,
                    isOnDevice: $0.isOnDevice,
                    generatedAt: $0.generatedAt
                )
            }

            let emotionAnalysis: BackupEmotionAnalysis? = model.emotionAnalysis.map {
                let evidence: [BackupSentimentEvidence]? = $0.evidence.isEmpty ? nil : $0.evidence.compactMap { dict in
                    guard let text = dict["text"], let emotion = dict["emotion"] else { return nil }
                    return BackupSentimentEvidence(text: text, emotion: emotion)
                }
                return BackupEmotionAnalysis(
                    id: $0.id,
                    primaryEmotion: $0.primaryEmotion.rawValue,
                    confidence: $0.confidence,
                    emotionScores: $0.emotionScores,
                    evidence: evidence,
                    analyzedAt: $0.analyzedAt
                )
            }

            return BackupMemo(
                id: model.id,
                title: model.title,
                createdAt: model.createdAt,
                updatedAt: model.updatedAt,
                durationSeconds: model.durationSeconds,
                audioFileName: audioFileName,
                audioFormat: model.audioFormat.rawValue,
                status: model.status.rawValue,
                isFavorite: model.isFavorite,
                transcription: transcription,
                aiSummary: aiSummary,
                emotionAnalysis: emotionAnalysis,
                tagNames: model.tags.map(\.name)
            )
        }

        // タグ → BackupTag 変換
        let backupTags = tagModels.map { model -> BackupTag in
            BackupTag(
                id: model.id,
                name: model.name,
                colorHex: model.colorHex,
                source: model.source.rawValue,
                createdAt: model.createdAt
            )
        }

        return BackupPayload(
            memos: backupMemos,
            tags: backupTags
        )
    }
}
