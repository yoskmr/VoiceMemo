import ComposableArchitecture
import Domain
import Foundation
import SharedUI

/// メモ一覧画面のTCA Reducer
/// TASK-0011: メモ一覧画面
/// 設計書 01-system-architecture.md セクション2.2 TCA適用方針
@Reducer
public struct MemoListReducer {

    // MARK: - State

    // TODO: [#10] State分割 - 検索関連を SearchState 子Stateに分離（searchQuery, searchResults, isSearching）
    // TODO: [#10] State分割 - 削除関連を DeletionState に分離（pendingDeleteID, showDeleteConfirmation）
    // 現在のStateプロパティ数が多く凝集度が低いため、Phase後半でサブState化を検討する
    @ObservableState
    public struct State: Equatable {
        public var memos: IdentifiedArrayOf<MemoItem> = []
        public var sections: [MemoSection] = []
        public var isLoading: Bool = false
        public var hasMorePages: Bool = true
        public var currentPage: Int = 0
        public var errorMessage: String?

        /// インライン検索（.searchable 統合）
        public var searchQuery: String = ""
        public var searchResults: [SearchResultItem] = []
        public var isSearching: Bool = false

        /// 検索がアクティブかどうか
        public var isSearchActive: Bool { !searchQuery.isEmpty }

        /// メモ詳細画面（NavigationStack push用、nilで非表示）
        @Presents public var selectedMemo: MemoDetailReducer.State?

        /// 感情トレンド画面（NavigationStack push用、nilで非表示）
        @Presents public var emotionTrendState: EmotionTrendReducer.State?

        /// 録音完了→メモ詳細遷移時の待機用ID（refreshCompleted前にselectMemoが届いた場合に保持）
        public var pendingMemoID: UUID?

        /// スワイプ削除確認ダイアログ用
        public var pendingDeleteID: UUID?
        public var showDeleteConfirmation: Bool = false

        /// AI分析クォータ情報（Phase 3 UXレビュー: 一覧上部に使用回数表示）
        public var aiQuotaUsed: Int = 0
        public var aiQuotaLimit: Int = 15
        public var nextResetDate: Date?

        /// 月上限到達時のダイアログ表示フラグ（T11: 月次制限UI）
        public var showQuotaExceededAlert: Bool = false

        /// ページネーション設定（NFR-005: 1,000件一覧 1秒以内）
        public static let pageSize = 50

        public init(
            memos: IdentifiedArrayOf<MemoItem> = [],
            sections: [MemoSection] = [],
            isLoading: Bool = false,
            hasMorePages: Bool = true,
            currentPage: Int = 0,
            errorMessage: String? = nil,
            searchQuery: String = "",
            searchResults: [SearchResultItem] = [],
            isSearching: Bool = false,
            selectedMemo: MemoDetailReducer.State? = nil,
            emotionTrendState: EmotionTrendReducer.State? = nil,
            pendingMemoID: UUID? = nil,
            pendingDeleteID: UUID? = nil,
            showDeleteConfirmation: Bool = false,
            aiQuotaUsed: Int = 0,
            aiQuotaLimit: Int = 15,
            nextResetDate: Date? = nil,
            showQuotaExceededAlert: Bool = false
        ) {
            self.memos = memos
            self.sections = sections
            self.isLoading = isLoading
            self.hasMorePages = hasMorePages
            self.currentPage = currentPage
            self.errorMessage = errorMessage
            self.searchQuery = searchQuery
            self.searchResults = searchResults
            self.isSearching = isSearching
            self.selectedMemo = selectedMemo
            self.emotionTrendState = emotionTrendState
            self.pendingMemoID = pendingMemoID
            self.pendingDeleteID = pendingDeleteID
            self.showDeleteConfirmation = showDeleteConfirmation
            self.aiQuotaUsed = aiQuotaUsed
            self.aiQuotaLimit = aiQuotaLimit
            self.nextResetDate = nextResetDate
            self.showQuotaExceededAlert = showQuotaExceededAlert
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

        public init(
            id: UUID,
            title: String,
            createdAt: Date,
            durationSeconds: Double,
            transcriptPreview: String,
            emotion: EmotionCategory?,
            tags: [String],
            audioFilePath: String
        ) {
            self.id = id
            self.title = title
            self.createdAt = createdAt
            self.durationSeconds = durationSeconds
            self.transcriptPreview = transcriptPreview
            self.emotion = emotion
            self.tags = tags
            self.audioFilePath = audioFilePath
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
        case deleteConfirmationPresented(Bool)
        case confirmDelete
        case deleteConfirmed(id: UUID)
        case deleteCancelled
        case memoDeleted(Result<UUID, EquatableError>)
        case searchQueryChanged(String)
        case searchCompleted(SearchResult)
        case trendIconTapped
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
    }

    /// 検索結果のEquatable準拠ラッパー
    public enum SearchResult: Equatable, Sendable {
        case success([SearchResultItem])
        case failure(String)
    }

    // MARK: - Cancellation IDs

    private enum CancelID { case search }

    // MARK: - Dependencies

    @Dependency(\.voiceMemoRepository) var voiceMemoRepository
    @Dependency(\.fts5IndexManager) var fts5IndexManager
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(\.calendar) var calendar
    @Dependency(\.aiQuota) var aiQuota

    public init() {}

    // MARK: - Reducer Body

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
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
                state.pendingDeleteID = id
                state.showDeleteConfirmation = true
                return .none

            case let .deleteConfirmationPresented(isPresented):
                state.showDeleteConfirmation = isPresented
                if !isPresented {
                    state.pendingDeleteID = nil
                }
                return .none

            case .confirmDelete:
                guard let id = state.pendingDeleteID else { return .none }
                state.showDeleteConfirmation = false
                state.pendingDeleteID = nil
                return .send(.deleteConfirmed(id: id))

            case let .deleteConfirmed(id):
                return .run { send in
                    let result = await Result {
                        try await voiceMemoRepository.delete(id)
                        return id
                    }.mapError { EquatableError($0) }
                    await send(.memoDeleted(result))
                }

            case let .memoDeleted(.success(id)):
                state.memos.remove(id: id)
                state.sections = Self.buildSections(
                    from: state.memos,
                    now: now,
                    calendar: calendar
                )
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
                state.searchQuery = query

                guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                    state.searchResults = []
                    state.isSearching = false
                    return .cancel(id: CancelID.search)
                }

                state.isSearching = true
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
                state.isSearching = false
                state.searchResults = items
                return .none

            case let .searchCompleted(.failure(errorMessage)):
                state.isSearching = false
                state.errorMessage = errorMessage
                return .none

            case .trendIconTapped:
                state.emotionTrendState = EmotionTrendReducer.State()
                return .none

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

            case .memoDetail:
                return .none

            case .deleteCancelled:
                state.showDeleteConfirmation = false
                state.pendingDeleteID = nil
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
                // Phase 3a: プレースホルダ（Phase 3cで課金画面に遷移）
                // 現時点ではアラートを閉じるのみ
                state.showQuotaExceededAlert = false
                return .none
            }
        }
        .ifLet(\.$selectedMemo, action: \.memoDetail) {
            MemoDetailReducer()
        }
        .ifLet(\.$emotionTrendState, action: \.emotionTrend) {
            EmotionTrendReducer()
        }
    }

    // MARK: - Helpers

    private func fetchMemoItems(page: Int) async throws -> [MemoItem] {
        let entities = try await voiceMemoRepository.fetchMemos(page, State.pageSize)
        return entities.map { entity in
            MemoItem(
                id: entity.id,
                title: entity.title,
                createdAt: entity.createdAt,
                durationSeconds: entity.durationSeconds,
                transcriptPreview: String((entity.transcription?.fullText ?? "").prefix(60)),
                emotion: entity.emotionAnalysis?.primaryEmotion,
                tags: entity.tags.map(\.name),
                audioFilePath: entity.audioFilePath
            )
        }
    }

    /// 日付セクションの構築
    // TODO: 1000件超の場合は差分更新を検討（現在は全件再構築のためO(n)コスト）
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
            tags: tags
        )
    }
}

