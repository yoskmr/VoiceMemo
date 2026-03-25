import XCTest
@testable import Domain

final class EmotionCategoryTests: XCTestCase {

    // MARK: - 全8カテゴリの存在確認

    func test_emotionCategory_has8Cases() {
        XCTAssertEqual(EmotionCategory.allCases.count, 8)
    }

    func test_emotionCategory_containsAllExpectedCases() {
        let expected: Set<EmotionCategory> = [
            .joy, .calm, .anticipation, .sadness,
            .anxiety, .anger, .surprise, .neutral,
        ]
        XCTAssertEqual(Set(EmotionCategory.allCases), expected)
    }

    // MARK: - rawValue の検証（統合仕様書準拠）

    func test_emotionCategory_rawValues() {
        XCTAssertEqual(EmotionCategory.joy.rawValue, "joy")
        XCTAssertEqual(EmotionCategory.calm.rawValue, "calm")
        XCTAssertEqual(EmotionCategory.anticipation.rawValue, "anticipation")
        XCTAssertEqual(EmotionCategory.sadness.rawValue, "sadness")
        XCTAssertEqual(EmotionCategory.anxiety.rawValue, "anxiety")
        XCTAssertEqual(EmotionCategory.anger.rawValue, "anger")
        XCTAssertEqual(EmotionCategory.surprise.rawValue, "surprise")
        XCTAssertEqual(EmotionCategory.neutral.rawValue, "neutral")
    }

    // MARK: - Codable のテスト

    func test_emotionCategory_encodeAndDecode() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for category in EmotionCategory.allCases {
            let data = try encoder.encode(category)
            let decoded = try decoder.decode(EmotionCategory.self, from: data)
            XCTAssertEqual(decoded, category)
        }
    }

    func test_emotionCategory_decodeFromRawValueString() throws {
        let json = "\"joy\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(EmotionCategory.self, from: data)
        XCTAssertEqual(decoded, .joy)
    }

    func test_emotionCategory_decodeInvalidRawValue() {
        let json = "\"invalid\""
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(EmotionCategory.self, from: data))
    }

    // MARK: - 旧カテゴリが存在しないことの確認

    func test_emotionCategory_doesNotContainDeprecatedValues() {
        // fear と disgust は統合仕様書で廃止
        XCTAssertNil(EmotionCategory(rawValue: "fear"))
        XCTAssertNil(EmotionCategory(rawValue: "disgust"))
    }
}
