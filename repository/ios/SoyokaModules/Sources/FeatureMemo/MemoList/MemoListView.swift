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
            mainContent
                .background(Color.vmBackground)
                .navigationTitle("きおく")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
                .searchable(
                    text: $store.search.query.sending(\.searchQueryChanged),
                    prompt: "きおくを検索..."
                )
                .toolbar { toolbarContent }
                .refreshable { store.send(.refreshRequested) }
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
                .sheet(
                    item: $store.scope(state: \.weeklyReportState, action: \.weeklyReport)
                ) { reportStore in
                    NavigationStack {
                        WeeklyReportView(store: reportStore)
                    }
                }
                .navigationDestination(
                    item: $store.scope(state: \.chatState, action: \.chat)
                ) { (chatStore: StoreOf<ChatReducer>) in
                    ChatView(store: chatStore)
                }
                .overlay(alignment: .bottom) { undoSnackbar }
                .alert(
                    "AI整理を実行できませんでした",
                    isPresented: $store.showQuotaExceededAlert.sending(\.quotaExceededAlertPresented)
                ) {
                    Button("閉じる", role: .cancel) {
                        store.send(.quotaExceededAlertPresented(false))
                    }
                    Button("Proを見る") {
                        store.send(.showProPlanTapped)
                    }
                } message: {
                    Text("しばらく時間をおいて、もう一度お試しください")
                }
                .alert(
                    "Proプランの機能です",
                    isPresented: $store.showProRequiredAlert.sending(\.proRequiredAlertPresented)
                ) {
                    Button("あとで", role: .cancel) {
                        store.send(.proRequiredAlertPresented(false))
                    }
                    Button("Proを見る") {
                        store.send(.proRequiredAlertPresented(false))
                        // Phase 3c: ここでサブスクリプション画面に遷移
                    }
                } message: {
                    Text("この機能はProプランでご利用いただけます")
                }
        }
        .onAppear { store.send(.onAppear) }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        Group {
            if store.search.isActive {
                searchResultsContent
            } else {
                memoListContent
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarTrailing) { toolbarButtons }
        #else
        ToolbarItem(placement: .automatic) { toolbarButtons }
        #endif
    }

    // MARK: - Undo Snackbar

    @ViewBuilder
    private var undoSnackbar: some View {
        if store.deletion.showUndoSnackbar,
           let deleted = store.deletion.recentlyDeletedMemo {
            HStack {
                Text("「\(deleted.title)」を削除しました")
                    .font(.vmCallout)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                Button("元に戻す") {
                    store.send(.undoDeleteTapped)
                }
                .font(.vmHeadline)
                .foregroundColor(.vmPrimary)
            }
            .padding(.horizontal, VMDesignTokens.Spacing.lg)
            .padding(.vertical, VMDesignTokens.Spacing.md)
            .background(Color.vmSurface.opacity(0.95))
            .cornerRadius(VMDesignTokens.CornerRadius.medium)
            .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
            .padding(.horizontal, VMDesignTokens.Spacing.lg)
            .padding(.bottom, VMDesignTokens.Spacing.lg)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.3), value: store.deletion.showUndoSnackbar)
        }
    }

    // MARK: - Sub Views

    private var memoListContent: some View {
        Group {
            if store.memos.isEmpty && !store.isLoading {
                // 空状態ビュー
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "plus.bubble.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.vmTextTertiary)
                    Text("きおくがありません")
                        .font(.vmTitle3)
                        .foregroundColor(.vmTextPrimary)
                    Text("つぶやきタブできおくを作成しましょう")
                        .font(.vmSubheadline)
                        .foregroundColor(.vmTextSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: VMDesignTokens.Spacing.md, pinnedViews: [.sectionHeaders]) {
                        // ローカルAI無制限化に伴い、月次クォータ表示を非表示
                        // クラウドAI（Pro専用）のクォータは別途Pro設定画面で確認する想定
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
                            ProgressView("きおくを読み込み中...")
                                .padding()
                        }
                    }
                }
            }
        }
    }

    private var searchResultsContent: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: VMDesignTokens.Spacing.md) {
                    if store.search.results.isEmpty && !store.search.isSearching {
                        Text("検索結果がありません")
                            .font(.vmCallout)
                            .foregroundColor(.vmTextSecondary)
                            .padding(.top, VMDesignTokens.Spacing.xxxl)
                    } else {
                        ForEach(store.search.results) { result in
                            SearchResultCard(item: result)
                                .onTapGesture {
                                    store.send(.memoTapped(id: result.id))
                                }
                                .padding(.horizontal, VMDesignTokens.Spacing.lg)
                        }
                    }
                }
            }
            .opacity(store.search.isSearching ? 0.5 : 1.0)

            if store.search.isSearching {
                VStack {
                    ProgressView()
                        .tint(.vmPrimary)
                        .padding(.top, VMDesignTokens.Spacing.xxxl)
                    Spacer()
                }
            }
        }
    }

    private var toolbarButtons: some View {
        HStack(spacing: VMDesignTokens.Spacing.md) {
            Button { store.send(.chatIconTapped) } label: {
                Image(systemName: "bubble.left.and.text.bubble.right")
            }
            .accessibilityLabel("きおくに聞く")
            Button { store.send(.weeklyReportTapped) } label: {
                Image(systemName: "doc.text.magnifyingglass")
            }
            Button { store.send(.trendIconTapped) } label: {
                Image(systemName: "chart.line.uptrend.xyaxis")
            }
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

/// AI整理の利用状況表示バー（Pro専用クラウドAI向け）
/// ローカルAIは無制限のため、通常は非表示
struct AIQuotaProgressBar: View {
    let used: Int
    let limit: Int
    let nextResetDate: Date?

    private var progress: Double {
        guard limit > 0 else { return 0 }
        return min(Double(used) / Double(limit), 1.0)
    }

    private var remaining: Int {
        max(limit - used, 0)
    }

    private var isExceeded: Bool {
        used >= limit
    }

    private var tintColor: Color {
        isExceeded ? .vmError : .vmWarning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.xs) {
            HStack {
                Text("AI整理 \(used)回利用")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextSecondary)
                Spacer()
                Text("\(used)/\(limit)")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)
            }
            ProgressView(value: progress)
                .tint(tintColor)
        }
        .padding(.vertical, VMDesignTokens.Spacing.sm)
        .padding(.horizontal, VMDesignTokens.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI整理の利用状況: \(limit)回中\(used)回使用")
    }
}
