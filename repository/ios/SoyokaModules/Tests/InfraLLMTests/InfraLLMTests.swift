import XCTest
@testable import InfraLLM

final class InfraLLMTests: XCTestCase {
    func testModuleVersion() {
        XCTAssertEqual(InfraLLMModule.version, "0.3.0")
    }
}
