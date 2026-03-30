import Testing
@testable import Domain

/// EmotionCategory テスト（P1-4: 8→13カテゴリ拡張対応）
@Suite("EmotionCategory")
struct EmotionCategoryTests {

    // MARK: - 全13カテゴリの存在確認

    @Test("CaseIterableが13件であること")
    func emotionCategory_has13Cases() {
        #expect(EmotionCategory.allCases.count == 13)
    }

    @Test("全13カテゴリが含まれていること")
    func emotionCategory_containsAll13ExpectedCases() {
        let expected: Set<EmotionCategory> = [
            .joy, .calm, .anticipation, .sadness,
            .anxiety, .anger, .surprise, .neutral,
            .gratitude, .achievement, .nostalgia, .ambivalence, .determination,
        ]
        #expect(Set(EmotionCategory.allCases) == expected)
    }

    // MARK: - rawValue の検証（統合仕様書準拠）

    @Test("既存8カテゴリのrawValueが正しいこと")
    func emotionCategory_legacyRawValues() {
        #expect(EmotionCategory.joy.rawValue == "joy")
        #expect(EmotionCategory.calm.rawValue == "calm")
        #expect(EmotionCategory.anticipation.rawValue == "anticipation")
        #expect(EmotionCategory.sadness.rawValue == "sadness")
        #expect(EmotionCategory.anxiety.rawValue == "anxiety")
        #expect(EmotionCategory.anger.rawValue == "anger")
        #expect(EmotionCategory.surprise.rawValue == "surprise")
        #expect(EmotionCategory.neutral.rawValue == "neutral")
    }

    @Test("新規5カテゴリのrawValueが正しいこと")
    func emotionCategory_newRawValues() {
        #expect(EmotionCategory.gratitude.rawValue == "gratitude")
        #expect(EmotionCategory.achievement.rawValue == "achievement")
        #expect(EmotionCategory.nostalgia.rawValue == "nostalgia")
        #expect(EmotionCategory.ambivalence.rawValue == "ambivalence")
        #expect(EmotionCategory.determination.rawValue == "determination")
    }

    // MARK: - displayNameJA の検証

    @Test("新規5カテゴリのdisplayNameJAが正しいこと")
    func emotionCategory_newDisplayNameJA() {
        #expect(EmotionCategory.gratitude.displayNameJA == "感謝")
        #expect(EmotionCategory.achievement.displayNameJA == "達成感")
        #expect(EmotionCategory.nostalgia.displayNameJA == "懐かしさ")
        #expect(EmotionCategory.ambivalence.displayNameJA == "もやもや")
        #expect(EmotionCategory.determination.displayNameJA == "決意")
    }

    @Test("既存8カテゴリのdisplayNameJAが正しいこと")
    func emotionCategory_legacyDisplayNameJA() {
        #expect(EmotionCategory.joy.displayNameJA == "喜び")
        #expect(EmotionCategory.calm.displayNameJA == "安心")
        #expect(EmotionCategory.anticipation.displayNameJA == "期待")
        #expect(EmotionCategory.sadness.displayNameJA == "悲しみ")
        #expect(EmotionCategory.anxiety.displayNameJA == "不安")
        #expect(EmotionCategory.anger.displayNameJA == "怒り")
        #expect(EmotionCategory.surprise.displayNameJA == "驚き")
        #expect(EmotionCategory.neutral.displayNameJA == "中立")
    }

    @Test("displayNameJAとlabelが一致すること")
    func emotionCategory_displayNameJA_matchesLabel() {
        for category in EmotionCategory.allCases {
            #expect(category.displayNameJA == category.label)
        }
    }

    // MARK: - legacyCategories の検証

    @Test("legacyCategoriesが8件であること")
    func legacyCategories_has8Cases() {
        #expect(EmotionCategory.legacyCategories.count == 8)
    }

    @Test("legacyCategoriesに既存8カテゴリのみ含まれること")
    func legacyCategories_containsOnlyOriginal8() {
        let expected: [EmotionCategory] = [
            .joy, .calm, .anticipation, .sadness, .anxiety, .anger, .surprise, .neutral,
        ]
        #expect(EmotionCategory.legacyCategories == expected)
    }

    @Test("legacyCategoriesに新規5カテゴリが含まれないこと")
    func legacyCategories_doesNotContainNewCategories() {
        let legacy = Set(EmotionCategory.legacyCategories)
        #expect(!legacy.contains(.gratitude))
        #expect(!legacy.contains(.achievement))
        #expect(!legacy.contains(.nostalgia))
        #expect(!legacy.contains(.ambivalence))
        #expect(!legacy.contains(.determination))
    }

    // MARK: - Codable のテスト

    @Test("全13カテゴリのエンコード・デコードが正しいこと")
    func emotionCategory_encodeAndDecode() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for category in EmotionCategory.allCases {
            let data = try encoder.encode(category)
            let decoded = try decoder.decode(EmotionCategory.self, from: data)
            #expect(decoded == category)
        }
    }

    @Test("新規カテゴリがrawValue文字列からデコードできること")
    func emotionCategory_decodeNewCategoriesFromRawValue() throws {
        let newRawValues = ["gratitude", "achievement", "nostalgia", "ambivalence", "determination"]
        let expected: [EmotionCategory] = [.gratitude, .achievement, .nostalgia, .ambivalence, .determination]

        for (rawValue, expectedCategory) in zip(newRawValues, expected) {
            let json = "\"\(rawValue)\""
            let data = json.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(EmotionCategory.self, from: data)
            #expect(decoded == expectedCategory)
        }
    }

    @Test("joyがrawValue文字列からデコードできること")
    func emotionCategory_decodeFromRawValueString() throws {
        let json = "\"joy\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(EmotionCategory.self, from: data)
        #expect(decoded == .joy)
    }

    @Test("不正なrawValueでデコードが失敗すること")
    func emotionCategory_decodeInvalidRawValue() {
        let json = "\"invalid\""
        let data = json.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(EmotionCategory.self, from: data)
        }
    }

    // MARK: - 旧カテゴリが存在しないことの確認

    @Test("廃止されたfear/disgustが存在しないこと")
    func emotionCategory_doesNotContainDeprecatedValues() {
        #expect(EmotionCategory(rawValue: "fear") == nil)
        #expect(EmotionCategory(rawValue: "disgust") == nil)
    }
}
