import XCTest
@testable import InfraStorage

final class InfraStorageTests: XCTestCase {
    func testModuleVersion() {
        XCTAssertEqual(InfraStorageModule.version, "0.1.0")
    }
}
