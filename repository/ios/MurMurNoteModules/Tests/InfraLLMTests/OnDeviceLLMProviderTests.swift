import XCTest
@testable import Domain
@testable import InfraLLM

/// T13: OnDeviceLLMProvider のユニットテスト
/// Phase 3a: モック化テスト（入力バリデーション、メモリチェック、レスポンスパース）
final class OnDeviceLLMProviderTests: XCTestCase {

    // MARK: - 入力バリデーション: 短すぎるテキスト

    func testProcess_inputTooShort_throwsInputTooShort() async {
        let provider = makeProvider()
        let request = LLMRequest(text: "短い", tasks: [.summarize])

        do {
            _ = try await provider.process(request)
            XCTFail("inputTooShort エラーが投げられるべき")
        } catch {
            XCTAssertEqual(error as? LLMError, .inputTooShort)
        }
    }

    func testProcess_inputExactly9Characters_throwsInputTooShort() async {
        let provider = makeProvider()
        let request = LLMRequest(text: "123456789", tasks: [.summarize])

        do {
            _ = try await provider.process(request)
            XCTFail("inputTooShort エラーが投げられるべき")
        } catch {
            XCTAssertEqual(error as? LLMError, .inputTooShort)
        }
    }

    func testProcess_inputExactly10Characters_success() async throws {
        let provider = makeProvider()
        let request = LLMRequest(text: "1234567890", tasks: [.summarize])

        let response = try await provider.process(request)
        XCTAssertNotNil(response.summary)
    }

    // MARK: - 入力バリデーション: 長すぎるテキスト

    func testProcess_inputTooLong_throwsInputTooLong() async {
        let provider = makeProvider()
        let longText = String(repeating: "あ", count: 501)
        let request = LLMRequest(text: longText, tasks: [.summarize])

        do {
            _ = try await provider.process(request)
            XCTFail("inputTooLong エラーが投げられるべき")
        } catch {
            XCTAssertEqual(error as? LLMError, .inputTooLong)
        }
    }

    func testProcess_inputExactly500Characters_success() async throws {
        let provider = makeProvider()
        let exactText = String(repeating: "あ", count: 500)
        let request = LLMRequest(text: exactText, tasks: [.summarize])

        let response = try await provider.process(request)
        XCTAssertNotNil(response.summary)
    }

    // MARK: - 入力バリデーション: 空白トリミング

    func testProcess_whitespaceOnlyInput_throwsInputTooShort() async {
        let provider = makeProvider()
        let request = LLMRequest(text: "   \n\t   ", tasks: [.summarize])

        do {
            _ = try await provider.process(request)
            XCTFail("inputTooShort エラーが投げられるべき")
        } catch {
            XCTAssertEqual(error as? LLMError, .inputTooShort)
        }
    }

    func testProcess_textWithLeadingTrailingWhitespace_countsTrimmedLength() async throws {
        let provider = makeProvider()
        // トリム後10文字ちょうど
        let request = LLMRequest(text: "  1234567890  ", tasks: [.summarize])

        let response = try await provider.process(request)
        XCTAssertNotNil(response.summary)
    }

    // MARK: - メモリチェック

    func testProcess_memoryInsufficient_throwsMemoryInsufficient() async {
        // 利用可能メモリ 1GB = メモリ不足
        let provider = makeProvider(availableMemory: 1 * 1024 * 1024 * 1024)
        let request = LLMRequest(text: "テスト用の十分な長さのテキストです", tasks: [.summarize])

        do {
            _ = try await provider.process(request)
            XCTFail("memoryInsufficient エラーが投げられるべき")
        } catch {
            XCTAssertEqual(error as? LLMError, .memoryInsufficient)
        }
    }

    func testProcess_memoryExactly2GB_throwsMemoryInsufficient() async {
        // 2GB ちょうどは「> 2GB」を満たさないため memoryInsufficient
        let provider = makeProvider(availableMemory: 2 * 1024 * 1024 * 1024)
        let request = LLMRequest(text: "テスト用の十分な長さのテキストです", tasks: [.summarize])

        do {
            _ = try await provider.process(request)
            XCTFail("memoryInsufficient エラーが投げられるべき")
        } catch {
            XCTAssertEqual(error as? LLMError, .memoryInsufficient)
        }
    }

    func testProcess_memorySufficient_success() async throws {
        // 3GB = 十分なメモリ
        let provider = makeProvider(availableMemory: 3 * 1024 * 1024 * 1024)
        let request = LLMRequest(text: "テスト用の十分な長さのテキストです", tasks: [.summarize])

        let response = try await provider.process(request)
        XCTAssertNotNil(response)
    }

    // MARK: - 正常系レスポンス

    func testProcess_normalInput_returnsSummaryAndTags() async throws {
        let provider = makeProvider()
        let request = LLMRequest(text: "今日は会議があって色々話し合いました", tasks: [.summarize, .tagging])

        let response = try await provider.process(request)

        XCTAssertNotNil(response.summary)
        XCTAssertFalse(response.tags.isEmpty)
        XCTAssertEqual(response.provider, .onDeviceLlamaCpp)
    }

    func testProcess_summarizeOnly_returnsSummaryNoTags() async throws {
        let provider = makeProvider()
        let request = LLMRequest(text: "今日は会議があって色々話し合いました", tasks: [.summarize])

        let response = try await provider.process(request)

        XCTAssertNotNil(response.summary)
        XCTAssertTrue(response.tags.isEmpty)
    }

    func testProcess_taggingOnly_returnsTagsNoSummary() async throws {
        let provider = makeProvider()
        let request = LLMRequest(text: "今日は会議があって色々話し合いました", tasks: [.tagging])

        let response = try await provider.process(request)

        XCTAssertNil(response.summary)
        XCTAssertFalse(response.tags.isEmpty)
    }

    // MARK: - isAvailable

    func testIsAvailable_supportedDevice_returnsTrue() async {
        let provider = makeProvider(machine: "iPhone16,1", physicalMemory: 8 * 1024 * 1024 * 1024)
        let available = await provider.isAvailable()
        XCTAssertTrue(available)
    }

    func testIsAvailable_unsupportedDevice_returnsFalse() async {
        let provider = makeProvider(machine: "iPhone14,7", physicalMemory: 4 * 1024 * 1024 * 1024)
        let available = await provider.isAvailable()
        XCTAssertFalse(available)
    }

    // MARK: - providerType

    func testProviderType_returnsOnDeviceLlamaCpp() {
        let provider = makeProvider()
        XCTAssertEqual(provider.providerType(), .onDeviceLlamaCpp)
    }

    // MARK: - unloadModel

    func testUnloadModel_thenProcess_reloadsAndSucceeds() async throws {
        let provider = makeProvider()
        let request = LLMRequest(text: "最初の処理テスト用テキストです", tasks: [.summarize])

        // 初回処理（モデルロード）
        _ = try await provider.process(request)

        // アンロード
        await provider.unloadModel()

        // 再処理（モデル再ロード）
        let response = try await provider.process(request)
        XCTAssertNotNil(response.summary)
    }

    // MARK: - asClient

    func testAsClient_process_delegatesToProvider() async throws {
        let provider = makeProvider()
        let client = provider.asClient()
        let request = LLMRequest(text: "クライアント経由のテスト用テキスト", tasks: [.summarize])

        let response = try await client.process(request)
        XCTAssertNotNil(response.summary)
    }

    func testAsClient_isAvailable_delegatesToProvider() async {
        let provider = makeProvider()
        let client = provider.asClient()

        let available = await client.isAvailable()
        XCTAssertTrue(available)
    }

    func testAsClient_providerType_delegatesToProvider() {
        let provider = makeProvider()
        let client = provider.asClient()
        XCTAssertEqual(client.providerType(), .onDeviceLlamaCpp)
    }

    func testAsClient_unloadModel_delegatesToProvider() async throws {
        let provider = makeProvider()
        let client = provider.asClient()
        let request = LLMRequest(text: "アンロードテスト用の十分な長さ", tasks: [.summarize])

        _ = try await client.process(request)
        await client.unloadModel()

        // 再処理が可能であること
        let response = try await client.process(request)
        XCTAssertNotNil(response.summary)
    }

    // MARK: - maxInputCharacters / minInputCharacters

    func testMaxInputCharacters_is500() {
        let provider = makeProvider()
        XCTAssertEqual(provider.maxInputCharacters, 500)
    }

    func testMinInputCharacters_is10() {
        let provider = makeProvider()
        XCTAssertEqual(provider.minInputCharacters, 10)
    }

    // MARK: - Helper

    private func makeProvider(
        machine: String = "iPhone16,1",
        physicalMemory: UInt64 = 8 * 1024 * 1024 * 1024,
        availableMemory: UInt64 = 3 * 1024 * 1024 * 1024
    ) -> OnDeviceLLMProvider {
        let env = DeviceCapabilityChecker.Environment(
            physicalMemory: physicalMemory,
            machineIdentifier: machine,
            availableMemoryProvider: { availableMemory }
        )
        let checker = DeviceCapabilityChecker(environment: env)
        return OnDeviceLLMProvider(
            capabilityChecker: checker,
            modelManager: LLMModelManager(),
            responseParser: LLMResponseParser()
        )
    }
}
