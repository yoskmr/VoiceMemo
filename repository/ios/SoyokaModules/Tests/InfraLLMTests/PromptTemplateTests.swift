import XCTest
@testable import Domain

/// T13: PromptTemplate v2.0.0（温かみジャーナル風プロンプト）のテスト
final class PromptTemplateTests: XCTestCase {

    // MARK: - バージョン

    func testOnDeviceSimple_version_is3_3_0() {
        XCTAssertEqual(PromptTemplate.onDeviceSimple.version, "3.3.0")
    }

    // MARK: - プレースホルダー置換

    func testBuildUserPrompt_replacesPlaceholder() {
        let text = "今日は天気がよかったので散歩に行きました"
        let prompt = PromptTemplate.onDeviceSimple.buildUserPrompt(text: text)

        XCTAssertTrue(prompt.contains(text))
        XCTAssertFalse(prompt.contains("{transcribed_text}"))
    }

    func testBuildUserPrompt_emptyText_replacesWithEmpty() {
        let prompt = PromptTemplate.onDeviceSimple.buildUserPrompt(text: "")

        XCTAssertFalse(prompt.contains("{transcribed_text}"))
    }

    func testBuildUserPrompt_specialCharacters_preservedInOutput() {
        let text = "「こんにちは！」と言って\n改行もある&記号<含む>"
        let prompt = PromptTemplate.onDeviceSimple.buildUserPrompt(text: text)

        XCTAssertTrue(prompt.contains(text))
    }

    // MARK: - テンプレート内容の確認

    func testOnDeviceSimple_containsNaturalToneInstruction() {
        let template = PromptTemplate.onDeviceSimple.userPromptTemplate

        XCTAssertTrue(template.contains("自然なトーン"))
        XCTAssertTrue(template.contains("雰囲気"))
    }

    func testOnDeviceSimple_containsJSONOutputInstruction() {
        let template = PromptTemplate.onDeviceSimple.userPromptTemplate

        XCTAssertTrue(template.contains("JSON形式"))
        XCTAssertTrue(template.contains("\"title\""))
        XCTAssertTrue(template.contains("\"cleaned\""))
        XCTAssertTrue(template.contains("\"tags\""))
    }

    func testOnDeviceSimple_containsCleaningInstructions() {
        let template = PromptTemplate.onDeviceSimple.userPromptTemplate

        XCTAssertTrue(template.contains("要約しない"))
        XCTAssertTrue(template.contains("清書"))
        XCTAssertTrue(template.contains("cleaned"))
    }

    func testOnDeviceSimple_doesNotContainBriefKey() {
        let template = PromptTemplate.onDeviceSimple.userPromptTemplate

        XCTAssertFalse(template.contains("\"brief\""))
    }

    func testOnDeviceSimple_containsTitleLengthConstraint() {
        let template = PromptTemplate.onDeviceSimple.userPromptTemplate

        XCTAssertTrue(template.contains("20文字以内"))
    }

    func testOnDeviceSimple_containsFillerRemovalRule() {
        let template = PromptTemplate.onDeviceSimple.userPromptTemplate

        XCTAssertTrue(template.contains("フィラー"))
    }

    func testOnDeviceSimple_containsPlaceholder() {
        let template = PromptTemplate.onDeviceSimple.userPromptTemplate

        XCTAssertTrue(template.contains("{transcribed_text}"))
    }

    // MARK: - カスタムテンプレート

    func testCustomTemplate_buildUserPrompt() {
        let custom = PromptTemplate(
            version: "1.0.0",
            userPromptTemplate: "要約してください: {transcribed_text}"
        )

        let prompt = custom.buildUserPrompt(text: "テスト入力")
        XCTAssertEqual(prompt, "要約してください: テスト入力")
    }

    func testCustomTemplate_multiplePlaceholders_replacesAll() {
        let custom = PromptTemplate(
            version: "1.0.0",
            userPromptTemplate: "入力1: {transcribed_text} 入力2: {transcribed_text}"
        )

        let prompt = custom.buildUserPrompt(text: "テスト")
        XCTAssertEqual(prompt, "入力1: テスト 入力2: テスト")
    }

    // MARK: - Equatable

    func testEquatable_sameTemplate_isEqual() {
        let t1 = PromptTemplate.onDeviceSimple
        let t2 = PromptTemplate.onDeviceSimple
        XCTAssertEqual(t1, t2)
    }

    func testEquatable_differentVersion_isNotEqual() {
        let t1 = PromptTemplate(version: "1.0.0", userPromptTemplate: "テスト")
        let t2 = PromptTemplate(version: "2.0.0", userPromptTemplate: "テスト")
        XCTAssertNotEqual(t1, t2)
    }
}
