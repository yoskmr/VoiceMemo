import ComposableArchitecture
import Domain
import XCTest

@testable import FeatureMemo

/// TASK-0044: 高精度仕上げのテスト
/// REQ-018 / US-305 / AC-305 準拠
@MainActor
final class MemoDetailPolishTests: XCTestCase {

    // MARK: - Test Helpers

    private let testMemoID = UUID()

    // MARK: - Test 1: Pro ユーザーが仕上げボタンを押すと仕上げが実行される

    func test_polishButtonTapped_Pro_仕上げが実行される() async {
        var polishedText: String?
        var receivedDict: [(reading: String, display: String)]?

        let store = TestStore(
            initialState: MemoDetailReducer.State(
                memoID: testMemoID,
                transcriptionText: "えっと、きょうはあの会議がありました",
                isPro: true
            )
        ) {
            MemoDetailReducer()
        } withDependencies: {
            $0.customDictionaryClient.getDictionaryPairs = {
                [("かいぎ", "会議")]
            }
            $0.textPolish.polish = { text, dict in
                polishedText = text
                receivedDict = dict
                return PolishResult(
                    polishedText: "今日は会議がありました。",
                    processingTimeMs: 450,
                    model: "gpt-4o-mini"
                )
            }
        }

        await store.send(.polishButtonTapped) {
            $0.isPolishing = true
            $0.polishError = nil
        }

        await store.receive(\.polishCompleted.success) {
            $0.isPolishing = false
            $0.polishOriginalText = "えっと、きょうはあの会議がありました"
            $0.transcriptionText = "今日は会議がありました。"
            $0.isPolished = true
        }

        XCTAssertEqual(polishedText, "えっと、きょうはあの会議がありました")
        XCTAssertEqual(receivedDict?.count, 1)
        XCTAssertEqual(receivedDict?.first?.reading, "かいぎ")
        XCTAssertEqual(receivedDict?.first?.display, "会議")
    }

    // MARK: - Test 2: Free ユーザーは ProPlan 案内が表示される

    func test_polishButtonTapped_Free_ProPlan案内() async {
        let store = TestStore(
            initialState: MemoDetailReducer.State(
                memoID: testMemoID,
                transcriptionText: "テスト文字起こし",
                isPro: false
            )
        ) {
            MemoDetailReducer()
        }

        await store.send(.polishButtonTapped)
        await store.receive(\.showProPlanTapped)
    }

    // MARK: - Test 3: 仕上げ成功時にテキスト更新とバッジ表示

    func test_polishCompleted_success_テキスト更新とバッジ表示() async {
        let store = TestStore(
            initialState: MemoDetailReducer.State(
                memoID: testMemoID,
                transcriptionText: "元のテキスト",
                isPolishing: true,
                isPro: true
            )
        ) {
            MemoDetailReducer()
        }

        let result = PolishResult(
            polishedText: "仕上げ後のテキスト",
            processingTimeMs: 300,
            model: "gpt-4o-mini"
        )

        await store.send(.polishCompleted(.success(result))) {
            $0.isPolishing = false
            $0.polishOriginalText = "元のテキスト"
            $0.transcriptionText = "仕上げ後のテキスト"
            $0.isPolished = true
        }
    }

    // MARK: - Test 4: 仕上げ失敗時にエラーメッセージ表示

    func test_polishCompleted_failure_エラーメッセージ表示() async {
        let store = TestStore(
            initialState: MemoDetailReducer.State(
                memoID: testMemoID,
                transcriptionText: "テスト",
                isPolishing: true,
                isPro: true
            )
        ) {
            MemoDetailReducer()
        }

        let error = EquatableError(NSError(domain: "test", code: -1))
        await store.send(.polishCompleted(.failure(error))) {
            $0.isPolishing = false
            $0.polishError = "仕上げに失敗しました。もう一度お試しください。"
        }
    }

    // MARK: - Test 5: 元のテキスト表示切替

    func test_toggleOriginalText_切替() async {
        let store = TestStore(
            initialState: MemoDetailReducer.State(
                memoID: testMemoID,
                isPolished: true,
                polishOriginalText: "元のテキスト",
                showOriginalText: false,
                isPro: true
            )
        ) {
            MemoDetailReducer()
        }

        await store.send(.toggleOriginalText) {
            $0.showOriginalText = true
        }

        await store.send(.toggleOriginalText) {
            $0.showOriginalText = false
        }
    }

    // MARK: - Test 6: 処理中は二重送信されない

    func test_polishButtonTapped_処理中は二重送信されない() async {
        let store = TestStore(
            initialState: MemoDetailReducer.State(
                memoID: testMemoID,
                transcriptionText: "テスト",
                isPolishing: true,
                isPro: true
            )
        ) {
            MemoDetailReducer()
        }

        // isPolishing = true の場合、何も起きない
        await store.send(.polishButtonTapped)
    }

    // MARK: - Test 7: エラークリア

    func test_dismissPolishError_エラークリア() async {
        let store = TestStore(
            initialState: MemoDetailReducer.State(
                memoID: testMemoID,
                polishError: "仕上げに失敗しました。もう一度お試しください。"
            )
        ) {
            MemoDetailReducer()
        }

        await store.send(.dismissPolishError) {
            $0.polishError = nil
        }
    }
}
