import Foundation

// MARK: - DataProtectionValidationResult

/// Data Protection検証の結果
public struct DataProtectionValidationResult: Sendable, Equatable {
    /// 検証対象のパス（表示用）
    public let path: String
    /// 期待する保護レベル
    public let expected: FileProtectionType
    /// 実際の保護レベル（取得できなかった場合は nil）
    public let actual: FileProtectionType?
    /// 検証が成功したかどうか
    public let isValid: Bool

    public init(
        path: String,
        expected: FileProtectionType,
        actual: FileProtectionType?,
        isValid: Bool
    ) {
        self.path = path
        self.expected = expected
        self.actual = actual
        self.isValid = isValid
    }
}

// MARK: - DataProtectionValidator

/// Data Protection設定の検証ユーティリティ
///
/// ファイルやディレクトリに設定された保護レベルが、
/// 統合仕様書 INT-SPEC-001 セクション8.1 の要件を満たしているかを検証する。
///
/// ## 使用例
/// ```swift
/// let results = DataProtectionValidator.validateAllProtections()
/// for result in results {
///     print("\(result.path): \(result.isValid ? "OK" : "NG")")
/// }
/// ```
public struct DataProtectionValidator: Sendable {

    // MARK: - Single Validation

    /// ファイル/ディレクトリの保護レベルを検証する
    ///
    /// - Parameters:
    ///   - url: 検証対象のファイル/ディレクトリURL
    ///   - expected: 期待する保護レベル
    /// - Returns: 保護レベルが一致すれば `true`
    public static func validateProtection(
        at url: URL,
        expected: FileProtectionType
    ) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path
        ) else {
            return false
        }
        guard let protection = attributes[.protectionKey] as? FileProtectionType else {
            return false
        }
        return protection == expected
    }

    // MARK: - Comprehensive Validation

    /// 全ディレクトリの保護レベルを一括検証する
    ///
    /// 統合仕様書セクション8.1 準拠の検証項目:
    /// - `Documents/Audio/`: `NSFileProtectionComplete`
    /// - `Library/Application Support/SecureStore/`: `NSFileProtectionComplete`
    /// - `tmp/Recording/`: `NSFileProtectionCompleteUntilFirstUserAuthentication`
    /// - `Library/Caches/Models/`: `NSFileProtectionCompleteUntilFirstUserAuthentication`
    ///
    /// - Returns: 各ディレクトリの検証結果の配列
    public static func validateAllProtections() -> [DataProtectionValidationResult] {
        let validationTargets: [(FileProtectionManager.DirectoryType, FileProtectionType, String)] = [
            (.audio, .complete, "Documents/Audio/"),
            (.secureStore, .complete, "Library/Application Support/SecureStore/"),
            (.temporaryRecording, .completeUntilFirstUserAuthentication, "tmp/Recording/"),
            (.modelCache, .completeUntilFirstUserAuthentication, "Library/Caches/Models/"),
        ]

        return validationTargets.map { directoryType, expectedProtection, displayPath in
            let url = FileProtectionManager.directoryURL(for: directoryType)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let actualProtection = attributes?[.protectionKey] as? FileProtectionType

            return DataProtectionValidationResult(
                path: displayPath,
                expected: expectedProtection,
                actual: actualProtection,
                isValid: actualProtection == expectedProtection
            )
        }
    }

    // MARK: - iCloud Backup Exclusion Validation

    /// iCloudバックアップ除外設定を検証する
    ///
    /// 統合仕様書セクション8.2 準拠の検証。
    ///
    /// - Parameter url: 検証対象のURL
    /// - Returns: バックアップから除外されていれば `true`
    public static func isExcludedFromBackup(url: URL) -> Bool {
        guard let resourceValues = try? url.resourceValues(
            forKeys: [.isExcludedFromBackupKey]
        ) else {
            return false
        }
        return resourceValues.isExcludedFromBackup ?? false
    }
}
