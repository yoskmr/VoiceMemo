import Dependencies
import Domain
import Foundation
import InfraLogging
import os.log

private let logger = Logger(subsystem: "app.soyoka", category: "RemotePrompt")

// MARK: - Response Type

/// リモートプロンプト配信レスポンス
public struct RemotePromptResponse: Sendable, Equatable, Codable {
    public let version: String
    public let updatedAt: String
    public let templates: [String: String]
    public let basePrompt: String

    public init(version: String, updatedAt: String, templates: [String: String], basePrompt: String) {
        self.version = version
        self.updatedAt = updatedAt
        self.templates = templates
        self.basePrompt = basePrompt
    }
}

// MARK: - RemotePromptClient

/// プロンプトテンプレートのリモート取得クライアント
public struct RemotePromptClient: Sendable {
    /// 最新プロンプトを取得する
    public var fetchLatest: @Sendable (_ baseURL: String) async throws -> RemotePromptResponse

    public init(
        fetchLatest: @escaping @Sendable (_ baseURL: String) async throws -> RemotePromptResponse
    ) {
        self.fetchLatest = fetchLatest
    }
}

// MARK: - Cache Helpers

extension RemotePromptClient {
    private static let cacheKey = "cachedPromptTemplate"

    /// キャッシュされたレスポンスを読み込む
    public static var cached: RemotePromptResponse? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(RemotePromptResponse.self, from: data)
    }

    /// レスポンスをキャッシュに保存する
    public static func saveCache(_ response: RemotePromptResponse) {
        guard let data = try? JSONEncoder().encode(response) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}

// MARK: - Live Implementation

extension RemotePromptClient {
    /// 本番用クライアント
    public static func live() -> RemotePromptClient {
        let session = URLSession.shared

        return RemotePromptClient(
            fetchLatest: { baseURL in
                guard let url = URL(string: "\(baseURL)/api/v1/prompts/latest") else {
                    throw RemotePromptError.invalidURL
                }

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 10

                let startTime = CFAbsoluteTimeGetCurrent()
                do {
                    let (data, response) = try await session.data(for: request)
                    let duration = CFAbsoluteTimeGetCurrent() - startTime
                    let responseBody = String(data: data, encoding: .utf8)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        let error = RemotePromptError.networkError("Invalid response type")
                        #if DEBUG
                        await APIRequestLogStore.shared.append(APIRequestLog(
                            source: .network, endpoint: "api/v1/prompts/latest", method: "GET",
                            status: .failure(message: error.localizedDescription), duration: duration,
                            request: RequestDetail(),
                            response: ResponseDetail(body: LogSanitizer.sanitizeBody(responseBody))
                        ))
                        #endif
                        throw error
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        let error = RemotePromptError.serverError(httpResponse.statusCode)
                        #if DEBUG
                        await APIRequestLogStore.shared.append(APIRequestLog(
                            source: .network, endpoint: "api/v1/prompts/latest", method: "GET",
                            status: .failure(message: error.localizedDescription), duration: duration,
                            request: RequestDetail(),
                            response: ResponseDetail(body: LogSanitizer.sanitizeBody(responseBody))
                        ))
                        #endif
                        throw error
                    }

                    let promptResponse = try JSONDecoder().decode(RemotePromptResponse.self, from: data)
                    // キャッシュに保存
                    RemotePromptClient.saveCache(promptResponse)
                    logger.info("プロンプトテンプレート取得成功: version=\(promptResponse.version)")
                    #if DEBUG
                    await APIRequestLogStore.shared.append(APIRequestLog(
                        source: .network, endpoint: "api/v1/prompts/latest", method: "GET",
                        status: .success(statusCode: httpResponse.statusCode), duration: duration,
                        request: RequestDetail(),
                        response: ResponseDetail(body: LogSanitizer.sanitizeBody(responseBody))
                    ))
                    #endif
                    return promptResponse
                } catch let error as RemotePromptError {
                    throw error
                } catch {
                    let duration = CFAbsoluteTimeGetCurrent() - startTime
                    #if DEBUG
                    await APIRequestLogStore.shared.append(APIRequestLog(
                        source: .network, endpoint: "api/v1/prompts/latest", method: "GET",
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

// MARK: - Errors

/// リモートプロンプト取得エラー
public enum RemotePromptError: Error, Sendable, Equatable {
    case invalidURL
    case networkError(String)
    case serverError(Int)
    case decodingFailed(String)
}

// MARK: - TCA DependencyKey

extension RemotePromptClient: TestDependencyKey {
    public static let testValue = RemotePromptClient(
        fetchLatest: unimplemented("RemotePromptClient.fetchLatest")
    )
}

extension DependencyValues {
    public var remotePromptClient: RemotePromptClient {
        get { self[RemotePromptClient.self] }
        set { self[RemotePromptClient.self] = newValue }
    }
}
