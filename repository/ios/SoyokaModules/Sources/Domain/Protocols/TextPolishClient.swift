import Dependencies
import Foundation

/// 高精度仕上げの TCA Dependency
/// TASK-0044: 高精度仕上げ（REQ-018 / US-305 / AC-305）
/// クラウドLLM経由で文字起こし結果を後処理し、固有名詞補正・句読点最適化・フィラー除去・文体整形を行う
public struct TextPolishClient: Sendable {
    /// テキストを高精度で仕上げる
    public var polish: @Sendable (
        _ text: String,
        _ customDictionary: [(reading: String, display: String)]
    ) async throws -> PolishResult

    public init(
        polish: @escaping @Sendable (
            _ text: String,
            _ customDictionary: [(reading: String, display: String)]
        ) async throws -> PolishResult
    ) {
        self.polish = polish
    }
}

// MARK: - DependencyKey

extension TextPolishClient: TestDependencyKey {
    public static let testValue = TextPolishClient(
        polish: unimplemented(
            "TextPolishClient.polish",
            placeholder: PolishResult(polishedText: "")
        )
    )
}

extension DependencyValues {
    public var textPolish: TextPolishClient {
        get { self[TextPolishClient.self] }
        set { self[TextPolishClient.self] = newValue }
    }
}
