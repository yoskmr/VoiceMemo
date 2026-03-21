import ComposableArchitecture
import Domain
import XCTest

@testable import FeatureAI

/// T15: AIProcessingReducer の TCA TestStore テスト
/// 正常系・月上限到達・リトライ・キャンセル・オンボーディングの全シナリオ
@MainActor
final class AIProcessingReducerTests: XCTestCase {

    private let testMemoID = UUID()
    private let testResetDate = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Test 1: startProcessing → クォータチェック → enqueue → ステータス完了

    func test_startProcessing_正常フロー_完了まで() async {
        // オンボーディング済みに設定
        UserDefaults.standard.set(true, forKey: "hasSeenAIOnboarding")
        defer { UserDefaults.standard.removeObject(forKey: "hasSeenAIOnboarding") }

        let statusStream = AsyncStream<AIProcessingStatus>.makeStream()

        let store = TestStore(
            initialState: AIProcessingReducer.State(memoID: testMemoID)
        ) {
            AIProcessingReducer()
        } withDependencies: {
            $0.aiQuota.canProcess = { true }
            $0.aiQuota.remainingCount = { 14 }
            $0.aiQuota.currentUsage = { 1 }
            $0.aiQuota.monthlyLimit = { 15 }
            $0.aiQuota.nextResetDate = { self.testResetDate }
            $0.aiProcessingQueue.enqueueProcessing = { _ in }
            $0.aiProcessingQueue.observeStatus = { _ in statusStream.stream }
        }
        store.exhaustivity = .off

        await store.send(.startProcessing)

        // クォータチェック完了
        await store.receive(._quotaCheckCompleted(canProcess: true, remaining: 14, used: 1)) {
            $0.remainingQuota = 14
            $0.quotaUsed = 1
            $0.quotaLimit = 15
        }

        // ステータス更新: processing
        statusStream.continuation.yield(.processing(progress: 0.5, description: "メモを整理中..."))
        await store.receive(.statusUpdated(.processing(progress: 0.5, description: "メモを整理中..."))) {
            $0.processingStatus = .processing(progress: 0.5, description: "メモを整理中...")
        }

        // ステータス更新: completed
        statusStream.continuation.yield(.completed(isOnDevice: true))
        await store.receive(.statusUpdated(.completed(isOnDevice: true))) {
            $0.processingStatus = .completed(isOnDevice: true)
        }

        statusStream.continuation.finish()
    }

    // MARK: - Test 2: quotaExceeded エラーケース

    func test_startProcessing_月次上限到達_quotaExceeded() async {
        UserDefaults.standard.set(true, forKey: "hasSeenAIOnboarding")
        defer { UserDefaults.standard.removeObject(forKey: "hasSeenAIOnboarding") }

        let store = TestStore(
            initialState: AIProcessingReducer.State(memoID: testMemoID)
        ) {
            AIProcessingReducer()
        } withDependencies: {
            $0.aiQuota.canProcess = { false }
            $0.aiQuota.remainingCount = { 0 }
            $0.aiQuota.currentUsage = { 15 }
            $0.aiQuota.monthlyLimit = { 15 }
            $0.aiQuota.nextResetDate = { self.testResetDate }
        }
        store.exhaustivity = .off

        await store.send(.startProcessing)

        await store.receive(._quotaCheckCompleted(canProcess: false, remaining: 0, used: 15)) {
            $0.remainingQuota = 0
            $0.quotaUsed = 15
            $0.quotaLimit = 15
            $0.processingStatus = .failed(.quotaExceeded(remaining: 0, resetDate: self.testResetDate))
        }
    }

    // MARK: - Test 3: retryProcessing

    func test_retryProcessing_ステータスリセットして再実行() async {
        UserDefaults.standard.set(true, forKey: "hasSeenAIOnboarding")
        defer { UserDefaults.standard.removeObject(forKey: "hasSeenAIOnboarding") }

        let statusStream = AsyncStream<AIProcessingStatus>.makeStream()

        let store = TestStore(
            initialState: AIProcessingReducer.State(
                memoID: testMemoID,
                processingStatus: .failed(.processingFailed("前回失敗"))
            )
        ) {
            AIProcessingReducer()
        } withDependencies: {
            $0.aiQuota.canProcess = { true }
            $0.aiQuota.remainingCount = { 14 }
            $0.aiQuota.currentUsage = { 1 }
            $0.aiQuota.monthlyLimit = { 15 }
            $0.aiQuota.nextResetDate = { self.testResetDate }
            $0.aiProcessingQueue.enqueueProcessing = { _ in }
            $0.aiProcessingQueue.observeStatus = { _ in statusStream.stream }
        }
        store.exhaustivity = .off

        await store.send(.retryProcessing) {
            $0.processingStatus = .idle
        }

        // retryProcessing は内部で startProcessing を送信する
        // → クォータチェック → enqueue のフロー
        await store.receive(.startProcessing)
        await store.receive(._quotaCheckCompleted(canProcess: true, remaining: 14, used: 1))

        statusStream.continuation.finish()
    }

    // MARK: - Test 4: cancelProcessing

    func test_cancelProcessing_キャンセル送信() async {
        let cancelledMemoID = LockIsolated<UUID?>(nil)

        let store = TestStore(
            initialState: AIProcessingReducer.State(
                memoID: testMemoID,
                processingStatus: .processing(progress: 0.5, description: "処理中...")
            )
        ) {
            AIProcessingReducer()
        } withDependencies: {
            $0.aiProcessingQueue.cancelProcessing = { id in
                cancelledMemoID.withValue { $0 = id }
            }
        }
        store.exhaustivity = .off

        await store.send(.cancelProcessing)

        // キャンセルが呼ばれたことを確認
        XCTAssertEqual(cancelledMemoID.value, testMemoID)
    }

    // MARK: - Test 5: オンボーディング表示 → dismiss → 処理開始

    func test_startProcessing_初回_オンボーディング表示() async {
        UserDefaults.standard.set(false, forKey: "hasSeenAIOnboarding")
        defer { UserDefaults.standard.removeObject(forKey: "hasSeenAIOnboarding") }

        let store = TestStore(
            initialState: AIProcessingReducer.State(memoID: testMemoID)
        ) {
            AIProcessingReducer()
        }
        store.exhaustivity = .off

        await store.send(.startProcessing) {
            $0.showOnboarding = true
        }
    }

    func test_onboardingDismissed_フラグ保存して処理開始() async {
        UserDefaults.standard.set(false, forKey: "hasSeenAIOnboarding")
        defer { UserDefaults.standard.removeObject(forKey: "hasSeenAIOnboarding") }

        let statusStream = AsyncStream<AIProcessingStatus>.makeStream()

        let store = TestStore(
            initialState: AIProcessingReducer.State(
                memoID: testMemoID,
                showOnboarding: true
            )
        ) {
            AIProcessingReducer()
        } withDependencies: {
            $0.aiQuota.canProcess = { true }
            $0.aiQuota.remainingCount = { 15 }
            $0.aiQuota.currentUsage = { 0 }
            $0.aiQuota.monthlyLimit = { 15 }
            $0.aiQuota.nextResetDate = { self.testResetDate }
            $0.aiProcessingQueue.enqueueProcessing = { _ in }
            $0.aiProcessingQueue.observeStatus = { _ in statusStream.stream }
        }
        store.exhaustivity = .off

        await store.send(.onboardingDismissed) {
            $0.showOnboarding = false
        }

        // onboardingDismissed は内部で startProcessing を送信
        await store.receive(.startProcessing)
        await store.receive(._quotaCheckCompleted(canProcess: true, remaining: 15, used: 0))

        // UserDefaults にフラグが保存されたことを確認
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "hasSeenAIOnboarding"))

        statusStream.continuation.finish()
    }

    // MARK: - Test 6: statusUpdated で completed → クォータ更新

    func test_statusUpdated_completed_クォータ更新エフェクト() async {
        let store = TestStore(
            initialState: AIProcessingReducer.State(
                memoID: testMemoID,
                remainingQuota: 15,
                quotaUsed: 0
            )
        ) {
            AIProcessingReducer()
        } withDependencies: {
            $0.aiQuota.remainingCount = { 14 }
            $0.aiQuota.currentUsage = { 1 }
        }
        store.exhaustivity = .off

        await store.send(.statusUpdated(.completed(isOnDevice: true))) {
            $0.processingStatus = .completed(isOnDevice: true)
        }

        await store.receive(.quotaUpdated(used: 1, remaining: 14)) {
            $0.quotaUsed = 1
            $0.remainingQuota = 14
        }
    }

    // MARK: - Test 7: statusUpdated で failed

    func test_statusUpdated_failed_ステータス更新のみ() async {
        let store = TestStore(
            initialState: AIProcessingReducer.State(memoID: testMemoID)
        ) {
            AIProcessingReducer()
        }

        await store.send(.statusUpdated(.failed(.processingFailed("テストエラー")))) {
            $0.processingStatus = .failed(.processingFailed("テストエラー"))
        }
    }

    // MARK: - Test 8: quotaUpdated

    func test_quotaUpdated_値が正しく更新される() async {
        let store = TestStore(
            initialState: AIProcessingReducer.State(
                memoID: testMemoID,
                remainingQuota: 15,
                quotaUsed: 0
            )
        ) {
            AIProcessingReducer()
        }

        await store.send(.quotaUpdated(used: 5, remaining: 10)) {
            $0.quotaUsed = 5
            $0.remainingQuota = 10
        }
    }

    // MARK: - Test 9: _errorOccurred

    func test_errorOccurred_processingFailedに変換() async {
        let store = TestStore(
            initialState: AIProcessingReducer.State(memoID: testMemoID)
        ) {
            AIProcessingReducer()
        }

        await store.send(._errorOccurred("何かのエラーです")) {
            $0.processingStatus = .failed(.processingFailed("何かのエラーです"))
        }
    }

    // MARK: - Test 10: オンボーディング済みの場合は直接処理開始

    func test_startProcessing_オンボーディング済み_直接クォータチェック() async {
        UserDefaults.standard.set(true, forKey: "hasSeenAIOnboarding")
        defer { UserDefaults.standard.removeObject(forKey: "hasSeenAIOnboarding") }

        let statusStream = AsyncStream<AIProcessingStatus>.makeStream()

        let store = TestStore(
            initialState: AIProcessingReducer.State(memoID: testMemoID)
        ) {
            AIProcessingReducer()
        } withDependencies: {
            $0.aiQuota.canProcess = { true }
            $0.aiQuota.remainingCount = { 15 }
            $0.aiQuota.currentUsage = { 0 }
            $0.aiQuota.monthlyLimit = { 15 }
            $0.aiQuota.nextResetDate = { self.testResetDate }
            $0.aiProcessingQueue.enqueueProcessing = { _ in }
            $0.aiProcessingQueue.observeStatus = { _ in statusStream.stream }
        }
        store.exhaustivity = .off

        await store.send(.startProcessing)

        // オンボーディングは表示されず、直接クォータチェック
        await store.receive(._quotaCheckCompleted(canProcess: true, remaining: 15, used: 0)) {
            $0.remainingQuota = 15
            $0.quotaUsed = 0
            $0.quotaLimit = 15
        }

        statusStream.continuation.finish()
    }

    // MARK: - Test 11: startProcessing クォータチェックでエラー

    func test_startProcessing_クォータチェック例外_errorOccurred() async {
        UserDefaults.standard.set(true, forKey: "hasSeenAIOnboarding")
        defer { UserDefaults.standard.removeObject(forKey: "hasSeenAIOnboarding") }

        let store = TestStore(
            initialState: AIProcessingReducer.State(memoID: testMemoID)
        ) {
            AIProcessingReducer()
        } withDependencies: {
            $0.aiQuota.canProcess = { throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "DB接続エラー"]) }
        }
        store.exhaustivity = .off

        await store.send(.startProcessing)

        await store.receive(._errorOccurred("DB接続エラー")) {
            $0.processingStatus = .failed(.processingFailed("DB接続エラー"))
        }
    }
}
