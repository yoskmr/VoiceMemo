import Dependencies
import Domain
import Foundation
import InfraNetwork
import UIKit

// MARK: - TextPolish Live Dependencies
// TASK-0044: 高精度仕上げの Live DI 接続

extension TextPolishClient: DependencyKey {
    public static let liveValue = TextPolishClient(
        polish: { text, customDictionary in
            @Dependency(\.backendProxy) var backendProxy

            // Backend Proxy 経由で POST /api/v1/ai/polish を呼び出す
            // トークン未取得時は自動認証してリトライする
            do {
                let response = try await backendProxy.polishText(text, customDictionary)
                return PolishResult(
                    polishedText: response.polished_text,
                    processingTimeMs: response.metadata.processing_time_ms,
                    model: response.metadata.model
                )
            } catch BackendProxyError.tokenNotFound {
                // 自動認証: デバイス情報を取得して JWT を取得
                let deviceID = await UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
                let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
                let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
                _ = try await backendProxy.authenticate(deviceID, appVersion, osVersion)

                // リトライ
                let response = try await backendProxy.polishText(text, customDictionary)
                return PolishResult(
                    polishedText: response.polished_text,
                    processingTimeMs: response.metadata.processing_time_ms,
                    model: response.metadata.model
                )
            }
        }
    )
}
