import XCTest
@testable import Domain

final class SubscriptionPlanTests: XCTestCase {

    func test_subscriptionPlan_has2Cases() {
        let allCases: [SubscriptionPlan] = [.free, .pro]
        XCTAssertEqual(allCases.count, 2)
    }

    func test_subscriptionPlan_rawValues() {
        XCTAssertEqual(SubscriptionPlan.free.rawValue, "free")
        XCTAssertEqual(SubscriptionPlan.pro.rawValue, "pro")
    }

    func test_subscriptionPlan_codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for plan in [SubscriptionPlan.free, .pro] {
            let data = try encoder.encode(plan)
            let decoded = try decoder.decode(SubscriptionPlan.self, from: data)
            XCTAssertEqual(decoded, plan)
        }
    }
}
