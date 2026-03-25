import XCTest
@testable import Domain
@testable import InfraLLM

final class MockLLMProviderTests: XCTestCase {

    // MARK: - デフォルト動作

    func testProcess_defaultResponse_returnsSummaryAndTags() async throws {
        let provider = MockLLMProvider()
        let request = LLMRequest(text: "テストテキスト", tasks: [.summarize, .tagging])

        let response = try await provider.process(request)

        XCTAssertNotNil(response.summary)
        XCTAssertFalse(response.tags.isEmpty)
        XCTAssertEqual(response.provider, .onDeviceLlamaCpp)
    }

    func testProcess_summarizeOnly_returnsOnlySummary() async throws {
        let provider = MockLLMProvider()
        let request = LLMRequest(text: "テストテキスト", tasks: [.summarize])

        let response = try await provider.process(request)

        XCTAssertNotNil(response.summary)
        XCTAssertTrue(response.tags.isEmpty)
    }

    func testProcess_taggingOnly_returnsOnlyTags() async throws {
        let provider = MockLLMProvider()
        let request = LLMRequest(text: "テストテキスト", tasks: [.tagging])

        let response = try await provider.process(request)

        XCTAssertNil(response.summary)
        XCTAssertFalse(response.tags.isEmpty)
    }

    // MARK: - カスタムレスポンス

    func testProcess_customResponse_returnsCustom() async throws {
        let customResponse = LLMResponse(
            summary: LLMSummaryResult(title: "カスタム", brief: "カスタム要約"),
            tags: [LLMTagResult(label: "テスト", confidence: 1.0)],
            processingTimeMs: 42,
            provider: .cloudGPT4oMini
        )
        let provider = MockLLMProvider(mockResponse: customResponse)
        let request = LLMRequest(text: "テスト", tasks: [.summarize, .tagging])

        let response = try await provider.process(request)

        XCTAssertEqual(response.summary?.title, "カスタム")
        XCTAssertEqual(response.processingTimeMs, 42)
        XCTAssertEqual(response.provider, .cloudGPT4oMini)
    }

    // MARK: - エラー注入

    func testProcess_mockError_throwsError() async {
        let provider = MockLLMProvider(mockError: .modelNotFound)
        let request = LLMRequest(text: "テスト", tasks: [.summarize])

        do {
            _ = try await provider.process(request)
            XCTFail("エラーが投げられるべき")
        } catch {
            XCTAssertEqual(error as? LLMError, .modelNotFound)
        }
    }

    // MARK: - 呼び出し記録

    func testProcess_tracksCallCount() async throws {
        let provider = MockLLMProvider()
        let request = LLMRequest(text: "テスト", tasks: [.summarize])

        XCTAssertEqual(provider.processCallCount, 0)

        _ = try await provider.process(request)
        XCTAssertEqual(provider.processCallCount, 1)

        _ = try await provider.process(request)
        XCTAssertEqual(provider.processCallCount, 2)
    }

    func testProcess_tracksLastRequest() async throws {
        let provider = MockLLMProvider()
        let request = LLMRequest(text: "特定のテキスト", tasks: [.summarize, .tagging], language: "en")

        _ = try await provider.process(request)

        XCTAssertEqual(provider.lastRequest?.text, "特定のテキスト")
        XCTAssertEqual(provider.lastRequest?.language, "en")
    }

    // MARK: - isAvailable / providerType

    func testIsAvailable_alwaysTrue() async {
        let provider = MockLLMProvider()
        let available = await provider.isAvailable()
        XCTAssertTrue(available)
    }

    func testProviderType_isOnDeviceLlamaCpp() {
        let provider = MockLLMProvider()
        XCTAssertEqual(provider.providerType, .onDeviceLlamaCpp)
    }

    // MARK: - asClient

    func testAsClient_process_delegatesToMock() async throws {
        let provider = MockLLMProvider()
        let client = provider.asClient()
        let request = LLMRequest(text: "テスト", tasks: [.summarize])

        let response = try await client.process(request)

        XCTAssertNotNil(response.summary)
        XCTAssertEqual(provider.processCallCount, 1)
    }

    func testAsClient_isAvailable_delegatesToMock() async {
        let provider = MockLLMProvider()
        let client = provider.asClient()

        let available = await client.isAvailable()

        XCTAssertTrue(available)
    }

    func testAsClient_providerType_delegatesToMock() {
        let provider = MockLLMProvider()
        let client = provider.asClient()

        XCTAssertEqual(client.providerType(), .onDeviceLlamaCpp)
    }
}
