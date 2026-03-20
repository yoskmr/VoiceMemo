import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI

/// 検索画面
/// TASK-0016: 検索UI画面
/// 設計書 04-ui-design-system.md セクション6.4 準拠
public struct SearchView: View {
    @Bindable var store: StoreOf<SearchReducer>

    public init(store: StoreOf<SearchReducer>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 検索バー
            searchBar
                .padding(.horizontal, VMDesignTokens.Spacing.lg)
                .padding(.vertical, VMDesignTokens.Spacing.sm)

            // フィルターパネル（展開時のみ）
            if store.showFilters {
                FilterPanel(store: store)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 検索結果
            if store.isInitialState {
                SearchHintView()
            } else if store.isSearching {
                Spacer()
                ProgressView()
                    .padding()
                Spacer()
            } else if store.results.isEmpty && !store.searchText.isEmpty {
                EmptySearchResultView(query: store.searchText)
            } else {
                // 検索結果カウント
                if store.resultCount > 0 {
                    HStack {
                        Text("\(store.resultCount)件の結果")
                            .font(.vmSubheadline)
                            .foregroundColor(.vmTextSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, VMDesignTokens.Spacing.lg)
                    .padding(.vertical, VMDesignTokens.Spacing.xs)
                }

                // 検索結果リスト
                ScrollView {
                    LazyVStack(spacing: VMDesignTokens.Spacing.sm) {
                        ForEach(store.results) { result in
                            SearchResultCard(result: result)
                                .onTapGesture {
                                    store.send(.resultTapped(id: result.id))
                                }
                                .padding(.horizontal, VMDesignTokens.Spacing.lg)
                        }
                    }
                    .padding(.vertical, VMDesignTokens.Spacing.sm)
                }
            }
        }
        .background(Color.vmBackground)
        .onAppear { store.send(.onAppear) }
    }

    private var searchBar: some View {
        HStack(spacing: VMDesignTokens.Spacing.sm) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.vmTextTertiary)
                TextField(
                    "メモを検索...",
                    text: Binding(
                        get: { store.searchText },
                        set: { store.send(.searchTextChanged($0)) }
                    )
                )
                .font(.vmBody())
                .foregroundColor(.vmTextPrimary)

                if !store.searchText.isEmpty {
                    Button {
                        store.send(.searchTextChanged(""))
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.vmTextTertiary)
                    }
                }
            }
            .padding(VMDesignTokens.Spacing.sm)
            .background(Color.vmSurfaceVariant)
            .cornerRadius(VMDesignTokens.CornerRadius.small)

            Button {
                store.send(.toggleFilters)
            } label: {
                Image(systemName: store.showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .foregroundColor(.vmPrimary)
            }
            .accessibilityLabel("フィルター")
            .accessibilityHint("ダブルタップでフィルターパネルを\(store.showFilters ? "閉じます" : "開きます")")
        }
    }
}

// MARK: - Sub-components

/// フィルターパネル
struct FilterPanel: View {
    @Bindable var store: StoreOf<SearchReducer>

    var body: some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.md) {
            // 日付フィルター
            VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.sm) {
                Text("期間")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextSecondary)
                HStack(spacing: VMDesignTokens.Spacing.sm) {
                    ForEach(SearchReducer.State.DateFilter.allCases, id: \.self) { filter in
                        FilterChip(
                            label: filter.rawValue,
                            isSelected: store.selectedDateFilter == filter
                        ) {
                            store.send(.dateFilterChanged(filter))
                        }
                    }
                }
            }

            // タグフィルター
            if !store.availableTags.isEmpty {
                VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.sm) {
                    Text("タグ")
                        .font(.vmCaption1)
                        .foregroundColor(.vmTextSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: VMDesignTokens.Spacing.sm) {
                            ForEach(store.availableTags, id: \.self) { tag in
                                FilterChip(
                                    label: tag,
                                    isSelected: store.selectedTags.contains(tag)
                                ) {
                                    store.send(.tagFilterToggled(tag))
                                }
                            }
                        }
                    }
                }
            }

            // クリアボタン
            if store.selectedDateFilter != .all || !store.selectedTags.isEmpty {
                Button {
                    store.send(.clearFilters)
                } label: {
                    Text("フィルターをクリア")
                        .font(.vmCaption1)
                        .foregroundColor(.vmPrimary)
                }
            }
        }
        .padding(VMDesignTokens.Spacing.lg)
        .background(Color.vmSurfaceVariant)
        .cornerRadius(VMDesignTokens.CornerRadius.medium)
        .padding(.horizontal, VMDesignTokens.Spacing.lg)
    }
}

/// フィルターチップ
struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Text(label)
            .font(.vmCaption1)
            .padding(.horizontal, VMDesignTokens.Spacing.md)
            .padding(.vertical, VMDesignTokens.Spacing.sm)
            .background(isSelected ? Color.vmPrimary : Color.vmSurfaceVariant)
            .foregroundColor(isSelected ? .white : .vmTextSecondary)
            .cornerRadius(VMDesignTokens.CornerRadius.small)
            .onTapGesture(perform: onTap)
    }
}

/// 検索結果カード
struct SearchResultCard: View {
    let result: SearchReducer.SearchResultItem

    var body: some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.sm) {
            // タイトル + 日時
            HStack {
                Text(result.title)
                    .font(.vmHeadline)
                    .foregroundColor(.vmTextPrimary)
                    .lineLimit(1)
                Spacer()
                Text(formattedDate(result.createdAt))
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)
            }

            // スニペット（ハイライト付き）
            HighlightedSnippetText(snippet: result.snippet)
                .font(.vmCallout)
                .lineLimit(2)

            // メタ情報
            HStack(spacing: VMDesignTokens.Spacing.sm) {
                if let emotion = result.emotion {
                    EmotionBadge(emotion: emotion)
                }
                Label(formattedDuration(result.durationSeconds), systemImage: "mic.fill")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)
            }
        }
        .padding(VMDesignTokens.Spacing.md)
        .background(Color.vmSurface)
        .cornerRadius(VMDesignTokens.CornerRadius.small)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.title)、\(formattedDate(result.createdAt))")
        .accessibilityHint("ダブルタップで詳細を表示します")
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// ハイライト付きスニペットテキスト
/// <mark>キーワード</mark> を AttributedString でハイライト表示
struct HighlightedSnippetText: View {
    let snippet: String

    var body: some View {
        Text(attributedSnippet)
    }

    private var attributedSnippet: AttributedString {
        var result = AttributedString()
        let parts = snippet.components(separatedBy: "<mark>")

        for (index, part) in parts.enumerated() {
            if index == 0 {
                var attr = AttributedString(part)
                attr.foregroundColor = .vmTextSecondary
                result.append(attr)
            } else {
                let subParts = part.components(separatedBy: "</mark>")
                if subParts.count == 2 {
                    var highlighted = AttributedString(subParts[0])
                    highlighted.foregroundColor = .vmTextPrimary
                    highlighted.backgroundColor = .vmAccentLight
                    result.append(highlighted)

                    var normal = AttributedString(subParts[1])
                    normal.foregroundColor = .vmTextSecondary
                    result.append(normal)
                } else {
                    var attr = AttributedString(part)
                    attr.foregroundColor = .vmTextSecondary
                    result.append(attr)
                }
            }
        }
        return result
    }
}

/// 検索ヒント（初期状態）
struct SearchHintView: View {
    var body: some View {
        VStack(spacing: VMDesignTokens.Spacing.md) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.vmTextTertiary)
            Text("メモを検索")
                .font(.vmTitle3)
                .foregroundColor(.vmTextSecondary)
            Text("キーワードを入力して\nメモを検索できます")
                .font(.vmCallout)
                .foregroundColor(.vmTextTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
}

/// 検索結果なし
struct EmptySearchResultView: View {
    let query: String

    var body: some View {
        VStack(spacing: VMDesignTokens.Spacing.md) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.vmTextTertiary)
            Text("「\(query)」に一致するメモはありません")
                .font(.vmCallout)
                .foregroundColor(.vmTextSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
}
