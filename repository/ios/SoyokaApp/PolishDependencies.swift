import Dependencies
import Domain
import Foundation
import InfraNetwork

// MARK: - TextPolish Live Dependencies
// TASK-0044: 高精度仕上げの Live DI 接続

extension TextPolishClient: DependencyKey {
    public static let liveValue: TextPolishClient = {
        @Dependency(\.backendProxy) var backendProxy

        return TextPolishClient(
            polish: { text, customDictionary in
                let response = try await backendProxy.polishText(text, customDictionary)
                return PolishResult(
                    polishedText: response.polished_text,
                    processingTimeMs: response.metadata.processing_time_ms,
                    model: response.metadata.model
                )
            }
        )
    }()
}
