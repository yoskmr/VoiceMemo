import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI

/// メモテキスト編集画面
/// TASK-0013: TextEditorで文字起こしテキスト編集
/// 設計書 04-ui-design-system.md セクション6.3 準拠
public struct MemoEditView: View {
    @Bindable var store: StoreOf<MemoEditReducer>
    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case title
        case transcription
    }

    public init(store: StoreOf<MemoEditReducer>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 保存成功メッセージ
            if let message = store.saveSuccessMessage {
                Text(message)
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextSecondary)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.vmPrimaryLight.opacity(0.1))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.lg) {
                    // タイトル編集
                    VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.xs) {
                        Text("タイトル")
                            .font(.vmSubheadline)
                            .foregroundColor(.vmTextSecondary)
                        TextField(
                            "タイトルを入力...",
                            text: Binding(
                                get: { store.title },
                                set: { store.send(.titleChanged($0)) }
                            )
                        )
                        .font(.vmTitle2)
                        .foregroundColor(.vmTextPrimary)
                        .focused($focusedField, equals: .title)
                        .accessibilityLabel("タイトル入力欄")
                    }

                    Divider()
                        .background(Color.vmDivider)
                        .accessibilityHidden(true)

                    // 文字起こしテキスト編集
                    VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.xs) {
                        Text("文字起こし")
                            .font(.vmSubheadline)
                            .foregroundColor(.vmTextSecondary)
                        TextEditor(
                            text: Binding(
                                get: { store.transcriptionText },
                                set: { store.send(.transcriptionTextChanged($0)) }
                            )
                        )
                        .font(.vmBody())
                        .foregroundColor(.vmTextPrimary)
                        .frame(minHeight: 300)
                        .focused($focusedField, equals: .transcription)
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel("文字起こしテキスト入力欄")
                    }
                }
                .padding(VMDesignTokens.Spacing.lg)
            }
            .background(Color.vmBackground)
        }
        .navigationTitle("編集")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                saveButton
            }
            ToolbarItem(placement: .keyboard) {
                Button("完了") { focusedField = nil }
            }
            #else
            ToolbarItem(placement: .automatic) {
                saveButton
            }
            #endif
        }
        .alert("未保存の変更があります", isPresented: Binding(
            get: { store.showDiscardAlert },
            set: { _ in }
        )) {
            Button("変更を破棄", role: .destructive) {
                store.send(.discardConfirmed)
            }
            Button("編集を続ける", role: .cancel) {
                store.send(.discardCancelled)
            }
        } message: {
            Text("保存せずに戻ると、変更内容が失われます。")
        }
        #if os(iOS)
        .interactiveDismissDisabled(store.hasUnsavedChanges)
        #endif
    }

    private var saveButton: some View {
        Button {
            store.send(.saveButtonTapped)
        } label: {
            if store.isSaving {
                ProgressView()
            } else {
                Text("保存")
                    .font(.vmHeadline)
                    .foregroundColor(store.hasUnsavedChanges ? .vmPrimary : .vmTextTertiary)
            }
        }
        .disabled(!store.hasUnsavedChanges || store.isSaving)
        .accessibilityLabel("保存ボタン")
        .accessibilityHint(store.hasUnsavedChanges ? "変更を保存します" : "変更がありません")
    }
}
