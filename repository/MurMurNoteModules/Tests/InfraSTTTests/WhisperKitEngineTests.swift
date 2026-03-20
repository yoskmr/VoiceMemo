import AVFoundation
import XCTest
@testable import Domain
@testable import InfraSTT

// MARK: - WhisperKitEngine Tests

final class WhisperKitEngineTests: XCTestCase {

    private var engine: WhisperKitEngine!

    override func setUp() {
        super.setUp()
        engine = WhisperKitEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - プロトコル適合テスト

    func test_conformsToSTTEngineProtocol() {
        let _: any STTEngineProtocol = engine
    }

    func test_conformsToSendable() {
        let _: any Sendable = engine
    }

    // MARK: - engineType テスト

    func test_engineType_isWhisperKit() {
        XCTAssertEqual(engine.engineType, .whisperKit)
    }

    // MARK: - supportedLanguages テスト

    func test_supportedLanguages_isNotEmpty() {
        XCTAssertFalse(engine.supportedLanguages.isEmpty)
    }

    func test_supportedLanguages_containsJapanese() {
        let hasJapanese = engine.supportedLanguages.contains { lang in
            lang.hasPrefix("ja")
        }
        XCTAssertTrue(hasJapanese, "日本語(ja)がsupportedLanguagesに含まれるべき")
    }

    func test_supportedLanguages_containsEnglish() {
        let hasEnglish = engine.supportedLanguages.contains { lang in
            lang.hasPrefix("en")
        }
        XCTAssertTrue(hasEnglish, "英語(en)がsupportedLanguagesに含まれるべき")
    }

    func test_supportedLanguages_containsExpectedLanguages() {
        // WhisperKit は ja, en, zh, ko をサポートするべき
        let expectedPrefixes = ["ja", "en", "zh", "ko"]
        for prefix in expectedPrefixes {
            let hasLang = engine.supportedLanguages.contains { $0.hasPrefix(prefix) }
            XCTAssertTrue(hasLang, "\(prefix) がsupportedLanguagesに含まれるべき")
        }
    }

    // MARK: - モデルロード/アンロード状態テスト

    func test_isModelLoaded_initiallyFalse() {
        XCTAssertFalse(engine.isModelLoaded)
    }

    func test_unloadModel_setsIsModelLoadedToFalse() {
        // unloadModel は何回呼んでもクラッシュしない
        engine.unloadModel()
        XCTAssertFalse(engine.isModelLoaded)
    }

    func test_unloadModel_multipleCallsDoNotCrash() {
        engine.unloadModel()
        engine.unloadModel()
        engine.unloadModel()
        XCTAssertFalse(engine.isModelLoaded)
    }

    // MARK: - stopTranscription テスト

    func test_stopTranscription_doesNotCrash() async {
        await engine.stopTranscription()
    }

    func test_stopTranscription_multipleCalls_doesNotCrash() async {
        await engine.stopTranscription()
        await engine.stopTranscription()
        await engine.stopTranscription()
    }

    // MARK: - finishTranscription テスト（認識未開始時）

    func test_finishTranscription_whenNotStarted_throwsEngineNotInitialized() async {
        do {
            _ = try await engine.finishTranscription()
            XCTFail("Expected STTError.engineNotInitialized")
        } catch let error as STTError {
            XCTAssertEqual(error, .engineNotInitialized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - setCustomDictionary テスト

    func test_setCustomDictionary_doesNotCrash() async {
        let dictionary = ["AI": "人工知能", "ML": "機械学習"]
        await engine.setCustomDictionary(dictionary)
    }

    func test_setCustomDictionary_emptyDictionary_doesNotCrash() async {
        await engine.setCustomDictionary([:])
    }

    // MARK: - startTranscription テスト（基本動作）

    func test_startTranscription_returnsAsyncStream() {
        let audioStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        let resultStream = engine.startTranscription(
            audioStream: audioStream,
            language: "ja"
        )

        // AsyncStream<TranscriptionResult> 型が返却されることを確認
        let _: AsyncStream<TranscriptionResult> = resultStream
    }

    func test_startTranscription_emptyStream_finishesGracefully() async {
        let audioStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        let resultStream = engine.startTranscription(
            audioStream: audioStream,
            language: "ja"
        )

        // 空のストリームの場合、結果が空で終了することを確認
        var results: [TranscriptionResult] = []
        for await result in resultStream {
            results.append(result)
        }
        // 空のストリームの場合 結果は0件またはモデル未ロード時は0件
        // （モデル未ロード状態ではトランスクリプションは実行されない）
    }

    // MARK: - isAvailable テスト

    func test_isAvailable_returnsWithoutCrash() async {
        let _ = await engine.isAvailable()
    }

    // MARK: - モデルディレクトリテスト

    func test_modelDirectory_isInCachesModels() {
        let modelDir = engine.modelDirectoryURL
        XCTAssertTrue(
            modelDir.path.contains("Caches/Models/whisperkit"),
            "モデルディレクトリは Library/Caches/Models/whisperkit/ 配下であるべき: \(modelDir.path)"
        )
    }

    // MARK: - finishTranscription 後の stopTranscription

    func test_stopTranscription_afterFinishAttempt_doesNotCrash() async {
        do {
            _ = try await engine.finishTranscription()
        } catch {
            // Expected
        }
        await engine.stopTranscription()
    }
}

// MARK: - MockWhisperKitEngine Tests (AsyncStream テスト)

final class MockWhisperKitTranscriptionTests: XCTestCase {

    // MARK: - Mock を使った AsyncStream テスト

    func test_mockEngine_yieldsPartialAndFinalResults() async {
        let mockEngine = MockWhisperKitEngine()

        let audioStream = AsyncStream<AVAudioPCMBuffer> { continuation in
            // 空のバッファを送信してすぐ終了
            continuation.finish()
        }

        let resultStream = mockEngine.startTranscription(
            audioStream: audioStream,
            language: "ja"
        )

        var results: [TranscriptionResult] = []
        for await result in resultStream {
            results.append(result)
        }

        // Mock は固定の部分結果と最終結果を返す
        XCTAssertGreaterThanOrEqual(results.count, 1, "少なくとも1つの結果が返されるべき")

        // 最後の結果は isFinal = true
        if let lastResult = results.last {
            XCTAssertTrue(lastResult.isFinal, "最後の結果はisFinal=trueであるべき")
        }
    }

    func test_mockEngine_yieldsCorrectLanguage() async {
        let mockEngine = MockWhisperKitEngine()
        let audioStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }

        let resultStream = mockEngine.startTranscription(
            audioStream: audioStream,
            language: "ja"
        )

        for await result in resultStream {
            XCTAssertEqual(result.language, "ja", "結果の言語は指定した言語と一致すべき")
        }
    }

    func test_mockEngine_engineType_isWhisperKit() {
        let mockEngine = MockWhisperKitEngine()
        XCTAssertEqual(mockEngine.engineType, .whisperKit)
    }

    func test_mockEngine_finishTranscription_returnsFinalResult() async throws {
        let mockEngine = MockWhisperKitEngine()

        // 先に startTranscription を呼んで認識状態にする
        let audioStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        _ = mockEngine.startTranscription(audioStream: audioStream, language: "ja")

        let result = try await mockEngine.finishTranscription()
        XCTAssertTrue(result.isFinal)
        XCTAssertEqual(result.language, "ja")
    }

    func test_mockEngine_setCustomDictionary_storesTerms() async {
        let mockEngine = MockWhisperKitEngine()
        let dictionary = ["AI": "人工知能", "STT": "音声認識"]
        await mockEngine.setCustomDictionary(dictionary)
        XCTAssertEqual(mockEngine.customDictionaryTerms.count, 2)
    }

    func test_mockEngine_stopTranscription_clearsState() async {
        let mockEngine = MockWhisperKitEngine()
        let audioStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        _ = mockEngine.startTranscription(audioStream: audioStream, language: "ja")
        await mockEngine.stopTranscription()
        XCTAssertFalse(mockEngine.isTranscribing)
    }

    func test_mockEngine_isAvailable_returnsTrue() async {
        let mockEngine = MockWhisperKitEngine()
        let available = await mockEngine.isAvailable()
        XCTAssertTrue(available)
    }

    func test_mockEngine_supportedLanguages_matchesWhisperKitEngine() {
        let mockEngine = MockWhisperKitEngine()
        let realEngine = WhisperKitEngine()

        // Mock と実エンジンの supportedLanguages が同じ定義であることを確認
        XCTAssertEqual(mockEngine.supportedLanguages, realEngine.supportedLanguages)
    }
}
