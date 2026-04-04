import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI

/// きおくに聞く（AI対話）画面
/// TASK-0041: AI対話機能（REQ-031 / US-309 / AC-309）
/// 設計書 04-ui-design-system.md 準拠
public struct ChatView: View {
    @Bindable public var store: StoreOf<ChatReducer>

    public init(store: StoreOf<ChatReducer>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            if !store.isPro {
                proRequiredContent
            } else if store.memoCount < ChatReducer.minimumMemoCount {
                emptyStateContent
            } else {
                chatContent
            }
        }
        .background(Color.vmBackground)
        .navigationTitle("きおくに聞く")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { chatToolbarContent }
        .onAppear { store.send(.onAppear) }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var chatToolbarContent: some ToolbarContent {
        if !store.messages.isEmpty {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                clearButton
            }
            #else
            ToolbarItem(placement: .automatic) {
                clearButton
            }
            #endif
        }
    }

    private var clearButton: some View {
        Button {
            store.send(.clearConversation)
        } label: {
            Image(systemName: "trash")
                .foregroundColor(.vmTextSecondary)
        }
        .accessibilityLabel("会話をクリア")
    }

    // MARK: - Chat Content

    private var chatContent: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: VMDesignTokens.Spacing.md) {
                        if store.messages.isEmpty {
                            suggestionsView
                                .padding(.top, VMDesignTokens.Spacing.xxxl)
                        }

                        ForEach(store.messages) { message in
                            ChatBubble(message: message, referencedMemoTitles: store.referencedMemoTitles) { memoID in
                                store.send(.referencedMemoTapped(memoID))
                            }
                            .id(message.id)
                        }

                        if store.isStreaming {
                            streamingIndicator
                        }
                    }
                    .padding(.horizontal, VMDesignTokens.Spacing.lg)
                    .padding(.vertical, VMDesignTokens.Spacing.md)
                }
                .onChange(of: store.messages.count) { _, _ in
                    if let lastMessage = store.messages.last {
                        withAnimation(.easeOut(duration: VMDesignTokens.Duration.normal)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            if let errorMessage = store.errorMessage {
                errorBanner(errorMessage)
            }

            inputBar
        }
    }

    // MARK: - Suggestions

    private var suggestionsView: some View {
        VStack(spacing: VMDesignTokens.Spacing.lg) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(.vmPrimary)

            Text("きおくに聞いてみよう")
                .font(.vmTitle3)
                .foregroundColor(.vmTextPrimary)

            Text("蓄積されたきおくをもとに、AIがあなたの質問に答えます")
                .font(.vmCallout)
                .foregroundColor(.vmTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(VMDesignTokens.LineSpacing.body)

            VStack(spacing: VMDesignTokens.Spacing.sm) {
                ForEach(ChatReducer.suggestions, id: \.self) { suggestion in
                    Button {
                        store.send(.suggestionTapped(suggestion))
                    } label: {
                        HStack {
                            Text(suggestion)
                                .font(.vmCallout)
                                .foregroundColor(.vmTextPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(.vmPrimary)
                        }
                        .padding(.horizontal, VMDesignTokens.Spacing.lg)
                        .padding(.vertical, VMDesignTokens.Spacing.md)
                        .background(Color.vmSurface)
                        .cornerRadius(VMDesignTokens.CornerRadius.medium)
                    }
                }
            }
            .padding(.top, VMDesignTokens.Spacing.sm)
        }
        .padding(.horizontal, VMDesignTokens.Spacing.lg)
    }

    // MARK: - Streaming Indicator

    private var streamingIndicator: some View {
        HStack(spacing: VMDesignTokens.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.vmCaption1)
                .foregroundColor(.vmPrimary)

            Text("考え中...")
                .font(.vmCallout)
                .foregroundColor(.vmTextSecondary)

            Spacer()
        }
        .padding(.horizontal, VMDesignTokens.Spacing.lg)
        .padding(.vertical, VMDesignTokens.Spacing.sm)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: VMDesignTokens.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.vmError)
            Text("うまくいきませんでした。もう一度お試しください")
                .font(.vmCaption1)
                .foregroundColor(.vmError)
            Spacer()
            Button { store.send(.dismissError) } label: {
                Image(systemName: "xmark")
                    .font(.vmCaption2)
                    .foregroundColor(.vmTextTertiary)
            }
            .accessibilityLabel("エラーを閉じる")
        }
        .padding(.horizontal, VMDesignTokens.Spacing.lg)
        .padding(.vertical, VMDesignTokens.Spacing.sm)
        .background(Color.vmError.opacity(0.1))
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
                .foregroundColor(.vmDivider)

            if store.isStreaming {
                // ストリーミング中は停止ボタン
                Button {
                    store.send(.stopGenerationTapped)
                } label: {
                    HStack(spacing: VMDesignTokens.Spacing.sm) {
                        Image(systemName: "stop.fill")
                            .font(.vmCaption1)
                        Text("生成を止める")
                            .font(.vmCallout)
                    }
                    .foregroundColor(.vmError)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, VMDesignTokens.Spacing.md)
                }
            } else {
                // 通常の入力エリア
                HStack(spacing: VMDesignTokens.Spacing.sm) {
                    TextField("きおくについて聞く...", text: $store.inputText.sending(\.inputTextChanged))
                        .font(.vmCallout)
                        .padding(.horizontal, VMDesignTokens.Spacing.md)
                        .padding(.vertical, VMDesignTokens.Spacing.sm)
                        .background(Color.vmSurfaceVariant)
                        .cornerRadius(VMDesignTokens.CornerRadius.small)
                        .submitLabel(.send)
                        .onSubmit {
                            store.send(.sendButtonTapped)
                        }

                    Button {
                        store.send(.sendButtonTapped)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(
                                store.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? .vmTextTertiary
                                    : .vmPrimary
                            )
                    }
                    .disabled(store.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("送信")
                }
                .padding(.horizontal, VMDesignTokens.Spacing.lg)
                .padding(.vertical, VMDesignTokens.Spacing.sm)
            }
        }
        .background(Color.vmSurface)
    }

    // MARK: - Empty State (メモ3件未満)

    private var emptyStateContent: some View {
        VStack(spacing: VMDesignTokens.Spacing.lg) {
            Spacer()

            Image(systemName: "text.bubble")
                .font(.system(size: 48))
                .foregroundColor(.vmTextTertiary)

            Text("きおくを増やしてから使えます")
                .font(.vmTitle3)
                .foregroundColor(.vmTextPrimary)

            Text("3件以上のきおくが必要です\n（現在\(store.memoCount)件）")
                .font(.vmCallout)
                .foregroundColor(.vmTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(VMDesignTokens.LineSpacing.body)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pro Required

    private var proRequiredContent: some View {
        VStack(spacing: VMDesignTokens.Spacing.lg) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.vmPrimary)

            Text("きおくに聞くはProプランの機能です")
                .font(.vmTitle3)
                .foregroundColor(.vmTextPrimary)

            Text("蓄積されたきおくにAIで質問できます。\n「先週何に悩んでた？」と自分と対話してみましょう")
                .font(.vmCallout)
                .foregroundColor(.vmTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(VMDesignTokens.LineSpacing.body)

            Button {
                store.send(.showProPlanTapped)
            } label: {
                Text("Proプランを見てみる")
                    .font(.vmHeadline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, VMDesignTokens.Spacing.md)
                    .background(Color.vmPrimary)
                    .cornerRadius(VMDesignTokens.CornerRadius.medium)
            }
            .padding(.horizontal, VMDesignTokens.Spacing.xxl)
            .accessibilityHint("Proプランの詳細画面に移動します")

            Button {
                store.send(.dismissProSheet)
            } label: {
                Text("あとで")
                    .font(.vmCallout)
                    .foregroundColor(.vmTextTertiary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Chat Bubble

/// チャットバブルコンポーネント
struct ChatBubble: View {
    let message: ChatMessage
    let referencedMemoTitles: [UUID: String]
    let onReferencedMemoTapped: (UUID) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: VMDesignTokens.Spacing.sm) {
            if message.role == .user {
                Spacer(minLength: VMDesignTokens.Spacing.xxxl)
            }

            if message.role == .assistant {
                // AIアイコン
                Image(systemName: "sparkles")
                    .font(.vmCaption1)
                    .foregroundColor(.vmPrimary)
                    .frame(width: 24, height: 24)
                    .padding(.top, VMDesignTokens.Spacing.xs)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: VMDesignTokens.Spacing.sm) {
                // メッセージテキスト
                Text(message.text)
                    .font(.vmCallout)
                    .foregroundColor(.vmTextPrimary)
                    .lineSpacing(VMDesignTokens.LineSpacing.body)
                    .padding(.horizontal, VMDesignTokens.Spacing.lg)
                    .padding(.vertical, VMDesignTokens.Spacing.md)
                    .background(bubbleBackground)
                    .cornerRadius(VMDesignTokens.CornerRadius.medium)

                // 参照きおくカード
                if !message.referencedMemoIDs.isEmpty {
                    referencedMemosView
                }
            }

            if message.role == .assistant {
                Spacer(minLength: VMDesignTokens.Spacing.xxxl)
            }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            Color.vmPrimaryLight.opacity(0.2)
        } else {
            // AI: SurfaceVariant + Primary 3pt 左ボーダー
            Color.vmSurfaceVariant
                .overlay(alignment: .leading) {
                    Color.vmPrimary
                        .frame(width: 3)
                }
        }
    }

    private var referencedMemosView: some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.xs) {
            Text("参照したきおく")
                .font(.vmCaption1)
                .foregroundColor(.vmTextTertiary)

            ForEach(message.referencedMemoIDs, id: \.self) { memoID in
                Button {
                    onReferencedMemoTapped(memoID)
                } label: {
                    HStack(spacing: VMDesignTokens.Spacing.sm) {
                        Image(systemName: "doc.text")
                            .font(.vmCaption1)
                            .foregroundColor(.vmPrimary)
                        Text(referencedMemoTitles[memoID] ?? "きおく")
                            .font(.vmCaption1)
                            .foregroundColor(.vmPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.vmCaption2)
                            .foregroundColor(.vmTextTertiary)
                    }
                    .padding(.horizontal, VMDesignTokens.Spacing.md)
                    .padding(.vertical, VMDesignTokens.Spacing.sm)
                    .background(Color.vmSurface)
                    .cornerRadius(VMDesignTokens.CornerRadius.small)
                }
            }
        }
    }
}
