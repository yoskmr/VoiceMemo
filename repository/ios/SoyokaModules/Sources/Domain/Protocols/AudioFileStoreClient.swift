import Dependencies
import Foundation

/// 音声ファイルの移動・保護レベル設定・削除を担う TCA Dependency ラッパー
/// @Dependency(\.audioFileStore) でReducerから注入可能にする
public struct AudioFileStoreClient: Sendable {
    /// 一時ファイルからDocuments/Audio/への移動
    public var moveToDocuments: @Sendable (_ tempURL: URL, _ id: UUID) async throws -> URL
    /// 確定済みファイルへのファイル保護レベル適用
    public var setFileProtection: @Sendable (_ url: URL) throws -> Void
    /// 音声ファイルの物理削除（TASK-0017: REQ-017 完全削除）
    public var deleteAudioFile: @Sendable (_ relativePath: String) async throws -> Void

    public init(
        moveToDocuments: @escaping @Sendable (_ tempURL: URL, _ id: UUID) async throws -> URL,
        setFileProtection: @escaping @Sendable (_ url: URL) throws -> Void,
        deleteAudioFile: @escaping @Sendable (_ relativePath: String) async throws -> Void = { _ in }
    ) {
        self.moveToDocuments = moveToDocuments
        self.setFileProtection = setFileProtection
        self.deleteAudioFile = deleteAudioFile
    }
}

// MARK: - DependencyKey

extension AudioFileStoreClient: TestDependencyKey {
    public static let testValue = AudioFileStoreClient(
        moveToDocuments: unimplemented("AudioFileStoreClient.moveToDocuments"),
        setFileProtection: unimplemented("AudioFileStoreClient.setFileProtection"),
        deleteAudioFile: unimplemented("AudioFileStoreClient.deleteAudioFile")
    )
}

extension DependencyValues {
    public var audioFileStore: AudioFileStoreClient {
        get { self[AudioFileStoreClient.self] }
        set { self[AudioFileStoreClient.self] = newValue }
    }
}
