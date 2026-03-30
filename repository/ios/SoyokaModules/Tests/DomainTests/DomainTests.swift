import XCTest
@testable import Domain

final class DomainTests: XCTestCase {
    func testModuleVersion() {
        XCTAssertEqual(DomainModule.version, "0.1.0")
    }
}
