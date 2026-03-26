import ComposableArchitecture
import SharedUI
import SharedUtil
import SwiftUI

/// 設定画面
/// 設計書 04-ui-design-system.md セクション5.2 準拠
/// Phase 1: カスタム辞書のみ遷移可能、他は「準備中」アラート
public struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsReducer>

    public init(store: StoreOf<SettingsReducer>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                // MARK: - AI処理セクション
                Section {
                    Toggle(isOn: Binding(
                        get: { store.emotionAnalysisEnabled },
                        set: { store.send(.emotionAnalysisToggled($0)) }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("感情分析")
                            Text("メモの内容をクラウドで分析し、感情を判定します。AI処理回数を1回消費します。")
                                .font(.vmCaption1)
                                .foregroundColor(.vmTextTertiary)
                        }
                    }
                    .tint(.vmPrimary)
                } header: {
                    Text("AI処理")
                }

                // MARK: - 一般セクション
                Section {
                    NavigationLink {
                        CustomDictionaryView(
                            store: store.scope(
                                state: \.customDictionary,
                                action: \.customDictionary
                            )
                        )
                    } label: {
                        Label("カスタム辞書", systemImage: "character.book.closed")
                    }
                } header: {
                    Text("一般")
                }

                // MARK: - きおくのバックアップセクション
                Section {
                    NavigationLink {
                        BackupView(
                            store: store.scope(
                                state: \.backup,
                                action: \.backup
                            )
                        )
                    } label: {
                        Label("きおくのバックアップ", systemImage: "externaldrive.fill")
                    }
                } header: {
                    Text("データ管理")
                }

                // MARK: - プライバシーセクション
                Section {
                    comingSoonButton(
                        title: "プライバシー設定",
                        icon: "hand.raised.fill",
                        feature: .privacySettings
                    )
                    comingSoonButton(
                        title: "アプリロック",
                        icon: "lock.fill",
                        feature: .appLock
                    )
                } header: {
                    Text("プライバシー")
                }

                // MARK: - プランセクション
                Section {
                    comingSoonButton(
                        title: "プラン管理",
                        icon: "creditcard.fill",
                        feature: .planManagement
                    )
                    comingSoonButton(
                        title: "テーマ設定",
                        icon: "paintbrush.fill",
                        feature: .themeSettings,
                        badge: "Pro"
                    )
                } header: {
                    Text("プラン")
                }

                // MARK: - その他セクション
                Section {
                    comingSoonButton(
                        title: "利用統計",
                        icon: "chart.bar.fill",
                        feature: .usageStats
                    )
                    HStack {
                        Label("バージョン", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.vmTextTertiary)
                    }
                } header: {
                    Text("その他")
                }

                // MARK: - デバッグセクション
                if AppEnvironment.current.isDebugMenuEnabled {
                    Section {
                        Button(role: .destructive) {
                            store.send(.resetQuotaTapped)
                        } label: {
                            HStack {
                                Text("AI処理回数をリセット")
                                Spacer()
                                Text("\(store.aiQuotaUsed)/\(store.aiQuotaLimit)")
                                    .foregroundColor(.vmTextTertiary)
                            }
                        }

                        Button {
                            UserDefaults.standard.set(false, forKey: "hasCompletedSetup")
                            UserDefaults.standard.set(false, forKey: "hasSeenAIOnboarding")
                        } label: {
                            Text("ウェルカム画面・オンボーディングをリセット")
                        }

                        HStack {
                            Text("STTエンジン")
                            Spacer()
                            Text("SpeechAnalyzer")
                                .foregroundColor(.vmTextTertiary)
                        }
                    } header: {
                        Text("デバッグ（\(AppEnvironment.current == .development ? "Development" : "Staging")）")
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("設定")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .onAppear {
                store.send(.onAppear)
            }
            .alert(
                store.comingSoonFeature?.displayName ?? "",
                isPresented: Binding(
                    get: { store.showComingSoonAlert },
                    set: { if !$0 { store.send(.dismissComingSoonAlert) } }
                )
            ) {
                Button("OK") {}
            } message: {
                Text("この機能は今後のアップデートで追加予定です")
            }
            .alert(
                "AI処理回数をリセット",
                isPresented: Binding(
                    get: { store.showResetQuotaConfirmation },
                    set: { if !$0 { store.send(.resetQuotaDismissed) } }
                )
            ) {
                Button("リセット", role: .destructive) {
                    store.send(.resetQuotaConfirmed)
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("今月のAI処理回数を0にリセットします")
            }
        }
    }

    // MARK: - Private Helpers

    /// 「準備中」機能のボタン行
    @ViewBuilder
    private func comingSoonButton(
        title: String,
        icon: String,
        feature: SettingsReducer.ComingSoonFeature,
        badge: String? = nil
    ) -> some View {
        Button {
            store.send(.comingSoonTapped(feature))
        } label: {
            HStack {
                Label(title, systemImage: icon)
                    .foregroundColor(.vmTextPrimary)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.vmCaption1)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.vmAccent)
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.vmCaption2)
                    .foregroundColor(.vmTextTertiary)
            }
        }
    }
}
