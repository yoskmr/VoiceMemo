import XCTest
@testable import Domain

final class LLMProviderClientTests: XCTestCase {

    // MARK: - LLMTask テスト

    func testLLMTask_allCases() {
        XCTAssertEqual(LLMTask.allCases.count, 2)
        XCTAssertTrue(LLMTask.allCases.contains(.summarize))
        XCTAssertTrue(LLMTask.allCases.contains(.tagging))
    }

    func testLLMTask_rawValues() {
        XCTAssertEqual(LLMTask.summarize.rawValue, "summarize")
        XCTAssertEqual(LLMTask.tagging.rawValue, "tagging")
    }

    // MARK: - LLMRequest テスト

    func testLLMRequest_defaultValues() {
        let request = LLMRequest(text: "テスト", tasks: [.summarize])

        XCTAssertEqual(request.text, "テスト")
        XCTAssertEqual(request.tasks, [.summarize])
        XCTAssertEqual(request.language, "ja")
        XCTAssertEqual(request.maxTokens, 650)
    }

    func testLLMRequest_customValues() {
        let request = LLMRequest(text: "hello", tasks: [.summarize, .tagging], language: "en", maxTokens: 500)

        XCTAssertEqual(request.text, "hello")
        XCTAssertEqual(request.tasks, [.summarize, .tagging])
        XCTAssertEqual(request.language, "en")
        XCTAssertEqual(request.maxTokens, 500)
    }

    func testLLMRequest_equatable() {
        let a = LLMRequest(text: "same", tasks: [.summarize])
        let b = LLMRequest(text: "same", tasks: [.summarize])
        let c = LLMRequest(text: "different", tasks: [.summarize])

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - LLMResponse テスト

    func testLLMResponse_equatable() {
        let response1 = LLMResponse(
            summary: LLMSummaryResult(title: "T", brief: "B"),
            tags: [LLMTagResult(label: "L", confidence: 0.8)],
            processingTimeMs: 100,
            provider: .onDeviceLlamaCpp
        )
        let response2 = LLMResponse(
            summary: LLMSummaryResult(title: "T", brief: "B"),
            tags: [LLMTagResult(label: "L", confidence: 0.8)],
            processingTimeMs: 100,
            provider: .onDeviceLlamaCpp
        )

        XCTAssertEqual(response1, response2)
    }

    func testLLMResponse_withNilSummary() {
        let response = LLMResponse(
            summary: nil,
            tags: [LLMTagResult(label: "tag", confidence: 0.5)],
            processingTimeMs: 50,
            provider: .cloudGPT4oMini
        )

        XCTAssertNil(response.summary)
        XCTAssertEqual(response.tags.count, 1)
        XCTAssertEqual(response.provider, .cloudGPT4oMini)
    }

    // MARK: - LLMSummaryResult テスト

    func testLLMSummaryResult_defaultKeyPoints() {
        let summary = LLMSummaryResult(title: "タイトル", brief: "要約")

        XCTAssertEqual(summary.keyPoints, [])
    }

    func testLLMSummaryResult_withKeyPoints() {
        let summary = LLMSummaryResult(title: "T", brief: "B", keyPoints: ["point1", "point2"])

        XCTAssertEqual(summary.keyPoints.count, 2)
    }

    // MARK: - LLMTagResult テスト

    func testLLMTagResult_equatable() {
        let a = LLMTagResult(label: "会議", confidence: 0.9)
        let b = LLMTagResult(label: "会議", confidence: 0.9)
        let c = LLMTagResult(label: "メモ", confidence: 0.9)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
