import XCTest
@testable import Domain

final class MemoStatusTests: XCTestCase {

    func test_memoStatus_rawValues() {
        XCTAssertEqual(MemoStatus.recording.rawValue, "recording")
        XCTAssertEqual(MemoStatus.processing.rawValue, "processing")
        XCTAssertEqual(MemoStatus.completed.rawValue, "completed")
        XCTAssertEqual(MemoStatus.failed.rawValue, "failed")
    }

    func test_memoStatus_codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for status in [MemoStatus.recording, .processing, .completed, .failed] {
            let data = try encoder.encode(status)
            let decoded = try decoder.decode(MemoStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }
}
