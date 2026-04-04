import Foundation

/// きおくに聞く の会話メッセージ
/// TASK-0041: AI対話機能（REQ-031 / US-309 / AC-309）
public struct ChatMessage: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let role: Role
    public let text: String
    public let referencedMemoIDs: [UUID]
    public let createdAt: Date

    public enum Role: String, Equatable, Sendable {
        case user
        case assistant
    }

    public init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        referencedMemoIDs: [UUID] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.referencedMemoIDs = referencedMemoIDs
        self.createdAt = createdAt
    }
}
