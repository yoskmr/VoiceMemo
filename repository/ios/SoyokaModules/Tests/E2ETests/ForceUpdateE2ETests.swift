@testable import InfraNetwork
import ComposableArchitecture
import XCTest

// AppReducer は SoyokaApp ターゲットにあるため、
// E2E テストでは ForceUpdateClient の振る舞いのみを検証する。

@MainActor
final class ForceUpdateE2ETests: XCTestCase {

    func test_check_updateRequired_正しいステータスを返す() async throws {
        let testURL = URL(string: "https://apps.apple.com/app/id123456")!
        let client = ForceUpdateClient(
            check: { _ in .updateRequired(storeURL: testURL) }
        )

        let status = try await client.check("https://api.example.com")
        XCTAssertEqual(status, .updateRequired(storeURL: testURL))
    }

    func test_check_upToDate_正しいステータスを返す() async throws {
        let client = ForceUpdateClient(
            check: { _ in .upToDate }
        )

        let status = try await client.check("https://api.example.com")
        XCTAssertEqual(status, .upToDate)
    }

    func test_check_networkError_エラーをスローする() async {
        let client = ForceUpdateClient(
            check: { _ in throw ForceUpdateError.networkError("timeout") }
        )

        do {
            _ = try await client.check("https://api.example.com")
            XCTFail("エラーがスローされるべき")
        } catch let error as ForceUpdateError {
            XCTAssertEqual(error, .networkError("timeout"))
        }
    }
}
