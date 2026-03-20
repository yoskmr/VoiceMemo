import ComposableArchitecture
import Foundation

/// 設定画面のTCA Reducer
/// 設計書 04-ui-design-system.md セクション5.2 準拠
/// Phase 1: カスタム辞書のみ実機能、他は「準備中」表示
@Reducer
public struct SettingsReducer {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        /// 「準備中」アラート表示フラグ
        public var showComingSoonAlert: Bool = false
        /// 「準備中」アラートに表示する機能名
        public var comingSoonFeature: String = ""
        /// 感情分析オプトインフラグ
        public var emotionAnalysisEnabled: Bool = false
        /// カスタム辞書のサブ State
        public var customDictionary = CustomDictionaryReducer.State()

        public init(
            showComingSoonAlert: Bool = false,
            comingSoonFeature: String = "",
            emotionAnalysisEnabled: Bool = false,
            customDictionary: CustomDictionaryReducer.State = .init()
        ) {
            self.showComingSoonAlert = showComingSoonAlert
            self.comingSoonFeature = comingSoonFeature
            self.emotionAnalysisEnabled = emotionAnalysisEnabled
            self.customDictionary = customDictionary
        }
    }

    // MARK: - Action

    public enum Action: Equatable, Sendable {
        /// 準備中の機能がタップされた
        case comingSoonTapped(String)
        /// 「準備中」アラートを閉じる
        case dismissComingSoonAlert
        /// 感情分析オプトインのトグル
        case emotionAnalysisToggled(Bool)
        /// カスタム辞書のサブ Action
        case customDictionary(CustomDictionaryReducer.Action)
    }

    // MARK: - Reducer Body

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
                state.comingSoonFeature = ""
                return .none

            case let .emotionAnalysisToggled(isEnabled):
                state.emotionAnalysisEnabled = isEnabled
                // TODO: UserSettingsRepository 実装時に UserDefaults/@AppStorage 相当の永続化を追加する
                // 現在はメモリ上のみで保持され、アプリ再起動時にリセットされる
                return .none

            case .customDictionary:
                return .none
            }
        }
    }
}
