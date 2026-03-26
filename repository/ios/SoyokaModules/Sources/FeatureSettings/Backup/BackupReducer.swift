import ComposableArchitecture
import Domain
import Foundation

/// バックアップ/リストア機能の TCA Reducer
/// 設計書 2026-03-26-backup-restore-design.md 準拠
/// SettingsReducer のサブステートとして統合される
@Reducer
public struct BackupReducer {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        /// エクスポート中フラグ
        public var isExporting: Bool = false
        /// インポート中フラグ
        public var isImporting: Bool = false
        /// エクスポート完了後の一時ファイル URL
        public var exportedFileURL: URL?
        /// ShareSheet 表示フラグ
        public var showShareSheet: Bool = false
        /// ファイルピッカー表示フラグ
        public var showFilePicker: Bool = false
        /// インポート結果アラート表示フラグ
        public var showImportResultAlert: Bool = false
        /// インポート結果
        public var importResult: BackupResult?
        /// エラーメッセージ
        public var errorMessage: String?

        public init(
            isExporting: Bool = false,
            isImporting: Bool = false,
            exportedFileURL: URL? = nil,
            showShareSheet: Bool = false,
            showFilePicker: Bool = false,
            showImportResultAlert: Bool = false,
            importResult: BackupResult? = nil,
            errorMessage: String? = nil
        ) {
            self.isExporting = isExporting
            self.isImporting = isImporting
            self.exportedFileURL = exportedFileURL
            self.showShareSheet = showShareSheet
            self.showFilePicker = showFilePicker
            self.showImportResultAlert = showImportResultAlert
            self.importResult = importResult
            self.errorMessage = errorMessage
        }
    }

    // MARK: - Action

    public enum Action: Equatable, Sendable {
        /// 「バックアップを作成」タップ
        case exportTapped
        /// エクスポート成功
        case exportCompleted(URL)
        /// エクスポート失敗
        case exportFailed
        /// ShareSheet が閉じられた（一時ファイルクリーンアップ）
        case shareSheetDismissed
        /// 「バックアップから復元」タップ
        case importTapped
        /// ファイルピッカーでファイルが選択された
        case importFileSelected(URL)
        /// ファイルピッカーがキャンセルされた
        case importFilePickerCancelled
        /// 外部 URL からのインポート（onOpenURL 経由で AppReducer から委譲）
        case importFromURL(URL)
        /// インポート成功
        case importCompleted(BackupResult)
        /// インポート失敗
        case importFailed(String)
        /// インポート結果アラートを閉じる
        case dismissImportResultAlert
        /// エラーアラートを閉じる
        case dismissError
    }

    // MARK: - Dependencies

    @Dependency(\.backupExport) var backupExport
    @Dependency(\.backupImport) var backupImport

    public init() {}

    // MARK: - Reducer Body

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .exportTapped:
                state.isExporting = true
                state.errorMessage = nil
                return .run { send in
                    do {
                        let url = try await backupExport.export()
                        await send(.exportCompleted(url))
                    } catch {
                        await send(.exportFailed)
                    }
                }

            case let .exportCompleted(url):
                state.isExporting = false
                state.exportedFileURL = url
                state.showShareSheet = true
                return .none

            case .exportFailed:
                state.isExporting = false
                state.errorMessage = "バックアップの作成に失敗しました"
                return .none

            case .shareSheetDismissed:
                // 一時ファイルのクリーンアップ
                if let url = state.exportedFileURL {
                    try? FileManager.default.removeItem(at: url)
                }
                state.showShareSheet = false
                state.exportedFileURL = nil
                return .none

            case .importTapped:
                state.showFilePicker = true
                state.errorMessage = nil
                return .none

            case let .importFileSelected(url):
                state.showFilePicker = false
                state.isImporting = true
                return .run { send in
                    do {
                        let result = try await backupImport.importBackup(url)
                        await send(.importCompleted(result))
                    } catch {
                        await send(.importFailed(error.localizedDescription))
                    }
                }

            case .importFilePickerCancelled:
                state.showFilePicker = false
                return .none

            case let .importFromURL(url):
                state.isImporting = true
                state.errorMessage = nil
                return .run { send in
                    do {
                        let result = try await backupImport.importBackup(url)
                        await send(.importCompleted(result))
                    } catch {
                        await send(.importFailed(error.localizedDescription))
                    }
                }

            case let .importCompleted(result):
                state.isImporting = false
                state.importResult = result
                state.showImportResultAlert = true
                return .none

            case let .importFailed(message):
                state.isImporting = false
                state.errorMessage = message
                return .none

            case .dismissImportResultAlert:
                state.showImportResultAlert = false
                state.importResult = nil
                return .none

            case .dismissError:
                state.errorMessage = nil
                return .none
            }
        }
    }
}
