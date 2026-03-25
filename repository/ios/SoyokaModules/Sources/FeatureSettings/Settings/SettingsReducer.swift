import ComposableArchitecture
import Domain
import Foundation

/// 設定画面のTCA Reducer
/// 設計書 04-ui-design-system.md セクション5.2 準拠
/// Phase 1: カスタム辞書のみ実機能、他は「準備中」表示
@Reducer
public struct SettingsReducer {

    /// 「準備中」機能の型安全な列挙（#39: String → enum化）
    public enum ComingSoonFeature: String, Equatable, Sendable {
        case privacySettings = "プライバシー設定"
        case appLock = "アプリロック"
        case planManagement = "プラン管理"
        case themeSettings = "テーマ設定"
        case usageStats = "利用統計"

        public var displayName: String { rawValue }
    }

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        /// 「準備中」アラート表示フラグ
        public var showComingSoonAlert: Bool = false
        /// 「準備中」アラートに表示する機能名
        public var comingSoonFeature: ComingSoonFeature?
        /// 感情分析オプトインフラグ
        public var emotionAnalysisEnabled: Bool = false
        /// カスタム辞書のサブ State
        public var customDictionary = CustomDictionaryReducer.State()
        /// AI処理回数リセット確認ダイアログ表示フラグ
        public var showResetQuotaConfirmation: Bool = false
        /// 今月のAI処理使用回数
        public var aiQuotaUsed: Int = 0
        /// AI処理月次上限
        public var aiQuotaLimit: Int = 15

        /// UserDefaults キー: 感情分析オプトイン
        static let emotionAnalysisKey = "emotionAnalysisEnabled"

        public init(
            showComingSoonAlert: Bool = false,
            comingSoonFeature: ComingSoonFeature? = nil,
            emotionAnalysisEnabled: Bool? = nil,
            customDictionary: CustomDictionaryReducer.State = .init(),
            showResetQuotaConfirmation: Bool = false,
            aiQuotaUsed: Int = 0,
            aiQuotaLimit: Int = 15
        ) {
            self.showComingSoonAlert = showComingSoonAlert
            self.comingSoonFeature = comingSoonFeature
            // UserDefaults から読み込み（明示的な値が渡された場合はそちらを優先）
            self.emotionAnalysisEnabled = emotionAnalysisEnabled
                ?? UserDefaults.standard.bool(forKey: Self.emotionAnalysisKey)
            self.customDictionary = customDictionary
            self.showResetQuotaConfirmation = showResetQuotaConfirmation
            self.aiQuotaUsed = aiQuotaUsed
            self.aiQuotaLimit = aiQuotaLimit
        }
    }

    // MARK: - Action

    public enum Action: Equatable, Sendable {
        /// 準備中の機能がタップされた（型安全enum版 #39）
        case comingSoonTapped(ComingSoonFeature)
        /// 「準備中」アラートを閉じる
        case dismissComingSoonAlert
        /// 感情分析オプトインのトグル
        case emotionAnalysisToggled(Bool)
        /// カスタム辞書のサブ Action
        case customDictionary(CustomDictionaryReducer.Action)
        /// 画面表示時
        case onAppear
        /// AI処理回数の取得結果
        case aiQuotaLoaded(used: Int, limit: Int)
        /// AI処理回数リセットボタンタップ
        case resetQuotaTapped
        /// リセット確認ダイアログで「リセット」を選択
        case resetQuotaConfirmed
        /// リセット確認ダイアログで「キャンセル」
        case resetQuotaDismissed
        /// リセット完了
        case resetQuotaCompleted
    }

    // MARK: - Reducer Body

    @Dependency(\.aiQuota) var aiQuota

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.customDictionary, action: \.customDictionary) {
            CustomDictionaryReducer()
        }
        Reduce { state, action in
            switch action {
            case let .comingSoonTapped(feature):
                state.comingSoonFeature = feature
                state.showComingSoonAlert = true
                return .none

            case .dismissComingSoonAlert:
                state.showComingSoonAlert = false
                state.comingSoonFeature = nil
                return .none

            case let .emotionAnalysisToggled(isEnabled):
                state.emotionAnalysisEnabled = isEnabled
                // UserDefaults に永続化（アプリ再起動後も設定が保持される）
                UserDefaults.standard.set(isEnabled, forKey: State.emotionAnalysisKey)
                return .none

            case .customDictionary:
                return .none

            case .onAppear:
                return .run { [aiQuota] send in
                    let used = try await aiQuota.currentUsage()
                    let limit = aiQuota.monthlyLimit()
                    await send(.aiQuotaLoaded(used: used, limit: limit))
                }

            case let .aiQuotaLoaded(used, limit):
                state.aiQuotaUsed = used
                state.aiQuotaLimit = limit
                return .none

            case .resetQuotaTapped:
                state.showResetQuotaConfirmation = true
                return .none

            case .resetQuotaConfirmed:
                state.showResetQuotaConfirmation = false
                return .run { [aiQuota] send in
                    try await aiQuota.resetUsage()
                    await send(.resetQuotaCompleted)
                }

            case .resetQuotaDismissed:
                state.showResetQuotaConfirmation = false
                return .none

            case .resetQuotaCompleted:
                state.aiQuotaUsed = 0
                return .none
            }
        }
    }
}
