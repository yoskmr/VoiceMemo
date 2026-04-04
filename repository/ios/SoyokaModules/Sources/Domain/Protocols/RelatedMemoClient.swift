import Dependencies
import Foundation

/// 関連メモ検索の TCA Dependency
/// TASK-0043: きおくのつながり Phase 1（REQ-033 / US-311 / AC-311）
public struct RelatedMemoClient: Sendable {
    /// 指定メモに関連するメモを検索（最大5件）
    public var findRelated: @Sendable (_ memoID: UUID, _ title: String, _ tags: [String]) async throws -> [RelatedMemo]

    public init(
        findRelated: @escaping @Sendable (_ memoID: UUID, _ title: String, _ tags: [String]) async throws -> [RelatedMemo]
    ) {
        self.findRelated = findRelated
    }
}

// MARK: - DependencyKey

extension RelatedMemoClient: TestDependencyKey {
    public static let testValue = RelatedMemoClient(
        findRelated: unimplemented("RelatedMemoClient.findRelated", placeholder: [])
    )
}

extension DependencyValues {
    public var relatedMemo: RelatedMemoClient {
        get { self[RelatedMemoClient.self] }
        set { self[RelatedMemoClient.self] = newValue }
    }
}
