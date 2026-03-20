import ComposableArchitecture
import Domain
import FeatureMemo
import FeatureRecording
import FeatureSettings
import SharedUI
import SwiftUI

@main
struct MurMurNoteApp: App {
    var body: some Scene {
        WindowGroup {
            AppView(
                store: Store(initialState: AppReducer.State()) {
                    AppReducer()
                }
            )
            .preferredColorScheme(.light)
        }
    }
}

// MARK: - AppReducer

@Reducer
struct AppReducer {
    @ObservableState
    struct State: Equatable {
        var selectedTab: Tab = .home
        var recording = RecordingFeature.State()
        var memoList = MemoListReducer.State()
        var settings = SettingsReducer.State()
        /// メモ詳細表示用（nilの場合は非表示）
        var selectedMemo: MemoDetailReducer.State?

        enum Tab: Hashable {
            case home
            case memoList
            case settings
        }
    }

    enum Action {
        case tabSelected(State.Tab)
        case recording(RecordingFeature.Action)
        case memoList(MemoListReducer.Action)
        case settings(SettingsReducer.Action)
        case memoDetail(MemoDetailReducer.Action)
        case dismissMemoDetail
    }

    @Dependency(\.fts5IndexManager) var fts5IndexManager

    var body: some ReducerOf<Self> {
        Scope(state: \.recording, action: \.recording) {
            RecordingFeature()
        }
        Scope(state: \.memoList, action: \.memoList) {
            MemoListReducer()
        }
        Scope(state: \.settings, action: \.settings) {
            SettingsReducer()
        }
        Reduce { state, action in
            switch action {
            case let .tabSelected(tab):
                state.selectedTab = tab
                return .none

            // 録音完了 → メモ一覧タブに切替 + 一覧をリフレッシュ + FTS5インデックス更新
            case let .recording(.recordingSaved(memo)):
                state.selectedTab = .memoList
                return .merge(
                    .send(.memoList(.refreshRequested)),
                    .run { [fts5IndexManager] _ in
                        // 保存されたメモのテキストをFTS5インデックスに追加
                        let title = memo.title
                        let text = memo.transcription?.fullText ?? ""
                        #if DEBUG
                        print("[FTS5] upsert: id=\(memo.id.uuidString.prefix(8)), title='\(title.prefix(20))', text_len=\(text.count)")
                        #endif
                        do {
                            try fts5IndexManager.upsertIndex(
                                memo.id.uuidString,
                                title,
                                text,
                                memo.aiSummary?.summaryText ?? "",
                                memo.tags.map(\.name).joined(separator: " ")
                            )
                            #if DEBUG
                            print("[FTS5] upsert 成功")
                            #endif
                        } catch {
                            #if DEBUG
                            print("[FTS5] upsert エラー: \(error)")
                            #endif
                        }
                    }
                )

            case .recording:
                return .none

            case .settings:
                return .none

            // メモ一覧でメモをタップ → メモ詳細を表示（検索結果タップも同じフローで統一）
            case let .memoList(.memoTapped(id: memoID)):
                state.selectedMemo = MemoDetailReducer.State(memoID: memoID)
                return .none

            case .memoList:
                return .none

            case .memoDetail(.backButtonTapped):
                state.selectedMemo = nil
                return .none

            // 削除完了 → メモ詳細を閉じて一覧をリフレッシュ
            case let .memoDetail(._deleteCompletedAndDismiss(_)):
                state.selectedMemo = nil
                return .send(.memoList(.refreshRequested))

            // 編集保存完了 → 一覧をリフレッシュ（詳細画面はそのまま表示）
            case .memoDetail(._editSavedAndReload):
                return .send(.memoList(.refreshRequested))

            case .memoDetail:
                return .none

            case .dismissMemoDetail:
                state.selectedMemo = nil
                return .none
            }
        }
        .ifLet(\.selectedMemo, action: \.memoDetail) {
            MemoDetailReducer()
        }
    }
}

// MARK: - AppView

struct AppView: View {
    @Bindable var store: StoreOf<AppReducer>

    var body: some View {
        TabView(selection: $store.selectedTab.sending(\.tabSelected)) {
            // ホームタブ: 録音画面
            NavigationStack {
                RecordingView(
                    store: store.scope(state: \.recording, action: \.recording)
                )
                .navigationTitle("つぶやき")
            }
            .tabItem { Label("録音", systemImage: "mic.fill") }
            .tag(AppReducer.State.Tab.home)

            // メモ一覧タブ
            MemoListView(
                store: store.scope(state: \.memoList, action: \.memoList)
            )
            .tabItem { Label("メモ", systemImage: "doc.text.fill") }
            .tag(AppReducer.State.Tab.memoList)

            // 設定タブ
            SettingsView(
                store: store.scope(state: \.settings, action: \.settings)
            )
            .tabItem { Label("設定", systemImage: "gearshape") }
            .tag(AppReducer.State.Tab.settings)
        }
        .tint(Color.vmPrimary)
        .sheet(
            item: Binding(
                get: {
                    store.selectedMemo.map { DetailSheetIdentifier(state: $0) }
                },
                set: { newValue in
                    if newValue == nil {
                        store.send(.dismissMemoDetail)
                    }
                }
            )
        ) { _ in
            if let detailStore = store.scope(state: \.selectedMemo, action: \.memoDetail) {
                NavigationStack {
                    MemoDetailView(store: detailStore)
                        .toolbar {
                            #if os(iOS)
                            ToolbarItem(placement: .topBarLeading) {
                                Button("閉じる") {
                                    store.send(.dismissMemoDetail)
                                }
                            }
                            #endif
                        }
                }
            }
        }
    }
}

// MARK: - Sheet識別用ラッパー

/// sheet(item:) に渡すための Identifiable ラッパー
private struct DetailSheetIdentifier: Identifiable {
    let id: UUID
    init(state: MemoDetailReducer.State) {
        self.id = state.memoID
    }
}
