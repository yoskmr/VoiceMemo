import Foundation

/// AI要約結果のドメインエンティティ
/// 01-Arch セクション5.2 準拠
public struct AISummaryEntity: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var summaryText: String
    public var keyPoints: [String]
    public var providerType: LLMProviderType
    public var isOnDevice: Bool
    public var generatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "",
        summaryText: String,
        keyPoints: [String] = [],
        providerType: LLMProviderType = .onDeviceLlamaCpp,
        isOnDevice: Bool = true,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.summaryText = summaryText
        self.keyPoints = keyPoints
        self.providerType = providerType
        self.isOnDevice = isOnDevice
        self.generatedAt = generatedAt
    }
}
