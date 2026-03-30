import AVFoundation
import Domain
import Foundation

/// 録音中の一時ファイル（チャンク）の保存・結合・復旧を担う実装
/// 設計書01-system-architecture.md セクション6.4 準拠
/// 統合仕様書 Critical #2: AVMutableComposition + AVAssetExportSession方式
///
/// - 5秒間隔でM4Aチャンクを `tmp/Recording/{UUID}_chunk_{N}.m4a` に保存
/// - AVMutableCompositionでチャンクを時間軸に沿って結合（Data.append禁止）
/// - アプリ再起動時に未完了録音を検出して復旧
public struct TemporaryRecordingStore: TemporaryRecordingStoreProtocol, Sendable {

    // MARK: - Properties

    private let tempDirectory: URL

    // MARK: - Initialization

    /// デフォルト初期化: tmp/Recording/ を使用
    public init() {
        let tmp = FileManager.default.temporaryDirectory
        let dir = tmp.appendingPathComponent("Recording", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.tempDirectory = dir
    }

    /// テスト用: 任意のディレクトリを指定
    public init(tempDirectory: URL) {
        self.tempDirectory = tempDirectory
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Private Helpers

    /// チャンクファイル名を生成する
    private func chunkFileName(recordingID: UUID, chunkIndex: Int) -> String {
        "\(recordingID.uuidString)_chunk_\(chunkIndex).m4a"
    }

    /// チャンクファイル名プレフィックスを生成する
    private func chunkPrefix(for recordingID: UUID) -> String {
        "\(recordingID.uuidString)_chunk_"
    }

    /// 最終出力ファイル名を生成する
    private func finalFileName(recordingID: UUID) -> String {
        "\(recordingID.uuidString)_final.m4a"
    }

    // MARK: - TemporaryRecordingStoreProtocol

    public func saveChunk(recordingID: UUID, chunkIndex: Int, data: Data) throws -> URL {
        let fileName = chunkFileName(recordingID: recordingID, chunkIndex: chunkIndex)
        let fileURL = tempDirectory.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    public func finalizeRecording(recordingID: UUID) async throws -> URL {
        let chunkURLs = try self.chunkURLs(for: recordingID)

        guard !chunkURLs.isEmpty else {
            throw RecordingError.noChunksFound
        }

        // AVMutableComposition で複数チャンクを正しく結合
        // 統合仕様書 Critical #2: Data.append() による単純バイト連結は禁止
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RecordingError.compositionFailed
        }

        var currentTime = CMTime.zero
        for chunkURL in chunkURLs {
            let asset = AVURLAsset(url: chunkURL)
            let duration = try await asset.load(.duration)
            guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                // 不完全なチャンク（途中で切れたファイル）はスキップ
                continue
            }
            try track.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: audioTrack,
                at: currentTime
            )
            currentTime = CMTimeAdd(currentTime, duration)
        }

        // AVAssetExportSession で正しいM4Aファイルを出力
        let outputURL = tempDirectory.appendingPathComponent(finalFileName(recordingID: recordingID))

        // 既存の出力ファイルがあれば削除
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw RecordingError.exportFailed
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        guard exportSession.status == .completed else {
            throw RecordingError.exportFailed
        }

        // 結合完了後にチャンクファイルを自動削除
        for chunkURL in chunkURLs {
            try? FileManager.default.removeItem(at: chunkURL)
        }

        return outputURL
    }

    public func recoverUnfinishedRecordings() -> [UUID] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tempDirectory, includingPropertiesForKeys: nil
        ) else { return [] }

        // _chunk_ パターンのファイルのみを対象にUUIDを抽出
        let recordingIDs = Set(contents.compactMap { url -> UUID? in
            let name = url.lastPathComponent
            guard name.contains("_chunk_") else { return nil }
            let uuidString = String(name.prefix(36))
            return UUID(uuidString: uuidString)
        })

        return Array(recordingIDs)
    }

    public func discardChunks(recordingID: UUID) throws {
        let urls = try chunkURLs(for: recordingID)
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }

        // _final.m4a も存在すれば削除
        let finalURL = tempDirectory.appendingPathComponent(finalFileName(recordingID: recordingID))
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try? FileManager.default.removeItem(at: finalURL)
        }
    }

    public func chunkURLs(for recordingID: UUID) throws -> [URL] {
        let prefix = chunkPrefix(for: recordingID)
        let contents = try FileManager.default.contentsOfDirectory(
            at: tempDirectory, includingPropertiesForKeys: nil
        )
        return contents
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
