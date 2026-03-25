import Foundation
import SwiftData
import Domain

/// SwiftData @Model: タグ
/// 01-Arch セクション5.2 準拠
@Model
public final class TagModel {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var colorHex: String
    public var sourceRawValue: String
    public var createdAt: Date

    @Relationship(inverse: \VoiceMemoModel.tags)
    public var memos: [VoiceMemoModel]

    public var source: TagSource {
        get { TagSource(rawValue: sourceRawValue) ?? .ai }
        set { sourceRawValue = newValue.rawValue }
    }

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
        self.sourceRawValue = source.rawValue
        self.createdAt = createdAt
        self.memos = []
    }

    /// ドメインエンティティに変換
    public func toEntity() -> TagEntity {
        TagEntity(
            id: id,
            name: name,
            colorHex: colorHex,
            source: source,
            createdAt: createdAt
        )
    }
}
