import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI

/// メモ詳細画面
/// TASK-0012: メモ詳細画面
/// 設計書 04-ui-design-system.md セクション6.3 準拠
public struct MemoDetailView: View {
    @Bindable public var store: StoreOf<MemoDetailReducer>

    public init(store: StoreOf<MemoDetailReducer>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.lg) {
                if store.isLoading {
                    ProgressView("メモを読み込み中...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    // タイトル
                    Text(store.title)
                        .font(.vmTitle2)
                        .foregroundColor(.vmTextPrimary)

                    // AI要約カード（最上部に移動: UXレビュー指摘）
                    AISummarySection(
                        summary: store.aiSummary,
                        aiProcessingStatus: store.aiProcessingStatus
                    )

                    // AI処理ステータスインジケーター（詳細化: Phase 3 UXレビュー）
                    AIProcessingStatusView(
                        status: store.aiProcessingStatus,
                        onRetry: { store.send(.regenerateAISummary) }
                    )

                    // メタ情報
                    MetaInfoRow(
                        date: store.createdAt,
                        duration: store.durationSeconds
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

                    // 感情バッジ（大サイズ）
                    if let emotion = store.emotion {
                        EmotionDetailCard(emotion: emotion)
                    }

                    // タグ一覧
                    if !store.tags.isEmpty {
                        TagFlowLayout(tags: store.tags) { tagName in
                            store.send(.tagTapped(tagName))
                        }
                    }

                    // 文字起こしセクション
                    TranscriptionSection(text: store.transcriptionText)

                    // プライバシー表示
                    PrivacyIndicator()
                }
            }
            .padding(VMDesignTokens.Spacing.lg)
        }
        .background(Color.vmBackground)
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
            "メモを削除",
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
            Text("このメモを完全に削除しますか？\nこの操作は取り消せません。")
        }
    }

    private var detailToolbarContent: some View {
        HStack(spacing: VMDesignTokens.Spacing.md) {
            Button { store.send(.editButtonTapped) } label: {
                Image(systemName: "pencil")
            }
            Menu {
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

/// メタ情報行（日時 + 録音時間）
struct MetaInfoRow: View {
    let date: Date
    let duration: Double

    var body: some View {
        HStack(spacing: VMDesignTokens.Spacing.lg) {
            Label(formattedDate, systemImage: "calendar")
                .font(.vmCaption1)
                .foregroundColor(.vmTextSecondary)
            Label(formattedDuration, systemImage: "mic.fill")
                .font(.vmCaption1)
                .foregroundColor(.vmTextTertiary)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/M/d HH:mm"
        return formatter
    }()

    private var formattedDate: String {
        Self.dateFormatter.string(from: date)
    }

    private var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// 感情詳細カード（大サイズバッジ + 説明テキスト）
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

/// タグ横並びレイアウト
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

/// AI処理ステータスインジケーター（詳細化: Phase 3 UXレビュー）
/// processing: 進捗バー + 処理段階説明
/// completed: 処理場所バッジ
/// failed: エラー種別ごとのUI分岐
struct AIProcessingStatusView: View {
    let status: AIProcessingStatus
    let onRetry: () -> Void

    var body: some View {
        switch status {
        case .idle, .queued:
            EmptyView()

        case let .processing(progress, description):
            VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.sm) {
                HStack(spacing: 8) {
                    ProgressView().tint(.vmInfo)
                    Text("AI分析中...")
                        .font(.vmCallout)
                        .foregroundColor(.vmTextSecondary)
                }
                ProgressView(value: progress, total: 1.0)
                    .tint(.vmInfo)
                Text(description)
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.vmInfo.opacity(0.1))
            .cornerRadius(12)

        case let .completed(isOnDevice):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.vmSuccess)
                Text("AI分析完了")
                    .font(.vmCallout)
                    .foregroundColor(.vmTextSecondary)
                Spacer()
                Text(isOnDevice ? "オンデバイス" : "クラウド")
                    .font(.vmCaption1)
                    .foregroundColor(isOnDevice ? .vmSuccess : .vmInfo)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (isOnDevice ? Color.vmSuccess : Color.vmInfo).opacity(0.1)
                    )
                    .cornerRadius(8)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color.vmSuccess.opacity(0.05))
            .cornerRadius(12)

        case let .failed(error):
            switch error {
            case let .quotaExceeded(remaining: _, resetDate: resetDate):
                quotaExceededView(resetDate: resetDate)
            case let .networkError(message):
                networkErrorView(message: message)
            case .processingFailed:
                processingFailedView()
            }
        }
    }

    private func quotaExceededView(resetDate: Date) -> some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.vmWarning)
                Text("月間AI分析の上限に達しました")
                    .font(.vmCallout)
                    .foregroundColor(.vmTextPrimary)
            }
            Text("次回リセット: \(Self.dateFormatter.string(from: resetDate))")
                .font(.vmCaption1)
                .foregroundColor(.vmTextTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vmWarning.opacity(0.1))
        .cornerRadius(12)
    }

    private func networkErrorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .foregroundColor(.vmError)
                Text("ネットワークエラー")
                    .font(.vmCallout)
                    .foregroundColor(.vmTextPrimary)
            }
            Text(message)
                .font(.vmCaption1)
                .foregroundColor(.vmTextTertiary)
            Text("オンデバイスAIで再試行できます")
                .font(.vmCaption1)
                .foregroundColor(.vmInfo)
            Button {
                onRetry()
            } label: {
                Text("オンデバイスで再試行")
                    .font(.vmCaption1)
                    .foregroundColor(.vmPrimary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vmError.opacity(0.1))
        .cornerRadius(12)
    }

    private func processingFailedView() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.vmError)
            Text("AI分析に失敗しました")
                .font(.vmCallout)
                .foregroundColor(.vmTextSecondary)
            Spacer()
            Button("リトライ") { onRetry() }
                .font(.vmCaption1)
                .foregroundColor(.vmPrimary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.vmError.opacity(0.1))
        .cornerRadius(12)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}

/// AI要約セクション（Phase 3 で実体実装、枠のみ）
/// 設計書 04-ui-design-system.md セクション4.5 準拠
/// Phase 3 UXレビュー: completed時の処理場所バッジ対応
struct AISummarySection: View {
    let summary: MemoDetailReducer.State.AISummaryState?
    var aiProcessingStatus: AIProcessingStatus = .idle

    var body: some View {
        if let summary {
            VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.sm) {
                HStack {
                    Label("AI要約", systemImage: "sparkles")
                        .font(.vmHeadline)
                        .foregroundColor(.vmPrimary)
                    Spacer()
                    if case let .completed(isOnDevice) = aiProcessingStatus {
                        Text(isOnDevice ? "オンデバイス処理" : "クラウド処理")
                            .font(.vmCaption1)
                            .foregroundColor(isOnDevice ? .vmSuccess : .vmInfo)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                (isOnDevice ? Color.vmSuccess : Color.vmInfo).opacity(0.1)
                            )
                            .cornerRadius(8)
                    }
                }
                Text(summary.summaryText)
                    .font(.vmCallout)
                    .foregroundColor(.vmTextPrimary)
                if !summary.keyPoints.isEmpty {
                    ForEach(summary.keyPoints, id: \.self) { point in
                        HStack(alignment: .top, spacing: VMDesignTokens.Spacing.xs) {
                            Text("*")
                                .foregroundColor(.vmPrimary)
                            Text(point)
                                .font(.vmCallout)
                                .foregroundColor(.vmTextSecondary)
                        }
                    }
                }
            }
            .padding(VMDesignTokens.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.vmPrimaryLight.opacity(0.1))
            .overlay(
                Rectangle()
                    .fill(Color.vmPrimary)
                    .frame(width: 3),
                alignment: .leading
            )
            .cornerRadius(VMDesignTokens.CornerRadius.medium)
        } else {
            // プレースホルダ: AI要約未生成
            VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.sm) {
                Label("AI要約", systemImage: "sparkles")
                    .font(.vmHeadline)
                    .foregroundColor(.vmTextTertiary)
                Text("AI要約はまだ生成されていません")
                    .font(.vmCallout)
                    .foregroundColor(.vmTextTertiary)
            }
            .padding(VMDesignTokens.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.vmPrimaryLight.opacity(0.05))
            .overlay(
                Rectangle()
                    .fill(Color.vmTextTertiary.opacity(0.3))
                    .frame(width: 3),
                alignment: .leading
            )
            .cornerRadius(VMDesignTokens.CornerRadius.medium)
        }
    }
}

/// 文字起こしセクション
struct TranscriptionSection: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.sm) {
            Text("文字起こし")
                .font(.vmHeadline)
                .foregroundColor(.vmTextSecondary)

            Divider()
                .background(Color.vmDivider)
                .accessibilityHidden(true)

            Text(text)
                .font(.vmBody())
                .foregroundColor(.vmTextPrimary)
                .textSelection(.enabled)
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

/// プライバシーインジケーター
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
