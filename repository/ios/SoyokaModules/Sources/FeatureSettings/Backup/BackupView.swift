import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI
import UniformTypeIdentifiers

/// .soyokabackup カスタム UTType
extension UTType {
    static let soyokaBackup = UTType(exportedAs: "app.soyoka.backup")
}

/// バックアップ/リストア画面
/// 設計書 2026-03-26-backup-restore-design.md UI設計準拠
/// 用語規約: 「メモ」→「きおく」
public struct BackupView: View {
    @Bindable var store: StoreOf<BackupReducer>

    public init(store: StoreOf<BackupReducer>) {
        self.store = store
    }

    public var body: some View {
        List {
            // MARK: - エクスポートセクション
            Section {
                Button {
                    store.send(.exportTapped)
                } label: {
                    HStack {
                        Label("バックアップを作成", systemImage: "square.and.arrow.up")
                            .foregroundColor(.vmTextPrimary)
                        Spacer()
                        if store.isExporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(store.isExporting || store.isImporting)
            } footer: {
                Text("すべてのきおくと音声データを書き出します")
                    .font(.vmCaption1)
            }

            // MARK: - インポートセクション
            Section {
                Button {
                    store.send(.importTapped)
                } label: {
                    HStack {
                        Label("バックアップから復元", systemImage: "square.and.arrow.down")
                            .foregroundColor(.vmTextPrimary)
                        Spacer()
                        if store.isImporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(store.isExporting || store.isImporting)
            } footer: {
                Text(".soyokabackup ファイルを選択してきおくを復元します。既に存在するきおくはスキップされます。")
                    .font(.vmCaption1)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("きおくのバックアップ")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        // ShareSheet
        .sheet(isPresented: Binding(
            get: { store.showShareSheet },
            set: { if !$0 { store.send(.shareSheetDismissed) } }
        )) {
            if let url = store.exportedFileURL {
                ShareSheetView(activityItems: [url])
            }
        }
        // ファイルピッカー
        .fileImporter(
            isPresented: Binding(
                get: { store.showFilePicker },
                set: { if !$0 { store.send(.importFilePickerCancelled) } }
            ),
            allowedContentTypes: [.soyokaBackup, .archive, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first {
                    store.send(.importFileSelected(url))
                }
            case .failure:
                store.send(.importFilePickerCancelled)
            }
        }
        // インポート結果アラート
        .alert(
            "復元完了",
            isPresented: Binding(
                get: { store.showImportResultAlert },
                set: { if !$0 { store.send(.dismissImportResultAlert) } }
            )
        ) {
            Button("OK") {}
        } message: {
            if let result = store.importResult {
                let message = "\(result.importedCount)件のきおくを復元しました"
                let skipMessage = result.skippedCount > 0 ? "（\(result.skippedCount)件はスキップ）" : ""
                let audioMessage = result.audioMissingCount > 0 ? "\n\(result.audioMissingCount)件は音声なしで復元" : ""
                Text(message + skipMessage + audioMessage)
            }
        }
        // エラーアラート
        .alert(
            "エラー",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.send(.dismissError) } }
            )
        ) {
            Button("OK") {}
        } message: {
            if let message = store.errorMessage {
                Text(message)
            }
        }
    }
}

// MARK: - ShareSheetView (UIActivityViewController ラッパー)

#if os(iOS)
struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
struct ShareSheetView: View {
    let activityItems: [Any]
    var body: some View {
        Text("ShareSheet は iOS のみ対応")
    }
}
#endif
