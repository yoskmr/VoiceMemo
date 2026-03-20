import XCTest
@testable import FeatureRecording

final class FeatureRecordingTests: XCTestCase {
    func testModuleVersion() {
        XCTAssertEqual(FeatureRecordingModule.version, "0.1.0")
    }
}
