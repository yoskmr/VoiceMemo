import ComposableArchitecture
import Domain
import FeatureMemo
import FeatureRecording
import FeatureSettings
import SharedUI
import SwiftUI

@main
struct SoyokaApp: App {
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedSetup {
                AppView(
                    store: Store(initialState: AppReducer.State()) {
                        AppReducer()
                    }
                )
            } else {
                WelcomeView {
                    hasCompletedSetup = true
                }
            }
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
        case openURL(URL)
        case aiProcessingCompleted(UUID)
    }

    @Dependency(\.fts5IndexManager) var fts5IndexManager
    @Dependency(\.aiProcessingQueue) var aiProcessingQueue

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

            // 録音完了 → FTS5インデックス更新 + AI処理キュー追加（完了画面表示中にバックグラウンドで実行）
            case let .recording(.recordingSaved(memo)):
                return .merge(
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
                    },
                    // AI処理を自動実行（録音完了後にバックグラウンドで要約・タグ付けを開始）
                    .run { [aiProcessingQueue] _ in
                        do {
                            try await aiProcessingQueue.enqueueProcessing(memo.id)
                            #if DEBUG
                            print("[AI] enqueueProcessing 成功: id=\(memo.id.uuidString.prefix(8))")
                            #endif
                        } catch {
                            // Phase 3aではオンデバイスのみなので失敗してもアプリは続行
                            #if DEBUG
                            print("[AI] enqueueProcessing エラー（無視）: \(error)")
                            #endif
                        }
                    },
                    // AI処理完了を監視し、完了したら通知を中継
                    .run { [aiProcessingQueue] send in
                        for await status in aiProcessingQueue.observeStatus(memo.id) {
                            if case .completed = status {
                                await send(.aiProcessingCompleted(memo.id))
                                break
                            }
                        }
                    }
                )

            // 「メモを見る」タップ → メモ一覧タブに切替 + リフレッシュ + メモ詳細遷移
            case let .recording(.navigateToMemoDetail(memoID)):
                state.selectedTab = .memoList
                return .merge(
                    .send(.memoList(.refreshRequested)),
                    .send(.memoList(.selectMemo(id: memoID)))
                )

            case let .aiProcessingCompleted(memoID):
                state.recording.aiProcessingCompleted = true
                #if DEBUG
                print("[AI] 処理完了通知: id=\(memoID.uuidString.prefix(8))")
                #endif
                return .none

            case .recording:
                return .none

            case .settings:
                return .none

            case let .openURL(url):
                // Deep Link: soyoka://memo/{id}
                if url.scheme == "soyoka", url.host == "memo",
                   let memoIDString = url.pathComponents.dropFirst().first,
                   let memoID = UUID(uuidString: memoIDString) {
                    state.selectedTab = .memoList
                    return .send(.memoList(.selectMemo(id: memoID)))
                }

                // Deep Link: soyoka://record
                if url.scheme == "soyoka", url.host == "record" {
                    state.selectedTab = .home
                    return .none
                }

                // .soyokabackup ファイルの処理を BackupReducer に委譲
                if url.pathExtension == "soyokabackup" {
                    return .send(.settings(.backup(.importFromURL(url))))
                }
                return .none

            case .memoList:
                return .none
            }
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
                .navigationBarTitleDisplayMode(.large)
            }
            .tabItem { Label("つぶやき", systemImage: "bubble.left.fill") }
            .tag(AppReducer.State.Tab.home)

            // メモ一覧タブ
            MemoListView(
                store: store.scope(state: \.memoList, action: \.memoList)
            )
            .tabItem { Label("きおく", systemImage: "book.fill") }
            .tag(AppReducer.State.Tab.memoList)

            // 設定タブ
            SettingsView(
                store: store.scope(state: \.settings, action: \.settings)
            )
            .tabItem { Label("設定", systemImage: "gearshape") }
            .tag(AppReducer.State.Tab.settings)
        }
        .tint(Color.vmPrimary)
        .onOpenURL { url in
            store.send(.openURL(url))
        }
    }
}
