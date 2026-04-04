import Charts
import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI

/// 感情トレンド画面
/// 設計書 04-ui-design-system.md セクション5.2 準拠
public struct EmotionTrendView: View {
    @Bindable public var store: StoreOf<EmotionTrendReducer>

    public init(store: StoreOf<EmotionTrendReducer>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            periodPicker
                .padding(.horizontal, VMDesignTokens.Spacing.lg)
                .padding(.vertical, VMDesignTokens.Spacing.md)

            if store.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if store.emotions.isEmpty {
                emptyStateView
            } else {
                if !store.dailyEmotions.isEmpty {
                    emotionChartView
                        .padding(.horizontal, VMDesignTokens.Spacing.lg)
                        .padding(.bottom, VMDesignTokens.Spacing.md)
                }
                emotionListView
            }
        }
        .background(Color.vmBackground)
        .navigationTitle("こころの流れ")
        .onAppear {
            store.send(.onAppear)
        }
    }

    // MARK: - Chart

    /// 感情カテゴリラベルの配列（チャートの domain 用）
    private var emotionLabels: [String] {
        EmotionCategory.allCases.map(\.label)
    }

    /// 感情カテゴリ色の配列（チャートの range 用）
    private var emotionColors: [Color] {
        EmotionCategory.allCases.map(\.color)
    }

    /// こころの流れチャート（100%積み上げエリアチャート）
    /// TASK-0042: BarMark → AreaMark に変更、catmullRom 補間で滑らかに
    private var emotionChartView: some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.sm) {
            Text("こころの流れ")
                .font(.vmHeadline)
                .foregroundColor(.vmTextPrimary)

            Chart {
                ForEach(store.dailyEmotions) { daily in
                    ForEach(EmotionCategory.allCases, id: \.self) { emotion in
                        if let score = daily.emotions[emotion], score > 0 {
                            AreaMark(
                                x: .value("日付", daily.date, unit: .day),
                                y: .value("スコア", score),
                                stacking: .normalized
                            )
                            .foregroundStyle(by: .value("感情", emotion.label))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                }
            }
            .chartForegroundStyleScale(domain: emotionLabels, range: emotionColors)
            .frame(height: 200)
        }
        .padding(VMDesignTokens.Spacing.md)
        .background(Color.vmSurface)
        .cornerRadius(VMDesignTokens.CornerRadius.small)
    }

    // MARK: - Sub Views

    /// ピリオド選択 Picker
    private var periodPicker: some View {
        Picker("期間", selection: $store.selectedPeriod.sending(\.periodChanged)) {
            ForEach(EmotionTrendReducer.Period.allCases, id: \.self) { period in
                Text(period.displayName).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    /// 感情データなしの空状態
    private var emptyStateView: some View {
        VStack(spacing: VMDesignTokens.Spacing.lg) {
            Spacer()

            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(.vmTextTertiary)

            Text("感情データがありません")
                .font(.vmTitle3)
                .foregroundColor(.vmTextPrimary)

            Text("きおくにこころの分析を適用すると、\nここに感情の推移が表示されます")
                .font(.vmSubheadline)
                .foregroundColor(.vmTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, VMDesignTokens.Spacing.xxl)

            Spacer()
        }
    }

    /// 感情データリスト（Pro/Free 分岐あり）
    private var emotionListView: some View {
        ScrollView {
            LazyVStack(spacing: VMDesignTokens.Spacing.sm) {
                ForEach(store.emotions) { entry in
                    emotionRow(entry)
                        .padding(.horizontal, VMDesignTokens.Spacing.lg)
                }

                if !store.isPro {
                    proUpgradeOverlay
                        .padding(.horizontal, VMDesignTokens.Spacing.lg)
                        .padding(.top, VMDesignTokens.Spacing.md)
                }
            }
            .padding(.vertical, VMDesignTokens.Spacing.sm)
        }
    }

    /// Free ユーザー向けのアップグレード誘導オーバーレイ
    /// TASK-0042: 最新3件のみ表示し、残りは鍵アイコン付きで誘導
    private var proUpgradeOverlay: some View {
        VStack(spacing: VMDesignTokens.Spacing.md) {
            Image(systemName: "lock.fill")
                .font(.system(size: 32))
                .foregroundColor(.vmTextTertiary)

            Text("こころの流れの全体表示はProプラン限定です")
                .font(.vmSubheadline)
                .foregroundColor(.vmTextSecondary)
                .multilineTextAlignment(.center)

            Button {
                store.send(.planManagementTapped)
            } label: {
                Text("Proプランを見てみる")
                    .font(.vmBody())
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, VMDesignTokens.Spacing.xl)
                    .padding(.vertical, VMDesignTokens.Spacing.sm)
                    .background(Color.vmAccent)
                    .cornerRadius(VMDesignTokens.CornerRadius.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(VMDesignTokens.Spacing.xl)
        .background(Color.vmSurface)
        .cornerRadius(VMDesignTokens.CornerRadius.small)
    }

    /// 感情エントリの行
    private func emotionRow(_ entry: EmotionTrendReducer.EmotionEntry) -> some View {
        HStack(spacing: VMDesignTokens.Spacing.md) {
            // 日付
            VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.xxs) {
                Text(entry.date, style: .date)
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextSecondary)
                Text(entry.date, style: .time)
                    .font(.vmCaption2)
                    .foregroundColor(.vmTextTertiary)
            }
            .frame(width: 80, alignment: .leading)

            // 感情バッジ
            EmotionBadge(emotion: entry.primaryEmotion)

            // メモタイトル
            if !entry.memoTitle.isEmpty {
                Text(entry.memoTitle)
                    .font(.vmFootnote)
                    .foregroundColor(.vmTextPrimary)
                    .lineLimit(1)
            }

            Spacer()

            // 信頼度
            Text("\(Int(entry.confidence * 100))%")
                .font(.vmCaption2)
                .foregroundColor(.vmTextTertiary)
        }
        .padding(VMDesignTokens.Spacing.md)
        .background(Color.vmSurface)
        .cornerRadius(VMDesignTokens.CornerRadius.small)
    }
}
