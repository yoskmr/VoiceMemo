import Foundation
import os.log
import Security

private let logger = Logger(subsystem: "app.soyoka", category: "Keychain")

// MARK: - KeychainItemType

/// Keychain保存項目の種別定義
///
/// 統合仕様書 INT-SPEC-001 セクション8.3 準拠。
/// 全項目で `ThisDeviceOnly` を必須とし、iCloudキーチェーン同期を防止する。
///
/// - Important: `kSecAttrAccessibleAfterFirstUnlock`（`ThisDeviceOnly` なし）は使用禁止。
public enum KeychainItemType: String, Sendable, CaseIterable {
    /// JWT アクセストークン
    case accessToken = "access_token"
    /// JWT リフレッシュトークン
    case refreshToken = "refresh_token"
    /// Apple Sign In ユーザー識別子
    case appleUserID = "apple_user_id"
    /// サブスクリプション検証キャッシュ
    case subscriptionCache = "subscription_cache"
    /// App Attest キーID
    case appAttestKeyID = "app_attest_key_id"

    /// アクセシビリティ属性
    ///
    /// 統合仕様書セクション8.3: 全項目で `ThisDeviceOnly` 必須。
    /// - `appleUserID`: ロック解除時のみアクセス可能（最高セキュリティ）
    /// - その他: 初回ロック解除後はアクセス可能（バックグラウンド処理対応）
    public var accessibility: CFString {
        switch self {
        case .appleUserID:
            return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .accessToken, .refreshToken, .subscriptionCache, .appAttestKeyID:
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
    }
}

// MARK: - KeychainError

/// Keychain操作で発生するエラー
public enum KeychainError: Error, Sendable, Equatable {
    /// 保存に失敗した（OSStatus コード付き）
    case saveFailed(OSStatus)
    /// 削除に失敗した（OSStatus コード付き）
    case deleteFailed(OSStatus)
    /// 保存対象のデータが空
    case emptyData
}

// MARK: - KeychainManager

/// Keychain管理の統一実装
///
/// 統合仕様書 INT-SPEC-001 セクション3.3 + セクション8.3 準拠。
/// 全項目で `ThisDeviceOnly` 属性を適用し、iCloudキーチェーン同期を防止する。
///
/// ## 使用例
/// ```swift
/// let manager = KeychainManager()
/// let tokenData = "eyJhbGciOi...".data(using: .utf8)!
/// try manager.save(key: .accessToken, data: tokenData)
/// let loaded = manager.load(key: .accessToken)
/// ```
public struct KeychainManager: Sendable {

    /// Keychainサービス識別子
    private let service: String

    /// イニシャライザ
    /// - Parameter service: Keychainサービス識別子（テスト時に差し替え可能）
    public init(service: String = "com.voicememo.api") {
        self.service = service
    }

    // MARK: - CRUD Operations

    /// データをKeychainに保存する（既存データがあればupsert）
    ///
    /// - Parameters:
    ///   - key: 保存するキーの種別
    ///   - data: 保存するバイナリデータ
    /// - Throws: `KeychainError.emptyData` データが空の場合
    /// - Throws: `KeychainError.saveFailed` SecItemAddが失敗した場合
    public func save(key: KeychainItemType, data: Data) throws {
        guard !data.isEmpty else {
            throw KeychainError.emptyData
        }

        // 既存アイテムを先に削除（upsert相当）
        // errSecItemNotFound は無視し、それ以外の削除エラーは throw する
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            throw KeychainError.deleteFailed(deleteStatus)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: key.accessibility,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Keychainからデータを読み込む
    ///
    /// - Parameter key: 読み込むキーの種別
    /// - Returns: 保存されているデータ。存在しない場合は `nil`
    public func load(key: KeychainItemType) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Keychainからデータを削除する
    ///
    /// - Parameter key: 削除するキーの種別
    @discardableResult
    public func delete(key: KeychainItemType) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// 全Keychainデータを削除する（サインアウト時に使用）
    public func deleteAll() {
        for key in KeychainItemType.allCases {
            let success = delete(key: key)
            if !success {
                logger.error("Keychainデータ削除失敗: key=\(key.rawValue)")
            }
        }
    }

    // MARK: - Convenience Methods

    /// 文字列をKeychainに保存する
    ///
    /// - Parameters:
    ///   - key: 保存するキーの種別
    ///   - string: 保存する文字列
    /// - Throws: `KeychainError` 保存に失敗した場合
    public func save(key: KeychainItemType, string: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.emptyData
        }
        try save(key: key, data: data)
    }

    /// Keychainから文字列を読み込む
    ///
    /// - Parameter key: 読み込むキーの種別
    /// - Returns: 保存されている文字列。存在しない場合は `nil`
    public func loadString(key: KeychainItemType) -> String? {
        guard let data = load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
