import ComposableArchitecture
import Domain
import FeatureSearch
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
            memoListContent
                .background(Color.vmBackground)
                .navigationTitle("メモ")
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
                    item: $store.scope(state: \.searchState, action: \.search)
                ) { (searchStore: StoreOf<SearchReducer>) in
                    SearchView(store: searchStore)
                        .navigationTitle("検索")
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

    private var toolbarButtons: some View {
        HStack(spacing: VMDesignTokens.Spacing.lg) {
            Button { store.send(.trendIconTapped) } label: {
                Image(systemName: "chart.line.uptrend.xyaxis")
            }
            Button { store.send(.searchIconTapped) } label: {
                Image(systemName: "magnifyingglass")
            }
        }
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
