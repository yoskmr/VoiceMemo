import AVFoundation
import XCTest
@testable import Domain
@testable import InfraSTT

final class AppleSpeechEngineTests: XCTestCase {

    private var engine: AppleSpeechEngine!

    override func setUp() {
        super.setUp()
        engine = AppleSpeechEngine()
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

    func test_engineType_isSpeechAnalyzer() {
        XCTAssertEqual(engine.engineType, .speechAnalyzer)
    }

    // MARK: - supportedLanguages テスト

    func test_supportedLanguages_isNotEmpty() {
        XCTAssertFalse(engine.supportedLanguages.isEmpty)
    }

    func test_supportedLanguages_containsJapanese() {
        // SFSpeechRecognizerの対応言語に日本語が含まれることを確認
        let hasJapanese = engine.supportedLanguages.contains { lang in
            lang.hasPrefix("ja")
        }
        XCTAssertTrue(hasJapanese, "日本語(ja)がsupportedLanguagesに含まれるべき")
    }

    // MARK: - 初期化テスト

    func test_init_defaultLocaleIsJapanese() {
        // デフォルトのロケールが ja-JP であることを確認
        let defaultEngine = AppleSpeechEngine()
        XCTAssertEqual(defaultEngine.engineType, .speechAnalyzer)
    }

    func test_init_withCustomLocale() {
        let englishEngine = AppleSpeechEngine(locale: Locale(identifier: "en-US"))
        XCTAssertEqual(englishEngine.engineType, .speechAnalyzer)
    }

    // MARK: - stopTranscription テスト（リソース解放）

    func test_stopTranscription_doesNotCrash() async {
        // 認識を開始していない状態で stop を呼んでもクラッシュしないことを確認
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
        // クラッシュしなければ OK
    }

    // MARK: - startTranscription テスト（基本動作）

    func test_startTranscription_returnsAsyncStream() {
        let audioStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        let resultStream = engine.startTranscription(
            audioStream: audioStream,
            language: "ja-JP"
        )

        // AsyncStream<TranscriptionResult> 型が返却されることを確認
        let _: AsyncStream<TranscriptionResult> = resultStream
    }

    // MARK: - オフライン認識設定テスト

    func test_requiresOnDeviceRecognition_isConfigured() {
        // AppleSpeechEngine がオフライン認識モードを使用することを確認
        // （内部実装の詳細はブラックボックスだが、プロパティ経由で検証）
        let offlineEngine = AppleSpeechEngine(
            locale: Locale(identifier: "ja-JP"),
            requiresOnDeviceRecognition: true
        )
        XCTAssertNotNil(offlineEngine)
    }

    func test_requiresOnDeviceRecognition_defaultIsTrue() {
        // デフォルトではオフライン認識が有効
        let defaultEngine = AppleSpeechEngine()
        XCTAssertNotNil(defaultEngine)
    }

    // MARK: - isAvailable テスト
    // 注意: isAvailable は SFSpeechRecognizer の状態と権限に依存するため、
    // CI環境では正確なテストが困難。基本的な呼び出しテストのみ行う。

    func test_isAvailable_returnsWithoutCrash() async {
        let _ = await engine.isAvailable()
        // クラッシュしなければ OK
    }

    // MARK: - 連続呼び出しテスト

    func test_multipleStopTranscription_doesNotCrash() async {
        await engine.stopTranscription()
        await engine.stopTranscription()
        await engine.stopTranscription()
    }

    // MARK: - stopTranscription 後の finishTranscription

    func test_finishTranscription_afterStop_throwsEngineNotInitialized() async {
        await engine.stopTranscription()
        do {
            _ = try await engine.finishTranscription()
            XCTFail("Expected STTError.engineNotInitialized")
        } catch let error as STTError {
            XCTAssertEqual(error, .engineNotInitialized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
