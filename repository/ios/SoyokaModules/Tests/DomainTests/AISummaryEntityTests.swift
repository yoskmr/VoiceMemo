import XCTest
@testable import Domain

final class AISummaryEntityTests: XCTestCase {

    func test_aiSummaryEntity_creation_withDefaults() {
        let summary = AISummaryEntity(summaryText: "テスト要約")

        XCTAssertEqual(summary.title, "")
        XCTAssertEqual(summary.summaryText, "テスト要約")
        XCTAssertTrue(summary.keyPoints.isEmpty)
        XCTAssertEqual(summary.providerType, .onDeviceLlamaCpp)
        XCTAssertTrue(summary.isOnDevice)
    }

    func test_aiSummaryEntity_keyPoints_preservation() {
        let keyPoints = ["ポイント1", "ポイント2", "ポイント3"]
        let summary = AISummaryEntity(
            summaryText: "テスト",
            keyPoints: keyPoints
        )

        XCTAssertEqual(summary.keyPoints, keyPoints)
        XCTAssertEqual(summary.keyPoints.count, 3)
    }

    func test_aiSummaryEntity_cloudProvider() {
        let summary = AISummaryEntity(
            summaryText: "クラウド要約",
            providerType: .cloudGPT4oMini,
            isOnDevice: false
        )

        XCTAssertEqual(summary.providerType, .cloudGPT4oMini)
        XCTAssertFalse(summary.isOnDevice)
    }
}
