import ComposableArchitecture
import Domain
import Foundation
import SharedUtil

/// 検索画面のTCA Reducer
/// TASK-0016: 検索UI画面
/// 設計書 01-system-architecture.md セクション2.2 TCA適用方針
@Reducer
public struct SearchReducer {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        public var searchText: String
        public var results: [SearchResultItem]
        public var resultCount: Int
        public var isSearching: Bool

        /// フィルター
        public var showFilters: Bool
        public var selectedDateFilter: DateFilter
        public var selectedTags: Set<String>
        public var availableTags: [String]

        /// UI
        public var errorMessage: String?
        public var isInitialState: Bool

        public init(
            searchText: String = "",
            results: [SearchResultItem] = [],
            resultCount: Int = 0,
            isSearching: Bool = false,
            showFilters: Bool = false,
            selectedDateFilter: DateFilter = .all,
            selectedTags: Set<String> = [],
            availableTags: [String] = [],
            errorMessage: String? = nil,
            isInitialState: Bool = true
        ) {
            self.searchText = searchText
            self.results = results
            self.resultCount = resultCount
            self.isSearching = isSearching
            self.showFilters = showFilters
            self.selectedDateFilter = selectedDateFilter
            self.selectedTags = selectedTags
            self.availableTags = availableTags
            self.errorMessage = errorMessage
            self.isInitialState = isInitialState
        }

        public enum DateFilter: String, CaseIterable, Equatable, Sendable {
            case today = "今日"
            case week = "過去1週間"
            case month = "過去1ヶ月"
            case all = "全期間"

            /// TCA Dependency 経由の now / calendar を受け取ってフィルター開始日を算出する
            public func startDate(now: Date, calendar: Calendar) -> Date? {
                switch self {
                case .today: return calendar.startOfDay(for: now)
                case .week: return calendar.date(byAdding: .day, value: -7, to: now)
                case .month: return calendar.date(byAdding: .month, value: -1, to: now)
                case .all: return nil
                }
            }
        }
    }

    /// 検索結果アイテム
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

    // MARK: - Action

    public enum Action: Equatable, Sendable {
        case onAppear
        case searchTextChanged(String)
        case performSearch
        case searchCompleted(SearchResult)
        case resultTapped(id: UUID)

        /// フィルター
        case toggleFilters
        case dateFilterChanged(State.DateFilter)
        case tagFilterToggled(String)
        case clearFilters

        /// タグ一覧
        case availableTagsLoaded([String])
    }

    /// 検索結果のEquatable準拠ラッパー
    public enum SearchResult: Equatable, Sendable {
        case success([SearchResultItem])
        case failure(String)
    }

    // MARK: - Dependencies

    @Dependency(\.fts5IndexManager) var fts5IndexManager
    @Dependency(\.voiceMemoRepository) var voiceMemoRepository
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(\.calendar) var calendar
    @Dependency(\.analyticsClient) var analyticsClient

    // MARK: - Cancellation IDs

    private enum SearchDebounceID { case debounce }
    private enum CancelID { case search }

    // MARK: - Reducer Body

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    let tags = try await voiceMemoRepository.fetchAllTags()
                    await send(.availableTagsLoaded(tags))
                }

            case let .availableTagsLoaded(tags):
                state.availableTags = tags
                return .none

            case let .searchTextChanged(text):
                state.searchText = text
                state.isInitialState = false

                guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                    state.results = []
                    state.resultCount = 0
                    return .cancel(id: SearchDebounceID.debounce)
                }

                // 300msデバウンス
                return .run { send in
                    try await clock.sleep(for: .milliseconds(300))
                    await send(.performSearch)
                }
                .cancellable(id: SearchDebounceID.debounce, cancelInFlight: true)

            case .performSearch:
                let query = state.searchText
                let dateFilter = state.selectedDateFilter
                let tagFilter = state.selectedTags
                let filterStartDate = dateFilter.startDate(now: now, calendar: calendar)

                guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                    state.results = []
                    state.resultCount = 0
                    return .none
                }

                state.isSearching = true
                analyticsClient.send("search.performed")
                return .run { [fts5IndexManager, voiceMemoRepository] send in
                    do {
                        #if DEBUG
                        print("[Search] クエリ: '\(query)'")
                        #endif
                        let ftsResults = try fts5IndexManager.searchWithSnippets(query, 2, 32)
                        #if DEBUG
                        print("[Search] FTS5結果: \(ftsResults.count)件")
                        #endif

                        // N+1クエリ解消: fetchMemosByIDsで一括取得（MemoListReducerと同じパターン）
                        let memoIDs = ftsResults.compactMap { UUID(uuidString: $0.memoID) }
                        let memosDict = try await voiceMemoRepository.fetchMemosByIDs(memoIDs)

                        var items: [SearchResultItem] = []
                        for ftsResult in ftsResults {
                            guard let memoID = UUID(uuidString: ftsResult.memoID),
                                  let memo = memosDict[memoID]
                            else { continue }

                            // 日付フィルター
                            if let startDate = filterStartDate,
                               memo.createdAt < startDate {
                                continue
                            }

                            // タグフィルター
                            if !tagFilter.isEmpty {
                                let memoTags = Set(memo.tags)
                                guard !memoTags.isDisjoint(with: tagFilter) else { continue }
                            }

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
                        print("[Search] エラー: \(error)")
                        #endif
                        await send(.searchCompleted(.failure(error.localizedDescription)))
                    }
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case let .searchCompleted(.success(items)):
                state.isSearching = false
                state.results = items
                state.resultCount = items.count
                return .none

            case let .searchCompleted(.failure(errorMessage)):
                state.isSearching = false
                state.errorMessage = errorMessage
                return .none

            case .toggleFilters:
                state.showFilters.toggle()
                return .none

            case let .dateFilterChanged(filter):
                state.selectedDateFilter = filter
                return .send(.performSearch)

            case let .tagFilterToggled(tag):
                if state.selectedTags.contains(tag) {
                    state.selectedTags.remove(tag)
                } else {
                    state.selectedTags.insert(tag)
                }
                return .send(.performSearch)

            case .clearFilters:
                state.selectedDateFilter = .all
                state.selectedTags = []
                return .send(.performSearch)

            case .resultTapped:
                return .none
            }
        }
    }
}
