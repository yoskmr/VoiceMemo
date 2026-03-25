import AVFoundation
import XCTest
@testable import Domain

// MARK: - MockAudioRecorder

/// AudioRecorderProtocolのモック実装
/// テスト用に状態遷移と音量レベルストリームをシミュレートする
final class MockAudioRecorder: AudioRecorderProtocol, @unchecked Sendable {
    private let lock = NSLock()

    private var _isRecording = false
    private var _isPaused = false
    private var continuation: AsyncStream<AudioLevelUpdate>.Continuation?

    /// ロックを取得してクロージャを実行する
    @discardableResult
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    var isRecording: Bool {
        withLock { _isRecording }
    }

    var isPaused: Bool {
        withLock { _isPaused }
    }

    /// テスト用: 音量レベル更新を送信する
    func sendAudioLevel(_ update: AudioLevelUpdate) {
        continuation?.yield(update)
    }

    /// テスト用: ストリームを終了する
    func finishStream() {
        continuation?.finish()
    }

    // テスト用: stopRecording で返す結果
    var recordingResultToReturn: RecordingResult?

    func startRecording() async throws -> (levels: AsyncStream<AudioLevelUpdate>, pcmBuffers: AsyncStream<AVAudioPCMBuffer>) {
        try withLock {
            if _isRecording {
                throw RecordingError.alreadyRecording
            }
            _isRecording = true
            _isPaused = false
        }

        let levelStream = AsyncStream<AudioLevelUpdate> { continuation in
            self.withLock {
                self.continuation = continuation
            }
        }
        let pcmStream = AsyncStream<AVAudioPCMBuffer> { _ in }

        return (levels: levelStream, pcmBuffers: pcmStream)
    }

    func pauseRecording() async throws {
        try withLock {
            guard _isRecording else {
                throw RecordingError.notRecording
            }
            guard !_isPaused else {
                return
            }
            _isPaused = true
        }
    }

    func resumeRecording() async throws {
        try withLock {
            guard _isRecording else {
                throw RecordingError.notRecording
            }
            guard _isPaused else {
                throw RecordingError.notPaused
            }
            _isPaused = false
        }
    }

    func stopRecording() async throws -> RecordingResult {
        try withLock {
            guard _isRecording else {
                throw RecordingError.notRecording
            }
            _isRecording = false
            _isPaused = false
        }

        continuation?.finish()

        guard let result = recordingResultToReturn else {
            throw RecordingError.fileSaveFailed("No recording result configured")
        }
        return result
    }
}

// MARK: - 状態遷移テスト

final class AudioRecorderStateTransitionTests: XCTestCase {

    private var recorder: MockAudioRecorder!

    override func setUp() {
        super.setUp()
        recorder = MockAudioRecorder()
    }

    override func tearDown() {
        recorder = nil
        super.tearDown()
    }

    // MARK: - 正常系: 録音開始

    func test_startRecording_setsIsRecordingToTrue() async throws {
        // Given: 録音していない状態
        XCTAssertFalse(recorder.isRecording)

        // When: 録音を開始
        _ = try await recorder.startRecording()

        // Then: isRecording が true になる
        XCTAssertTrue(recorder.isRecording)
        XCTAssertFalse(recorder.isPaused)
    }

    // MARK: - 正常系: 録音停止

    func test_stopRecording_returnsRecordingResult() async throws {
        // Given: 録音中の状態
        let expectedURL = URL(fileURLWithPath: "/tmp/test.m4a")
        recorder.recordingResultToReturn = RecordingResult(
            fileURL: expectedURL,
            duration: 10.5,
            format: .m4a
        )
        _ = try await recorder.startRecording()

        // When: 録音を停止
        let result = try await recorder.stopRecording()

        // Then: 録音結果が正しく返却される
        XCTAssertEqual(result.fileURL, expectedURL)
        XCTAssertEqual(result.duration, 10.5)
        XCTAssertEqual(result.format, .m4a)
        XCTAssertFalse(recorder.isRecording)
    }

    // MARK: - 正常系: 一時停止

    func test_pauseRecording_setsIsPausedToTrue() async throws {
        // Given: 録音中の状態
        _ = try await recorder.startRecording()

        // When: 一時停止
        try await recorder.pauseRecording()

        // Then: isPaused が true になる
        XCTAssertTrue(recorder.isRecording)
        XCTAssertTrue(recorder.isPaused)
    }

    // MARK: - 正常系: 再開

    func test_resumeRecording_setsIsPausedToFalse() async throws {
        // Given: 一時停止中の状態
        _ = try await recorder.startRecording()
        try await recorder.pauseRecording()
        XCTAssertTrue(recorder.isPaused)

        // When: 再開
        try await recorder.resumeRecording()

        // Then: isPaused が false になる
        XCTAssertTrue(recorder.isRecording)
        XCTAssertFalse(recorder.isPaused)
    }

    // MARK: - 正常系: 完全なライフサイクル

    func test_fullRecordingLifecycle() async throws {
        // Given
        let expectedURL = URL(fileURLWithPath: "/tmp/lifecycle.m4a")
        recorder.recordingResultToReturn = RecordingResult(
            fileURL: expectedURL,
            duration: 30.0,
            format: .m4a
        )

        // Step 1: 初期状態
        XCTAssertFalse(recorder.isRecording)
        XCTAssertFalse(recorder.isPaused)

        // Step 2: 録音開始
        _ = try await recorder.startRecording()
        XCTAssertTrue(recorder.isRecording)
        XCTAssertFalse(recorder.isPaused)

        // Step 3: 一時停止
        try await recorder.pauseRecording()
        XCTAssertTrue(recorder.isRecording)
        XCTAssertTrue(recorder.isPaused)

        // Step 4: 再開
        try await recorder.resumeRecording()
        XCTAssertTrue(recorder.isRecording)
        XCTAssertFalse(recorder.isPaused)

        // Step 5: 停止
        let result = try await recorder.stopRecording()
        XCTAssertFalse(recorder.isRecording)
        XCTAssertFalse(recorder.isPaused)
        XCTAssertEqual(result.duration, 30.0)
    }

    // MARK: - 異常系: 二重start防止

    func test_startRecording_whileAlreadyRecording_throwsAlreadyRecording() async throws {
        // Given: 録音中の状態
        _ = try await recorder.startRecording()

        // When/Then: 二度目のstartでエラー
        do {
            _ = try await recorder.startRecording()
            XCTFail("Expected RecordingError.alreadyRecording")
        } catch let error as RecordingError {
            XCTAssertEqual(error, .alreadyRecording)
        }
    }

    // MARK: - 異常系: 録音していない状態での停止

    func test_stopRecording_whenNotRecording_throwsNotRecording() async {
        // Given: 録音していない状態

        // When/Then: stopでエラー
        do {
            _ = try await recorder.stopRecording()
            XCTFail("Expected RecordingError.notRecording")
        } catch let error as RecordingError {
            XCTAssertEqual(error, .notRecording)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - 異常系: 録音していない状態での一時停止

    func test_pauseRecording_whenNotRecording_throwsNotRecording() async {
        // Given: 録音していない状態

        // When/Then: pauseでエラー
        do {
            try await recorder.pauseRecording()
            XCTFail("Expected RecordingError.notRecording")
        } catch let error as RecordingError {
            XCTAssertEqual(error, .notRecording)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - 異常系: 一時停止中でない状態での再開

    func test_resumeRecording_whenNotPaused_throwsNotPaused() async throws {
        // Given: 録音中だが一時停止していない状態
        _ = try await recorder.startRecording()

        // When/Then: resumeでエラー
        do {
            try await recorder.resumeRecording()
            XCTFail("Expected RecordingError.notPaused")
        } catch let error as RecordingError {
            XCTAssertEqual(error, .notPaused)
        }
    }
}

// MARK: - AudioLevelUpdate ストリーム配信テスト

final class AudioLevelStreamTests: XCTestCase {

    private var recorder: MockAudioRecorder!

    override func setUp() {
        super.setUp()
        recorder = MockAudioRecorder()
    }

    override func tearDown() {
        recorder = nil
        super.tearDown()
    }

    func test_audioLevelStream_receivesUpdates() async throws {
        // Given: 録音を開始
        let stream = try await recorder.startRecording()

        // When: 音量レベルを送信
        let expectedUpdates = [
            AudioLevelUpdate(averagePower: -20.0, peakPower: -10.0, timestamp: 0.1),
            AudioLevelUpdate(averagePower: -15.0, peakPower: -5.0, timestamp: 0.2),
            AudioLevelUpdate(averagePower: -30.0, peakPower: -20.0, timestamp: 0.3),
        ]

        // バックグラウンドで更新を送信
        Task {
            for update in expectedUpdates {
                // 少し待機してストリームのイテレータが準備完了するのを待つ
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                recorder.sendAudioLevel(update)
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
            recorder.finishStream()
        }

        // Then: ストリームから受信
        var receivedUpdates: [AudioLevelUpdate] = []
        for await update in stream.levels {
            receivedUpdates.append(update)
        }

        XCTAssertEqual(receivedUpdates.count, expectedUpdates.count)
        for (received, expected) in zip(receivedUpdates, expectedUpdates) {
            XCTAssertEqual(received.averagePower, expected.averagePower)
            XCTAssertEqual(received.peakPower, expected.peakPower)
            XCTAssertEqual(received.timestamp, expected.timestamp)
        }
    }

    func test_audioLevelStream_finishesWhenRecordingStopped() async throws {
        // Given: 録音を開始
        let expectedURL = URL(fileURLWithPath: "/tmp/stream_test.m4a")
        recorder.recordingResultToReturn = RecordingResult(
            fileURL: expectedURL,
            duration: 5.0,
            format: .m4a
        )
        let stream = try await recorder.startRecording()

        // When: いくつか更新を送信してから停止
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000)
            recorder.sendAudioLevel(
                AudioLevelUpdate(averagePower: -20.0, peakPower: -10.0, timestamp: 0.1)
            )
            try? await Task.sleep(nanoseconds: 10_000_000)
            _ = try await recorder.stopRecording()
        }

        // Then: ストリームが終了する
        var count = 0
        for await _ in stream.levels {
            count += 1
        }

        XCTAssertGreaterThanOrEqual(count, 1)
    }
}

// MARK: - AudioLevelUpdate 値オブジェクトテスト

final class AudioLevelUpdateTests: XCTestCase {

    func test_init_setsProperties() {
        let update = AudioLevelUpdate(averagePower: -25.0, peakPower: -12.0, timestamp: 1.5)

        XCTAssertEqual(update.averagePower, -25.0)
        XCTAssertEqual(update.peakPower, -12.0)
        XCTAssertEqual(update.timestamp, 1.5)
    }

    func test_equatable_sameValues_areEqual() {
        let a = AudioLevelUpdate(averagePower: -20.0, peakPower: -10.0, timestamp: 0.5)
        let b = AudioLevelUpdate(averagePower: -20.0, peakPower: -10.0, timestamp: 0.5)

        XCTAssertEqual(a, b)
    }

    func test_equatable_differentValues_areNotEqual() {
        let a = AudioLevelUpdate(averagePower: -20.0, peakPower: -10.0, timestamp: 0.5)
        let b = AudioLevelUpdate(averagePower: -15.0, peakPower: -10.0, timestamp: 0.5)

        XCTAssertNotEqual(a, b)
    }
}

// MARK: - RecordingResult 値オブジェクトテスト

final class RecordingResultTests: XCTestCase {

    func test_init_setsProperties() {
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        let result = RecordingResult(fileURL: url, duration: 60.0, format: .m4a)

        XCTAssertEqual(result.fileURL, url)
        XCTAssertEqual(result.duration, 60.0)
        XCTAssertEqual(result.format, .m4a)
    }

    func test_equatable_sameValues_areEqual() {
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        let a = RecordingResult(fileURL: url, duration: 60.0, format: .m4a)
        let b = RecordingResult(fileURL: url, duration: 60.0, format: .m4a)

        XCTAssertEqual(a, b)
    }

    func test_equatable_differentFormat_areNotEqual() {
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        let a = RecordingResult(fileURL: url, duration: 60.0, format: .m4a)
        let b = RecordingResult(fileURL: url, duration: 60.0, format: .opus)

        XCTAssertNotEqual(a, b)
    }
}

// MARK: - RecordingError テスト

final class RecordingErrorTests: XCTestCase {

    func test_equatable_sameErrors_areEqual() {
        XCTAssertEqual(RecordingError.alreadyRecording, RecordingError.alreadyRecording)
        XCTAssertEqual(RecordingError.notRecording, RecordingError.notRecording)
        XCTAssertEqual(RecordingError.notPaused, RecordingError.notPaused)
        XCTAssertEqual(RecordingError.microphonePermissionDenied, RecordingError.microphonePermissionDenied)
        XCTAssertEqual(RecordingError.compositionFailed, RecordingError.compositionFailed)
        XCTAssertEqual(RecordingError.exportFailed, RecordingError.exportFailed)
        XCTAssertEqual(RecordingError.insufficientStorage, RecordingError.insufficientStorage)
    }

    func test_equatable_differentErrors_areNotEqual() {
        XCTAssertNotEqual(RecordingError.alreadyRecording, RecordingError.notRecording)
        XCTAssertNotEqual(RecordingError.notRecording, RecordingError.notPaused)
    }
}
