import Dependencies
import Foundation

/// バックアップエクスポートの TCA Dependency ラッパー
/// @Dependency(\.backupExport) で Reducer から注入可能にする
public struct BackupExportClient: Sendable {
    /// 全メモ + 音声ファイルを ZIP エクスポートし、一時ファイルの URL を返す
    public var export: @Sendable () async throws -> URL

    public init(
        export: @escaping @Sendable () async throws -> URL
    ) {
        self.export = export
    }
}

// MARK: - DependencyKey

extension BackupExportClient: TestDependencyKey {
    public static let testValue = BackupExportClient(
        export: unimplemented("BackupExportClient.export")
    )
}

extension DependencyValues {
    public var backupExport: BackupExportClient {
        get { self[BackupExportClient.self] }
        set { self[BackupExportClient.self] = newValue }
    }
}
