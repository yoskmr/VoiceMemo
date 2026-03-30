import ComposableArchitecture
import Domain
import Foundation

/// AI処理の開始・ステータス監視・リトライ・キャンセルを管理するTCA Reducer
/// T08: Phase 3a Wave 3 前半
/// 設計書 DES-PHASE3A-001 セクション3.3 準拠
@Reducer
public struct AIProcessingReducer {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        /// 対象メモID
        public var memoID: UUID
        /// AI処理ステータス
        public var processingStatus: AIProcessingStatus = .idle
        /// 今月の残りクォータ
        public var remainingQuota: Int = 15
        /// 今月の使用回数
        public var quotaUsed: Int = 0
        /// 月次上限
        public var quotaLimit: Int = 15
        /// 初回オンボーディング表示フラグ
        public var showOnboarding: Bool = false

        public init(
            memoID: UUID,
            processingStatus: AIProcessingStatus = .idle,
            remainingQuota: Int = 15,
            quotaUsed: Int = 0,
            quotaLimit: Int = 15,
            showOnboarding: Bool = false
        ) {
            self.memoID = memoID
            self.processingStatus = processingStatus
            self.remainingQuota = remainingQuota
            self.quotaUsed = quotaUsed
            self.quotaLimit = quotaLimit
            self.showOnboarding = showOnboarding
        }
    }

    // MARK: - Action

    public enum Action: Equatable, Sendable {
        /// AI処理を開始する
        case startProcessing
        /// ステータスが更新された（observeStatus からのストリーム）
        case statusUpdated(AIProcessingStatus)
        /// クォータ情報が更新された
        case quotaUpdated(used: Int, remaining: Int)
        /// リトライ
        case retryProcessing
        /// キャンセル
        case cancelProcessing
        /// オンボーディングを閉じた
        case onboardingDismissed
        /// クォータチェック結果を受信
        case _quotaCheckCompleted(canProcess: Bool, remaining: Int, used: Int)
        /// エラーが発生した
        case _errorOccurred(String)
    }

    // MARK: - Cancellation IDs

    private enum CancelID {
        case observeStatus
        case processing
    }

    // MARK: - Dependencies

    @Dependency(\.aiProcessingQueue) var aiProcessingQueue
    @Dependency(\.aiQuota) var aiQuota

    public init() {}

    // MARK: - Reducer Body

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startProcessing:
                // 初回オンボーディングチェック
                let hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenAIOnboarding")
                if !hasSeenOnboarding {
                    state.showOnboarding = true
                    return .none
                }

                // ローカルAIは無制限のためクォータチェックをスキップし、常に処理を許可
                // クラウドAIの制限はAIProcessingQueue側でプラン判定して制御する
                return .run { send in
                    let used = (try? await aiQuota.currentUsage()) ?? 0
                    let remaining = (try? await aiQuota.remainingCount()) ?? 0
                    await send(._quotaCheckCompleted(
                        canProcess: true,
                        remaining: remaining,
                        used: used
                    ))
                } catch: { error, send in
                    await send(._errorOccurred(error.localizedDescription))
                }

            case let ._quotaCheckCompleted(canProcess, remaining, used):
                state.remainingQuota = remaining
                state.quotaUsed = used
                state.quotaLimit = aiQuota.monthlyLimit()

                if !canProcess {
                    let resetDate = aiQuota.nextResetDate()
                    state.processingStatus = .failed(
                        .quotaExceeded(remaining: 0, resetDate: resetDate)
                    )
                    return .none
                }

                // キューに追加してステータス監視を開始
                let memoID = state.memoID
                return .merge(
                    .run { _ in
                        try await aiProcessingQueue.enqueueProcessing(memoID)
                    } catch: { error, send in
                        await send(._errorOccurred(error.localizedDescription))
                    },
                    .run { send in
                        for await status in aiProcessingQueue.observeStatus(memoID) {
                            await send(.statusUpdated(status))
                        }
                    }
                    .cancellable(id: CancelID.observeStatus, cancelInFlight: true)
                )

            case let .statusUpdated(status):
                state.processingStatus = status

                // 完了時にクォータを更新
                if case .completed = status {
                    return .run { send in
                        let remaining = try await aiQuota.remainingCount()
                        let used = try await aiQuota.currentUsage()
                        await send(.quotaUpdated(used: used, remaining: remaining))
                    } catch: { _, _ in
                        // クォータ取得失敗は無視（処理自体は完了済み）
                    }
                }
                return .none

            case let .quotaUpdated(used, remaining):
                state.quotaUsed = used
                state.remainingQuota = remaining
                return .none

            case .retryProcessing:
                state.processingStatus = .idle
                return .send(.startProcessing)

            case .cancelProcessing:
                let memoID = state.memoID
                return .merge(
                    .cancel(id: CancelID.observeStatus),
                    .run { _ in
                        try await aiProcessingQueue.cancelProcessing(memoID)
                    } catch: { _, _ in
                        // キャンセル失敗は無視
                    }
                )

            case .onboardingDismissed:
                state.showOnboarding = false
                UserDefaults.standard.set(true, forKey: "hasSeenAIOnboarding")
                return .send(.startProcessing)

            case let ._errorOccurred(message):
                state.processingStatus = .failed(.processingFailed(message))
                return .none
            }
        }
    }
}
