import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI

/// メモ一覧画面
/// TASK-0011: メモ一覧画面
/// 設計書 04-ui-design-system.md セクション6.2 準拠
public struct MemoListView: View {
    @Bindable public var store: StoreOf<MemoListReducer>

    public init(store: StoreOf<MemoListReducer>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Group {
                if store.isSearchActive {
                    searchResultsContent
                } else {
                    memoListContent
                }
            }
            .background(Color.vmBackground)
            .navigationTitle("メモ")
            .searchable(
                text: $store.searchQuery.sending(\.searchQueryChanged),
                prompt: "メモを検索..."
            )
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    toolbarButtons
                }
                #else
                ToolbarItem(placement: .automatic) {
                    toolbarButtons
                }
                #endif
            }
            .refreshable {
                store.send(.refreshRequested)
            }
            .navigationDestination(
                item: $store.scope(state: \.selectedMemo, action: \.memoDetail)
            ) { (detailStore: StoreOf<MemoDetailReducer>) in
                MemoDetailView(store: detailStore)
            }
            .navigationDestination(
                item: $store.scope(state: \.emotionTrendState, action: \.emotionTrend)
            ) { (emotionTrendStore: StoreOf<EmotionTrendReducer>) in
                EmotionTrendView(store: emotionTrendStore)
            }
            // スワイプ削除確認ダイアログ
            .alert(
                "メモを削除",
                isPresented: $store.showDeleteConfirmation.sending(\.deleteConfirmationPresented)
            ) {
                Button("削除", role: .destructive) {
                    store.send(.confirmDelete)
                }
                Button("キャンセル", role: .cancel) {
                    store.send(.deleteCancelled)
                }
            } message: {
                Text("このメモを完全に削除しますか？\nこの操作は取り消せません。")
            }
        }
        .onAppear {
            store.send(.onAppear)
        }
    }

    // MARK: - Sub Views

    private var memoListContent: some View {
        Group {
            if store.memos.isEmpty && !store.isLoading {
                // 空状態ビュー
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "mic.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.vmTextTertiary)
                    Text("メモがありません")
                        .font(.vmTitle3)
                        .foregroundColor(.vmTextPrimary)
                    Text("録音タブでメモを作成しましょう")
                        .font(.vmSubheadline)
                        .foregroundColor(.vmTextSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: VMDesignTokens.Spacing.md, pinnedViews: [.sectionHeaders]) {
                        // AI分析クォータ表示（Phase 3 UXレビュー）
                        AIQuotaProgressBar(
                            used: store.aiQuotaUsed,
                            limit: store.aiQuotaLimit,
                            nextResetDate: store.nextResetDate
                        )
                        .padding(.horizontal, VMDesignTokens.Spacing.lg)
                        .padding(.bottom, VMDesignTokens.Spacing.sm)
                        ForEach(store.sections) { section in
                            Section {
                                ForEach(section.memoIDs, id: \.self) { memoID in
                                    if let memo = store.memos[id: memoID] {
                                        MemoCard(data: memo.cardData)
                                            .onTapGesture {
                                                store.send(.memoTapped(id: memoID))
                                            }
                                            .swipeActions(edge: .trailing) {
                                                Button(role: .destructive) {
                                                    store.send(.swipeToDelete(id: memoID))
                                                } label: {
                                                    Label("削除", systemImage: "trash")
                                                }
                                            }
                                            .padding(.horizontal, VMDesignTokens.Spacing.lg)
                                    }
                                }

                                // ページネーション: 最後のセクションでトリガー
                                if section.id == store.sections.last?.id,
                                   store.hasMorePages {
                                    Color.clear
                                        .frame(height: 1)
                                        .onAppear {
                                            store.send(.loadNextPage)
                                        }
                                }
                            } header: {
                                SectionHeader(label: section.label)
                            }
                        }

                        if store.isLoading {
                            ProgressView("メモを読み込み中...")
                                .padding()
                        }
                    }
                }
            }
        }
    }

    private var searchResultsContent: some View {
        ScrollView {
            LazyVStack(spacing: VMDesignTokens.Spacing.md) {
                if store.isSearching {
                    ProgressView("検索中...")
                        .padding()
                } else if store.searchResults.isEmpty {
                    Text("検索結果がありません")
                        .font(.vmCallout)
                        .foregroundColor(.vmTextSecondary)
                        .padding(.top, VMDesignTokens.Spacing.xxxl)
                } else {
                    ForEach(store.searchResults) { result in
                        SearchResultCard(item: result)
                            .onTapGesture {
                                store.send(.memoTapped(id: result.id))
                            }
                            .padding(.horizontal, VMDesignTokens.Spacing.lg)
                    }
                }
            }
        }
    }

    private var toolbarButtons: some View {
        Button { store.send(.trendIconTapped) } label: {
            Image(systemName: "chart.line.uptrend.xyaxis")
        }
    }
}

// MARK: - SearchResultCard

/// 検索結果アイテムのカード表示
struct SearchResultCard: View {
    let item: MemoListReducer.SearchResultItem

    var body: some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.sm) {
            Text(item.title)
                .font(.vmHeadline)
                .foregroundColor(.vmTextPrimary)
                .lineLimit(1)

            Self.highlightedText(item.snippet)
                .font(.vmCallout)
                .lineLimit(2)

            // タグ表示（最大3件）
            if !item.tags.isEmpty {
                HStack(spacing: VMDesignTokens.Spacing.xs) {
                    ForEach(item.tags.prefix(3), id: \.self) { tag in
                        TagChip(text: tag)
                    }
                }
            }

            HStack {
                Text(formattedDate)
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)

                Spacer()

                if let emotion = item.emotion {
                    EmotionBadge(emotion: emotion)
                }
            }
        }
        .padding(VMDesignTokens.Spacing.lg)
        .background(Color.vmSurface)
        .cornerRadius(VMDesignTokens.CornerRadius.medium)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(formattedDate)")
    }

    /// FTS5スニペットの <mark> タグをパースし、セグメント配列に分解する
    /// View側でText構築に使用（文字列生成コストを削減）
    static func parseSnippet(_ snippet: String) -> [(text: String, isHighlighted: Bool)] {
        var segments: [(text: String, isHighlighted: Bool)] = []
        var remaining = snippet
        while let openRange = remaining.range(of: "<mark>") {
            let before = String(remaining[remaining.startIndex..<openRange.lowerBound])
            if !before.isEmpty {
                segments.append((text: before, isHighlighted: false))
            }
            remaining = String(remaining[openRange.upperBound...])
            if let closeRange = remaining.range(of: "</mark>") {
                let highlighted = String(remaining[remaining.startIndex..<closeRange.lowerBound])
                segments.append((text: highlighted, isHighlighted: true))
                remaining = String(remaining[closeRange.upperBound...])
            }
        }
        if !remaining.isEmpty {
            segments.append((text: remaining, isHighlighted: false))
        }
        return segments
    }

    /// FTS5スニペットの <mark> タグをパースし、ヒット箇所を強調表示する
    static func highlightedText(_ snippet: String) -> Text {
        let segments = parseSnippet(snippet)
        var result = Text("")
        for segment in segments {
            if segment.isHighlighted {
                result = result + Text(segment.text).bold().foregroundColor(.vmPrimary)
            } else {
                result = result + Text(segment.text).foregroundColor(.vmTextSecondary)
            }
        }
        return result
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/M/d HH:mm"
        return formatter
    }()

    private var formattedDate: String {
        Self.dateFormatter.string(from: item.createdAt)
    }
}

/// 日付セクションヘッダー
struct SectionHeader: View {
    let label: String

    var body: some View {
        HStack {
            Text(label)
                .font(.vmSubheadline)
                .foregroundColor(.vmTextSecondary)
            Spacer()
        }
        .padding(.horizontal, VMDesignTokens.Spacing.lg)
        .padding(.vertical, VMDesignTokens.Spacing.sm)
        .background(Color.vmBackground)
    }
}

/// AI分析クォータ表示バー（Phase 3 UXレビュー）
/// メモ一覧上部に月間使用回数を表示
struct AIQuotaProgressBar: View {
    let used: Int
    let limit: Int
    let nextResetDate: Date?

    private var progress: Double {
        guard limit > 0 else { return 0 }
        return min(Double(used) / Double(limit), 1.0)
    }

    private var isNearLimit: Bool {
        guard limit > 0 else { return false }
        return Double(used) / Double(limit) >= 0.8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.xs) {
            HStack {
                Label("AI分析", systemImage: "sparkles")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextSecondary)
                Spacer()
                Text("\(used) / \(limit) 回")
                    .font(.vmCaption1)
                    .foregroundColor(isNearLimit ? .vmWarning : .vmTextTertiary)
            }
            ProgressView(value: progress)
                .tint(isNearLimit ? .vmWarning : .vmPrimary)
            if let nextResetDate {
                Text("リセット: \(Self.dateFormatter.string(from: nextResetDate))")
                    .font(.system(size: 10))
                    .foregroundColor(.vmTextTertiary)
            }
        }
        .padding(VMDesignTokens.Spacing.md)
        .background(Color.vmSurface)
        .cornerRadius(VMDesignTokens.CornerRadius.small)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}
