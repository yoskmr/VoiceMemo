import AVFoundation
import XCTest
@testable import Domain
@testable import InfraSTT

@available(iOS 26.0, macOS 26.0, *)
final class SpeechAnalyzerEngineTests: XCTestCase {

    private var engine: SpeechAnalyzerEngine!

    override func setUp() {
        super.setUp()
        engine = SpeechAnalyzerEngine()
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
        let hasJapanese = engine.supportedLanguages.contains { $0.hasPrefix("ja") }
        XCTAssertTrue(hasJapanese, "日本語(ja)がsupportedLanguagesに含まれるべき")
    }

    func test_supportedLanguages_containsEnglish() {
        let hasEnglish = engine.supportedLanguages.contains { $0.hasPrefix("en") }
        XCTAssertTrue(hasEnglish, "英語(en)がsupportedLanguagesに含まれるべき")
    }

    // MARK: - stopTranscription テスト

    func test_stopTranscription_doesNotCrash() async {
        await engine.stopTranscription()
    }

    func test_multipleStopTranscription_doesNotCrash() async {
        await engine.stopTranscription()
        await engine.stopTranscription()
        await engine.stopTranscription()
    }

    // MARK: - finishTranscription テスト

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
        await engine.setCustomDictionary(["AI": "人工知能", "ML": "機械学習"])
    }

    func test_setCustomDictionary_emptyDictionary_doesNotCrash() async {
        await engine.setCustomDictionary([:])
    }

    // MARK: - startTranscription テスト

    func test_startTranscription_returnsAsyncStream() {
        let audioStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        let resultStream = engine.startTranscription(
            audioStream: audioStream,
            language: "ja-JP"
        )
        let _: AsyncStream<TranscriptionResult> = resultStream
    }

    func test_startTranscription_emptyStream_finishesGracefully() async {
        let audioStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        let resultStream = engine.startTranscription(
            audioStream: audioStream,
            language: "ja-JP"
        )

        var results: [TranscriptionResult] = []
        for await result in resultStream {
            results.append(result)
        }
        // 空ストリームの場合、結果は0件で正常終了
    }

    // MARK: - 競合テスト

    func test_stopTranscription_afterFinishAttempt_doesNotCrash() async {
        do {
            _ = try await engine.finishTranscription()
        } catch {}
        await engine.stopTranscription()
    }

    func test_doubleStart_doesNotCrash() {
        let stream1 = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        let stream2 = AsyncStream<AVAudioPCMBuffer> { $0.finish() }

        // 2回連続で startTranscription を呼んでもクラッシュしない
        let _ = engine.startTranscription(audioStream: stream1, language: "ja-JP")
        let _ = engine.startTranscription(audioStream: stream2, language: "ja-JP")
    }

    // MARK: - isAvailable テスト

    func test_isAvailable_returnsWithoutCrash() async {
        let _ = await engine.isAvailable()
    }

    // MARK: - downloadLanguagePack テスト

    func test_downloadLanguagePack_unsupportedLocale_throws() async {
        do {
            try await engine.downloadLanguagePack(locale: Locale(identifier: "xx-XX"))
            XCTFail("Expected STTError.languageNotSupported")
        } catch let error as STTError {
            if case .languageNotSupported = error {
                // 期待通り
            } else {
                XCTFail("Expected languageNotSupported, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
