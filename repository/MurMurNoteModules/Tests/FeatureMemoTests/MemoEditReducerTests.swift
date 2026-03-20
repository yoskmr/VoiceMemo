import ComposableArchitecture
import XCTest
@testable import Domain
@testable import FeatureMemo

@MainActor
final class MemoEditReducerTests: XCTestCase {

    // MARK: - Test 1: onAppear で初期値が設定される

    func test_onAppear_初期値が設定される() async {
        let memoID = UUID()
        let store = TestStore(
            initialState: MemoEditReducer.State(memoID: memoID)
        ) {
            MemoEditReducer()
        }

        await store.send(.onAppear(title: "元タイトル", transcriptionText: "元テキスト")) {
            $0.title = "元タイトル"
            $0.transcriptionText = "元テキスト"
            $0.originalTitle = "元タイトル"
            $0.originalTranscriptionText = "元テキスト"
        }
    }

    // MARK: - Test 2: titleChanged で変更検出

    func test_titleChanged_変更検出() async {
        let memoID = UUID()
        let clock = TestClock()
        let store = TestStore(
            initialState: MemoEditReducer.State(
                memoID: memoID,
                title: "元タイトル",
                originalTitle: "元タイトル",
                originalTranscriptionText: "元テキスト"
            )
        ) {
            MemoEditReducer()
        } withDependencies: {
            $0.continuousClock = clock
        }

        await store.send(.titleChanged("新タイトル")) {
            $0.title = "新タイトル"
            $0.hasUnsavedChanges = true
        }

        // デバウンスタイマーをキャンセル（テスト終了のため）
        await store.skipInFlightEffects()
    }

    // MARK: - Test 3: transcriptionTextChanged で変更検出

    func test_transcriptionTextChanged_変更検出() async {
        let memoID = UUID()
        let clock = TestClock()
        let store = TestStore(
            initialState: MemoEditReducer.State(
                memoID: memoID,
                title: "元タイトル",
                transcriptionText: "元テキスト",
                originalTitle: "元タイトル",
                originalTranscriptionText: "元テキスト"
            )
        ) {
            MemoEditReducer()
        } withDependencies: {
            $0.continuousClock = clock
        }

        await store.send(.transcriptionTextChanged("編集後テキスト")) {
            $0.transcriptionText = "編集後テキスト"
            $0.hasUnsavedChanges = true
        }

        await store.skipInFlightEffects()
    }

    // MARK: - Test 4: 元に戻すと未変更

    func test_titleChanged_元に戻すと未変更() async {
        let memoID = UUID()
        let clock = TestClock()
        let store = TestStore(
            initialState: MemoEditReducer.State(
                memoID: memoID,
                title: "元タイトル",
                transcriptionText: "元テキスト",
                originalTitle: "元タイトル",
                originalTranscriptionText: "元テキスト"
            )
        ) {
            MemoEditReducer()
        } withDependencies: {
            $0.continuousClock = clock
        }

        await store.send(.titleChanged("新タイトル")) {
            $0.title = "新タイトル"
            $0.hasUnsavedChanges = true
        }

        await store.send(.titleChanged("元タイトル")) {
            $0.title = "元タイトル"
            $0.hasUnsavedChanges = false
        }

        await store.skipInFlightEffects()
    }

    // MARK: - Test 5: 自動保存デバウンス

    func test_autoSave_2秒デバウンス後に保存() async {
        let memoID = UUID()
        let clock = TestClock()

        let store = TestStore(
            initialState: MemoEditReducer.State(
                memoID: memoID,
                title: "元タイトル",
                transcriptionText: "元テキスト",
                originalTitle: "元タイトル",
                originalTranscriptionText: "元テキスト"
            )
        ) {
            MemoEditReducer()
        } withDependencies: {
            $0.continuousClock = clock
            $0.voiceMemoRepository.updateMemoText = { _, _, _ in }
            $0.fts5IndexManager.upsertIndex = { _, _, _, _, _ in }
        }

        await store.send(.transcriptionTextChanged("編集後テキスト")) {
            $0.transcriptionText = "編集後テキスト"
            $0.hasUnsavedChanges = true
        }

        await clock.advance(by: .seconds(2))

        await store.receive(.autoSaveTriggered) {
            $0.isSaving = true
        }

        await store.receive(.saveCompleted(.success)) {
            $0.isSaving = false
            $0.originalTranscriptionText = "編集後テキスト"
            $0.hasUnsavedChanges = false
            $0.saveSuccessMessage = "保存しました"
        }

        // dismissSaveSuccess のタイマーをスキップ
        await store.skipInFlightEffects()
    }

    // MARK: - Test 6: 連続入力でデバウンスリセット

    func test_autoSave_連続入力でデバウンスリセット() async {
        let memoID = UUID()
        let clock = TestClock()

        let store = TestStore(
            initialState: MemoEditReducer.State(
                memoID: memoID,
                title: "元タイトル",
                transcriptionText: "元テキスト",
                originalTitle: "元タイトル",
                originalTranscriptionText: "元テキスト"
            )
        ) {
            MemoEditReducer()
        } withDependencies: {
            $0.continuousClock = clock
            $0.voiceMemoRepository.updateMemoText = { _, _, _ in }
            $0.fts5IndexManager.upsertIndex = { _, _, _, _, _ in }
        }

        // 1回目の入力
        await store.send(.transcriptionTextChanged("テキスト1")) {
            $0.transcriptionText = "テキスト1"
            $0.hasUnsavedChanges = true
        }

        // 1秒後に2回目の入力（デバウンスリセット）
        await clock.advance(by: .seconds(1))

        await store.send(.transcriptionTextChanged("テキスト2")) {
            $0.transcriptionText = "テキスト2"
        }

        // さらに2秒後に自動保存
        await clock.advance(by: .seconds(2))

        await store.receive(.autoSaveTriggered) {
            $0.isSaving = true
        }

        await store.receive(.saveCompleted(.success)) {
            $0.isSaving = false
            $0.originalTranscriptionText = "テキスト2"
            $0.hasUnsavedChanges = false
            $0.saveSuccessMessage = "保存しました"
        }

        await store.skipInFlightEffects()
    }

    // MARK: - Test 7: 保存ボタンで即座に保存

    func test_saveButtonTapped_即座に保存() async {
        let memoID = UUID()
        let store = TestStore(
            initialState: MemoEditReducer.State(
                memoID: memoID,
                title: "新タイトル",
                transcriptionText: "新テキスト",
                originalTitle: "元タイトル",
                originalTranscriptionText: "元テキスト",
                hasUnsavedChanges: true
            )
        ) {
            MemoEditReducer()
        } withDependencies: {
            $0.voiceMemoRepository.updateMemoText = { _, _, _ in }
            $0.fts5IndexManager.upsertIndex = { _, _, _, _, _ in }
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.saveButtonTapped) {
            $0.isSaving = true
        }

        await store.receive(.saveCompleted(.success)) {
            $0.isSaving = false
            $0.originalTitle = "新タイトル"
            $0.originalTranscriptionText = "新テキスト"
            $0.hasUnsavedChanges = false
            $0.saveSuccessMessage = "保存しました"
        }

        await store.receive(.dismissSaveSuccess) {
            $0.saveSuccessMessage = nil
        }
    }

    // MARK: - Test 8: 保存完了でoriginalが更新される

    func test_saveCompleted_originalが更新される() async {
        let memoID = UUID()
        let store = TestStore(
            initialState: MemoEditReducer.State(
                memoID: memoID,
                title: "新タイトル",
                transcriptionText: "新テキスト",
                originalTitle: "元タイトル",
                originalTranscriptionText: "元テキスト",
                isSaving: true,
                hasUnsavedChanges: true
            )
        ) {
            MemoEditReducer()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.saveCompleted(.success)) {
            $0.isSaving = false
            $0.originalTitle = "新タイトル"
            $0.originalTranscriptionText = "新テキスト"
            $0.hasUnsavedChanges = false
            $0.saveSuccessMessage = "保存しました"
        }

        await store.receive(.dismissSaveSuccess) {
            $0.saveSuccessMessage = nil
        }
    }

    // MARK: - Test 9: 保存失敗でエラー表示

    func test_saveCompleted_failure_エラー表示() async {
        let memoID = UUID()
        let store = TestStore(
            initialState: MemoEditReducer.State(
                memoID: memoID,
                title: "新タイトル",
                transcriptionText: "新テキスト",
                originalTitle: "元タイトル",
                originalTranscriptionText: "元テキスト",
                isSaving: true,
                hasUnsavedChanges: true
            )
        ) {
            MemoEditReducer()
        }

        await store.send(.saveCompleted(.failure("保存に失敗しました"))) {
            $0.isSaving = false
            $0.errorMessage = "保存に失敗しました"
        }
    }

    // MARK: - Test 10: 戻るボタン（未保存変更あり）でアラート表示

    func test_backButton_未保存変更ありでアラート表示() async {
        let memoID = UUID()
        let store = TestStore(
            initialState: MemoEditReducer.State(
                memoID: memoID,
                hasUnsavedChanges: true
            )
        ) {
            MemoEditReducer()
        }

        await store.send(.backButtonTapped) {
            $0.showDiscardAlert = true
        }
    }

    // MARK: - Test 11: 戻るボタン（未保存変更なし）でそのまま戻る

    func test_backButton_未保存変更なしでそのまま戻る() async {
        let memoID = UUID()
        let store = TestStore(
            initialState: MemoEditReducer.State(
                memoID: memoID,
                hasUnsavedChanges: false
            )
        ) {
            MemoEditReducer()
        }

        await store.send(.backButtonTapped)
        // showDiscardAlert は false のまま
    }

    // MARK: - Test 12: discardConfirmed で変更破棄

    func test_discardConfirmed_変更破棄() async {
        let memoID = UUID()
        let store = TestStore(
            initialState: MemoEditReducer.State(
                memoID: memoID,
                hasUnsavedChanges: true,
                showDiscardAlert: true
            )
        ) {
            MemoEditReducer()
        }

        await store.send(.discardConfirmed) {
            $0.showDiscardAlert = false
            $0.hasUnsavedChanges = false
        }
    }
}
