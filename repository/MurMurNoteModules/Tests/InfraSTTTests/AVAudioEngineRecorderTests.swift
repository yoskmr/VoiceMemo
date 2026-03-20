import XCTest
@testable import Domain
@testable import InfraSTT

/// AVAudioEngineRecorderの単体テスト
/// 注意: 実際のマイク入力が必要なテストはCI環境では実行できないため、
/// 初期状態と状態遷移のエラーケースのみテストする
final class AVAudioEngineRecorderTests: XCTestCase {

    private var recorder: AVAudioEngineRecorder!

    override func setUp() {
        super.setUp()
        recorder = AVAudioEngineRecorder()
    }

    override func tearDown() {
        recorder = nil
        super.tearDown()
    }

    // MARK: - 初期状態テスト

    func test_initialState_isNotRecording() {
        XCTAssertFalse(recorder.isRecording)
    }

    func test_initialState_isNotPaused() {
        XCTAssertFalse(recorder.isPaused)
    }

    // MARK: - 異常系: 録音していない状態での操作

    func test_stopRecording_whenNotRecording_throwsNotRecording() async {
        do {
            _ = try await recorder.stopRecording()
            XCTFail("Expected RecordingError.notRecording")
        } catch let error as RecordingError {
            XCTAssertEqual(error, .notRecording)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_pauseRecording_whenNotRecording_throwsNotRecording() async {
        do {
            try await recorder.pauseRecording()
            XCTFail("Expected RecordingError.notRecording")
        } catch let error as RecordingError {
            XCTAssertEqual(error, .notRecording)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_resumeRecording_whenNotRecording_throwsNotRecording() async {
        do {
            try await recorder.resumeRecording()
            XCTFail("Expected RecordingError.notRecording")
        } catch let error as RecordingError {
            XCTAssertEqual(error, .notRecording)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - 型適合テスト

    func test_conformsToAudioRecorderProtocol() {
        // AVAudioEngineRecorder が AudioRecorderProtocol に準拠していることを確認
        let _: any AudioRecorderProtocol = recorder
    }

    func test_isSendable() {
        // Sendable 適合の確認（コンパイル時チェック）
        let _: any Sendable = recorder
    }
}
