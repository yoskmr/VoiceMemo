import ComposableArchitecture
import Domain
import FeatureSearch
import Foundation
import SharedUI

/// メモ一覧画面のTCA Reducer
/// TASK-0011: メモ一覧画面
/// 設計書 01-system-architecture.md セクション2.2 TCA適用方針
@Reducer
public struct MemoListReducer {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        public var memos: IdentifiedArrayOf<MemoItem> = []
        public var sections: [MemoSection] = []
        public var isLoading: Bool = false
        public var hasMorePages: Bool = true
        public var currentPage: Int = 0
        public var errorMessage: String?

        /// 検索画面（NavigationStack push用、nilで非表示）
        @Presents public var searchState: SearchReducer.State?

        /// ページネーション設定（NFR-005: 1,000件一覧 1秒以内）
        public static let pageSize = 50

        public init(
            memos: IdentifiedArrayOf<MemoItem> = [],
            sections: [MemoSection] = [],
            isLoading: Bool = false,
            hasMorePages: Bool = true,
            currentPage: Int = 0,
            errorMessage: String? = nil,
            searchState: SearchReducer.State? = nil
        ) {
            self.memos = memos
            self.sections = sections
            self.isLoading = isLoading
            self.hasMorePages = hasMorePages
            self.currentPage = currentPage
            self.errorMessage = errorMessage
            self.searchState = searchState
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
        case deleteConfirmed(id: UUID)
        case deleteCancelled
        case memoDeleted(Result<UUID, EquatableError>)
        case searchIconTapped
        case trendIconTapped
        case refreshRequested
        case refreshCompleted(Result<[MemoItem], EquatableError>)
        case search(PresentationAction<SearchReducer.Action>)
    }

    // MARK: - Dependencies

    @Dependency(\.voiceMemoRepository) var voiceMemoRepository
    @Dependency(\.date.now) var now
    @Dependency(\.calendar) var calendar

    public init() {}

    // MARK: - Reducer Body

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.memos.isEmpty else { return .none }
                state.isLoading = true
                state.currentPage = 0
                return .run { send in
                    let result = await Result {
                        try await self.fetchMemoItems(page: 0)
                    }.mapError { EquatableError($0) }
                    await send(.memosLoaded(result))
                }

            case .loadNextPage:
                guard !state.isLoading, state.hasMorePages else { return .none }
                state.isLoading = true
                let nextPage = state.currentPage + 1
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
                return .none

            case let .refreshCompleted(.failure(error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                return .none

            case .searchIconTapped:
                state.searchState = SearchReducer.State()
                return .none

            case .search(.presented(.resultTapped)):
                // 検索結果タップは親Reducerに伝播
                return .none

            case .search:
                return .none

            case .memoTapped, .deleteCancelled, .trendIconTapped:
                return .none
            }
        }
        .ifLet(\.$searchState, action: \.search) {
            SearchReducer()
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

    static func sectionLabel(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "今日" }
        if calendar.isDateInYesterday(date) { return "昨日" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
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

// MARK: - EquatableError

/// Error を Equatable 準拠させるためのラッパー
public struct EquatableError: Error, Equatable, Sendable {
    public let localizedDescription: String

    public init(_ error: Error) {
        self.localizedDescription = error.localizedDescription
    }

    public init(_ message: String) {
        self.localizedDescription = message
    }

    public static func == (lhs: EquatableError, rhs: EquatableError) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}
