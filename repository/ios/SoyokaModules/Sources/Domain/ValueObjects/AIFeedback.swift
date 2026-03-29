import Foundation

/// AI整理結果へのフィードバック
public struct AIFeedback: Equatable, Sendable, Codable {
    public let memoID: UUID
    public let isPositive: Bool  // true = good, false = bad
    public let writingStyle: String
    public let promptVersion: String
    public let createdAt: Date

    public init(memoID: UUID, isPositive: Bool, writingStyle: String, promptVersion: String, createdAt: Date = Date()) {
        self.memoID = memoID
        self.isPositive = isPositive
        self.writingStyle = writingStyle
        self.promptVersion = promptVersion
        self.createdAt = createdAt
    }
}
