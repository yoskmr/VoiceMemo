import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI

/// カスタム辞書管理画面
/// TASK-0018: カスタム辞書（STT精度向上）
/// 設計書 04-ui-design-system.md セクション6.5 設定画面 → カスタム辞書
public struct CustomDictionaryView: View {
    @Bindable var store: StoreOf<CustomDictionaryReducer>

    public init(store: StoreOf<CustomDictionaryReducer>) {
        self.store = store
    }

    public var body: some View {
        List {
            // 新規追加セクション
            Section {
                VStack(spacing: VMDesignTokens.Spacing.md) {
                    HStack(spacing: VMDesignTokens.Spacing.md) {
                        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.xs) {
                            Text("読み")
                                .font(.vmCaption1)
                                .foregroundColor(.vmTextSecondary)
                            TextField(
                                "よみがな",
                                text: Binding(
                                    get: { store.newReading },
                                    set: { store.send(.newReadingChanged($0)) }
                                )
                            )
                            .font(.vmBody())
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("読み入力欄")
                        }

                        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.xs) {
                            Text("表記")
                                .font(.vmCaption1)
                                .foregroundColor(.vmTextSecondary)
                            TextField(
                                "漢字・英語等",
                                text: Binding(
                                    get: { store.newDisplay },
                                    set: { store.send(.newDisplayChanged($0)) }
                                )
                            )
                            .font(.vmBody())
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("表記入力欄")
                        }
                    }

                    if let validationError = store.validationError {
                        Text(validationError)
                            .font(.vmCaption1)
                            .foregroundColor(.vmError)
                    }

                    Button {
                        store.send(.addButtonTapped)
                    } label: {
                        HStack {
                            if store.isAdding {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text("追加")
                                .font(.vmHeadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.vmPrimary)
                        .foregroundColor(.white)
                        .cornerRadius(VMDesignTokens.CornerRadius.small)
                    }
                    .disabled(store.isAdding)
                    .accessibilityLabel("単語を追加")
                    .accessibilityHint("読みと表記を入力してからタップしてください")
                }
            } header: {
                Text("新しい単語を登録")
            }

            // 登録済み単語一覧
            Section {
                if store.entries.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: VMDesignTokens.Spacing.sm) {
                            Image(systemName: "character.book.closed")
                                .font(.system(size: 32))
                                .foregroundColor(.vmTextTertiary)
                            Text("登録された単語はありません")
                                .font(.vmCallout)
                                .foregroundColor(.vmTextTertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 20)
                } else {
                    ForEach(store.entries) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.xxs) {
                                Text(entry.display)
                                    .font(.vmHeadline)
                                    .foregroundColor(.vmTextPrimary)
                                Text(entry.reading)
                                    .font(.vmCaption1)
                                    .foregroundColor(.vmTextSecondary)
                            }
                            Spacer()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(entry.display)、読み: \(entry.reading)")
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let entry = store.entries[index]
                            store.send(.deleteEntry(id: entry.id))
                        }
                    }
                }
            } header: {
                Text("登録済み単語（\(store.entries.count)件）")
            } footer: {
                Text("登録した単語は音声認識時に優先的に認識されます。専門用語や固有名詞の登録が効果的です。")
                    .font(.vmCaption2)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("カスタム辞書")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("エラー", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.send(.dismissError) } }
        )) {
            Button("OK") { store.send(.dismissError) }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onAppear { store.send(.onAppear) }
    }
}
