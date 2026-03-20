import Dependencies
import Foundation

/// VoiceMemoRepositoryProtocol の TCA Dependency ラッパー
/// @Dependency(\.voiceMemoRepository) でReducerから注入可能にする
public struct VoiceMemoRepositoryClient: Sendable {
    public var save: @Sendable (_ memo: VoiceMemoEntity) async throws -> Void
    public var fetchByID: @Sendable (_ id: UUID) async throws -> VoiceMemoEntity?
    public var fetchAll: @Sendable () async throws -> [VoiceMemoEntity]
    public var delete: @Sendable (_ id: UUID) async throws -> Void
    /// ページネーション対応のメモ取得（TASK-0011）
    public var fetchMemos: @Sendable (_ page: Int, _ pageSize: Int) async throws -> [VoiceMemoEntity]
    /// メモ詳細取得（TASK-0012）
    public var fetchMemoDetail: @Sendable (_ id: UUID) async throws -> VoiceMemoEntity
    /// メモテキスト更新（TASK-0013）
    public var updateMemoText: @Sendable (_ id: UUID, _ title: String, _ transcriptionText: String) async throws -> Void
    /// 音声ファイルパス取得（TASK-0017 削除前に取得）
    public var getAudioFilePath: @Sendable (_ id: UUID) async throws -> String
    /// 全タグ一覧取得（TASK-0016 検索フィルター用）
    public var fetchAllTags: @Sendable () async throws -> [String]
    /// 検索用メモ情報取得（TASK-0016）
    public var fetchMemoForSearch: @Sendable (_ id: UUID) async throws -> SearchableMemo?

    public init(
        save: @escaping @Sendable (_ memo: VoiceMemoEntity) async throws -> Void,
        fetchByID: @escaping @Sendable (_ id: UUID) async throws -> VoiceMemoEntity?,
        fetchAll: @escaping @Sendable () async throws -> [VoiceMemoEntity],
        delete: @escaping @Sendable (_ id: UUID) async throws -> Void,
        fetchMemos: @escaping @Sendable (_ page: Int, _ pageSize: Int) async throws -> [VoiceMemoEntity] = { _, _ in [] },
        fetchMemoDetail: @escaping @Sendable (_ id: UUID) async throws -> VoiceMemoEntity = { _ in
            throw NSError(domain: "VoiceMemoRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
        },
        updateMemoText: @escaping @Sendable (_ id: UUID, _ title: String, _ transcriptionText: String) async throws -> Void = { _, _, _ in },
        getAudioFilePath: @escaping @Sendable (_ id: UUID) async throws -> String = { _ in "" },
        fetchAllTags: @escaping @Sendable () async throws -> [String] = { [] },
        fetchMemoForSearch: @escaping @Sendable (_ id: UUID) async throws -> SearchableMemo? = { _ in nil }
    ) {
        self.save = save
        self.fetchByID = fetchByID
        self.fetchAll = fetchAll
        self.delete = delete
        self.fetchMemos = fetchMemos
        self.fetchMemoDetail = fetchMemoDetail
        self.updateMemoText = updateMemoText
        self.getAudioFilePath = getAudioFilePath
        self.fetchAllTags = fetchAllTags
        self.fetchMemoForSearch = fetchMemoForSearch
    }
}

/// 検索結果表示用の軽量メモ情報（TASK-0016）
public struct SearchableMemo: Sendable, Equatable {
    public let title: String
    public let createdAt: Date
    public let emotion: EmotionCategory?
    public let durationSeconds: Double
    public let tags: [String]

    public init(
        title: String,
        createdAt: Date,
        emotion: EmotionCategory?,
        durationSeconds: Double,
        tags: [String]
    ) {
        self.title = title
        self.createdAt = createdAt
        self.emotion = emotion
        self.durationSeconds = durationSeconds
        self.tags = tags
    }
}

// MARK: - DependencyKey

extension VoiceMemoRepositoryClient: TestDependencyKey {
    public static let testValue = VoiceMemoRepositoryClient(
        save: unimplemented("VoiceMemoRepositoryClient.save"),
        fetchByID: unimplemented("VoiceMemoRepositoryClient.fetchByID"),
        fetchAll: unimplemented("VoiceMemoRepositoryClient.fetchAll"),
        delete: unimplemented("VoiceMemoRepositoryClient.delete"),
        fetchMemos: unimplemented("VoiceMemoRepositoryClient.fetchMemos"),
        fetchMemoDetail: unimplemented("VoiceMemoRepositoryClient.fetchMemoDetail"),
        updateMemoText: unimplemented("VoiceMemoRepositoryClient.updateMemoText"),
        getAudioFilePath: unimplemented("VoiceMemoRepositoryClient.getAudioFilePath"),
        fetchAllTags: unimplemented("VoiceMemoRepositoryClient.fetchAllTags"),
        fetchMemoForSearch: unimplemented("VoiceMemoRepositoryClient.fetchMemoForSearch")
    )
}

extension DependencyValues {
    public var voiceMemoRepository: VoiceMemoRepositoryClient {
        get { self[VoiceMemoRepositoryClient.self] }
        set { self[VoiceMemoRepositoryClient.self] = newValue }
    }
}
