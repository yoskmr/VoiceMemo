import XCTest
@testable import FeatureAI

final class FeatureAITests: XCTestCase {
    func testModuleVersion() {
        XCTAssertEqual(FeatureAIModule.version, "0.1.0")
    }
}
