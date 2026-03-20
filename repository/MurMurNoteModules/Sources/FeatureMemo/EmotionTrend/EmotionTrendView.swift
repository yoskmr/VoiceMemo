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
                emotionListView
            }
        }
        .background(Color.vmBackground)
        .navigationTitle("感情トレンド")
        .onAppear {
            store.send(.onAppear)
        }
    }

    // MARK: - Sub Views

    /// ピリオド選択 Picker
    private var periodPicker: some View {
        Picker("期間", selection: $store.selectedPeriod.sending(\.periodChanged)) {
            ForEach(EmotionTrendReducer.Period.allCases, id: \.self) { period in
                Text(period.rawValue).tag(period)
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

            Text("録音にAI感情分析を適用すると、\nここに感情の推移が表示されます")
                .font(.vmSubheadline)
                .foregroundColor(.vmTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, VMDesignTokens.Spacing.xxl)

            Spacer()
        }
    }

    /// 感情データリスト
    private var emotionListView: some View {
        ScrollView {
            LazyVStack(spacing: VMDesignTokens.Spacing.sm) {
                ForEach(store.emotions) { entry in
                    emotionRow(entry)
                        .padding(.horizontal, VMDesignTokens.Spacing.lg)
                }
            }
            .padding(.vertical, VMDesignTokens.Spacing.sm)
        }
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
