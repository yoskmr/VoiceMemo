import Foundation

/// 高精度仕上げの結果
/// TASK-0044: 高精度仕上げ（REQ-018 / US-305 / AC-305）
public struct PolishResult: Equatable, Sendable {
    public let polishedText: String
    public let processingTimeMs: Int
    public let model: String

    public init(
        polishedText: String,
        processingTimeMs: Int = 0,
        model: String = "gpt-4o-mini"
    ) {
        self.polishedText = polishedText
        self.processingTimeMs = processingTimeMs
        self.model = model
    }
}
