#if DEBUG
import Foundation

/// デバッグ専用の設定ラッパー
/// 全デバッグ設定を UserDefaults 経由で読み書きする
/// 本番ビルドでは完全に除外される（`#if DEBUG`）
public final class DebugSettings: @unchecked Sendable {
    public static let shared = DebugSettings()

    private let defaults = UserDefaults.standard

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let forceProPlan = "debug_forceProPlan"
        static let forceLLMProvider = "debug_forceLLMProvider"
        static let forceSentimentAnalysis = "debug_forceSentimentAnalysis"
        static let forceSTTEngine = "debug_forceSTTEngine"
        static let backendURL = "debug_backendURL"
        static let forceOffline = "debug_forceOffline"

        static let allKeys: [String] = [
            forceProPlan,
            forceLLMProvider,
            forceSentimentAnalysis,
            forceSTTEngine,
            backendURL,
            forceOffline,
        ]
    }

    // MARK: - サブスクリプション

    /// Pro プランを強制的に有効化する
    public var forceProPlan: Bool {
        get { defaults.bool(forKey: Keys.forceProPlan) }
        set { defaults.set(newValue, forKey: Keys.forceProPlan) }
    }

    // MARK: - AI処理

    /// LLM プロバイダを強制指定（nil = 自動選択）
    public var forceLLMProvider: String? {
        get { defaults.string(forKey: Keys.forceLLMProvider) }
        set { defaults.set(newValue, forKey: Keys.forceLLMProvider) }
    }

    /// 感情分析を強制的に有効化する（Pro でなくても実行）
    public var forceSentimentAnalysis: Bool {
        get { defaults.bool(forKey: Keys.forceSentimentAnalysis) }
        set { defaults.set(newValue, forKey: Keys.forceSentimentAnalysis) }
    }

    // MARK: - STTエンジン

    /// STT エンジンを強制指定（nil = 自動選択）
    public var forceSTTEngine: String? {
        get { defaults.string(forKey: Keys.forceSTTEngine) }
        set { defaults.set(newValue, forKey: Keys.forceSTTEngine) }
    }

    // MARK: - ネットワーク

    /// Backend URL（nil = デフォルト dev 環境）
    public var backendURL: String? {
        get { defaults.string(forKey: Keys.backendURL) }
        set { defaults.set(newValue, forKey: Keys.backendURL) }
    }

    /// オフラインモードを強制する
    public var forceOffline: Bool {
        get { defaults.bool(forKey: Keys.forceOffline) }
        set { defaults.set(newValue, forKey: Keys.forceOffline) }
    }

    // MARK: - リセット

    /// 全デバッグ設定を初期状態に戻す
    public func resetAll() {
        Keys.allKeys.forEach { defaults.removeObject(forKey: $0) }
    }
}
#endif
