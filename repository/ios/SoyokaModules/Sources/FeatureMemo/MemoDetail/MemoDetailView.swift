import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI

/// メモ詳細画面
/// ミニマルデザイン: 必要最小限の情報のみ表示、余白を活かしたシンプルなレイアウト
public struct MemoDetailView: View {
    @Bindable public var store: StoreOf<MemoDetailReducer>

    public init(store: StoreOf<MemoDetailReducer>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.lg) {
                if store.isLoading {
                    ProgressView("きおくを読み込み中...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    // タイトル
                    Text(store.title)
                        .font(.vmTitle2)
                        .foregroundColor(.vmTextPrimary)

                    // メタ情報（プレーンテキスト）
                    MetaInfoRow(
                        date: store.createdAt,
                        duration: store.durationSeconds
                    )

                    // AI処理中: 美しいアニメーション表示
                    if isAIProcessing(store.aiProcessingStatus) && store.aiSummary == nil {
                        AIProcessingAnimationView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, VMDesignTokens.Spacing.xxl)
                            .transition(.opacity)
                    }
                    // AI要約セクション（シンプル版）— 処理中でなければ表示
                    else {
                        AISummarySection(
                            summary: store.aiSummary,
                            aiProcessingStatus: store.aiProcessingStatus,
                            isExpanded: store.isSummaryExpanded,
                            remainingQuota: store.remainingQuota,
                            onToggleExpand: { store.send(.toggleSummaryExpanded) },
                            onRegenerate: { store.send(.regenerateAISummary) },
                            onTriggerAI: { store.send(.triggerAIProcessing) }
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(store.aiSummary?.summaryText ?? "AI整理待機中")
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    // AIフィードバックボタン（AI整理結果がある場合のみ表示）
                    if store.aiSummary != nil {
                        AISummaryFeedbackRow(
                            feedback: store.aiFeedback,
                            onPositive: { store.send(.aiFeedbackTapped(isPositive: true)) },
                            onNegative: { store.send(.aiFeedbackTapped(isPositive: false)) }
                        )
                    }

                    // AI処理失敗時のリトライ表示
                    AIProcessingStatusView(
                        status: store.aiProcessingStatus,
                        onRetry: { store.send(.regenerateAISummary) }
                    )

                    // 音声プレイヤー
                    if let audioPlayerStore = store.scope(
                        state: \.audioPlayer,
                        action: \.audioPlayer
                    ) {
                        AudioPlayerView(store: audioPlayerStore)
                    } else {
                        AudioPlayerPlaceholder()
                    }

                    // タグ（インラインテキスト表示）
                    if !store.tags.isEmpty {
                        SimpleTagRow(tags: store.tags) { tagName in
                            store.send(.tagTapped(tagName))
                        }
                    }

                    // 感情バッジ（感情分析結果がある場合のみ表示）
                    if let emotion = store.emotion {
                        EmotionBadge(emotion: emotion.category)
                    }

                    // MARK: - つながるきおく（TASK-0043）
                    // 常にセクションを表示し、Pro/Free・データ有無で内容を切り替え
                    if store.isPro {
                        if !store.relatedMemos.isEmpty {
                            // Pro + 関連あり: カード表示（現行通り）
                            RelatedMemosSection(
                                relatedMemos: store.relatedMemos,
                                onTap: { id in store.send(.relatedMemoTapped(id)) }
                            )
                        } else if !store.isLoadingRelated {
                            // Pro + 関連なし: エンプティステート
                            RelatedMemosEmptyState()
                        }
                    } else {
                        // Free: 機能の存在を見せる + アップグレード案内
                        RelatedMemosLockedSection(
                            previewMemo: store.relatedMemos.first,
                            onUpgrade: { store.send(.showProPlanTapped) }
                        )
                    }

                    // 文字起こし（折りたたみ、デフォルト非表示）
                    TranscriptionSection(text: store.transcriptionText)
                }
            }
            .padding(VMDesignTokens.Spacing.lg)
            .animation(.easeOut(duration: 0.5), value: isAIProcessing(store.aiProcessingStatus))
            .animation(.easeOut(duration: 0.5), value: store.aiSummary?.summaryText)
        }
        .background(Color.vmBackground)
        .overlay(alignment: .bottom) {
            if let recommendation = store.dictionaryRecommendation {
                DictionaryRecommendationBanner(
                    recommendation: recommendation,
                    onAccept: { store.send(.acceptDictionaryRecommendation(recommendation)) },
                    onDismiss: { store.send(.dismissDictionaryRecommendation(recommendation)) }
                )
                .padding(.horizontal, VMDesignTokens.Spacing.lg)
                .padding(.bottom, VMDesignTokens.Spacing.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: store.dictionaryRecommendation)
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                detailToolbarContent
            }
            #else
            ToolbarItem(placement: .automatic) {
                detailToolbarContent
            }
            #endif
        }
        .onAppear { store.send(.onAppear) }
        // 編集シート
        .sheet(
            isPresented: Binding(
                get: { store.editState != nil },
                set: { isPresented in
                    if !isPresented {
                        store.send(.dismissEditSheet)
                    }
                }
            )
        ) {
            if let editStore = store.scope(state: \.editState, action: \.edit) {
                NavigationStack {
                    MemoEditView(store: editStore)
                        .toolbar {
                            #if os(iOS)
                            ToolbarItem(placement: .topBarLeading) {
                                Button("閉じる") {
                                    store.send(.dismissEditSheet)
                                }
                            }
                            #endif
                        }
                }
            } else {
                // editState が nil の間（dismiss アニメーション中）の一時的な表示
                EmptyView()
            }
        }
        // 削除確認ダイアログ
        .alert(
            "きおくを削除",
            isPresented: Binding(
                get: { store.showDeleteConfirmation },
                set: { store.send(.deleteConfirmationPresented($0)) }
            )
        ) {
            Button("削除", role: .destructive) {
                store.send(.delete(.deleteConfirmed(id: store.memoID)))
            }
            Button("キャンセル", role: .cancel) {
                store.send(.delete(.deleteCancelled))
            }
        } message: {
            Text("このきおくを完全に削除しますか？\nこの操作は取り消せません。")
        }
        // AIオンボーディングシート（初回AI処理時に表示）
        .sheet(
            isPresented: Binding(
                get: { store.showAIOnboarding },
                set: { isPresented in
                    if !isPresented {
                        store.send(.aiOnboardingDismissed)
                    }
                }
            )
        ) {
            MemoDetailAIOnboardingSheet {
                store.send(.aiOnboardingDismissed)
            }
        }
    }

    /// AI処理が進行中かどうかを判定（processing / queued）
    private func isAIProcessing(_ status: AIProcessingStatus) -> Bool {
        switch status {
        case .processing, .queued:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    private var detailToolbarContent: some View {
        HStack(spacing: VMDesignTokens.Spacing.md) {
            Button { store.send(.editButtonTapped) } label: {
                Image(systemName: "pencil")
            }
            Menu {
                // 再生成をメニューに統合
                if store.aiSummary != nil {
                    Button { store.send(.regenerateAISummary) } label: {
                        Label("AI再生成", systemImage: "arrow.clockwise")
                    }
                }
                Button { store.send(.shareButtonTapped) } label: {
                    Label("共有", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    store.send(.deleteButtonTapped)
                } label: {
                    Label("削除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - つながるきおく サブビュー

    /// Pro + 関連なし: エンプティステート
    private var relatedMemosEmptyState: some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.md) {
            HStack {
                Image(systemName: "link")
                    .foregroundColor(.vmPrimary)
                Text("つながるきおく")
                    .font(.vmHeadline)
                    .foregroundColor(.vmTextPrimary)
            }

            HStack(spacing: VMDesignTokens.Spacing.md) {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 24))
                    .foregroundColor(.vmTextTertiary)
                Text("きおくが増えると、似たテーマのつぶやきが自動でつながります")
                    .font(.vmCallout)
                    .foregroundColor(.vmTextSecondary)
            }
            .padding(VMDesignTokens.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.vmSurfaceVariant.opacity(0.5))
            .cornerRadius(VMDesignTokens.CornerRadius.small)
        }
        .padding(VMDesignTokens.Spacing.lg)
        .background(Color.vmSurface)
        .cornerRadius(VMDesignTokens.CornerRadius.medium)
    }

    /// Free ユーザー用: 機能の存在を見せる + アップグレード案内
    private func relatedMemosLockedSection(previewMemo: RelatedMemo?, onUpgrade: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.md) {
            HStack {
                Image(systemName: "link")
                    .foregroundColor(.vmPrimary)
                Text("つながるきおく")
                    .font(.vmHeadline)
                    .foregroundColor(.vmTextPrimary)
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)
            }

            // プレビュー: 1件だけ見せる（あれば）
            if let memo = previewMemo {
                lockedPreviewCard(memo)
            }

            // アップグレード案内
            VStack(spacing: VMDesignTokens.Spacing.sm) {
                Text("Proプランで、似たテーマのきおくが自動でつながります")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextSecondary)
                    .multilineTextAlignment(.center)

                Button(action: onUpgrade) {
                    Text("Proプランを見てみる")
                        .font(.vmCaption1.bold())
                        .foregroundColor(.vmPrimary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, VMDesignTokens.Spacing.xs)
        }
        .padding(VMDesignTokens.Spacing.lg)
        .background(Color.vmSurface)
        .cornerRadius(VMDesignTokens.CornerRadius.medium)
    }

    /// Free ユーザー向けプレビューカード（半透明 + オーバーレイ）
    private func lockedPreviewCard(_ memo: RelatedMemo) -> some View {
        HStack(spacing: VMDesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.xxs) {
                Text(memo.title)
                    .font(.vmCallout)
                    .foregroundColor(.vmTextPrimary)
                    .lineLimit(1)

                HStack(spacing: VMDesignTokens.Spacing.sm) {
                    Text(memo.createdAt, style: .date)
                        .font(.vmCaption2)
                        .foregroundColor(.vmTextTertiary)

                    if let emotion = memo.emotion {
                        EmotionBadge(emotion: emotion)
                    }

                    ForEach(memo.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.vmCaption2)
                            .foregroundColor(.vmTextSecondary)
                            .padding(.horizontal, VMDesignTokens.Spacing.xs)
                            .padding(.vertical, VMDesignTokens.Spacing.xxs)
                            .background(Color.vmSurfaceVariant)
                            .cornerRadius(VMDesignTokens.CornerRadius.small)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.vmCaption1)
                .foregroundColor(.vmTextTertiary)
        }
        .padding(VMDesignTokens.Spacing.md)
        .background(Color.vmSurfaceVariant.opacity(0.5))
        .cornerRadius(VMDesignTokens.CornerRadius.small)
        .opacity(0.6)
        .overlay(
            Color.vmSurface.opacity(0.3)
        )
    }
}

// MARK: - EditSheet識別用ラッパー

/// sheet(item:) に渡すための Identifiable ラッパー
private struct EditSheetIdentifier: Identifiable {
    let id: UUID
    init(state: MemoEditReducer.State) {
        self.id = state.memoID
    }
}

// MARK: - Sub-components

/// メタ情報行（プレーンテキスト: 日付 · つぶやき時間）
struct MetaInfoRow: View {
    let date: Date
    let duration: Double

    var body: some View {
        Text("\(formattedDate) · \(formattedDuration)")
            .font(.vmCaption1)
            .foregroundColor(.vmTextTertiary)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    private var formattedDate: String {
        Self.dateFormatter.string(from: date)
    }

    private var formattedDuration: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes)分\(seconds)秒"
    }
}

/// シンプルなタグ行（インラインテキスト表示）
struct SimpleTagRow: View {
    let tags: [MemoDetailReducer.State.TagItem]
    let onTap: (String) -> Void

    var body: some View {
        HStack(spacing: VMDesignTokens.Spacing.sm) {
            ForEach(tags) { tag in
                Text("#\(tag.name)")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextSecondary)
                    .onTapGesture {
                        onTap(tag.name)
                    }
            }
        }
    }
}

/// 感情詳細カード（後方互換性のために残す — 詳細画面からは使用しない）
/// 設計書 04-ui-design-system.md セクション4.3 準拠
struct EmotionDetailCard: View {
    let emotion: MemoDetailReducer.State.EmotionState

    var body: some View {
        HStack(spacing: VMDesignTokens.Spacing.md) {
            Image(systemName: emotion.category.iconName)
                .font(.system(size: 24))
                .foregroundColor(emotion.category.color)

            VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.xs) {
                Text(emotion.category.label)
                    .font(.vmHeadline)
                    .foregroundColor(emotion.category.color)
                Text(emotion.emotionDescription)
                    .font(.vmCallout)
                    .foregroundColor(.vmTextSecondary)
            }
        }
        .padding(VMDesignTokens.Spacing.lg)
        .background(emotion.category.color.opacity(0.1))
        .cornerRadius(VMDesignTokens.CornerRadius.medium)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("感情: \(emotion.category.label), \(emotion.emotionDescription)")
    }
}

/// タグ横並びレイアウト（後方互換性のために残す）
struct TagFlowLayout: View {
    let tags: [MemoDetailReducer.State.TagItem]
    let onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VMDesignTokens.Spacing.sm) {
                ForEach(tags) { tag in
                    TagChip(text: tag.name)
                        .onTapGesture {
                            onTap(tag.name)
                        }
                }
            }
        }
    }
}

/// T10: タグアニメーション付き横並びレイアウト（後方互換性のために残す）
struct AnimatedTagFlowLayout: View {
    let tags: [MemoDetailReducer.State.TagItem]
    let onTap: (String) -> Void
    @State private var visibleTagCount: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VMDesignTokens.Spacing.sm) {
                ForEach(Array(tags.enumerated()), id: \.element.id) { index, tag in
                    tagView(for: tag)
                        .opacity(visibleTagCount > index ? 1 : 0)
                        .scaleEffect(visibleTagCount > index ? 1 : 0.5)
                        .offset(y: visibleTagCount > index ? 0 : 10)
                        .animation(
                            reduceMotion
                                ? .none
                                : .spring(response: 0.4, dampingFraction: 0.7)
                                    .delay(Double(index) * 0.3),
                            value: visibleTagCount
                        )
                        .onTapGesture {
                            onTap(tag.name)
                        }
                }
            }
        }
        .onAppear {
            if reduceMotion {
                visibleTagCount = tags.count
            } else {
                withAnimation {
                    visibleTagCount = tags.count
                }
            }
        }
        .onChange(of: tags.count) { _, newCount in
            if reduceMotion {
                visibleTagCount = newCount
            } else {
                withAnimation {
                    visibleTagCount = newCount
                }
            }
        }
    }

    @ViewBuilder
    private func tagView(for tag: MemoDetailReducer.State.TagItem) -> some View {
        if tag.source == "ai" {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                Text("#\(tag.name)")
            }
            .font(.vmCaption2)
            .foregroundColor(.vmSecondaryDark)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.vmAccentLight.opacity(0.5))
            .cornerRadius(VMDesignTokens.CornerRadius.small)
            .accessibilityLabel("AIが生成したタグ: \(tag.name)")
        } else {
            Text("#\(tag.name)")
                .font(.vmCaption2)
                .foregroundColor(.vmSecondaryDark)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.vmSurfaceVariant)
                .cornerRadius(VMDesignTokens.CornerRadius.small)
                .accessibilityLabel("タグ: \(tag.name)")
        }
    }
}

/// AI処理ステータスインジケーター（ミニマル版）
/// processing時のみ小さなインジケーター表示、completed/failedの大きなカードは削除
struct AIProcessingStatusView: View {
    let status: AIProcessingStatus
    let onRetry: () -> Void

    var body: some View {
        switch status {
        case .idle, .queued, .completed:
            EmptyView()

        case let .processing(_, description):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.vmTextTertiary)
                Text(description)
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)
            }

        case let .failed(error):
            HStack(spacing: 8) {
                Text(failedMessage(for: error))
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)
                Spacer()
                Button("リトライ") { onRetry() }
                    .font(.vmCaption1)
                    .foregroundColor(.vmPrimary)
            }
        }
    }

    private func failedMessage(for error: AIProcessingError) -> String {
        switch error {
        case .quotaExceeded(remaining: _, resetDate: _):
            return "AI整理を実行できませんでした"
        case .networkError(_):
            return "ネットワークエラー"
        case .processingFailed(_):
            return "AI整理に失敗しました"
        }
    }
}

/// AI要約セクション（ミニマル版）
/// ヘッダーのアイコン・バッジ削除、テキストのみ表示
struct AISummarySection: View {
    let summary: MemoDetailReducer.State.AISummaryState?
    var aiProcessingStatus: AIProcessingStatus = .idle
    var isExpanded: Bool = false
    var remainingQuota: Int = 10
    var onToggleExpand: (() -> Void)?
    var onRegenerate: (() -> Void)?
    var onTriggerAI: (() -> Void)?

    /// 折りたたみ表示時の最大行数
    private let collapsedLineLimit: Int = 3

    var body: some View {
        if let summary {
            summaryCard(summary: summary)
        } else {
            placeholderCard
        }
    }

    // MARK: - AI要約が存在する場合のカード

    private func summaryCard(summary: MemoDetailReducer.State.AISummaryState) -> some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.md) {
            // Markdown見出し（## ）をパースして構造化表示
            ForEach(Array(Self.parseStructuredText(summary.summaryText).enumerated()), id: \.offset) { _, block in
                if block.isHeading {
                    Text(block.text)
                        .font(.vmHeadline)
                        .foregroundColor(.vmTextPrimary)
                        .padding(.top, VMDesignTokens.Spacing.sm)
                } else {
                    Text(block.text)
                        .font(.vmBody())
                        .foregroundColor(.vmTextPrimary)
                        .lineSpacing(VMDesignTokens.LineSpacing.body)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary.summaryText)
    }

    /// Markdownの「## 見出し」をパースして構造化ブロックに分割
    private struct TextBlock {
        let text: String
        let isHeading: Bool
    }

    private static func parseStructuredText(_ text: String) -> [TextBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [TextBlock] = []
        var currentBody = ""

        for line in lines {
            if line.hasPrefix("## ") {
                // 溜まった本文を先に追加
                let trimmed = currentBody.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    blocks.append(TextBlock(text: trimmed, isHeading: false))
                }
                currentBody = ""
                // 見出しを追加
                let heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                blocks.append(TextBlock(text: heading, isHeading: true))
            } else {
                currentBody += (currentBody.isEmpty ? "" : "\n") + line
            }
        }

        // 残りの本文
        let trimmed = currentBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            blocks.append(TextBlock(text: trimmed, isHeading: false))
        }

        return blocks
    }

    // MARK: - AI整理の待機中プレースホルダ

    private var placeholderCard: some View {
        VStack(spacing: VMDesignTokens.Spacing.md) {
            // パルスアニメーション付きアイコン
            PulsingDotView()
                .frame(height: 32)

            Text("きおくを整理しています...")
                .font(.vmCallout)
                .foregroundColor(.vmTextTertiary)

            if let onTriggerAI {
                Button {
                    onTriggerAI()
                } label: {
                    Text("AI整理を実行する")
                        .font(.vmCallout)
                        .foregroundColor(.vmPrimary)
                }
                .accessibilityLabel("AI整理を実行する")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, VMDesignTokens.Spacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI整理待機中")
    }
}

/// AI整理結果のフィードバック行（控えめな表示）
/// UX原則: 操作を止めない。タップしたらすぐ反映、確認ダイアログなし
struct AISummaryFeedbackRow: View {
    let feedback: AIFeedback?
    let onPositive: () -> Void
    let onNegative: () -> Void

    var body: some View {
        HStack(spacing: VMDesignTokens.Spacing.lg) {
            Spacer()
            if let feedback {
                // フィードバック済み
                Text(feedback.isPositive ? "\u{1F44D}" : "\u{1F44E}")
                    .font(.system(size: 16))
                    .foregroundColor(.vmTextTertiary)
                    .accessibilityLabel(feedback.isPositive ? "高評価済み" : "低評価済み")
            } else {
                // 未フィードバック
                Button(action: onPositive) {
                    Text("\u{1F44D}")
                        .font(.system(size: 16))
                        .opacity(0.5)
                }
                .accessibilityLabel("AI整理を高評価する")
                Button(action: onNegative) {
                    Text("\u{1F44E}")
                        .font(.system(size: 16))
                        .opacity(0.5)
                }
                .accessibilityLabel("AI整理を低評価する")
            }
        }
        .padding(.top, VMDesignTokens.Spacing.xs)
    }
}

/// つながるきおく: Pro + 関連なし時のエンプティステート
struct RelatedMemosEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.md) {
            HStack {
                Image(systemName: "link")
                    .foregroundColor(.vmPrimary)
                Text("つながるきおく")
                    .font(.vmHeadline)
                    .foregroundColor(.vmTextPrimary)
            }

            HStack(spacing: VMDesignTokens.Spacing.md) {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 24))
                    .foregroundColor(.vmTextTertiary)
                Text("きおくが増えると、似たテーマのつぶやきが自動でつながります")
                    .font(.vmCallout)
                    .foregroundColor(.vmTextSecondary)
                    .lineSpacing(VMDesignTokens.LineSpacing.caption)
            }
            .padding(VMDesignTokens.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.vmSurfaceVariant.opacity(0.5))
            .cornerRadius(VMDesignTokens.CornerRadius.small)
        }
    }
}

/// つながるきおく: Free ユーザー用ロックセクション
struct RelatedMemosLockedSection: View {
    let previewMemo: RelatedMemo?
    let onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.md) {
            HStack {
                Image(systemName: "link")
                    .foregroundColor(.vmPrimary)
                Text("つながるきおく")
                    .font(.vmHeadline)
                    .foregroundColor(.vmTextPrimary)
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)
            }

            if let memo = previewMemo {
                previewCard(memo)
            }

            VStack(spacing: VMDesignTokens.Spacing.sm) {
                Text("Proプランで、似たテーマのきおくが自動でつながります")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(VMDesignTokens.LineSpacing.caption)

                Button(action: onUpgrade) {
                    Text("Proプランを見てみる")
                        .font(.vmCaption1.bold())
                        .foregroundColor(.vmPrimary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, VMDesignTokens.Spacing.xs)
        }
    }

    private func previewCard(_ memo: RelatedMemo) -> some View {
        HStack(spacing: VMDesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.xxs) {
                Text(memo.title)
                    .font(.vmCallout)
                    .foregroundColor(.vmTextTertiary)
                    .lineLimit(1)
                Text(memo.createdAt, style: .date)
                    .font(.vmCaption2)
                    .foregroundColor(.vmTextTertiary)
            }
            Spacer()
            Image(systemName: "lock.fill")
                .font(.vmCaption2)
                .foregroundColor(.vmTextTertiary)
        }
        .padding(VMDesignTokens.Spacing.md)
        .background(Color.vmSurfaceVariant.opacity(0.3))
        .cornerRadius(VMDesignTokens.CornerRadius.small)
    }
}

/// つながるきおくセクション（TASK-0043）
/// 関連メモを最大5件表示し、タップで該当メモへ遷移する
struct RelatedMemosSection: View {
    let relatedMemos: [RelatedMemo]
    let onTap: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.md) {
            HStack {
                Image(systemName: "link")
                    .foregroundColor(.vmPrimary)
                Text("つながるきおく")
                    .font(.vmHeadline)
                    .foregroundColor(.vmTextPrimary)
            }

            ForEach(relatedMemos.prefix(5)) { memo in
                Button {
                    onTap(memo.id)
                } label: {
                    relatedMemoCard(memo)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("つながるきおく")
    }

    private func relatedMemoCard(_ memo: RelatedMemo) -> some View {
        HStack(spacing: VMDesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.xxs) {
                Text(memo.title)
                    .font(.vmCallout)
                    .foregroundColor(.vmTextPrimary)
                    .lineLimit(1)

                HStack(spacing: VMDesignTokens.Spacing.sm) {
                    Text(memo.createdAt, style: .date)
                        .font(.vmCaption2)
                        .foregroundColor(.vmTextTertiary)

                    if let emotion = memo.emotion {
                        EmotionBadge(emotion: emotion)
                    }

                    ForEach(memo.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.vmCaption2)
                            .foregroundColor(.vmTextSecondary)
                            .padding(.horizontal, VMDesignTokens.Spacing.xs)
                            .padding(.vertical, VMDesignTokens.Spacing.xxs)
                            .background(Color.vmSurfaceVariant)
                            .cornerRadius(VMDesignTokens.CornerRadius.small)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.vmCaption1)
                .foregroundColor(.vmTextTertiary)
        }
        .padding(VMDesignTokens.Spacing.md)
        .background(Color.vmSurfaceVariant.opacity(0.5))
        .cornerRadius(VMDesignTokens.CornerRadius.small)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(memo.title)")
        .accessibilityHint("タップで詳細を表示")
    }
}

/// 文字起こしセクション（折りたたみ式、デフォルト非表示）
struct TranscriptionSection: View {
    let text: String
    @State private var isExpanded: Bool = false

    var body: some View {
        if !text.isEmpty {
            DisclosureGroup(
                isExpanded: $isExpanded
            ) {
                Text(text)
                    .font(.vmBody())
                    .foregroundColor(.vmTextPrimary)
                    .textSelection(.enabled)
                    .padding(.top, VMDesignTokens.Spacing.sm)
            } label: {
                Text("文字起こし（元のテキスト）")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)
            }
            .tint(.vmTextTertiary)
        }
    }
}

/// 音声プレイヤー プレースホルダ（AudioPlayerReducerが未初期化時に表示）
struct AudioPlayerPlaceholder: View {
    var body: some View {
        HStack {
            Image(systemName: "play.fill")
                .foregroundColor(.vmTextTertiary)
            ProgressView(value: 0, total: 1)
                .tint(.vmPrimary)
            Text("0:00 / 0:00")
                .font(.vmCaption1)
                .foregroundColor(.vmTextTertiary)
        }
        .padding(VMDesignTokens.Spacing.md)
        .background(Color.vmSurfaceVariant)
        .cornerRadius(VMDesignTokens.CornerRadius.small)
        .accessibilityLabel("音声再生（未実装）")
    }
}

/// プライバシーインジケーター（後方互換性のために残す — 詳細画面からは使用しない）
struct PrivacyIndicator: View {
    var body: some View {
        HStack(spacing: VMDesignTokens.Spacing.sm) {
            Image(systemName: "iphone")
                .foregroundColor(.vmTextTertiary)
            Text("このデバイスに保存")
                .font(.vmCaption1)
                .foregroundColor(.vmTextTertiary)
        }
        .padding(VMDesignTokens.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.vmSurfaceVariant)
        .cornerRadius(VMDesignTokens.CornerRadius.small)
    }
}

/// 初回AI処理時に表示する簡易オンボーディングシート
/// AIOnboardingView (FeatureAI) の store 依存を除去した MemoDetail 専用版
struct MemoDetailAIOnboardingSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: VMDesignTokens.Spacing.xl) {
            Spacer()

            // タイトル
            Text("AI整理について")
                .font(.vmTitle2)
                .foregroundColor(.vmTextPrimary)
                .multilineTextAlignment(.center)

            Divider()
                .padding(.horizontal, VMDesignTokens.Spacing.xxl)
                .accessibilityHidden(true)

            // 説明セクション
            VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.lg) {
                onboardingFeatureRow(
                    text: "話した内容を、読みやすい日記風の文章に整理します"
                )

                onboardingFeatureRow(
                    text: "あなたの言葉は、設定で選んだ処理方法に沿って大切に扱われます"
                )

                onboardingFeatureRow(
                    text: "AI整理は回数制限なく、いつでもご利用いただけます"
                )
            }
            .padding(.horizontal, VMDesignTokens.Spacing.xxl)

            Spacer()

            // CTAボタン
            Button {
                onDismiss()
            } label: {
                Text("はじめる")
                    .font(.vmHeadline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, VMDesignTokens.Spacing.md)
            }
            .background(Color.vmPrimaryDark)
            .cornerRadius(VMDesignTokens.CornerRadius.medium)
            .padding(.horizontal, VMDesignTokens.Spacing.xxl)
            .padding(.bottom, VMDesignTokens.Spacing.xxl)
        }
        .background(Color.vmBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI整理機能の説明")
    }

    private func onboardingFeatureRow(text: String) -> some View {
        Text(text)
            .font(.vmBody())
            .foregroundColor(.vmTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
