import Dependencies
import Foundation
import InfraLogging
import os.log

private let logger = Logger(subsystem: "app.soyoka", category: "ForceUpdate")

// MARK: - Response Type

struct VersionCheckResponse: Sendable, Equatable, Codable {
    let minimumVersion: String
    let storeUrl: String

    private enum CodingKeys: String, CodingKey {
        case minimumVersion = "minimum_version"
        case storeUrl = "store_url"
    }
}

// MARK: - Status

public enum ForceUpdateStatus: Sendable, Equatable {
    case upToDate
    case updateRequired(storeURL: URL)
}

// MARK: - Errors

public enum ForceUpdateError: Error, Sendable, Equatable {
    case invalidURL
    case networkError(String)
    case serverError(Int)
    case decodingFailed
}

// MARK: - ForceUpdateClient

public struct ForceUpdateClient: Sendable {
    public var check: @Sendable (_ baseURL: String) async throws -> ForceUpdateStatus

    public init(
        check: @escaping @Sendable (_ baseURL: String) async throws -> ForceUpdateStatus
    ) {
        self.check = check
    }
}

// MARK: - Semver Comparison

extension ForceUpdateClient {
    /// current < minimum なら true を返す
    public static func isVersionLessThan(_ current: String, minimum: String) -> Bool {
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let minimumParts = minimum.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(currentParts.count, minimumParts.count)
        for i in 0..<maxCount {
            let c = i < currentParts.count ? currentParts[i] : 0
            let m = i < minimumParts.count ? minimumParts[i] : 0
            if c < m { return true }
            if c > m { return false }
        }
        return false
    }
}

// MARK: - Live Implementation

extension ForceUpdateClient {
    /// 本番用クライアント
    public static func live(baseURL: URL) -> ForceUpdateClient {
        let session = URLSession.shared

        return ForceUpdateClient(
            check: { _ in
                let url = baseURL.appendingPathComponent("api/v1/version/check")

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 10

                let startTime = CFAbsoluteTimeGetCurrent()
                do {
                    let (data, response) = try await session.data(for: request)
                    let duration = CFAbsoluteTimeGetCurrent() - startTime
                    let responseBody = String(data: data, encoding: .utf8)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        let error = ForceUpdateError.networkError("Invalid response type")
                        #if DEBUG
                        await APIRequestLogStore.shared.append(APIRequestLog(
                            source: .network, endpoint: "api/v1/version/check", method: "GET",
                            status: .failure(message: error.localizedDescription), duration: duration,
                            request: RequestDetail(),
                            response: ResponseDetail(body: LogSanitizer.sanitizeBody(responseBody))
                        ))
                        #endif
                        throw error
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        let error = ForceUpdateError.serverError(httpResponse.statusCode)
                        #if DEBUG
                        await APIRequestLogStore.shared.append(APIRequestLog(
                            source: .network, endpoint: "api/v1/version/check", method: "GET",
                            status: .failure(message: error.localizedDescription), duration: duration,
                            request: RequestDetail(),
                            response: ResponseDetail(body: LogSanitizer.sanitizeBody(responseBody))
                        ))
                        #endif
                        throw error
                    }

                    let decoder = JSONDecoder()
                    guard let versionCheck = try? decoder.decode(VersionCheckResponse.self, from: data) else {
                        #if DEBUG
                        await APIRequestLogStore.shared.append(APIRequestLog(
                            source: .network, endpoint: "api/v1/version/check", method: "GET",
                            status: .failure(message: ForceUpdateError.decodingFailed.localizedDescription),
                            duration: duration,
                            request: RequestDetail(),
                            response: ResponseDetail(body: LogSanitizer.sanitizeBody(responseBody))
                        ))
                        #endif
                        throw ForceUpdateError.decodingFailed
                    }

                    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

                    #if DEBUG
                    await APIRequestLogStore.shared.append(APIRequestLog(
                        source: .network, endpoint: "api/v1/version/check", method: "GET",
                        status: .success(statusCode: httpResponse.statusCode), duration: duration,
                        request: RequestDetail(),
                        response: ResponseDetail(body: LogSanitizer.sanitizeBody(responseBody))
                    ))
                    #endif

                    if isVersionLessThan(currentVersion, minimum: versionCheck.minimumVersion) {
                        guard let storeURL = URL(string: versionCheck.storeUrl), !versionCheck.storeUrl.isEmpty else {
                            logger.error("store_url が無効: '\(versionCheck.storeUrl)' — 強制アップデートをスキップ")
                            return .upToDate
                        }
                        logger.info("強制アップデート: current=\(currentVersion) < minimum=\(versionCheck.minimumVersion)")
                        return .updateRequired(storeURL: storeURL)
                    }

                    logger.debug("バージョンOK: current=\(currentVersion) >= minimum=\(versionCheck.minimumVersion)")
                    return .upToDate
                } catch let error as ForceUpdateError {
                    throw error
                } catch {
                    let duration = CFAbsoluteTimeGetCurrent() - startTime
                    #if DEBUG
                    await APIRequestLogStore.shared.append(APIRequestLog(
                        source: .network, endpoint: "api/v1/version/check", method: "GET",
                        status: .failure(message: error.localizedDescription), duration: duration,
                        request: RequestDetail(), response: nil
                    ))
                    #endif
                    throw error
                }
            }
        )
    }
}

// MARK: - TCA DependencyKey

extension ForceUpdateClient: TestDependencyKey {
    public static let testValue = ForceUpdateClient(
        check: unimplemented("ForceUpdateClient.check")
    )
}

extension DependencyValues {
    public var forceUpdateClient: ForceUpdateClient {
        get { self[ForceUpdateClient.self] }
        set { self[ForceUpdateClient.self] = newValue }
    }
}
