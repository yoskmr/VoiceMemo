import XCTest
@testable import FeatureMemo

final class FeatureMemoTests: XCTestCase {
    func testModuleVersion() {
        XCTAssertEqual(FeatureMemoModule.version, "0.1.0")
    }
}
