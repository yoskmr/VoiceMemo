import Foundation

public actor APIRequestLogStore {
    public static let shared = APIRequestLogStore()

    private var logs: [APIRequestLog] = []
    private var totalBytes: Int = 0

    private let maxEntries = 100
    private let maxTotalBytes = 1_048_576 // 1MB

    public init() {}

    public func append(_ log: APIRequestLog) {
        let entryBytes = log.estimatedBytes
        logs.insert(log, at: 0)
        totalBytes += entryBytes

        while logs.count > maxEntries {
            let removed = logs.removeLast()
            totalBytes -= removed.estimatedBytes
        }

        while totalBytes > maxTotalBytes, logs.count > 1 {
            let removed = logs.removeLast()
            totalBytes -= removed.estimatedBytes
        }
    }

    public func getAll() -> [APIRequestLog] { logs }

    public func clear() {
        logs.removeAll()
        totalBytes = 0
    }

    public func export() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601

        struct ExportData: Codable {
            let exportedAt: Date
            let count: Int
            let logs: [APIRequestLog]
        }

        let data = ExportData(exportedAt: Date(), count: logs.count, logs: logs)
        do {
            let jsonData = try encoder.encode(data)
            guard let json = String(data: jsonData, encoding: .utf8) else {
                return "{\"error\": \"utf8 conversion failed\"}"
            }
            return json
        } catch {
            return "{\"error\": \"export failed: \(error)\"}"
        }
    }
}
