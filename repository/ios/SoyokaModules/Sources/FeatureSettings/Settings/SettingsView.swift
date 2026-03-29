import ComposableArchitecture
import Domain
import FeatureSubscription
import SharedUI
import SharedUtil
import SwiftUI

/// 設定画面
/// 設計書 04-ui-design-system.md セクション5.2 準拠
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
                    // こころの分析（Pro限定）
                    Toggle(isOn: Binding(
                        get: { store.emotionAnalysisEnabled },
                        set: { store.send(.emotionAnalysisToggled($0)) }
                    )) {
                        HStack(spacing: VMDesignTokens.Spacing.sm) {
                            Label("こころの分析", systemImage: "heart.text.square")
                            Spacer()
                            proBadge
                        }
                    }
                    .tint(.vmPrimary)

                    // 処理方法（プライバシー）
                    Picker(selection: Binding(
                        get: { store.aiProcessingMode },
                        set: { store.send(.aiProcessingModeChanged($0)) }
                    )) {
                        ForEach(AIProcessingMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("処理方法")
                                Text(store.aiProcessingMode.description)
                                    .font(.vmCaption1)
                                    .foregroundColor(.vmTextTertiary)
                            }
                        } icon: {
                            Image(systemName: "shield.checkered")
                        }
                    }

                    // 文体選択（メニュー形式でコンパクトに）
                    Picker(selection: Binding(
                        get: { store.writingStyle },
                        set: { store.send(.writingStyleChanged($0)) }
                    )) {
                        ForEach(WritingStyle.allCases, id: \.self) { style in
                            HStack {
                                Text(style.displayName)
                                if style.requiresPro {
                                    Text("Pro")
                                        .font(.caption2)
                                        .foregroundColor(.vmAccent)
                                }
                            }
                            .tag(style)
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("わたしの文体")
                                Text(store.writingStyle.description)
                                    .font(.vmCaption1)
                                    .foregroundColor(.vmTextTertiary)
                            }
                        } icon: {
                            Image(systemName: "textformat.alt")
                        }
                    }
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
                } header: {
                    Text("プラン")
                }

                // MARK: - その他セクション
                Section {
                    // プライバシーポリシー
                    Link(destination: URL(string: "https://soyoka.app/privacy")!) {
                        HStack {
                            Label("プライバシーポリシー", systemImage: "hand.raised.fill")
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
                            Label("利用規約", systemImage: "doc.text.fill")
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

    /// Pro バッジ（統一スタイル）
    private var proBadge: some View {
        Text("Pro")
            .font(.vmCaption2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.vmAccent)
            .clipShape(Capsule())
    }

}
