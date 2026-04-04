@testable import InfraLogging
import XCTest

@MainActor
final class LogSanitizerTests: XCTestCase {

    // MARK: - ヘッダーマスキング

    func test_sanitizeHeaders_Authorizationヘッダーがマスクされる() {
        let headers = [
            "Content-Type": "application/json",
            "Authorization": "Bearer eyJhbGci...",
        ]
        let result = LogSanitizer.sanitizeHeaders(headers)
        XCTAssertEqual(result?["Authorization"], "***")
        XCTAssertEqual(result?["Content-Type"], "application/json")
    }

    func test_sanitizeHeaders_複数の機密ヘッダーがマスクされる() {
        let headers = [
            "Cookie": "session=abc123",
            "Set-Cookie": "token=xyz",
            "X-API-Key": "sk-12345",
            "Accept": "application/json",
        ]
        let result = LogSanitizer.sanitizeHeaders(headers)
        XCTAssertEqual(result?["Cookie"], "***")
        XCTAssertEqual(result?["Set-Cookie"], "***")
        XCTAssertEqual(result?["X-API-Key"], "***")
        XCTAssertEqual(result?["Accept"], "application/json")
    }

    func test_sanitizeHeaders_nilの場合nilを返す() {
        XCTAssertNil(LogSanitizer.sanitizeHeaders(nil))
    }

    func test_sanitizeHeaders_大文字小文字を区別せずマスクする() {
        let headers = ["authorization": "Bearer token"]
        let result = LogSanitizer.sanitizeHeaders(headers)
        XCTAssertEqual(result?["authorization"], "***")
    }

    // MARK: - ボディマスキング

    func test_sanitizeBody_JSONのtokenフィールドがマスクされる() {
        let body = """
        {"access_token":"eyJhbG...","user":"test"}
        """
        let result = LogSanitizer.sanitizeBody(body)!
        XCTAssertFalse(result.contains("eyJhbG"))
        XCTAssertTrue(result.contains("test"))
    }

    func test_sanitizeBody_passwordフィールドがマスクされる() {
        let body = """
        {"password":"secret123","name":"test"}
        """
        let result = LogSanitizer.sanitizeBody(body)!
        XCTAssertFalse(result.contains("secret123"))
        XCTAssertTrue(result.contains("test"))
    }

    func test_sanitizeBody_16KB超はトリミングされる() {
        let largeBody = String(repeating: "a", count: 20_000)
        let result = LogSanitizer.sanitizeBody(largeBody)!
        XCTAssertLessThanOrEqual(result.utf8.count, 16_384 + 100) // マージン
        XCTAssertTrue(result.hasSuffix("...(truncated)"))
    }

    func test_sanitizeBody_nilの場合nilを返す() {
        XCTAssertNil(LogSanitizer.sanitizeBody(nil))
    }

    func test_sanitizeBody_JSON以外のテキストはそのまま返す() {
        let body = "plain text body"
        XCTAssertEqual(LogSanitizer.sanitizeBody(body), "plain text body")
    }
}
