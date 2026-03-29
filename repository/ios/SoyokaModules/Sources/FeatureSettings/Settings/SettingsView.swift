import ComposableArchitecture
import FeatureSubscription
import SharedUI
import SharedUtil
import SwiftUI

/// 設定画面
/// 設計書 04-ui-design-system.md セクション5.2 準拠
/// Phase 1: カスタム辞書のみ遷移可能、他は「準備中」インライン表示
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

                // MARK: - データのバックアップセクション
                Section {
                    NavigationLink {
                        BackupView(
                            store: store.scope(
                                state: \.backup,
                                action: \.backup
                            )
                        )
                    } label: {
                        Label("データのバックアップ", systemImage: "externaldrive.fill")
                    }
                } header: {
                    Text("データ管理")
                }

                // MARK: - プライバシーセクション
                Section {
                    comingSoonButton(
                        title: "プライバシー設定",
                        icon: "hand.raised.fill"
                    )
                    comingSoonButton(
                        title: "アプリロック",
                        icon: "lock.fill"
                    )
                } header: {
                    Text("プライバシー")
                }

                // MARK: - プランセクション
                Section {
                    Button {
                        store.send(.planManagementTapped)
                    } label: {
                        HStack {
                            Label("プラン管理", systemImage: "creditcard.fill")
                                .foregroundColor(.vmTextPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.vmCaption2)
                                .foregroundColor(.vmTextTertiary)
                        }
                    }
                    comingSoonButton(
                        title: "テーマ設定",
                        icon: "paintbrush.fill",
                        badge: "Pro"
                    )
                } header: {
                    Text("プラン")
                }

                // MARK: - その他セクション
                Section {
                    comingSoonButton(
                        title: "利用統計",
                        icon: "chart.bar.fill"
                    )

                    // プライバシーポリシー
                    Link(destination: URL(string: "https://soyoka.app/privacy")!) {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                                .foregroundColor(.vmTextTertiary)
                            Text("プライバシーポリシー")
                                .font(.vmBody())
                                .foregroundColor(.vmTextPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.vmCaption1)
                                .foregroundColor(.vmTextTertiary)
                        }
                    }

                    // 利用規約
                    Link(destination: URL(string: "https://soyoka.app/terms")!) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.vmTextTertiary)
                            Text("利用規約")
                                .font(.vmBody())
                                .foregroundColor(.vmTextPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.vmCaption1)
                                .foregroundColor(.vmTextTertiary)
                        }
                    }

                    HStack {
                        Label("バージョン", systemImage: "info.circle")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundColor(.vmTextTertiary)
                    }
                } header: {
                    Text("その他")
                }

                // MARK: - フッター
                Section {
                    HStack {
                        Spacer()
                        Text("Soyoka v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                            .font(.vmCaption1)
                            .foregroundColor(.vmTextTertiary)
                        Spacer()
                    }
                }

                // MARK: - デバッグセクション
                #if DEBUG
                if AppEnvironment.current.isDebugMenuEnabled {
                    Section {
                        NavigationLink {
                            DebugMenuView(
                                onResetQuota: { store.send(.resetQuotaTapped) },
                                aiQuotaUsed: store.aiQuotaUsed,
                                aiQuotaLimit: store.aiQuotaLimit
                            )
                        } label: {
                            Label("デバッグメニュー", systemImage: "ant.fill")
                        }
                    } header: {
                        Text("開発者メニュー")
                    }
                }
                #endif
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
            .sheet(
                item: $store.scope(
                    state: \.subscription,
                    action: \.subscription
                )
            ) { subscriptionStore in
                NavigationStack {
                    SubscriptionView(store: subscriptionStore)
                        .navigationTitle("プラン管理")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                }
            }
        }
    }

    // MARK: - Private Helpers

    /// 「準備中」機能の行（非活性・インライン表示）
    /// アラートを出さず、行自体で準備中であることを示す
    @ViewBuilder
    private func comingSoonButton(
        title: String,
        icon: String,
        badge: String? = nil
    ) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundColor(.vmTextTertiary)
            Spacer()
            if let badge {
                Text(badge)
                    .font(.vmCaption1)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.vmAccent.opacity(0.5))
                    .clipShape(Capsule())
            }
            Text("準備中")
                .font(.vmCaption1)
                .foregroundColor(.vmTextTertiary)
        }
    }
}
