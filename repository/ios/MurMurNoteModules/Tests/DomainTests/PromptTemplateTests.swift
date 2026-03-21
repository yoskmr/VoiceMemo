import XCTest
@testable import Domain

final class PromptTemplateTests: XCTestCase {

    // MARK: - onDeviceSimple テンプレート

    func testOnDeviceSimple_version() {
        XCTAssertEqual(PromptTemplate.onDeviceSimple.version, "3.0.0")
    }

    func testOnDeviceSimple_containsPlaceholder() {
        XCTAssertTrue(PromptTemplate.onDeviceSimple.userPromptTemplate.contains("{transcribed_text}"))
    }

    func testOnDeviceSimple_containsJSONFormatInstruction() {
        let template = PromptTemplate.onDeviceSimple.userPromptTemplate
        XCTAssertTrue(template.contains("JSON形式"))
        XCTAssertTrue(template.contains("title"))
        XCTAssertTrue(template.contains("cleaned"))
        XCTAssertTrue(template.contains("tags"))
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

    // MARK: - buildUserPrompt テスト

    func testBuildUserPrompt_replacesPlaceholder() {
        let prompt = PromptTemplate.onDeviceSimple.buildUserPrompt(text: "今日の会議で話したこと")

        XCTAssertTrue(prompt.contains("今日の会議で話したこと"))
        XCTAssertFalse(prompt.contains("{transcribed_text}"))
    }

    func testBuildUserPrompt_emptyText() {
        let prompt = PromptTemplate.onDeviceSimple.buildUserPrompt(text: "")

        XCTAssertFalse(prompt.contains("{transcribed_text}"))
        XCTAssertTrue(prompt.contains("メモ: "))
    }

    func testBuildUserPrompt_longText() {
        let longText = String(repeating: "テスト文章。", count: 100)
        let prompt = PromptTemplate.onDeviceSimple.buildUserPrompt(text: longText)

        XCTAssertTrue(prompt.contains(longText))
    }

    func testBuildUserPrompt_specialCharacters() {
        let specialText = "特殊文字: {}, [], \"quotes\", \\backslash"
        let prompt = PromptTemplate.onDeviceSimple.buildUserPrompt(text: specialText)

        XCTAssertTrue(prompt.contains(specialText))
    }

    // MARK: - カスタムテンプレート

    func testCustomTemplate_buildUserPrompt() {
        let template = PromptTemplate(
            version: "3.0.0",
            userPromptTemplate: "Summarize: {transcribed_text}"
        )

        let prompt = template.buildUserPrompt(text: "Hello world")

        XCTAssertEqual(prompt, "Summarize: Hello world")
    }

    // MARK: - Equatable テスト

    func testPromptTemplate_equatable() {
        let a = PromptTemplate(version: "1.0", userPromptTemplate: "template")
        let b = PromptTemplate(version: "1.0", userPromptTemplate: "template")
        let c = PromptTemplate(version: "2.0", userPromptTemplate: "template")

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
