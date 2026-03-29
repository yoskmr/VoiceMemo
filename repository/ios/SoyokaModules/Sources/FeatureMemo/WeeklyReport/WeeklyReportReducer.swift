import ComposableArchitecture
import Domain
import Foundation

/// 週次レポート画面のTCA Reducer
/// Pro限定機能: 今週のきおくを振り返るレポートを生成
@Reducer
public struct WeeklyReportReducer {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        public var report: WeeklyReport?
        public var isLoading: Bool = false
        public var errorMessage: String?

        public init() {}
    }

    // MARK: - Action

    public enum Action: Equatable, Sendable {
        case onAppear
        case reportLoaded(WeeklyReport)
        case reportFailed(String)
    }

    // MARK: - Dependencies

    @Dependency(\.voiceMemoRepository) var voiceMemoRepository
    @Dependency(\.calendar) var calendar
    @Dependency(\.date.now) var now

    public init() {}

    // MARK: - Reducer Body

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = true
                return .run { [voiceMemoRepository, now, calendar] send in
                    do {
                        let report = try await Self.buildReport(
                            voiceMemoRepository: voiceMemoRepository,
                            now: now,
                            calendar: calendar
                        )
                        await send(.reportLoaded(report))
                    } catch {
                        await send(.reportFailed(error.localizedDescription))
                    }
                }

            case let .reportLoaded(report):
                state.isLoading = false
                state.report = report
                return .none

            case let .reportFailed(message):
                state.isLoading = false
                state.errorMessage = message
                return .none
            }
        }
    }

    // MARK: - Helpers

    /// 今週のレポートを構築する
    private static func buildReport(
        voiceMemoRepository: VoiceMemoRepositoryClient,
        now: Date,
        calendar: Calendar
    ) async throws -> WeeklyReport {
        // 今週の開始日（月曜）と終了日（日曜）を計算
        let weekday = calendar.component(.weekday, from: now)
        let daysToMonday = (weekday + 5) % 7
        let weekStart = calendar.date(
            byAdding: .day,
            value: -daysToMonday,
            to: calendar.startOfDay(for: now)
        )!
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!

        // リポジトリから今週のメモを取得
        let allMemos = try await voiceMemoRepository.fetchMemos(0, 1000)
        let weekMemos = allMemos.filter { memo in
            memo.createdAt >= weekStart && memo.createdAt <= weekEnd
        }

        // 活動サマリー計算
        let memoCount = weekMemos.count
        let totalDuration = weekMemos.reduce(0.0) { $0 + $1.durationSeconds }

        // タグ頻度計算
        var tagCounts: [String: Int] = [:]
        for memo in weekMemos {
            for tag in memo.tags {
                tagCounts[tag.name, default: 0] += 1
            }
        }
        let topTags = tagCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { TagFrequency(name: $0.key, count: $0.value) }

        // 感情分布計算
        var emotionCounts: [EmotionCategory: Int] = [:]
        for memo in weekMemos {
            if let emotion = memo.emotionAnalysis?.primaryEmotion {
                emotionCounts[emotion, default: 0] += 1
            }
        }
        let totalEmotionMemos = emotionCounts.values.reduce(0, +)
        let emotionDistribution: [EmotionCategory: Double] = totalEmotionMemos > 0
            ? emotionCounts.mapValues { Double($0) / Double(totalEmotionMemos) }
            : [:]
        let dominantEmotion = emotionCounts.max(by: { $0.value < $1.value })?.key

        // 感情トレンドコメント
        let emotionTrend: String? = dominantEmotion.flatMap { dominant in
            switch dominant {
            case .joy: return "喜びに満ちた一週間でした"
            case .calm: return "穏やかな一週間を過ごしました"
            case .anticipation: return "期待に胸を膨らませた一週間でした"
            case .sadness: return "少し寂しさを感じた一週間だったかもしれません"
            case .anxiety: return "不安を抱えた場面もあったようです"
            case .anger: return "もどかしさを感じることがあったようです"
            case .surprise: return "驚きのある一週間でした"
            case .neutral: return "落ち着いた一週間を過ごしました"
            }
        }

        // AIコメント（ローカル生成）
        let aiComment: String? = {
            if memoCount == 0 {
                return "今週はまだきおくがありません。ひとつ、つぶやいてみませんか？"
            }
            if memoCount >= 7 {
                return "毎日きおくを残していますね。素敵な習慣です。"
            }
            if memoCount >= 3 {
                return "今週も声を残してくれてありがとう。"
            }
            return "少しずつ、あなたの声が積み重なっています。"
        }()

        return WeeklyReport(
            weekStart: weekStart,
            weekEnd: weekEnd,
            memoCount: memoCount,
            totalRecordingDuration: totalDuration,
            topTags: topTags,
            dominantEmotion: dominantEmotion,
            emotionDistribution: emotionDistribution,
            emotionTrend: emotionTrend,
            aiComment: aiComment
        )
    }
}
