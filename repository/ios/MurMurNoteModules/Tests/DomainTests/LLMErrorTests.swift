import XCTest
@testable import Domain

final class LLMErrorTests: XCTestCase {

    func testLLMError_isEquatable() {
        XCTAssertEqual(LLMError.modelNotFound, LLMError.modelNotFound)
        XCTAssertEqual(LLMError.memoryInsufficient, LLMError.memoryInsufficient)
        XCTAssertEqual(LLMError.inputTooShort, LLMError.inputTooShort)
        XCTAssertEqual(LLMError.inputTooLong, LLMError.inputTooLong)
        XCTAssertEqual(LLMError.invalidOutput, LLMError.invalidOutput)
        XCTAssertEqual(LLMError.quotaExceeded, LLMError.quotaExceeded)
        XCTAssertEqual(LLMError.deviceNotSupported, LLMError.deviceNotSupported)
        XCTAssertEqual(LLMError.cancelled, LLMError.cancelled)
    }

    func testLLMError_associatedValues() {
        XCTAssertEqual(
            LLMError.modelLoadFailed("reason"),
            LLMError.modelLoadFailed("reason")
        )
        XCTAssertNotEqual(
            LLMError.modelLoadFailed("reason1"),
            LLMError.modelLoadFailed("reason2")
        )
        XCTAssertEqual(
            LLMError.processingFailed("error"),
            LLMError.processingFailed("error")
        )
    }

    func testLLMError_isError() {
        let error: Error = LLMError.modelNotFound
        XCTAssertTrue(error is LLMError)
    }

    func testLLMError_isSendable() {
        // Sendable 準拠の確認（コンパイルが通れば OK）
        let error: Sendable = LLMError.modelNotFound
        XCTAssertNotNil(error)
    }
}
