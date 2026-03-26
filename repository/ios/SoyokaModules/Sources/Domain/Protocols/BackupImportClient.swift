import Dependencies
import Foundation

/// バックアップインポートの TCA Dependency ラッパー
/// @Dependency(\.backupImport) で Reducer から注入可能にする
public struct BackupImportClient: Sendable {
    /// .soyokabackup ファイルからインポートし、結果を返す
    public var importBackup: @Sendable (_ fileURL: URL) async throws -> BackupResult

    public init(
        importBackup: @escaping @Sendable (_ fileURL: URL) async throws -> BackupResult
    ) {
        self.importBackup = importBackup
    }
}

// MARK: - DependencyKey

extension BackupImportClient: TestDependencyKey {
    public static let testValue = BackupImportClient(
        importBackup: unimplemented("BackupImportClient.importBackup")
    )
}

extension DependencyValues {
    public var backupImport: BackupImportClient {
        get { self[BackupImportClient.self] }
        set { self[BackupImportClient.self] = newValue }
    }
}
