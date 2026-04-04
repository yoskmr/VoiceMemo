import Dependencies
import Foundation

/// きおくに聞く（AI対話）の TCA Dependency
/// TASK-0041: AI対話機能（REQ-031 / US-309 / AC-309）
public struct MemoConversationClient: Sendable {
    /// メモコンテキスト付きでAIに質問を送信
    public var sendQuestion: @Sendable (
        _ question: String,
        _ contextMemos: [MemoContext]
    ) async throws -> ChatResponse

    public init(
        sendQuestion: @escaping @Sendable (
            _ question: String,
            _ contextMemos: [MemoContext]
        ) async throws -> ChatResponse
    ) {
        self.sendQuestion = sendQuestion
    }
}

/// AI対話のコンテキストに含めるメモ情報
public struct MemoContext: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let text: String
    public let date: String
    public let emotion: String?
    public let tags: [String]

    public init(
        id: UUID,
        title: String,
        text: String,
        date: String,
        emotion: String?,
        tags: [String]
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.date = date
        self.emotion = emotion
        self.tags = tags
    }
}

/// AI対話のレスポンス
public struct ChatResponse: Equatable, Sendable {
    public let answer: String
    public let referencedMemoIDs: [String]

    public init(answer: String, referencedMemoIDs: [String]) {
        self.answer = answer
        self.referencedMemoIDs = referencedMemoIDs
    }
}

// MARK: - DependencyKey

extension MemoConversationClient: TestDependencyKey {
    public static let testValue = MemoConversationClient(
        sendQuestion: unimplemented(
            "MemoConversationClient.sendQuestion",
            placeholder: ChatResponse(answer: "", referencedMemoIDs: [])
        )
    )
}

extension DependencyValues {
    public var memoConversation: MemoConversationClient {
        get { self[MemoConversationClient.self] }
        set { self[MemoConversationClient.self] = newValue }
    }
}
