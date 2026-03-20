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
            .background(Color.vmBackground)
            .navigationTitle("メモ")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: VMDesignTokens.Spacing.lg) {
                        Button { store.send(.trendIconTapped) } label: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                        }
                        Button { store.send(.searchIconTapped) } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: VMDesignTokens.Spacing.lg) {
                        Button { store.send(.trendIconTapped) } label: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                        }
                        Button { store.send(.searchIconTapped) } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
                #endif
            }
            .refreshable {
                store.send(.refreshRequested)
            }
        }
        .onAppear {
            store.send(.onAppear)
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
