import Foundation

/// タグのドメインエンティティ
/// 01-Arch セクション5.2 準拠
public struct TagEntity: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var colorHex: String
    public var source: TagSource
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#FF9500",
        source: TagSource = .ai,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.source = source
        self.createdAt = createdAt
    }
}
