import ComposableArchitecture
import SharedUI
import SwiftUI

/// メモ削除確認ダイアログのViewModifier
/// TASK-0017: 確認ダイアログ（.confirmationDialog）
/// 設計書 04-ui-design-system.md セクション7.6 準拠
public struct MemoDeleteConfirmationModifier: ViewModifier {
    @Bindable var store: StoreOf<MemoDeleteReducer>

    public init(store: StoreOf<MemoDeleteReducer>) {
        self.store = store
    }

    public func body(content: Content) -> some View {
        content
            .alert(
                "きおくを削除しますか？",
                isPresented: Binding(
                    get: { store.showDeleteConfirmation },
                    set: { _ in }
                )
            ) {
                Button("キャンセル", role: .cancel) {
                    store.send(.deleteCancelled)
                }
                if let id = store.pendingDeleteID {
                    Button("削除", role: .destructive) {
                        store.send(.deleteConfirmed(id: id))
                    }
                }
            } message: {
                Text("この操作は取り消せません。音声ファイルとすべての関連データが完全に削除されます。")
            }
    }
}

extension View {
    /// メモ削除確認ダイアログを付加する
    public func memoDeleteConfirmation(store: StoreOf<MemoDeleteReducer>) -> some View {
        modifier(MemoDeleteConfirmationModifier(store: store))
    }
}
