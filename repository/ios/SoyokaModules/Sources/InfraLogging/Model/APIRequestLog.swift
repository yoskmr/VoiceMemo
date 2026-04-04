import Foundation

public enum LogSource: String, Sendable, Equatable, Codable {
    case network
    case llm
}

public enum LogStatus: Sendable, Equatable, Codable {
    case success(statusCode: Int?)
    case failure(message: String)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    public var displayText: String {
        switch self {
        case .success(let code):
            if let code { return "\(code) OK" }
            return "成功"
        case .failure(let message):
            return message
        }
    }
}

public struct RequestDetail: Sendable, Equatable, Codable {
    public let headers: [String: String]?
    public let body: String?

    public init(headers: [String: String]? = nil, body: String? = nil) {
        self.headers = headers
        self.body = body
    }
}

public struct ResponseDetail: Sendable, Equatable, Codable {
    public let headers: [String: String]?
    public let body: String?

    public init(headers: [String: String]? = nil, body: String? = nil) {
        self.headers = headers
        self.body = body
    }
}

public struct APIRequestLog: Identifiable, Sendable, Equatable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let source: LogSource
    public let endpoint: String
    public let method: String?
    public let status: LogStatus
    public let duration: TimeInterval
    public let request: RequestDetail
    public let response: ResponseDetail?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: LogSource,
        endpoint: String,
        method: String? = nil,
        status: LogStatus,
        duration: TimeInterval,
        request: RequestDetail,
        response: ResponseDetail? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.endpoint = endpoint
        self.method = method
        self.status = status
        self.duration = duration
        self.request = request
        self.response = response
    }

    /// ボディの推定バイトサイズ
    var estimatedBytes: Int {
        var total = 0
        total += request.body?.utf8.count ?? 0
        total += request.headers?.description.utf8.count ?? 0
        total += response?.body?.utf8.count ?? 0
        total += response?.headers?.description.utf8.count ?? 0
        total += endpoint.utf8.count + 100
        return total
    }
}
