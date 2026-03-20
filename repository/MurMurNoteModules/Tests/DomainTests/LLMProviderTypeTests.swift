import XCTest
@testable import Domain

final class LLMProviderTypeTests: XCTestCase {

    func test_llmProviderType_has4Cases() {
        let allCases: [LLMProviderType] = [
            .onDeviceAppleIntelligence, .onDeviceLlamaCpp,
            .cloudGPT4oMini, .cloudClaude,
        ]
        XCTAssertEqual(allCases.count, 4)
    }

    func test_llmProviderType_rawValues() {
        XCTAssertEqual(LLMProviderType.onDeviceAppleIntelligence.rawValue, "on_device_apple_intelligence")
        XCTAssertEqual(LLMProviderType.onDeviceLlamaCpp.rawValue, "on_device_llama_cpp")
        XCTAssertEqual(LLMProviderType.cloudGPT4oMini.rawValue, "cloud_gpt4o_mini")
        XCTAssertEqual(LLMProviderType.cloudClaude.rawValue, "cloud_claude")
    }

    func test_llmProviderType_invalidRawValues() {
        XCTAssertNil(LLMProviderType(rawValue: "onDevice"))
        XCTAssertNil(LLMProviderType(rawValue: "onDeviceCoreML"))
        XCTAssertNil(LLMProviderType(rawValue: "cloudGPT"))
    }

    func test_llmProviderType_codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for providerType in [LLMProviderType.onDeviceAppleIntelligence, .onDeviceLlamaCpp, .cloudGPT4oMini, .cloudClaude] {
            let data = try encoder.encode(providerType)
            let decoded = try decoder.decode(LLMProviderType.self, from: data)
            XCTAssertEqual(decoded, providerType)
        }
    }
}
