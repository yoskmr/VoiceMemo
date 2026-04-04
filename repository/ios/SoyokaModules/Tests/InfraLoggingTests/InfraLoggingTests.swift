@testable import InfraLogging
import XCTest

final class InfraLoggingTests: XCTestCase {
    func test_moduleVersionIsSet() {
        XCTAssertEqual(InfraLoggingModule.version, "0.1.0")
    }
}
