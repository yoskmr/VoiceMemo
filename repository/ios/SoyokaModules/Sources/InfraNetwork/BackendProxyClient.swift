import Dependencies
import Domain
import Foundation
import os.log

private let logger = Logger(subsystem: "app.soyoka", category: "BackendProxy")

// MARK: - Request/Response Types

/// デバイス認証レスポンス
public struct AuthResponse: Sendable, Equatable, Codable {
    /// JWT アクセストークン
    public let accessToken: String
    /// トークン有効期限
    public let expiresAt: Date
    /// デバイスID（サーバー側で発行）
    public let deviceID: String

    public init(accessToken: String, expiresAt: Date, deviceID: String) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.deviceID = deviceID
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresAt = "expires_at"
        case deviceID = "device_id"
    }
}

/// AI処理リクエストオプション
public struct AIRequestOptions: Sendable, Equatable {
    /// 要約処理を実行するか
    public let summary: Bool
    /// タグ生成を実行するか
    public let tags: Bool
    /// 感情分析を実行するか
    public let sentiment: Bool

    public init(summary: Bool = true, tags: Bool = true, sentiment: Bool = false) {
        self.summary = summary
        self.tags = tags
        self.sentiment = sentiment
    }
}

/// Cloud AI処理レスポンス（Backend Proxy 形式）
public struct CloudAIResponse: Sendable, Equatable, Codable {
    /// 要約結果
    public let summary: CloudSummary?
    /// タグ結果
    public let tags: [CloudTag]?
    /// 感情分析結果
    public let sentiment: CloudSentiment?
    /// 使用量情報
    public let usage: CloudUsageInfo?
    /// メタデータ
    public let metadata: CloudMetadata?

    public init(
        summary: CloudSummary? = nil,
        tags: [CloudTag]? = nil,
        sentiment: CloudSentiment? = nil,
        usage: CloudUsageInfo? = nil,
        metadata: CloudMetadata? = nil
    ) {
        self.summary = summary
        self.tags = tags
        self.sentiment = sentiment
        self.usage = usage
        self.metadata = metadata
    }
}

/// Cloud要約結果
public struct CloudSummary: Sendable, Equatable, Codable {
    public let title: String
    public let brief: String
    public let keyPoints: [String]

    public init(title: String, brief: String, keyPoints: [String] = []) {
        self.title = title
        self.brief = brief
        self.keyPoints = keyPoints
    }

    private enum CodingKeys: String, CodingKey {
        case title, brief
        case keyPoints = "key_points"
    }
}

/// Cloudタグ結果
public struct CloudTag: Sendable, Equatable, Codable {
    public let label: String
    public let confidence: Double

    public init(label: String, confidence: Double) {
        self.label = label
        self.confidence = confidence
    }
}

/// Cloud感情分析結果
public struct CloudSentiment: Sendable, Equatable, Codable {
    /// 主要感情（文字列: "joy", "calm", "anticipation" 等）
    public let primary: String
    /// 各感情のスコア
    public let scores: [String: Double]
    /// 根拠テキスト
    public let evidence: [CloudSentimentEvidence]

    public init(primary: String, scores: [String: Double], evidence: [CloudSentimentEvidence] = []) {
        self.primary = primary
        self.scores = scores
        self.evidence = evidence
    }
}

/// Cloud感情分析の根拠
public struct CloudSentimentEvidence: Sendable, Equatable, Codable {
    public let text: String
    public let emotion: String

    public init(text: String, emotion: String) {
        self.text = text
        self.emotion = emotion
    }
}

/// Cloud使用量情報（レスポンス内埋め込み）
public struct CloudUsageInfo: Sendable, Equatable, Codable {
    public let tokensUsed: Int

    public init(tokensUsed: Int) {
        self.tokensUsed = tokensUsed
    }

    private enum CodingKeys: String, CodingKey {
        case tokensUsed = "tokens_used"
    }
}

/// Cloudメタデータ
public struct CloudMetadata: Sendable, Equatable, Codable {
    public let model: String
    public let processingTimeMs: Int

    public init(model: String, processingTimeMs: Int) {
        self.model = model
        self.processingTimeMs = processingTimeMs
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case processingTimeMs = "processing_time_ms"
    }
}

/// Cloud使用量レスポンス（GET /api/v1/usage）
public struct CloudUsageResponse: Sendable, Equatable, Codable {
    /// 使用済み回数
    public let used: Int
    /// 月間上限回数
    public let limit: Int
    /// プラン名
    public let plan: String
    /// リセット日時
    public let resetsAt: Date

    public init(used: Int, limit: Int, plan: String, resetsAt: Date) {
        self.used = used
        self.limit = limit
        self.plan = plan
        self.resetsAt = resetsAt
    }

    private enum CodingKeys: String, CodingKey {
        case used, limit, plan
        case resetsAt = "resets_at"
    }
}

// MARK: - BackendProxyClient

/// Backend Proxy との通信クライアント
/// 統合仕様書 INT-SPEC-001 セクション3.3 準拠
public struct BackendProxyClient: Sendable {
    /// デバイス認証（JWT取得）
    public var authenticate: @Sendable (_ deviceID: String, _ appVersion: String, _ osVersion: String) async throws -> AuthResponse
    /// AI処理リクエスト
    public var processAI: @Sendable (_ text: String, _ language: String, _ options: AIRequestOptions) async throws -> CloudAIResponse
    /// 使用量取得
    public var getUsage: @Sendable () async throws -> CloudUsageResponse

    public init(
        authenticate: @escaping @Sendable (_ deviceID: String, _ appVersion: String, _ osVersion: String) async throws -> AuthResponse,
        processAI: @escaping @Sendable (_ text: String, _ language: String, _ options: AIRequestOptions) async throws -> CloudAIResponse,
        getUsage: @escaping @Sendable () async throws -> CloudUsageResponse
    ) {
        self.authenticate = authenticate
        self.processAI = processAI
        self.getUsage = getUsage
    }
}

// MARK: - BackendProxy Errors

/// Backend Proxy 通信エラー
public enum BackendProxyError: Error, Sendable, Equatable {
    /// 認証失敗
    case authenticationFailed(String)
    /// トークン取得不可（未認証）
    case tokenNotFound
    /// ネットワークエラー
    case networkError(String)
    /// サーバーエラー（ステータスコード付き）
    case serverError(Int)
    /// レスポンスのデコード失敗
    case decodingFailed(String)
    /// 使用量上限到達
    case quotaExceeded
}

// MARK: - Live Implementation

extension BackendProxyClient {

    /// 本番用 BackendProxyClient を生成する
    ///
    /// - Parameters:
    ///   - baseURL: Backend Proxy の Base URL
    ///   - keychainManager: Keychain管理（JWT保存・取得）
    /// - Returns: 本番用クライアント
    public static func live(
        baseURL: URL,
        keychainManager: KeychainManager = KeychainManager()
    ) -> BackendProxyClient {
        let session = URLSession.shared

        // 共有 JSONDecoder（ISO 8601日時対応）
        let decoder: JSONDecoder = {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            return d
        }()

        return BackendProxyClient(
            authenticate: { deviceID, appVersion, osVersion in
                let url = baseURL.appendingPathComponent("api/v1/auth/device")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let body: [String: String] = [
                    "device_id": deviceID,
                    "app_version": appVersion,
                    "os_version": osVersion,
                ]
                request.httpBody = try JSONEncoder().encode(body)

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw BackendProxyError.networkError("Invalid response type")
                }

                guard httpResponse.statusCode == 200 else {
                    throw BackendProxyError.authenticationFailed("HTTP \(httpResponse.statusCode)")
                }

                let authResponse = try decoder.decode(AuthResponse.self, from: data)

                // JWT を Keychain に保存
                try keychainManager.save(key: .accessToken, string: authResponse.accessToken)

                logger.info("デバイス認証成功: device_id=\(authResponse.deviceID)")
                return authResponse
            },

            processAI: { text, language, options in
                // JWT を Keychain から取得
                guard let token = keychainManager.loadString(key: .accessToken) else {
                    throw BackendProxyError.tokenNotFound
                }

                let url = baseURL.appendingPathComponent("api/v1/ai/process")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                let body: [String: Any] = [
                    "text": text,
                    "language": language,
                    "options": [
                        "summary": options.summary,
                        "tags": options.tags,
                        "sentiment": options.sentiment,
                    ],
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw BackendProxyError.networkError("Invalid response type")
                }

                // 401: トークン期限切れ → 再認証が必要
                if httpResponse.statusCode == 401 {
                    logger.warning("AI処理: 401 Unauthorized → 再認証が必要")
                    throw BackendProxyError.tokenNotFound
                }

                // 429: 使用量上限
                if httpResponse.statusCode == 429 {
                    throw BackendProxyError.quotaExceeded
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw BackendProxyError.serverError(httpResponse.statusCode)
                }

                do {
                    let aiResponse = try decoder.decode(CloudAIResponse.self, from: data)
                    logger.info("AI処理成功: model=\(aiResponse.metadata?.model ?? "unknown")")
                    return aiResponse
                } catch {
                    throw BackendProxyError.decodingFailed(error.localizedDescription)
                }
            },

            getUsage: {
                // JWT を Keychain から取得
                guard let token = keychainManager.loadString(key: .accessToken) else {
                    throw BackendProxyError.tokenNotFound
                }

                let url = baseURL.appendingPathComponent("api/v1/usage")
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw BackendProxyError.networkError("Invalid response type")
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw BackendProxyError.serverError(httpResponse.statusCode)
                }

                do {
                    let usageResponse = try decoder.decode(CloudUsageResponse.self, from: data)
                    logger.info("使用量取得成功: \(usageResponse.used)/\(usageResponse.limit)")
                    return usageResponse
                } catch {
                    throw BackendProxyError.decodingFailed(error.localizedDescription)
                }
            }
        )
    }
}

// MARK: - TCA DependencyKey

extension BackendProxyClient: TestDependencyKey {
    public static let testValue = BackendProxyClient(
        authenticate: unimplemented("BackendProxyClient.authenticate"),
        processAI: unimplemented("BackendProxyClient.processAI"),
        getUsage: unimplemented("BackendProxyClient.getUsage")
    )
}

extension DependencyValues {
    public var backendProxy: BackendProxyClient {
        get { self[BackendProxyClient.self] }
        set { self[BackendProxyClient.self] = newValue }
    }
}
