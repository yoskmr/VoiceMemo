import CryptoKit
import DeviceCheck
import Foundation
import os.log

private let logger = Logger(subsystem: "app.soyoka", category: "AppAttest")

// MARK: - AppAttestError

/// App Attest 操作で発生するエラー
public enum AppAttestError: Error, Sendable {
    /// Keychain に App Attest キーが見つからない
    case keyNotFound
    /// Attestation（キー検証）に失敗した
    case attestationFailed(String)
    /// Assertion（リクエスト署名）に失敗した
    case assertionFailed(String)
    /// デバイスが App Attest に非対応
    case notSupported
}

// MARK: - AppAttestManager

/// App Attest によるデバイス認証管理
///
/// 設計書 05-security.md 準拠。
/// DCAppAttestService を使用してデバイスの正当性を検証し、
/// リクエスト署名（Assertion）を生成する。
///
/// ## 使用例
/// ```swift
/// let manager = AppAttestManager(keychainManager: KeychainManager())
/// let keyID = try await manager.generateKeyIfNeeded()
/// let assertion = try await manager.generateAssertion(challenge: challengeData)
/// ```
///
/// - Important: iOS 14+ / 実デバイスのみ対応。シミュレータでは `isSupported` が `false` を返す。
public final class AppAttestManager: @unchecked Sendable {

    private let keychainManager: KeychainManager

    /// イニシャライザ
    /// - Parameter keychainManager: Keychain管理（App Attest キーID の保存・取得）
    public init(keychainManager: KeychainManager) {
        self.keychainManager = keychainManager
    }

    // MARK: - Support Check

    /// App Attest がサポートされているか
    ///
    /// シミュレータ・古いデバイスでは `false` を返す。
    /// MVP では非対応端末もサポートするため、呼び出し側で `false` の場合はスキップ可能。
    public var isSupported: Bool {
        DCAppAttestService.shared.isSupported
    }

    // MARK: - Key Management

    /// Attest キーを生成（初回のみ）
    ///
    /// Keychain に既存のキーIDがあればそれを返し、なければ新規生成して Keychain に保存する。
    ///
    /// - Returns: App Attest キーID
    /// - Throws: `AppAttestError.notSupported` デバイスが非対応の場合
    /// - Throws: `KeychainError` Keychain 保存に失敗した場合
    public func generateKeyIfNeeded() async throws -> String {
        // Keychain に既存キーがあればそれを返す
        if let existingKeyID = keychainManager.loadString(key: .appAttestKeyID) {
            logger.debug("既存の App Attest キーを使用: keyID=\(existingKeyID.prefix(8))...")
            return existingKeyID
        }

        guard isSupported else {
            throw AppAttestError.notSupported
        }

        // 新しいキーを生成
        let keyID = try await DCAppAttestService.shared.generateKey()

        // Keychain に保存
        try keychainManager.save(key: .appAttestKeyID, string: keyID)

        logger.info("新しい App Attest キーを生成: keyID=\(keyID.prefix(8))...")
        return keyID
    }

    // MARK: - Attestation

    /// Attest キーを検証（初回認証時）
    ///
    /// サーバーから受け取ったチャレンジを使用して、キーの正当性を Apple に証明する。
    /// 返却される Attestation オブジェクトをサーバーに送信して検証を完了する。
    ///
    /// - Parameter challenge: サーバーから受け取ったチャレンジデータ
    /// - Returns: Attestation オブジェクト（サーバーに送信する）
    /// - Throws: `AppAttestError.keyNotFound` キーが未生成の場合
    /// - Throws: `AppAttestError.attestationFailed` Attestation に失敗した場合
    public func attestKey(challenge: Data) async throws -> Data {
        guard let keyID = keychainManager.loadString(key: .appAttestKeyID) else {
            throw AppAttestError.keyNotFound
        }

        let hash = SHA256.hash(data: challenge)
        let clientDataHash = Data(hash)

        do {
            let attestation = try await DCAppAttestService.shared.attestKey(
                keyID, clientDataHash: clientDataHash
            )
            logger.info("App Attest キー検証成功")
            return attestation
        } catch {
            logger.error("App Attest キー検証失敗: \(error.localizedDescription)")
            throw AppAttestError.attestationFailed(error.localizedDescription)
        }
    }

    // MARK: - Assertion

    /// チャレンジに対する Assertion を生成
    ///
    /// API リクエストごとにサーバーから受け取ったチャレンジを署名し、
    /// `X-App-Attest-Assertion` ヘッダーとして付加する。
    ///
    /// - Parameter challenge: サーバーから受け取ったチャレンジデータ
    /// - Returns: Assertion データ（Base64エンコードしてヘッダーに付加する）
    /// - Throws: `AppAttestError.keyNotFound` キーが未生成の場合
    /// - Throws: `AppAttestError.assertionFailed` Assertion 生成に失敗した場合
    public func generateAssertion(challenge: Data) async throws -> Data {
        guard let keyID = keychainManager.loadString(key: .appAttestKeyID) else {
            throw AppAttestError.keyNotFound
        }

        // challenge のハッシュを作成
        let hash = SHA256.hash(data: challenge)
        let clientDataHash = Data(hash)

        do {
            let assertion = try await DCAppAttestService.shared.generateAssertion(
                keyID, clientDataHash: clientDataHash
            )
            logger.debug("App Attest Assertion 生成成功")
            return assertion
        } catch {
            logger.error("App Attest Assertion 生成失敗: \(error.localizedDescription)")
            throw AppAttestError.assertionFailed(error.localizedDescription)
        }
    }
}
