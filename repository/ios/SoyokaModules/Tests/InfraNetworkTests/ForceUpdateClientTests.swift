@testable import InfraNetwork
import XCTest

final class ForceUpdateClientTests: XCTestCase {

    // MARK: - Semver Comparison

    func test_isVersionLessThan_マイナーバージョンが低い場合_trueを返す() {
        XCTAssertTrue(ForceUpdateClient.isVersionLessThan("1.0.0", minimum: "1.1.0"))
    }

    func test_isVersionLessThan_メジャーバージョンが低い場合_trueを返す() {
        XCTAssertTrue(ForceUpdateClient.isVersionLessThan("1.9.9", minimum: "2.0.0"))
    }

    func test_isVersionLessThan_パッチバージョンが低い場合_trueを返す() {
        XCTAssertTrue(ForceUpdateClient.isVersionLessThan("1.0.0", minimum: "1.0.1"))
    }

    func test_isVersionLessThan_同一バージョンの場合_falseを返す() {
        XCTAssertFalse(ForceUpdateClient.isVersionLessThan("1.0.0", minimum: "1.0.0"))
    }

    func test_isVersionLessThan_現在が高い場合_falseを返す() {
        XCTAssertFalse(ForceUpdateClient.isVersionLessThan("2.0.0", minimum: "1.9.9"))
    }

    func test_isVersionLessThan_パーツ数が異なる場合_正しく比較する() {
        XCTAssertTrue(ForceUpdateClient.isVersionLessThan("1.0", minimum: "1.0.1"))
        XCTAssertFalse(ForceUpdateClient.isVersionLessThan("1.0.1", minimum: "1.0"))
    }

    func test_isVersionLessThan_大きな数字の比較() {
        XCTAssertTrue(ForceUpdateClient.isVersionLessThan("1.0.99", minimum: "1.1.0"))
        XCTAssertFalse(ForceUpdateClient.isVersionLessThan("10.0.0", minimum: "9.99.99"))
    }
}
