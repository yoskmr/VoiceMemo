@testable import InfraLogging
import XCTest

@MainActor
final class APIRequestLogStoreTests: XCTestCase {

    private func makeLog(
        source: LogSource = .network,
        endpoint: String = "/api/v1/test",
        method: String? = "GET",
        status: LogStatus = .success(statusCode: 200),
        duration: TimeInterval = 0.5,
        bodySize: Int = 100
    ) -> APIRequestLog {
        APIRequestLog(
            source: source,
            endpoint: endpoint,
            method: method,
            status: status,
            duration: duration,
            request: RequestDetail(body: String(repeating: "x", count: bodySize)),
            response: ResponseDetail(body: String(repeating: "y", count: bodySize))
        )
    }

    func test_append_ログが追加される() async {
        let store = APIRequestLogStore()
        let log = makeLog()
        await store.append(log)
        let logs = await store.getAll()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.endpoint, "/api/v1/test")
    }

    func test_append_複数ログが新しい順に返される() async {
        let store = APIRequestLogStore()
        await store.append(makeLog(endpoint: "/first"))
        await store.append(makeLog(endpoint: "/second"))
        let logs = await store.getAll()
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(logs.first?.endpoint, "/second")
    }

    func test_append_100件を超えると古いログが削除される() async {
        let store = APIRequestLogStore()
        for i in 0..<110 {
            await store.append(makeLog(endpoint: "/api/\(i)", bodySize: 10))
        }
        let logs = await store.getAll()
        XCTAssertEqual(logs.count, 100)
        XCTAssertEqual(logs.first?.endpoint, "/api/109")
        XCTAssertEqual(logs.last?.endpoint, "/api/10")
    }

    func test_append_総容量1MBを超えると古いログが削除される() async {
        let store = APIRequestLogStore()
        for i in 0..<15 {
            await store.append(makeLog(endpoint: "/api/\(i)", bodySize: 50_000))
        }
        let logs = await store.getAll()
        let totalBytes = logs.reduce(0) { $0 + $1.estimatedBytes }
        XCTAssertLessThanOrEqual(totalBytes, 1_048_576)
    }

    func test_clear_全ログが削除される() async {
        let store = APIRequestLogStore()
        await store.append(makeLog())
        await store.append(makeLog())
        await store.clear()
        let logs = await store.getAll()
        XCTAssertTrue(logs.isEmpty)
    }

    func test_export_JSON形式で出力される() async {
        let store = APIRequestLogStore()
        await store.append(makeLog(endpoint: "/api/v1/test"))
        let json = await store.export()
        XCTAssertTrue(json.contains("/api/v1/test"))
        XCTAssertTrue(json.contains("exportedAt"))
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(json.utf8)))
    }
}
