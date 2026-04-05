import Dependencies
import Domain
import Foundation
import InfraLogging
import InfraNetwork
import UIKit

// MARK: - TextPolish Live Dependencies
// TASK-0044: 高精度仕上げの Live DI 接続

extension TextPolishClient: DependencyKey {
    public static let liveValue = TextPolishClient(
        polish: { text, customDictionary in
            @Dependency(\.backendProxy) var backendProxy

            let startTime = CFAbsoluteTimeGetCurrent()

            do {
                let response: PolishResponseDTO
                do {
                    response = try await backendProxy.polishText(text, customDictionary)
                } catch BackendProxyError.tokenNotFound {
                    // 自動認証
                    let deviceID = await UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
                    let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
                    _ = try await backendProxy.authenticate(deviceID, appVersion, osVersion)
                    response = try await backendProxy.polishText(text, customDictionary)
                }

                let duration = CFAbsoluteTimeGetCurrent() - startTime
                #if DEBUG
                await APIRequestLogStore.shared.append(APIRequestLog(
                    source: .network,
                    endpoint: "/api/v1/ai/polish",
                    method: "POST",
                    status: .success(statusCode: 200),
                    duration: duration,
                    request: RequestDetail(body: "text: \(text.prefix(80))..., dict: \(customDictionary.count)件"),
                    response: ResponseDetail(body: "polished: \(response.polished_text.prefix(100))...")
                ))
                #endif

                return PolishResult(
                    polishedText: response.polished_text,
                    processingTimeMs: response.metadata.processing_time_ms,
                    model: response.metadata.model
                )
            } catch {
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                #if DEBUG
                await APIRequestLogStore.shared.append(APIRequestLog(
                    source: .network,
                    endpoint: "/api/v1/ai/polish",
                    method: "POST",
                    status: .failure(message: error.localizedDescription),
                    duration: duration,
                    request: RequestDetail(body: "text: \(text.prefix(80))..."),
                    response: nil
                ))
                #endif
                throw error
            }
        }
    )
}
