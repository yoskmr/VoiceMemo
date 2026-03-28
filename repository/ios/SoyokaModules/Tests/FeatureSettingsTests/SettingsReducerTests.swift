import ComposableArchitecture
import FeatureSubscription
import XCTest
@testable import FeatureSettings

@MainActor
final class SettingsReducerTests: XCTestCase {

    // MARK: - Test 1: 初期状態の検証

    func test_initialState() {
        let state = SettingsReducer.State()
        XCTAssertFalse(state.showComingSoonAlert)
        XCTAssertNil(state.comingSoonFeature)
        XCTAssertEqual(state.customDictionary.entries.count, 0)
    }

    // MARK: - Test 2: comingSoonTapped でアラート表示

    func test_comingSoonTapped_アラート表示() async {
        let store = TestStore(
            initialState: SettingsReducer.State()
        ) {
            SettingsReducer()
        }

        await store.send(.comingSoonTapped(.privacySettings)) {
            $0.comingSoonFeature = .privacySettings
            $0.showComingSoonAlert = true
        }
    }

    // MARK: - Test 3: dismissComingSoonAlert でアラート非表示

    func test_dismissComingSoonAlert_アラート非表示() async {
        let store = TestStore(
            initialState: SettingsReducer.State(
                showComingSoonAlert: true,
                comingSoonFeature: .appLock
            )
        ) {
            SettingsReducer()
        }

        await store.send(.dismissComingSoonAlert) {
            $0.showComingSoonAlert = false
            $0.comingSoonFeature = nil
        }
    }

    // MARK: - Test 4: 異なる機能名で comingSoonTapped

    func test_comingSoonTapped_テーマ設定() async {
        let store = TestStore(
            initialState: SettingsReducer.State()
        ) {
            SettingsReducer()
        }

        await store.send(.comingSoonTapped(.themeSettings)) {
            $0.comingSoonFeature = .themeSettings
            $0.showComingSoonAlert = true
        }
    }

    // MARK: - Test 5: comingSoonTapped → dismiss → 再度 comingSoonTapped

    func test_comingSoonTapped_dismiss_再度tapped() async {
        let store = TestStore(
            initialState: SettingsReducer.State()
        ) {
            SettingsReducer()
        }

        await store.send(.comingSoonTapped(.privacySettings)) {
            $0.comingSoonFeature = .privacySettings
            $0.showComingSoonAlert = true
        }

        await store.send(.dismissComingSoonAlert) {
            $0.showComingSoonAlert = false
            $0.comingSoonFeature = nil
        }

        await store.send(.comingSoonTapped(.usageStats)) {
            $0.comingSoonFeature = .usageStats
            $0.showComingSoonAlert = true
        }
    }

    // MARK: - Test 6: planManagement タップでサブスクリプション画面を表示

    func test_comingSoonTapped_planManagement_サブスクリプション画面表示() async {
        let store = TestStore(
            initialState: SettingsReducer.State()
        ) {
            SettingsReducer()
        }

        await store.send(.comingSoonTapped(.planManagement)) {
            $0.subscription = SubscriptionReducer.State()
        }
    }
}
