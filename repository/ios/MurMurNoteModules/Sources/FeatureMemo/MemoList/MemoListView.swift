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
        }
        .onAppear {
            store.send(.onAppear)
        }
    }

    // MARK: - Sub Views

    private var memoListContent: some View {
        ScrollView {
            LazyVStack(spacing: VMDesignTokens.Spacing.md, pinnedViews: [.sectionHeaders]) {
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
                    ProgressView()
                        .padding()
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
    }

    /// FTS5スニペットの <mark> タグをパースし、ヒット箇所を強調表示する
    static func highlightedText(_ snippet: String) -> Text {
        var result = Text("")
        var remaining = snippet
        while let openRange = remaining.range(of: "<mark>") {
            // <mark> の前のテキスト
            let before = String(remaining[remaining.startIndex..<openRange.lowerBound])
            if !before.isEmpty {
                result = result + Text(before).foregroundColor(.vmTextSecondary)
            }
            remaining = String(remaining[openRange.upperBound...])
            // </mark> を探す
            if let closeRange = remaining.range(of: "</mark>") {
                let highlighted = String(remaining[remaining.startIndex..<closeRange.lowerBound])
                result = result + Text(highlighted).bold().foregroundColor(.vmPrimary)
                remaining = String(remaining[closeRange.upperBound...])
            }
        }
        // 残りのテキスト
        if !remaining.isEmpty {
            result = result + Text(remaining).foregroundColor(.vmTextSecondary)
        }
        return result
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/M/d HH:mm"
        return formatter.string(from: item.createdAt)
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
