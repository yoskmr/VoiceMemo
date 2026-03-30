import XCTest
@testable import Domain

final class STTErrorTests: XCTestCase {

    // MARK: - Equatable テスト

    func test_engineNotInitialized_isEquatable() {
        XCTAssertEqual(STTError.engineNotInitialized, STTError.engineNotInitialized)
    }

    func test_authorizationDenied_isEquatable() {
        XCTAssertEqual(STTError.authorizationDenied, STTError.authorizationDenied)
    }

    func test_languageNotSupported_isEquatable() {
        XCTAssertEqual(
            STTError.languageNotSupported("xx-XX"),
            STTError.languageNotSupported("xx-XX")
        )
    }

    func test_differentLanguageNotSupported_areNotEqual() {
        XCTAssertNotEqual(
            STTError.languageNotSupported("ja-JP"),
            STTError.languageNotSupported("en-US")
        )
    }

    func test_recognitionFailed_isEquatable() {
        XCTAssertEqual(
            STTError.recognitionFailed("error"),
            STTError.recognitionFailed("error")
        )
    }

    func test_differentErrors_areNotEqual() {
        XCTAssertNotEqual(
            STTError.engineNotInitialized as STTError,
            STTError.authorizationDenied as STTError
        )
    }

    // MARK: - Error プロトコル適合テスト

    func test_conformsToError() {
        let error: any Error = STTError.engineNotInitialized
        XCTAssertNotNil(error)
    }

    // MARK: - Sendable テスト

    func test_isSendable() {
        let _: any Sendable = STTError.engineNotInitialized
    }
}
