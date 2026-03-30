import Foundation

/// バックアップインポート結果
public struct BackupResult: Sendable, Equatable {
    /// インポート成功件数
    public let importedCount: Int
    /// UUID 重複によりスキップされた件数
    public let skippedCount: Int
    /// 音声ファイル欠損でメタデータのみ復元された件数
    public let audioMissingCount: Int
    /// カスタム辞書インポート件数
    public let dictionaryImportedCount: Int

    public init(
        importedCount: Int,
        skippedCount: Int,
        audioMissingCount: Int = 0,
        dictionaryImportedCount: Int = 0
    ) {
        self.importedCount = importedCount
        self.skippedCount = skippedCount
        self.audioMissingCount = audioMissingCount
        self.dictionaryImportedCount = dictionaryImportedCount
    }

    /// 合計処理件数
    public var totalCount: Int {
        importedCount + skippedCount
    }
}
