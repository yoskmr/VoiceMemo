import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI

/// 週次レポート画面
/// Soyoka のトーン・デザイントークンに準拠。温かく寄り添うレポート画面。
public struct WeeklyReportView: View {
    let store: StoreOf<WeeklyReportReducer>

    public init(store: StoreOf<WeeklyReportReducer>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            if store.isLoading {
                ProgressView("ふりかえりを準備中...")
                    .padding(.top, VMDesignTokens.Spacing.xxxl)
            } else if let report = store.report {
                VStack(spacing: VMDesignTokens.Spacing.xl) {
                    // ヘッダー
                    headerSection(report)

                    // AIコメント（最も目立つ位置）
                    if let comment = report.aiComment {
                        aiCommentCard(comment)
                    }

                    // 活動サマリー
                    activitySection(report)

                    // 感情トレンド
                    if report.dominantEmotion != nil {
                        emotionSection(report)
                    }

                    // 習慣
                    habitSection(report)

                    // よく使ったタグ
                    if !report.topTags.isEmpty {
                        tagsSection(report)
                    }

                    // よく使った言葉
                    if !report.topWords.isEmpty {
                        wordsSection(report)
                    }
                }
                .padding(.horizontal, VMDesignTokens.Spacing.lg)
                .padding(.vertical, VMDesignTokens.Spacing.xl)
            }
        }
        .background(Color.vmBackground)
        .navigationTitle("今週のふりかえり")
        .onAppear { store.send(.onAppear) }
    }

    // MARK: - Sub Views

    private func headerSection(_ report: WeeklyReport) -> some View {
        let formatter = Self.headerDateFormatter
        let start = formatter.string(from: report.weekStart)
        let end = formatter.string(from: report.weekEnd)

        return Text("\(start) - \(end)")
            .font(.vmSubheadline)
            .foregroundColor(.vmTextSecondary)
    }

    private func aiCommentCard(_ comment: String) -> some View {
        VStack(spacing: VMDesignTokens.Spacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundColor(.vmPrimary)

            Text(comment)
                .font(.vmBody())
                .foregroundColor(.vmTextPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(VMDesignTokens.LineSpacing.body)
        }
        .padding(VMDesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(Color.vmSurface)
        .cornerRadius(VMDesignTokens.CornerRadius.medium)
    }

    private func activitySection(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.md) {
            Text("今週のきおく")
                .font(.vmHeadline)
                .foregroundColor(.vmTextPrimary)

            HStack(spacing: VMDesignTokens.Spacing.xl) {
                statView(
                    value: "\(report.memoCount)",
                    label: "きおく"
                )
                statView(
                    value: formatDuration(report.totalRecordingDuration),
                    label: "つぶやき時間"
                )
            }
        }
        .padding(VMDesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vmSurface)
        .cornerRadius(VMDesignTokens.CornerRadius.medium)
    }

    private func emotionSection(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.md) {
            Text("こころの動き")
                .font(.vmHeadline)
                .foregroundColor(.vmTextPrimary)

            if let trend = report.emotionTrend {
                Text(trend)
                    .font(.vmCallout)
                    .foregroundColor(.vmTextSecondary)
                    .lineSpacing(VMDesignTokens.LineSpacing.caption)
            }

            if let dominant = report.dominantEmotion {
                HStack {
                    Text(dominant.label)
                        .font(.vmBody())
                        .foregroundColor(.vmTextPrimary)
                    Spacer()
                    EmotionBadge(emotion: dominant)
                }
            }
        }
        .padding(VMDesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vmSurface)
        .cornerRadius(VMDesignTokens.CornerRadius.medium)
    }

    private func tagsSection(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.md) {
            Text("よく使ったタグ")
                .font(.vmHeadline)
                .foregroundColor(.vmTextPrimary)

            ForEach(report.topTags, id: \.name) { tag in
                HStack {
                    Text(tag.name)
                        .font(.vmCallout)
                        .foregroundColor(.vmTextPrimary)
                    Spacer()
                    Text("\(tag.count)回")
                        .font(.vmCaption1)
                        .foregroundColor(.vmTextTertiary)
                }
            }
        }
        .padding(VMDesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vmSurface)
        .cornerRadius(VMDesignTokens.CornerRadius.medium)
    }

    private func habitSection(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.md) {
            Text("つづける力")
                .font(.vmHeadline)
                .foregroundColor(.vmTextPrimary)

            HStack(spacing: VMDesignTokens.Spacing.xl) {
                statView(value: "\(report.activeDays)/7", label: "記録した日")
                if report.streakDays > 0 {
                    statView(value: "\(report.streakDays)日", label: "連続記録")
                }
            }

            if report.activeDays >= 5 {
                Text("すばらしい！ほぼ毎日声を残していますね")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextSecondary)
            } else if report.activeDays >= 3 {
                Text("いいペースです。無理せず続けていきましょう")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextSecondary)
            }
        }
        .padding(VMDesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vmSurface)
        .cornerRadius(VMDesignTokens.CornerRadius.medium)
    }

    private func wordsSection(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.md) {
            Text("よく使った言葉")
                .font(.vmHeadline)
                .foregroundColor(.vmTextPrimary)

            ForEach(report.topWords, id: \.word) { word in
                HStack {
                    Text(word.word)
                        .font(.vmCallout)
                        .foregroundColor(.vmTextPrimary)
                    Spacer()
                    Text("\(word.count)回")
                        .font(.vmCaption1)
                        .foregroundColor(.vmTextTertiary)
                }
            }
        }
        .padding(VMDesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vmSurface)
        .cornerRadius(VMDesignTokens.CornerRadius.medium)
    }

    // MARK: - Helpers

    private func statView(value: String, label: String) -> some View {
        VStack {
            Text(value)
                .font(.vmTitle2)
                .foregroundColor(.vmPrimary)
            Text(label)
                .font(.vmCaption1)
                .foregroundColor(.vmTextSecondary)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes < 60 { return "\(minutes)分" }
        let hours = minutes / 60
        let remainMinutes = minutes % 60
        return "\(hours)時間\(remainMinutes)分"
    }

    private static let headerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d"
        return formatter
    }()
}
