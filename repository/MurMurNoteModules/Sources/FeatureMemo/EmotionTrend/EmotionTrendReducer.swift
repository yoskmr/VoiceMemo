import ComposableArchitecture
import Domain
import Foundation

/// 感情トレンド画面のTCA Reducer
/// 設計書 04-ui-design-system.md セクション5.2 準拠
@Reducer
public struct EmotionTrendReducer {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        public var emotions: [EmotionEntry] = []
        public var isLoading: Bool = false
        public var selectedPeriod: Period = .week

        public init(
            emotions: [EmotionEntry] = [],
            isLoading: Bool = false,
            selectedPeriod: Period = .week
        ) {
            self.emotions = emotions
            self.isLoading = isLoading
            self.selectedPeriod = selectedPeriod
        }
    }

    /// 感情エントリ（日付ごとの感情データ）
    public struct EmotionEntry: Equatable, Identifiable, Sendable {
        public let id: UUID
        public let date: Date
        public let primaryEmotion: EmotionCategory
        public let confidence: Double
        public let memoTitle: String

        public init(
            id: UUID = UUID(),
            date: Date,
            primaryEmotion: EmotionCategory,
            confidence: Double,
            memoTitle: String = ""
        ) {
            self.id = id
            self.date = date
            self.primaryEmotion = primaryEmotion
            self.confidence = confidence
            self.memoTitle = memoTitle
        }
    }

    /// 表示期間
    public enum Period: String, CaseIterable, Equatable, Sendable {
        case week = "1週間"
        case month = "1ヶ月"
        case all = "全期間"

        /// TCA Dependency 経由の now / calendar を受け取ってフィルター開始日を算出する
        public func startDate(now: Date, calendar: Calendar) -> Date? {
            switch self {
            case .week: return calendar.date(byAdding: .day, value: -7, to: now)
            case .month: return calendar.date(byAdding: .month, value: -1, to: now)
            case .all: return nil
            }
        }
    }

    // MARK: - Action

    public enum Action: Equatable, Sendable {
        case onAppear
        case periodChanged(Period)
        case emotionsLoaded(Result<[EmotionEntry], EquatableError>)
    }

    // MARK: - Cancellation IDs

    private enum CancelID { case fetch }

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
                state.isLoading = true
                let period = state.selectedPeriod
                return .run { send in
                    let result = await Result {
                        try await self.fetchEmotionEntries(period: period)
                    }.mapError { EquatableError($0) }
                    await send(.emotionsLoaded(result))
                }
                .cancellable(id: CancelID.fetch, cancelInFlight: true)

            case let .periodChanged(period):
                state.selectedPeriod = period
                state.isLoading = true
                return .run { send in
                    let result = await Result {
                        try await self.fetchEmotionEntries(period: period)
                    }.mapError { EquatableError($0) }
                    await send(.emotionsLoaded(result))
                }
                .cancellable(id: CancelID.fetch, cancelInFlight: true)

            case let .emotionsLoaded(.success(entries)):
                state.isLoading = false
                state.emotions = entries
                return .none

            case .emotionsLoaded(.failure):
                state.isLoading = false
                state.emotions = []
                return .none
            }
        }
    }

    // MARK: - Helpers

    private func fetchEmotionEntries(period: Period) async throws -> [EmotionEntry] {
        let allMemos = try await voiceMemoRepository.fetchAll()
        let startDate = period.startDate(now: now, calendar: calendar)

        return allMemos
            .filter { memo in
                guard let analysis = memo.emotionAnalysis else { return false }
                // confidence が 0 より大きいもののみ（実際に分析済み）
                guard analysis.confidence > 0 else { return false }
                if let startDate {
                    return memo.createdAt >= startDate
                }
                return true
            }
            .sorted { $0.createdAt > $1.createdAt }
            .map { memo in
                EmotionEntry(
                    id: memo.id,
                    date: memo.createdAt,
                    primaryEmotion: memo.emotionAnalysis!.primaryEmotion,
                    confidence: memo.emotionAnalysis!.confidence,
                    memoTitle: memo.title
                )
            }
    }
}
