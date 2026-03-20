import Foundation

/// 録音中の一時ファイル（チャンク）の保存・結合・復旧を担うプロトコル
/// 設計書01-system-architecture.md セクション6.4 準拠
/// 統合仕様書 Critical #2: AVAssetExportSession方式でのチャンク結合を規定
///
/// Domain層で定義し、InfraStorage層で具象実装を提供する
public protocol TemporaryRecordingStoreProtocol: Sendable {

    /// チャンクの保存（5秒間隔で呼び出される）
    /// - Parameters:
    ///   - recordingID: 録音セッションを識別するUUID
    ///   - chunkIndex: チャンクの連番（0始まり）
    ///   - data: M4Aフォーマットの音声データ
    /// - Returns: 保存されたチャンクファイルのURL
    /// - Throws: `RecordingError.fileSaveFailed` ファイル書き込みに失敗した場合
    func saveChunk(recordingID: UUID, chunkIndex: Int, data: Data) throws -> URL

    /// 録音完了時にチャンクを結合して最終ファイルを生成する
    /// 統合仕様書 Critical #2: AVMutableComposition + AVAssetExportSession を使用
    /// Data.append() による単純バイト連結は禁止
    /// - Parameter recordingID: 録音セッションを識別するUUID
    /// - Returns: 結合された最終音声ファイルのURL
    /// - Throws: `RecordingError.compositionFailed`, `RecordingError.exportFailed`
    func finalizeRecording(recordingID: UUID) async throws -> URL

    /// アプリ再起動時に未完了の録音セッションを検出する
    /// tmp/Recording/ ディレクトリを走査し、チャンクファイルが残存しているUUIDを返す
    /// - Returns: 未完了録音のUUID配列
    func recoverUnfinishedRecordings() -> [UUID]

    /// 指定された録音セッションのチャンクファイルを全削除する
    /// ユーザーが復旧を拒否した場合に使用
    /// - Parameter recordingID: 削除対象の録音セッションUUID
    func discardChunks(recordingID: UUID) throws

    /// 指定された録音セッションのチャンクファイルURLリストを取得する
    /// - Parameter recordingID: 録音セッションを識別するUUID
    /// - Returns: チャンクファイルURL配列（chunkIndex昇順）
    func chunkURLs(for recordingID: UUID) throws -> [URL]
}
