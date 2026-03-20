import ComposableArchitecture
import SharedUI
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

                // MARK: - プライバシーセクション
                Section {
                    comingSoonButton(
                        title: "プライバシー設定",
                        icon: "hand.raised.fill",
                        feature: "プライバシー設定"
                    )
                    comingSoonButton(
                        title: "アプリロック",
                        icon: "lock.fill",
                        feature: "アプリロック"
                    )
                } header: {
                    Text("プライバシー")
                }

                // MARK: - プランセクション
                Section {
                    comingSoonButton(
                        title: "プラン管理",
                        icon: "creditcard.fill",
                        feature: "プラン管理"
                    )
                    comingSoonButton(
                        title: "テーマ設定",
                        icon: "paintbrush.fill",
                        feature: "テーマ設定",
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
                        feature: "利用統計"
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
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("設定")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .alert(
                store.comingSoonFeature,
                isPresented: Binding(
                    get: { store.showComingSoonAlert },
                    set: { if !$0 { store.send(.dismissComingSoonAlert) } }
                )
            ) {
                Button("OK") {}
            } message: {
                Text("この機能は今後のアップデートで追加予定です")
            }
        }
    }

    // MARK: - Private Helpers

    /// 「準備中」機能のボタン行
    @ViewBuilder
    private func comingSoonButton(
        title: String,
        icon: String,
        feature: String,
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
