import ComposableArchitecture
import FeatureSubscription
import XCTest
@testable import FeatureSettings

@MainActor
final class SettingsReducerTests: XCTestCase {

    // MARK: - Test 1: 初期状態の検証

    func test_initialState() {
        let state = SettingsReducer.State()
        XCTAssertEqual(state.customDictionary.entries.count, 0)
    }

    // MARK: - Test 2: planManagementTapped でサブスクリプション画面を表示

    func test_planManagementTapped_サブスクリプション画面表示() async {
        let store = TestStore(
            initialState: SettingsReducer.State()
        ) {
            SettingsReducer()
        }

        await store.send(.planManagementTapped) {
            $0.subscription = SubscriptionReducer.State()
        }
    }
}
