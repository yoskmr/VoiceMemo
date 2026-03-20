import ComposableArchitecture
import XCTest
@testable import FeatureSettings

@MainActor
final class SettingsReducerTests: XCTestCase {

    // MARK: - Test 1: 初期状態の検証

    func test_initialState() {
        let state = SettingsReducer.State()
        XCTAssertFalse(state.showComingSoonAlert)
        XCTAssertEqual(state.comingSoonFeature, "")
        XCTAssertEqual(state.customDictionary.entries.count, 0)
    }

    // MARK: - Test 2: comingSoonTapped でアラート表示

    func test_comingSoonTapped_アラート表示() async {
        let store = TestStore(
            initialState: SettingsReducer.State()
        ) {
            SettingsReducer()
        }

        await store.send(.comingSoonTapped("プライバシー設定")) {
            $0.comingSoonFeature = "プライバシー設定"
            $0.showComingSoonAlert = true
        }
    }

    // MARK: - Test 3: dismissComingSoonAlert でアラート非表示

    func test_dismissComingSoonAlert_アラート非表示() async {
        let store = TestStore(
            initialState: SettingsReducer.State(
                showComingSoonAlert: true,
                comingSoonFeature: "アプリロック"
            )
        ) {
            SettingsReducer()
        }

        await store.send(.dismissComingSoonAlert) {
            $0.showComingSoonAlert = false
            $0.comingSoonFeature = ""
        }
    }

    // MARK: - Test 4: 異なる機能名で comingSoonTapped

    func test_comingSoonTapped_テーマ設定() async {
        let store = TestStore(
            initialState: SettingsReducer.State()
        ) {
            SettingsReducer()
        }

        await store.send(.comingSoonTapped("テーマ設定")) {
            $0.comingSoonFeature = "テーマ設定"
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

        await store.send(.comingSoonTapped("プラン管理")) {
            $0.comingSoonFeature = "プラン管理"
            $0.showComingSoonAlert = true
        }

        await store.send(.dismissComingSoonAlert) {
            $0.showComingSoonAlert = false
            $0.comingSoonFeature = ""
        }

        await store.send(.comingSoonTapped("利用統計")) {
            $0.comingSoonFeature = "利用統計"
            $0.showComingSoonAlert = true
        }
    }
}
