import Dependencies
import Foundation

/// TemporaryRecordingStoreProtocol の TCA Dependency ラッパー
/// @Dependency(\.temporaryRecordingStore) でReducerから注入可能にする
public struct TemporaryRecordingStoreClient: Sendable {
    /// 指定された録音セッションの一時ファイルを全削除する
    public var cleanup: @Sendable (_ recordingID: UUID) throws -> Void

    public init(
        cleanup: @escaping @Sendable (_ recordingID: UUID) throws -> Void
    ) {
        self.cleanup = cleanup
    }
}

// MARK: - DependencyKey

extension TemporaryRecordingStoreClient: TestDependencyKey {
    public static let testValue = TemporaryRecordingStoreClient(
        cleanup: unimplemented("TemporaryRecordingStoreClient.cleanup")
    )
}

extension DependencyValues {
    public var temporaryRecordingStore: TemporaryRecordingStoreClient {
        get { self[TemporaryRecordingStoreClient.self] }
        set { self[TemporaryRecordingStoreClient.self] = newValue }
    }
}
