import ComposableArchitecture
import Domain
import Foundation

/// 感情トレンド画面のTCA Reducer
/// 設計書 04-ui-design-system.md セクション5.2 準拠
/// TASK-0042: 「こころの流れ」Pro機能拡張（REQ-032 / US-310 / AC-310）
@Reducer
public struct EmotionTrendReducer {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        public var emotions: [EmotionEntry] = []
        public var dailyEmotions: [DailyEmotion] = []
        public var isLoading: Bool = false
        public var selectedPeriod: Period = .week
        public var isPro: Bool = false
        public var errorMessage: String?

        public init(
            emotions: [EmotionEntry] = [],
            dailyEmotions: [DailyEmotion] = [],
            isLoading: Bool = false,
            selectedPeriod: Period = .week,
            isPro: Bool = false,
            errorMessage: String? = nil
        ) {
            self.emotions = emotions
            self.dailyEmotions = dailyEmotions
            self.isLoading = isLoading
            self.selectedPeriod = selectedPeriod
            self.isPro = isPro
            self.errorMessage = errorMessage
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

    /// 日別の感情集計データ（チャート描画用）
    public struct DailyEmotion: Equatable, Identifiable, Sendable {
        public var id: Date { date }
        public let date: Date
        public let emotions: [EmotionCategory: Double]
        public let memoCount: Int

        public init(date: Date, emotions: [EmotionCategory: Double], memoCount: Int) {
            self.date = date
            self.emotions = emotions
            self.memoCount = memoCount
        }
    }

    /// 表示期間
    public enum Period: String, CaseIterable, Equatable, Sendable {
        case week, month, quarter, all

        public var displayName: String {
            switch self {
            case .week: return "1週間"
            case .month: return "1ヶ月"
            case .quarter: return "3ヶ月"
            case .all: return "すべて"
            }
        }

        /// TCA Dependency 経由の now / calendar を受け取ってフィルター開始日を算出する
        public func startDate(now: Date, calendar: Calendar) -> Date? {
            switch self {
            case .week: return calendar.date(byAdding: .day, value: -7, to: now)
            case .month: return calendar.date(byAdding: .month, value: -1, to: now)
            case .quarter: return calendar.date(byAdding: .month, value: -3, to: now)
            case .all: return nil
            }
        }
    }

    // MARK: - Action

    public enum Action: Equatable, Sendable {
        case onAppear
        case periodChanged(Period)
        case emotionsLoaded(Result<[EmotionEntry], EquatableError>)
        case dailyEmotionsLoaded([DailyEmotion])
        case subscriptionStateLoaded(Bool)
        case planManagementTapped
        case retryTapped
        case dismissError
    }

    // MARK: - Cancellation IDs

    private enum CancelID { case fetch }

    // MARK: - Dependencies

    @Dependency(\.voiceMemoRepository) var voiceMemoRepository
    @Dependency(\.subscriptionClient) var subscriptionClient
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
                return .merge(
                    .run { send in
                        let result = await Result {
                            try await self.fetchEmotionEntries(period: period)
                        }.mapError { EquatableError($0) }
                        await send(.emotionsLoaded(result))
                        let dailyEmotions = await self.aggregateDailyEmotions(period: period)
                        await send(.dailyEmotionsLoaded(dailyEmotions))
                    }
                    .cancellable(id: CancelID.fetch, cancelInFlight: true),
                    .run { [subscriptionClient] send in
                        let subState = await subscriptionClient.currentSubscription()
                        let isPro: Bool
                        if case .pro = subState { isPro = true } else { isPro = false }
                        await send(.subscriptionStateLoaded(isPro))
                    }
                )

            case let .periodChanged(period):
                state.selectedPeriod = period
                state.isLoading = true
                return .run { send in
                    let result = await Result {
                        try await self.fetchEmotionEntries(period: period)
                    }.mapError { EquatableError($0) }
                    await send(.emotionsLoaded(result))
                    let dailyEmotions = await self.aggregateDailyEmotions(period: period)
                    await send(.dailyEmotionsLoaded(dailyEmotions))
                }
                .cancellable(id: CancelID.fetch, cancelInFlight: true)

            case let .emotionsLoaded(.success(entries)):
                state.isLoading = false
                if state.isPro {
                    state.emotions = entries
                } else {
                    state.emotions = Array(entries.prefix(3))
                }
                return .none

            case .emotionsLoaded(.failure):
                state.isLoading = false
                state.emotions = []
                state.dailyEmotions = []
                state.errorMessage = "こころの記録を読み込めませんでした"
                return .none

            case let .dailyEmotionsLoaded(dailyEmotions):
                state.dailyEmotions = dailyEmotions
                return .none

            case let .subscriptionStateLoaded(isPro):
                state.isPro = isPro
                return .none

            case .planManagementTapped:
                // 親Reducerに委譲（MemoListReducerで処理）
                return .none

            case .retryTapped:
                state.errorMessage = nil
                state.isLoading = true
                let period = state.selectedPeriod
                return .run { send in
                    let result = await Result {
                        try await self.fetchEmotionEntries(period: period)
                    }.mapError { EquatableError($0) }
                    await send(.emotionsLoaded(result))
                    let dailyEmotions = await self.aggregateDailyEmotions(period: period)
                    await send(.dailyEmotionsLoaded(dailyEmotions))
                }
                .cancellable(id: CancelID.fetch, cancelInFlight: true)

            case .dismissError:
                state.errorMessage = nil
                return .none
            }
        }
    }

    // MARK: - Helpers

    /// メモを日別に集計し、各感情カテゴリのスコアを算出する
    private func aggregateDailyEmotions(period: Period) async -> [DailyEmotion] {
        guard let allMemos = try? await voiceMemoRepository.fetchAll() else { return [] }
        let startDate = period.startDate(now: now, calendar: calendar)

        let filteredMemos = allMemos.filter { memo in
            guard let analysis = memo.emotionAnalysis else { return false }
            guard analysis.confidence > 0 else { return false }
            if let startDate {
                return memo.createdAt >= startDate
            }
            return true
        }

        // 日付ごとにグルーピング
        var grouped: [Date: [Domain.VoiceMemoEntity]] = [:]
        for memo in filteredMemos {
            let dayStart = calendar.startOfDay(for: memo.createdAt)
            grouped[dayStart, default: []].append(memo)
        }

        return grouped.map { date, memos in
            var emotionScores: [EmotionCategory: Double] = [:]
            for memo in memos {
                guard let analysis = memo.emotionAnalysis else { continue }
                let category = analysis.primaryEmotion
                emotionScores[category, default: 0] += analysis.confidence
            }
            return DailyEmotion(date: date, emotions: emotionScores, memoCount: memos.count)
        }
        .sorted { $0.date < $1.date }
    }

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
