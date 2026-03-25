import AVFoundation
import XCTest
@testable import Domain

// MARK: - Mock STT Engine for Protocol Conformance Tests

/// テスト用のモックSTTエンジン
/// STTEngineProtocol の適合テストに使用
final class MockSTTEngine: STTEngineProtocol, @unchecked Sendable {
    let engineType: STTEngineType
    private(set) var startTranscriptionCallCount = 0
    private(set) var finishTranscriptionCallCount = 0
    private(set) var stopTranscriptionCallCount = 0
    private(set) var isAvailableCallCount = 0
    private(set) var setCustomDictionaryCallCount = 0
    private(set) var lastLanguage: String?
    private(set) var lastDictionary: [String: String]?

    var mockSupportedLanguages: [String] = ["ja-JP", "en-US"]
    var mockIsAvailable: Bool = true
    var mockResults: [TranscriptionResult] = []
    var mockFinalResult: TranscriptionResult = .empty()
    var mockFinishError: Error?

    init(engineType: STTEngineType = .speechAnalyzer) {
        self.engineType = engineType
    }

    var supportedLanguages: [String] {
        mockSupportedLanguages
    }

    func startTranscription(
        audioStream: AsyncStream<AVAudioPCMBuffer>,
        language: String
    ) -> AsyncStream<TranscriptionResult> {
        startTranscriptionCallCount += 1
        lastLanguage = language
        let results = mockResults
        return AsyncStream { continuation in
            Task {
                for result in results {
                    continuation.yield(result)
                }
                continuation.finish()
            }
        }
    }

    func finishTranscription() async throws -> TranscriptionResult {
        finishTranscriptionCallCount += 1
        if let error = mockFinishError {
            throw error
        }
        return mockFinalResult
    }

    func stopTranscription() async {
        stopTranscriptionCallCount += 1
    }

    func isAvailable() async -> Bool {
        isAvailableCallCount += 1
        return mockIsAvailable
    }

    func setCustomDictionary(_ dictionary: [String: String]) async {
        setCustomDictionaryCallCount += 1
        lastDictionary = dictionary
    }
}

// MARK: - Protocol Conformance Tests

final class STTEngineProtocolTests: XCTestCase {

    private var mockEngine: MockSTTEngine!

    override func setUp() {
        super.setUp()
        mockEngine = MockSTTEngine()
    }

    override func tearDown() {
        mockEngine = nil
        super.tearDown()
    }

    // MARK: - プロトコル適合テスト

    func test_conformsToSTTEngineProtocol() {
        let _: any STTEngineProtocol = mockEngine
    }

    func test_conformsToSendable() {
        let _: any Sendable = mockEngine
    }

    // MARK: - engineType テスト

    func test_engineType_returnsSpeechAnalyzer() {
        let engine = MockSTTEngine(engineType: .speechAnalyzer)
        XCTAssertEqual(engine.engineType, .speechAnalyzer)
    }

    func test_engineType_returnsWhisperKit() {
        let engine = MockSTTEngine(engineType: .whisperKit)
        XCTAssertEqual(engine.engineType, .whisperKit)
    }

    func test_engineType_returnsCloudSTT() {
        let engine = MockSTTEngine(engineType: .cloudSTT)
        XCTAssertEqual(engine.engineType, .cloudSTT)
    }

    // MARK: - supportedLanguages テスト

    func test_supportedLanguages_returnsExpectedLanguages() {
        mockEngine.mockSupportedLanguages = ["ja-JP", "en-US", "zh-CN"]
        XCTAssertEqual(mockEngine.supportedLanguages, ["ja-JP", "en-US", "zh-CN"])
    }

    func test_supportedLanguages_containsJapanese() {
        XCTAssertTrue(mockEngine.supportedLanguages.contains("ja-JP"))
    }

    // MARK: - startTranscription テスト

    func test_startTranscription_incrementsCallCount() async {
        let audioStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        _ = mockEngine.startTranscription(audioStream: audioStream, language: "ja-JP")
        XCTAssertEqual(mockEngine.startTranscriptionCallCount, 1)
    }

    func test_startTranscription_recordsLanguage() async {
        let audioStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        _ = mockEngine.startTranscription(audioStream: audioStream, language: "ja-JP")
        XCTAssertEqual(mockEngine.lastLanguage, "ja-JP")
    }

    func test_startTranscription_yieldsPartialResults() async {
        let partialResult = TranscriptionResult(
            text: "こんに",
            confidence: 0.6,
            isFinal: false,
            language: "ja-JP"
        )
        let finalResult = TranscriptionResult(
            text: "こんにちは",
            confidence: 0.95,
            isFinal: true,
            language: "ja-JP"
        )
        mockEngine.mockResults = [partialResult, finalResult]

        let audioStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        let resultStream = mockEngine.startTranscription(
            audioStream: audioStream,
            language: "ja-JP"
        )

        var collected: [TranscriptionResult] = []
        for await result in resultStream {
            collected.append(result)
        }

        XCTAssertEqual(collected.count, 2)
        XCTAssertFalse(collected[0].isFinal)
        XCTAssertTrue(collected[1].isFinal)
        XCTAssertEqual(collected[0].text, "こんに")
        XCTAssertEqual(collected[1].text, "こんにちは")
    }

    func test_startTranscription_multipleYieldsInOrder() async {
        let results = (1...5).map { i in
            TranscriptionResult(
                text: String(repeating: "あ", count: i),
                confidence: Double(i) / 5.0,
                isFinal: i == 5,
                language: "ja-JP"
            )
        }
        mockEngine.mockResults = results

        let audioStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        let resultStream = mockEngine.startTranscription(
            audioStream: audioStream,
            language: "ja-JP"
        )

        var collected: [TranscriptionResult] = []
        for await result in resultStream {
            collected.append(result)
        }

        XCTAssertEqual(collected.count, 5)
        for i in 0..<5 {
            XCTAssertEqual(collected[i].text, String(repeating: "あ", count: i + 1))
        }
    }

    // MARK: - finishTranscription テスト

    func test_finishTranscription_returnsFinalResult() async throws {
        let expectedResult = TranscriptionResult(
            text: "完了テキスト",
            confidence: 0.98,
            isFinal: true,
            language: "ja-JP"
        )
        mockEngine.mockFinalResult = expectedResult

        let result = try await mockEngine.finishTranscription()
        XCTAssertEqual(result, expectedResult)
        XCTAssertTrue(result.isFinal)
        XCTAssertEqual(mockEngine.finishTranscriptionCallCount, 1)
    }

    func test_finishTranscription_throwsOnError() async {
        mockEngine.mockFinishError = STTError.engineNotInitialized

        do {
            _ = try await mockEngine.finishTranscription()
            XCTFail("Expected STTError.engineNotInitialized")
        } catch let error as STTError {
            XCTAssertEqual(error, .engineNotInitialized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - stopTranscription テスト

    func test_stopTranscription_incrementsCallCount() async {
        await mockEngine.stopTranscription()
        XCTAssertEqual(mockEngine.stopTranscriptionCallCount, 1)
    }

    // MARK: - isAvailable テスト

    func test_isAvailable_returnsTrueWhenAvailable() async {
        mockEngine.mockIsAvailable = true
        let available = await mockEngine.isAvailable()
        XCTAssertTrue(available)
    }

    func test_isAvailable_returnsFalseWhenUnavailable() async {
        mockEngine.mockIsAvailable = false
        let available = await mockEngine.isAvailable()
        XCTAssertFalse(available)
    }

    // MARK: - setCustomDictionary テスト

    func test_setCustomDictionary_recordsDictionary() async {
        let dictionary = ["meeting": "ミーティング", "project": "プロジェクト"]
        await mockEngine.setCustomDictionary(dictionary)
        XCTAssertEqual(mockEngine.setCustomDictionaryCallCount, 1)
        XCTAssertEqual(mockEngine.lastDictionary, dictionary)
    }

    // MARK: - AsyncStream 終了テスト

    func test_startTranscription_streamFinishesAfterAllResults() async {
        mockEngine.mockResults = [
            TranscriptionResult(
                text: "テスト",
                confidence: 0.9,
                isFinal: true,
                language: "ja-JP"
            ),
        ]

        let audioStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        let resultStream = mockEngine.startTranscription(
            audioStream: audioStream,
            language: "ja-JP"
        )

        var resultCount = 0
        for await _ in resultStream {
            resultCount += 1
        }
        // AsyncStream の for-await ループが正常に終了（finish）されることを確認
        XCTAssertEqual(resultCount, 1)
    }

    func test_startTranscription_emptyResultsStreamFinishes() async {
        mockEngine.mockResults = []

        let audioStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        let resultStream = mockEngine.startTranscription(
            audioStream: audioStream,
            language: "ja-JP"
        )

        var resultCount = 0
        for await _ in resultStream {
            resultCount += 1
        }
        XCTAssertEqual(resultCount, 0)
    }
}
