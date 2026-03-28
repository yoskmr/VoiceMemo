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
        // StorageDependencies.swift で定義された sharedModelContainer を共有参照
        let exporter = BackupExporter(modelContainer: sharedModelContainer)

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
        // StorageDependencies.swift で定義された sharedModelContainer を共有参照
        @Dependency(\.fts5IndexManager) var fts5IndexManager

        let importer = BackupImporter(
            modelContainer: sharedModelContainer,
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
