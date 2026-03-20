import Foundation

// MARK: - FileProtectionLevel

/// ファイル保護レベルの種別
///
/// 統合仕様書 INT-SPEC-001 セクション8.1 準拠。
/// データのライフサイクルに応じて保護レベルを分離する。
public enum FileProtectionLevel: Sendable {
    /// 録音中一時ファイル用: バックグラウンド録音（EC-003）対応
    /// 端末ロック中も書き込み継続が必要
    case recording

    /// 確定済みデータ用: 録音完了後は閲覧のみ
    /// 端末ロック時のアクセス不要。最高保護
    case finalized

    /// MLモデルファイル用: バックグラウンドでのモデル事前ロードに対応
    case model

    /// 対応する `FileProtectionType`
    public var fileProtectionType: FileProtectionType {
        switch self {
        case .recording, .model:
            return .completeUntilFirstUserAuthentication
        case .finalized:
            return .complete
        }
    }

    /// 対応する `FileAttributeKey` 用の値
    var fileAttributeValue: FileProtectionType {
        fileProtectionType
    }
}

// MARK: - FileProtectionManager

/// ファイル/ディレクトリのData Protection設定を管理するユーティリティ
///
/// 統合仕様書 INT-SPEC-001 セクション8.1 準拠。
/// - 録音中一時ファイル: `NSFileProtectionCompleteUntilFirstUserAuthentication`
/// - 確定済みデータ: `NSFileProtectionComplete`
///
/// ## 使用例
/// ```swift
/// let audioDir = FileProtectionManager.ensureDirectory(
///     for: .audio,
///     protectionLevel: .finalized
/// )
/// ```
public struct FileProtectionManager: Sendable {

    // MARK: - Known Directory Types

    /// アプリが使用する既知のディレクトリ種別
    public enum DirectoryType: Sendable {
        /// 確定済み音声ファイル（`Documents/Audio/`）
        case audio
        /// セキュアストア（`Library/Application Support/SecureStore/`）
        case secureStore
        /// 録音中一時ファイル（`tmp/Recording/`）
        case temporaryRecording
        /// MLモデルキャッシュ（`Library/Caches/Models/`）
        case modelCache
    }

    // MARK: - File Protection

    /// ファイルまたはディレクトリにData Protection属性を設定する
    ///
    /// - Parameters:
    ///   - url: 対象のファイル/ディレクトリURL
    ///   - level: 適用する保護レベル
    /// - Throws: `FileManager` のエラー
    public static func setProtection(
        at url: URL,
        level: FileProtectionLevel
    ) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: level.fileProtectionType],
            ofItemAtPath: url.path
        )
    }

    /// ディレクトリを作成し、Data Protection属性を設定する
    ///
    /// ディレクトリが既に存在する場合は保護属性のみ設定する。
    ///
    /// - Parameters:
    ///   - directoryType: 既知のディレクトリ種別
    ///   - protectionLevel: 適用する保護レベル
    /// - Returns: 作成/確認されたディレクトリのURL
    /// - Throws: ディレクトリ作成またはファイル属性設定のエラー
    @discardableResult
    public static func ensureDirectory(
        for directoryType: DirectoryType,
        protectionLevel: FileProtectionLevel
    ) throws -> URL {
        let url = directoryURL(for: directoryType)
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: protectionLevel.fileProtectionType]
            )
        } else {
            try setProtection(at: url, level: protectionLevel)
        }

        return url
    }

    // MARK: - iCloud Backup Exclusion

    /// ファイルまたはディレクトリをiCloudバックアップから除外する
    ///
    /// 統合仕様書 INT-SPEC-001 セクション8.2 準拠。
    /// 音声データ・AI処理結果はプライバシーデータのため除外が必要。
    ///
    /// - Parameter url: 除外対象のURL
    /// - Throws: リソース値の設定エラー
    public static func excludeFromBackup(url: URL) throws {
        var targetURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try targetURL.setResourceValues(resourceValues)
    }

    /// 既知のディレクトリに対してiCloudバックアップ除外を設定する
    ///
    /// 統合仕様書セクション8.2 で除外対象として指定されたディレクトリに対して
    /// 一括で `isExcludedFromBackup` を設定する。
    ///
    /// - Throws: リソース値の設定エラー
    public static func configureBackupExclusions() throws {
        let excludedDirectories: [DirectoryType] = [
            .audio,
            .secureStore,
            // .temporaryRecording と .modelCache は iOS標準で除外済み
        ]

        for directoryType in excludedDirectories {
            let url = directoryURL(for: directoryType)
            if FileManager.default.fileExists(atPath: url.path) {
                try excludeFromBackup(url: url)
            }
        }
    }

    // MARK: - Directory URL Resolution

    /// 既知のディレクトリ種別に対応するURLを返す
    ///
    /// - Parameter directoryType: ディレクトリ種別
    /// - Returns: 対応するディレクトリのURL
    public static func directoryURL(for directoryType: DirectoryType) -> URL {
        let fileManager = FileManager.default

        switch directoryType {
        case .audio:
            // Documents/Audio/
            return fileManager
                .urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Audio", isDirectory: true)

        case .secureStore:
            // Library/Application Support/SecureStore/
            return fileManager
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("SecureStore", isDirectory: true)

        case .temporaryRecording:
            // tmp/Recording/
            return fileManager
                .temporaryDirectory
                .appendingPathComponent("Recording", isDirectory: true)

        case .modelCache:
            // Library/Caches/Models/
            return fileManager
                .urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Models", isDirectory: true)
        }
    }

    // MARK: - Initial Setup

    /// アプリ起動時にData Protection対象ディレクトリを初期化する
    ///
    /// 各ディレクトリを適切な保護レベルで作成し、
    /// iCloudバックアップ除外を設定する。
    ///
    /// - Throws: ディレクトリ作成または設定エラー
    public static func setupAllDirectories() throws {
        // 確定済み音声: NSFileProtectionComplete
        try ensureDirectory(for: .audio, protectionLevel: .finalized)

        // セキュアストア: NSFileProtectionComplete
        try ensureDirectory(for: .secureStore, protectionLevel: .finalized)

        // 録音中一時ファイル: NSFileProtectionCompleteUntilFirstUserAuthentication
        try ensureDirectory(for: .temporaryRecording, protectionLevel: .recording)

        // MLモデルキャッシュ: NSFileProtectionCompleteUntilFirstUserAuthentication
        try ensureDirectory(for: .modelCache, protectionLevel: .model)

        // iCloudバックアップ除外設定
        try configureBackupExclusions()
    }
}
