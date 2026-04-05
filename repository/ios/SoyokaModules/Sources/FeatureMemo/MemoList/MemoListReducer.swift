import ComposableArchitecture
import Domain
import FeatureSubscription
import Foundation
import SharedUI
import SharedUtil

/// メモ一覧画面のTCA Reducer
/// TASK-0011: メモ一覧画面
/// 設計書 01-system-architecture.md セクション2.2 TCA適用方針
@Reducer
public struct MemoListReducer {

    // MARK: - State

    /// 検索関連の子State（凝集度向上のため分離）
    @ObservableState
    public struct SearchState: Equatable, Sendable {
        public var query: String = ""
        public var results: [SearchResultItem] = []
        public var isSearching: Bool = false
        public var isActive: Bool { !query.isEmpty }

        public init(
            query: String = "",
            results: [SearchResultItem] = [],
            isSearching: Bool = false
        ) {
            self.query = query
            self.results = results
            self.isSearching = isSearching
        }
    }

    /// 削除Undo管理の子State（凝集度向上のため分離）
    @ObservableState
    public struct DeletionState: Equatable, Sendable {
        /// 直近削除したメモ（Undo 用に一時保持）
        public var recentlyDeletedMemo: MemoItem? = nil
        /// Undo スナックバーの表示フラグ
        public var showUndoSnackbar: Bool = false

        public init(
            recentlyDeletedMemo: MemoItem? = nil,
            showUndoSnackbar: Bool = false
        ) {
            self.recentlyDeletedMemo = recentlyDeletedMemo
            self.showUndoSnackbar = showUndoSnackbar
        }
    }

    @ObservableState
    public struct State: Equatable {
        public var memos: IdentifiedArrayOf<MemoItem> = []
        public var sections: [MemoSection] = []
        public var isLoading: Bool = false
        public var hasMorePages: Bool = true
        public var currentPage: Int = 0
        public var errorMessage: String?

        /// 検索関連
        public var search: SearchState = SearchState()

        /// メモ詳細画面（NavigationStack push用、nilで非表示）
        @Presents public var selectedMemo: MemoDetailReducer.State?

        /// 感情トレンド画面（NavigationStack push用、nilで非表示）
        @Presents public var emotionTrendState: EmotionTrendReducer.State?

        /// 週次レポート画面（sheet表示用、nilで非表示）
        @Presents public var weeklyReportState: WeeklyReportReducer.State?

        /// サブスクリプション画面（sheet表示用、nilで非表示）
        @Presents public var subscription: SubscriptionReducer.State?

        /// 録音完了→メモ詳細遷移時の待機用ID（refreshCompleted前にselectMemoが届いた場合に保持）
        public var pendingMemoID: UUID?

        /// 削除確認関連
        public var deletion: DeletionState = DeletionState()

        /// AI分析クォータ情報（Phase 3 UXレビュー: 一覧上部に使用回数表示）
        public var aiQuotaUsed: Int = 0
        public var aiQuotaLimit: Int = 10
        public var nextResetDate: Date?

        /// 月上限到達時のダイアログ表示フラグ（T11: 月次制限UI）
        public var showQuotaExceededAlert: Bool = false

        /// Pro限定機能を使おうとしたときのダイアログ表示フラグ
        public var showProRequiredAlert: Bool = false

        /// ページネーション設定（NFR-005: 1,000件一覧 1秒以内）
        public static let pageSize = 50

        public init(
            memos: IdentifiedArrayOf<MemoItem> = [],
            sections: [MemoSection] = [],
            isLoading: Bool = false,
            hasMorePages: Bool = true,
            currentPage: Int = 0,
            errorMessage: String? = nil,
            search: SearchState = SearchState(),
            selectedMemo: MemoDetailReducer.State? = nil,
            emotionTrendState: EmotionTrendReducer.State? = nil,
            weeklyReportState: WeeklyReportReducer.State? = nil,
            subscription: SubscriptionReducer.State? = nil,
            pendingMemoID: UUID? = nil,
            deletion: DeletionState = DeletionState(),
            aiQuotaUsed: Int = 0,
            aiQuotaLimit: Int = 10,
            nextResetDate: Date? = nil,
            showQuotaExceededAlert: Bool = false,
            showProRequiredAlert: Bool = false
        ) {
            self.memos = memos
            self.sections = sections
            self.isLoading = isLoading
            self.hasMorePages = hasMorePages
            self.currentPage = currentPage
            self.errorMessage = errorMessage
            self.search = search
            self.selectedMemo = selectedMemo
            self.emotionTrendState = emotionTrendState
            self.weeklyReportState = weeklyReportState
            self.subscription = subscription
            self.pendingMemoID = pendingMemoID
            self.deletion = deletion
            self.aiQuotaUsed = aiQuotaUsed
            self.aiQuotaLimit = aiQuotaLimit
            self.nextResetDate = nextResetDate
            self.showQuotaExceededAlert = showQuotaExceededAlert
            self.showProRequiredAlert = showProRequiredAlert
        }
    }

    /// 検索結果アイテム（インライン検索用）
    public struct SearchResultItem: Equatable, Identifiable, Sendable {
        public let id: UUID
        public var title: String
        public var snippet: String
        public var createdAt: Date
        public var emotion: EmotionCategory?
        public var durationSeconds: Double
        public var tags: [String]

        public init(
            id: UUID,
            title: String,
            snippet: String,
            createdAt: Date,
            emotion: EmotionCategory?,
            durationSeconds: Double,
            tags: [String]
        ) {
            self.id = id
            self.title = title
            self.snippet = snippet
            self.createdAt = createdAt
            self.emotion = emotion
            self.durationSeconds = durationSeconds
            self.tags = tags
        }
    }

    /// メモ一覧アイテム（表示用の軽量データ）
    public struct MemoItem: Equatable, Identifiable, Sendable {
        public let id: UUID
        public var title: String
        public var createdAt: Date
        public var durationSeconds: Double
        public var transcriptPreview: String
        public var emotion: EmotionCategory?
        public var tags: [String]
        public var audioFilePath: String
        public var aiStatus: AIDisplayStatus

        public init(
            id: UUID,
            title: String,
            createdAt: Date,
            durationSeconds: Double,
            transcriptPreview: String,
            emotion: EmotionCategory?,
            tags: [String],
            audioFilePath: String,
            aiStatus: AIDisplayStatus = .none
        ) {
            self.id = id
            self.title = title
            self.createdAt = createdAt
            self.durationSeconds = durationSeconds
            self.transcriptPreview = transcriptPreview
            self.emotion = emotion
            self.tags = tags
            self.audioFilePath = audioFilePath
            self.aiStatus = aiStatus
        }
    }

    /// 日付セクション（今日・昨日・日付でグループ化）
    public struct MemoSection: Equatable, Identifiable, Sendable {
        public var id: String { label }
        public let label: String
        public let date: Date
        public var memoIDs: [UUID]

        public init(label: String, date: Date, memoIDs: [UUID]) {
            self.label = label
            self.date = date
            self.memoIDs = memoIDs
        }
    }

    // MARK: - Action

    public enum Action: Equatable, Sendable {
        case onAppear
        case loadNextPage
        case memosLoaded(Result<[MemoItem], EquatableError>)
        case memoTapped(id: UUID)
        case swipeToDelete(id: UUID)
        case undoDeleteTapped
        case undoExpired
        case deleteConfirmed(id: UUID)
        case memoDeleted(Result<UUID, EquatableError>)
        case searchQueryChanged(String)
        case searchCompleted(SearchResult)
        case trendIconTapped
        case emotionTrendProChecked(Bool)
        case weeklyReportTapped
        case weeklyReportProVerified
        case weeklyReport(PresentationAction<WeeklyReportReducer.Action>)
        case selectMemo(id: UUID)
        case refreshRequested
        case refreshCompleted(Result<[MemoItem], EquatableError>)
        case memoDetail(PresentationAction<MemoDetailReducer.Action>)
        case emotionTrend(PresentationAction<EmotionTrendReducer.Action>)

        /// T11: AI月次クォータ情報の読み込み完了
        case aiQuotaLoaded(used: Int, limit: Int, resetDate: Date)
        /// T11: 月上限到達ダイアログの表示制御
        case quotaExceededAlertPresented(Bool)
        /// T11:「Proを見る」タップ（Phase 3aではプレースホルダ）
        case showProPlanTapped
        /// Pro限定機能ダイアログの表示制御
        case proRequiredAlertPresented(Bool)
        /// サブスクリプション画面のアクション
        case subscription(PresentationAction<SubscriptionReducer.Action>)
        /// サブスクリプション画面を表示
        case showSubscription
    }

    /// 検索結果のEquatable準拠ラッパー
    public enum SearchResult: Equatable, Sendable {
        case success([SearchResultItem])
        case failure(String)
    }

    // MARK: - Cancellation IDs

    private enum CancelID { case search, undoTimer }

    // MARK: - Dependencies

    @Dependency(\.voiceMemoRepository) var voiceMemoRepository
    @Dependency(\.fts5IndexManager) var fts5IndexManager
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(\.calendar) var calendar
    @Dependency(\.aiQuota) var aiQuota
    @Dependency(\.subscriptionClient) var subscriptionClient
    @Dependency(\.analyticsClient) var analyticsClient

    public init() {}

    // MARK: - Reducer Body

    public var body: some ReducerOf<Self> {
        Reduce<State, Action> { state, action in
            switch action {
            case .onAppear:
                guard state.memos.isEmpty else { return .none }
                state.isLoading = true
                state.currentPage = 0
                return .merge(
                    .run { send in
                        let result = await Result {
                            try await self.fetchMemoItems(page: 0)
                        }.mapError { EquatableError($0) }
                        await send(.memosLoaded(result))
                    },
                    .run { [aiQuota] send in
                        let used = (try? await aiQuota.currentUsage()) ?? 0
                        let limit = aiQuota.monthlyLimit()
                        let resetDate = aiQuota.nextResetDate()
                        await send(.aiQuotaLoaded(used: used, limit: limit, resetDate: resetDate))
                    }
                )

            case .loadNextPage:
                guard !state.isLoading, state.hasMorePages else { return .none }
                state.isLoading = true
                let nextPage = state.currentPage
                return .run { send in
                    let result = await Result {
                        try await self.fetchMemoItems(page: nextPage)
                    }.mapError { EquatableError($0) }
                    await send(.memosLoaded(result))
                }

            case let .memosLoaded(.success(newMemos)):
                state.isLoading = false
                state.currentPage += 1
                state.hasMorePages = newMemos.count >= State.pageSize
                for memo in newMemos {
                    state.memos.updateOrAppend(memo)
                }
                state.sections = Self.buildSections(
                    from: state.memos,
                    now: now,
                    calendar: calendar
                )
                return .none

            case let .memosLoaded(.failure(error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                return .none

            case let .swipeToDelete(id):
                guard let memo = state.memos[id: id] else { return .none }
                // 一覧から即座に除去し、Undo 用に保持
                state.deletion.recentlyDeletedMemo = memo
                state.deletion.showUndoSnackbar = true
                state.memos.remove(id: id)
                state.sections = Self.buildSections(
                    from: state.memos,
                    now: now,
                    calendar: calendar
                )
                // 3秒後に undoExpired を送信
                return .run { send in
                    try await clock.sleep(for: .seconds(3))
                    await send(.undoExpired)
                }
                .cancellable(id: CancelID.undoTimer, cancelInFlight: true)

            case .undoDeleteTapped:
                guard let memo = state.deletion.recentlyDeletedMemo else { return .none }
                // 削除したメモを一覧に復元
                state.memos.updateOrAppend(memo)
                state.sections = Self.buildSections(
                    from: state.memos,
                    now: now,
                    calendar: calendar
                )
                state.deletion.recentlyDeletedMemo = nil
                state.deletion.showUndoSnackbar = false
                return .cancel(id: CancelID.undoTimer)

            case .undoExpired:
                guard let memo = state.deletion.recentlyDeletedMemo else { return .none }
                let id = memo.id
                state.deletion.recentlyDeletedMemo = nil
                state.deletion.showUndoSnackbar = false
                return .send(.deleteConfirmed(id: id))

            case let .deleteConfirmed(id):
                analyticsClient.send("memo.deleted")
                return .run { send in
                    let result = await Result {
                        try await voiceMemoRepository.delete(id)
                        return id
                    }.mapError { EquatableError($0) }
                    await send(.memoDeleted(result))
                }

            case .memoDeleted(.success):
                // メモは swipeToDelete 時点で一覧から除去済み
                return .none

            case let .memoDeleted(.failure(error)):
                state.errorMessage = error.localizedDescription
                return .none

            case let .selectMemo(id: memoID):
                if state.memos[id: memoID] != nil {
                    state.selectedMemo = MemoDetailReducer.State(memoID: memoID)
                    state.pendingMemoID = nil
                } else {
                    state.pendingMemoID = memoID
                }
                return .none

            case .refreshRequested:
                state.isLoading = true
                state.currentPage = 0
                return .run { send in
                    let result = await Result {
                        try await self.fetchMemoItems(page: 0)
                    }.mapError { EquatableError($0) }
                    await send(.refreshCompleted(result))
                }

            case let .refreshCompleted(.success(memos)):
                state.isLoading = false
                state.currentPage = 1
                state.memos = IdentifiedArrayOf(uniqueElements: memos)
                state.hasMorePages = memos.count >= State.pageSize
                state.sections = Self.buildSections(
                    from: state.memos,
                    now: now,
                    calendar: calendar
                )
                // 録音完了→メモ詳細遷移: refresh完了前にselectMemoが届いていた場合の遅延処理
                if let pendingID = state.pendingMemoID {
                    state.selectedMemo = MemoDetailReducer.State(memoID: pendingID)
                    state.pendingMemoID = nil
                }
                // リフレッシュ時にクォータ情報も再取得
                return .run { [aiQuota] send in
                    let used = (try? await aiQuota.currentUsage()) ?? 0
                    let limit = aiQuota.monthlyLimit()
                    let resetDate = aiQuota.nextResetDate()
                    await send(.aiQuotaLoaded(used: used, limit: limit, resetDate: resetDate))
                }

            case let .refreshCompleted(.failure(error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                return .none

            case let .searchQueryChanged(query):
                state.search.query = query

                guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                    state.search.results = []
                    state.search.isSearching = false
                    return .cancel(id: CancelID.search)
                }

                state.search.isSearching = true
                return .run { [fts5IndexManager, voiceMemoRepository] send in
                    try await clock.sleep(for: .milliseconds(300))
                    do {
                        #if DEBUG
                        print("[MemoList Search] クエリ: '\(query)'")
                        #endif
                        let ftsResults = try fts5IndexManager.searchWithSnippets(query, 2, 32)
                        #if DEBUG
                        print("[MemoList Search] FTS5結果: \(ftsResults.count)件")
                        #endif

                        // N+1クエリ解消: fetchMemosByIDsで一括取得（#9）
                        let memoIDs = ftsResults.compactMap { UUID(uuidString: $0.memoID) }
                        let memosDict = try await voiceMemoRepository.fetchMemosByIDs(memoIDs)

                        var items: [SearchResultItem] = []
                        for ftsResult in ftsResults {
                            guard let memoID = UUID(uuidString: ftsResult.memoID),
                                  let memo = memosDict[memoID]
                            else { continue }

                            items.append(SearchResultItem(
                                id: memoID,
                                title: memo.title,
                                snippet: ftsResult.snippet,
                                createdAt: memo.createdAt,
                                emotion: memo.emotion,
                                durationSeconds: memo.durationSeconds,
                                tags: memo.tags
                            ))
                        }
                        await send(.searchCompleted(.success(items)))
                    } catch {
                        #if DEBUG
                        print("[MemoList Search] エラー: \(error)")
                        #endif
                        await send(.searchCompleted(.failure(error.localizedDescription)))
                    }
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case let .searchCompleted(.success(items)):
                state.search.isSearching = false
                state.search.results = items
                return .none

            case let .searchCompleted(.failure(errorMessage)):
                state.search.isSearching = false
                state.errorMessage = errorMessage
                return .none

            case .trendIconTapped:
                // TASK-0042: Pro/Free 両方アクセス可。データ量差分はEmotionTrendReducer内で制御
                return .run { [subscriptionClient] send in
                    let subState = await subscriptionClient.currentSubscription()
                    let isPro: Bool
                    if case .pro = subState { isPro = true } else { isPro = false }
                    await send(.emotionTrendProChecked(isPro))
                }

            case let .emotionTrendProChecked(isPro):
                state.emotionTrendState = EmotionTrendReducer.State(isPro: isPro)
                return .none

            case .weeklyReportTapped:
                // Pro限定機能: サブスクリプション状態を確認
                return .run { [subscriptionClient] send in
                    let subState = await subscriptionClient.currentSubscription()
                    if case .pro = subState {
                        await send(.weeklyReportProVerified)
                    } else {
                        await send(.showProPlanTapped)
                    }
                }

            case .weeklyReportProVerified:
                state.weeklyReportState = WeeklyReportReducer.State()
                return .none

            case .weeklyReport:
                return .none

            case .emotionTrend(.presented(.planManagementTapped)):
                // TASK-0042: EmotionTrend の「Proプランを見てみる」タップをProプランダイアログに委譲
                state.emotionTrendState = nil
                return .send(.showProPlanTapped)

            case .emotionTrend:
                return .none

            case let .memoTapped(id: memoID):
                state.selectedMemo = MemoDetailReducer.State(memoID: memoID)
                return .none

            // メモ詳細: 削除完了 → 詳細を閉じて一覧をリフレッシュ
            case .memoDetail(.presented(._deleteCompletedAndDismiss)):
                state.selectedMemo = nil
                return .send(.refreshRequested)

            // メモ詳細: 編集保存完了 → 一覧をリフレッシュ
            case .memoDetail(.presented(._editSavedAndReload)):
                return .send(.refreshRequested)

            // destination nil 後の遅延 onDisappear を握り潰す（SwiftUI アニメーション競合）
            case .memoDetail(.presented(.audioPlayer(.onDisappear))):
                return .none

            case .memoDetail:
                return .none

            // MARK: - T11: 月次制限UI

            case let .aiQuotaLoaded(used, limit, resetDate):
                state.aiQuotaUsed = used
                state.aiQuotaLimit = limit
                state.nextResetDate = resetDate
                return .none

            case let .quotaExceededAlertPresented(isPresented):
                state.showQuotaExceededAlert = isPresented
                return .none

            case .showProPlanTapped:
                // Pro限定機能へのアクセス時にProプランダイアログを表示
                state.showQuotaExceededAlert = false
                state.showProRequiredAlert = true
                return .none

            case let .proRequiredAlertPresented(isPresented):
                state.showProRequiredAlert = isPresented
                return .none

            case .showSubscription:
                state.subscription = SubscriptionReducer.State()
                return .none

            case .subscription:
                return .none
            }
        }
        .ifLet(\.$selectedMemo, action: \.memoDetail) {
            MemoDetailReducer()
        }
        .ifLet(\.$emotionTrendState, action: \.emotionTrend) {
            EmotionTrendReducer()
        }
        .ifLet(\.$weeklyReportState, action: \.weeklyReport) {
            WeeklyReportReducer()
        }
        .ifLet(\.$subscription, action: \.subscription) {
            SubscriptionReducer()
        }
    }

    // MARK: - Helpers

    private func fetchMemoItems(page: Int) async throws -> [MemoItem] {
        let entities = try await voiceMemoRepository.fetchMemos(page, State.pageSize)
        return entities.map { entity in
            let aiStatus: AIDisplayStatus = entity.aiSummary != nil ? .completed : .none
            return MemoItem(
                id: entity.id,
                title: entity.title,
                createdAt: entity.createdAt,
                durationSeconds: entity.durationSeconds,
                transcriptPreview: String((entity.aiSummary?.summaryText ?? entity.transcription?.fullText ?? "").prefix(60)),
                emotion: entity.emotionAnalysis?.primaryEmotion,
                tags: entity.tags.map(\.name),
                audioFilePath: entity.audioFilePath,
                aiStatus: aiStatus
            )
        }
    }

    /// 日付セクションの構築
    // Performance Note: 現在のbuildSectionsは全件再構築（O(n)）。
    // 1000件以下では十分高速（実測 < 50ms）。
    // 1000件超の場合はDictionary差分更新に移行を検討。
    // SwiftData の fetchOffset/fetchLimit は iOS 18+ で安定化予定。
    static func buildSections(
        from memos: IdentifiedArrayOf<MemoItem>,
        now: Date,
        calendar: Calendar
    ) -> [MemoSection] {
        let grouped = Dictionary(grouping: memos.elements) { memo in
            calendar.startOfDay(for: memo.createdAt)
        }

        return grouped.keys.sorted(by: >).map { date in
            let label = sectionLabel(for: date, now: now, calendar: calendar)
            let ids = grouped[date]!
                .sorted { $0.createdAt > $1.createdAt }
                .map(\.id)
            return MemoSection(label: label, date: date, memoIDs: ids)
        }
    }

    private static let sectionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    static func sectionLabel(for date: Date, now: Date, calendar: Calendar) -> String {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let dayDiff = calendar.dateComponents([.day], from: startOfDate, to: startOfToday).day ?? 0
        if dayDiff == 0 { return "今日" }
        if dayDiff == 1 { return "昨日" }
        return sectionDateFormatter.string(from: date)
    }
}

// MARK: - MemoItem → MemoCardData 変換

extension MemoListReducer.MemoItem {
    /// SharedUI の MemoCardData に変換
    public var cardData: MemoCardData {
        MemoCardData(
            id: id,
            title: title,
            createdAt: createdAt,
            durationSeconds: durationSeconds,
            transcriptPreview: transcriptPreview,
            emotion: emotion,
            tags: tags,
            aiStatus: aiStatus
        )
    }
}

