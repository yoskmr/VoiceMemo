import XCTest
@testable import InfraSTT

final class InfraSTTTests: XCTestCase {
    func testModuleVersion() {
        XCTAssertEqual(InfraSTTModule.version, "0.1.0")
    }
}
