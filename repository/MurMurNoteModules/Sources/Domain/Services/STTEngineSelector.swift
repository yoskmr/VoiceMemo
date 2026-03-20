import Foundation

/// STTエンジンの自動選択に必要な環境情報
/// テスタビリティのために `#available` を外部から注入する設計
public struct STTEngineSelectionContext: Sendable, Equatable {
    /// ユーザーが手動設定したSTTエンジン（nil = 自動選択）
    public let userPreference: STTEngineType?
    /// 現在のサブスクリプションプラン
    public let subscriptionPlan: SubscriptionPlan
    /// ネットワーク接続状態
    public let isNetworkAvailable: Bool
    /// デバイスがWhisperKit対応か（A16+ & 6GB+）
    public let isDeviceCapable: Bool
    /// iOS 26以上かどうか（`#available` の結果を外部から注入）
    public let isIOS26OrLater: Bool

    public init(
        userPreference: STTEngineType?,
        subscriptionPlan: SubscriptionPlan,
        isNetworkAvailable: Bool,
        isDeviceCapable: Bool,
        isIOS26OrLater: Bool
    ) {
        self.userPreference = userPreference
        self.subscriptionPlan = subscriptionPlan
        self.isNetworkAvailable = isNetworkAvailable
        self.isDeviceCapable = isDeviceCapable
        self.isIOS26OrLater = isIOS26OrLater
    }
}

/// STTエンジンの自動選択ロジック
/// 統合仕様書セクション7.3: iOS バージョン分岐の統一パターン
/// 01-Arch セクション4.2: STTエンジン切替フロー準拠
///
/// 選択優先度:
/// 1. ユーザー手動設定
/// 2. Pro + ネットワーク接続 -> cloudSTT
/// 3. iOS 26+ -> speechAnalyzer
/// 4. A16+ & 6GB+ -> whisperKit
/// 5. フォールバック -> speechAnalyzer
public struct STTEngineSelector: Sendable {

    public init() {}

    /// 環境情報に基づいて最適なSTTエンジンを選択する
    /// - Parameter context: エンジン選択に必要な環境情報
    /// - Returns: 選択されたSTTエンジン種別
    public func selectEngine(context: STTEngineSelectionContext) -> STTEngineType {
        // 1. ユーザー手動設定がある場合はそれを優先
        if let preference = context.userPreference {
            return preference
        }

        // 2. Proプラン + ネットワーク接続 -> クラウドSTT
        if context.subscriptionPlan == .pro && context.isNetworkAvailable {
            return .cloudSTT
        }

        // 3. iOS 26+ -> SpeechAnalyzer
        if context.isIOS26OrLater {
            return .speechAnalyzer
        }

        // 4. A16+ & 6GB+ -> WhisperKit（高精度オンデバイス）
        if context.isDeviceCapable {
            return .whisperKit
        }

        // 5. フォールバック -> SpeechAnalyzer（Apple Speech Framework）
        return .speechAnalyzer
    }
}
