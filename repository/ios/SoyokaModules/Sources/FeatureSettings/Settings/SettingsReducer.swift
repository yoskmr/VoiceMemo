import ComposableArchitecture
import Domain
import FeatureSubscription
import Foundation

/// 設定画面のTCA Reducer
/// 設計書 04-ui-design-system.md セクション5.2 準拠
/// Phase 1: カスタム辞書のみ実機能、他は「準備中」インライン表示
@Reducer
public struct SettingsReducer {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        /// 感情分析オプトインフラグ
        public var emotionAnalysisEnabled: Bool = false
        /// AI整理の文体
        public var writingStyle: WritingStyle = WritingStyle.current
        /// カスタム辞書のサブ State
        public var customDictionary = CustomDictionaryReducer.State()
        /// バックアップのサブ State
        public var backup = BackupReducer.State()
        /// AI処理回数リセット確認ダイアログ表示フラグ
        public var showResetQuotaConfirmation: Bool = false
        /// 今月のAI処理使用回数
        public var aiQuotaUsed: Int = 0
        /// AI処理月次上限
        public var aiQuotaLimit: Int = 15
        /// サブスクリプション画面の表示状態
        @Presents public var subscription: SubscriptionReducer.State?

        /// UserDefaults キー: 感情分析オプトイン
        static let emotionAnalysisKey = "emotionAnalysisEnabled"

        public init(
            emotionAnalysisEnabled: Bool? = nil,
            writingStyle: WritingStyle? = nil,
            customDictionary: CustomDictionaryReducer.State = .init(),
            backup: BackupReducer.State = .init(),
            showResetQuotaConfirmation: Bool = false,
            aiQuotaUsed: Int = 0,
            aiQuotaLimit: Int = 15,
            subscription: SubscriptionReducer.State? = nil
        ) {
            // UserDefaults から読み込み（明示的な値が渡された場合はそちらを優先）
            self.emotionAnalysisEnabled = emotionAnalysisEnabled
                ?? UserDefaults.standard.bool(forKey: Self.emotionAnalysisKey)
            self.writingStyle = writingStyle ?? WritingStyle.current
            self.customDictionary = customDictionary
            self.backup = backup
            self.showResetQuotaConfirmation = showResetQuotaConfirmation
            self.aiQuotaUsed = aiQuotaUsed
            self.aiQuotaLimit = aiQuotaLimit
            self.subscription = subscription
        }
    }

    // MARK: - Action

    public enum Action: Equatable, Sendable {
        /// プラン管理がタップされた
        case planManagementTapped
        /// 感情分析オプトインのトグル
        case emotionAnalysisToggled(Bool)
        /// AI整理の文体が変更された
        case writingStyleChanged(WritingStyle)
        /// AI整理の文体変更確定（Pro検証後）
        case writingStyleConfirmed(WritingStyle)
        /// カスタム辞書のサブ Action
        case customDictionary(CustomDictionaryReducer.Action)
        /// バックアップのサブ Action
        case backup(BackupReducer.Action)
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
        /// サブスクリプション画面のアクション
        case subscription(PresentationAction<SubscriptionReducer.Action>)
    }

    // MARK: - Reducer Body

    @Dependency(\.aiQuota) var aiQuota
    @Dependency(\.subscriptionClient) var subscriptionClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.customDictionary, action: \.customDictionary) {
            CustomDictionaryReducer()
        }
        Scope(state: \.backup, action: \.backup) {
            BackupReducer()
        }
        Reduce { state, action in
            switch action {
            case .planManagementTapped:
                state.subscription = SubscriptionReducer.State()
                return .none

            case let .emotionAnalysisToggled(isEnabled):
                state.emotionAnalysisEnabled = isEnabled
                // UserDefaults に永続化（アプリ再起動後も設定が保持される）
                UserDefaults.standard.set(isEnabled, forKey: State.emotionAnalysisKey)
                return .none

            case let .writingStyleChanged(style):
                // Pro限定チェック
                if style.requiresPro {
                    return .run { send in
                        let subState = await subscriptionClient.currentSubscription()
                        if case .pro = subState {
                            await send(.writingStyleConfirmed(style))
                        } else {
                            // Pro でない場合はプラン管理画面を表示
                            await send(.planManagementTapped)
                        }
                    }
                }
                state.writingStyle = style
                WritingStyle.setCurrent(style)
                return .none

            case let .writingStyleConfirmed(style):
                state.writingStyle = style
                WritingStyle.setCurrent(style)
                return .none

            case .customDictionary:
                return .none

            case .backup:
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

            case .subscription:
                return .none
            }
        }
        .ifLet(\.$subscription, action: \.subscription) {
            SubscriptionReducer()
        }
    }
}
