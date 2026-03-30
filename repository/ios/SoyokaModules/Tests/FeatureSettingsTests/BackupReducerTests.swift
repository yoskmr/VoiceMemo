import ComposableArchitecture
import Foundation
import Testing
@testable import Domain
@testable import FeatureSettings

@Suite("BackupReducer テスト")
@MainActor
struct BackupReducerTests {

    @Test("エクスポートタップ → isExporting = true → 成功 → fileURL が設定される")
    func test_exportTapped_成功() async {
        let testURL = URL(fileURLWithPath: "/tmp/test.soyokabackup")
        let store = TestStore(
            initialState: BackupReducer.State()
        ) {
            BackupReducer()
        } withDependencies: {
            $0.backupExport.export = { testURL }
        }

        await store.send(.exportTapped) {
            $0.isExporting = true
        }
        await store.receive(\.exportCompleted) {
            $0.isExporting = false
            $0.exportedFileURL = testURL
            $0.showShareSheet = true
        }
    }

    @Test("エクスポート失敗 → errorMessage が設定される")
    func test_exportTapped_失敗() async {
        let store = TestStore(
            initialState: BackupReducer.State()
        ) {
            BackupReducer()
        } withDependencies: {
            $0.backupExport.export = { throw NSError(domain: "test", code: -1) }
        }

        await store.send(.exportTapped) {
            $0.isExporting = true
        }
        await store.receive(\.exportFailed) {
            $0.isExporting = false
            $0.errorMessage = "バックアップの作成に失敗しました"
        }
    }

    @Test("ShareSheet 閉じる → showShareSheet = false, fileURL = nil")
    func test_shareSheetDismissed() async {
        let store = TestStore(
            initialState: BackupReducer.State(
                exportedFileURL: URL(fileURLWithPath: "/tmp/test.soyokabackup"),
                showShareSheet: true
            )
        ) {
            BackupReducer()
        }

        await store.send(.shareSheetDismissed) {
            $0.showShareSheet = false
            $0.exportedFileURL = nil
        }
    }

    @Test("インポートタップ → ファイルピッカー表示")
    func test_importTapped() async {
        let store = TestStore(
            initialState: BackupReducer.State()
        ) {
            BackupReducer()
        }

        await store.send(.importTapped) {
            $0.showFilePicker = true
        }
    }

    @Test("インポート成功 → 結果アラート表示")
    func test_importFileSelected_成功() async {
        let testURL = URL(fileURLWithPath: "/tmp/test.soyokabackup")
        let result = BackupResult(importedCount: 5, skippedCount: 2, audioMissingCount: 1)
        let store = TestStore(
            initialState: BackupReducer.State()
        ) {
            BackupReducer()
        } withDependencies: {
            $0.backupImport.importBackup = { _ in result }
        }

        await store.send(.importFileSelected(testURL)) {
            $0.showFilePicker = false
            $0.isImporting = true
        }
        await store.receive(\.importCompleted) {
            $0.isImporting = false
            $0.importResult = result
            $0.showImportResultAlert = true
        }
    }

    @Test("インポート失敗 → エラーメッセージ表示")
    func test_importFileSelected_失敗() async {
        let testURL = URL(fileURLWithPath: "/tmp/test.soyokabackup")
        let store = TestStore(
            initialState: BackupReducer.State()
        ) {
            BackupReducer()
        } withDependencies: {
            $0.backupImport.importBackup = { _ in
                throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "テストエラー"])
            }
        }

        await store.send(.importFileSelected(testURL)) {
            $0.showFilePicker = false
            $0.isImporting = true
        }
        await store.receive(\.importFailed) {
            $0.isImporting = false
            $0.errorMessage = "テストエラー"
        }
    }

    @Test("外部 URL からのインポート（onOpenURL 経由）")
    func test_importFromURL() async {
        let testURL = URL(fileURLWithPath: "/tmp/external.soyokabackup")
        let result = BackupResult(importedCount: 3, skippedCount: 0)
        let store = TestStore(
            initialState: BackupReducer.State()
        ) {
            BackupReducer()
        } withDependencies: {
            $0.backupImport.importBackup = { _ in result }
        }

        await store.send(.importFromURL(testURL)) {
            $0.isImporting = true
        }
        await store.receive(\.importCompleted) {
            $0.isImporting = false
            $0.importResult = result
            $0.showImportResultAlert = true
        }
    }
}
