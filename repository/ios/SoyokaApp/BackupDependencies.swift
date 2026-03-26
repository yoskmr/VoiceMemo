import Dependencies
import Domain
import Foundation
import InfraStorage
import SwiftData

// MARK: - Backup Dependencies
// バックアップエクスポート・インポートの Dependency 実装

// MARK: BackupExportClient → BackupExporter Live実装

extension BackupExportClient: DependencyKey {
    public static let liveValue: BackupExportClient = {
        // 注意: StorageDependencies.swift と同じ ModelContainer を使用する必要がある
        // TODO: ModelContainer のシングルトン化（現在は各 Dependency ファイルで別インスタンスを生成している）
        let container: ModelContainer = {
            do {
                return try ModelContainerConfiguration.create(inMemory: false)
            } catch {
                fatalError("SwiftData ModelContainer の初期化に失敗 (Backup): \(error)")
            }
        }()

        let exporter = BackupExporter(modelContainer: container)

        return BackupExportClient(
            export: {
                try await MainActor.run {
                    try exporter.export()
                }
            }
        )
    }()
}

// MARK: BackupImportClient → BackupImporter Live実装

extension BackupImportClient: DependencyKey {
    public static let liveValue: BackupImportClient = {
        let container: ModelContainer = {
            do {
                return try ModelContainerConfiguration.create(inMemory: false)
            } catch {
                fatalError("SwiftData ModelContainer の初期化に失敗 (Backup): \(error)")
            }
        }()

        @Dependency(\.fts5IndexManager) var fts5IndexManager

        let importer = BackupImporter(
            modelContainer: container,
            fts5Upsert: { memoID, title, text, summary, tags in
                try fts5IndexManager.upsertIndex(memoID, title, text, summary, tags)
            }
        )

        return BackupImportClient(
            importBackup: { url in
                try await importer.importBackup(fileURL: url)
            }
        )
    }()
}
