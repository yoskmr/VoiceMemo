import Foundation
import os.log
import SwiftData

private let logger = Logger(subsystem: "com.murmurnote", category: "ModelContainer")

/// SwiftData ModelContainer の構成
/// 01-Arch セクション6.3 準拠
/// 統合仕様書セクション8 準拠
public enum ModelContainerConfiguration {

    /// SwiftData ModelContainer を生成する
    /// - Parameter inMemory: テスト用にインメモリストアを使用する場合 true
    /// - Returns: 構成済みの ModelContainer
    public static func create(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            VoiceMemoModel.self,
            TranscriptionModel.self,
            AISummaryModel.self,
            TagModel.self,
            EmotionAnalysisModel.self,
            UserSettingsModel.self,
            AIQuotaRecordModel.self,
        ])

        let configuration = ModelConfiguration(
            "VoiceMemoStore",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true
        )

        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )

        if !inMemory {
            do {
                try configureDataProtection()
            } catch {
                logger.error("データ保護の設定に失敗: \(error.localizedDescription)")
            }
        }

        return container
    }

    /// データ保護の設定
    /// 統合仕様書セクション8.1, 8.2 準拠
    private static func configureDataProtection() throws {
        try configureSecureStoreDirectory()
        try configureAudioDirectory()
    }

    /// SecureStore ディレクトリの保護設定
    /// - NSFileProtectionComplete を適用
    /// - iCloudバックアップから除外
    private static func configureSecureStoreDirectory() throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let storeDir = appSupport.appendingPathComponent("SecureStore")

        try FileManager.default.createDirectory(
            at: storeDir,
            withIntermediateDirectories: true
        )

        try excludeFromBackup(url: storeDir)
        try setFileProtection(url: storeDir, protection: .complete)
    }

    /// Audio ディレクトリの保護設定
    /// - NSFileProtectionComplete を適用
    /// - iCloudバックアップから除外
    private static func configureAudioDirectory() throws {
        guard let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return }

        let audioDir = documents.appendingPathComponent("Audio")

        try FileManager.default.createDirectory(
            at: audioDir,
            withIntermediateDirectories: true
        )

        try excludeFromBackup(url: audioDir)
        try setFileProtection(url: audioDir, protection: .complete)
    }

    /// iCloudバックアップからの除外設定
    /// - Throws: リソース値の設定に失敗した場合
    static func excludeFromBackup(url: URL) throws {
        var mutableURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try mutableURL.setResourceValues(resourceValues)
    }

    /// ファイル保護レベルの設定
    /// - Throws: ファイル属性の設定に失敗した場合
    static func setFileProtection(url: URL, protection: FileProtectionType) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: protection],
            ofItemAtPath: url.path
        )
    }
}
