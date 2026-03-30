import AVFoundation
import Dependencies
import Foundation

/// AudioRecorderProtocol の TCA Dependency ラッパー
/// @Dependency(\.audioRecorder) でReducerから注入可能にする
public struct AudioRecorderClient: Sendable {
    /// 録音開始。AudioLevelUpdateストリームとPCMバッファストリーム（STT用）を返す
    public var startRecording: @Sendable () async throws -> (levels: AsyncStream<AudioLevelUpdate>, pcmBuffers: AsyncStream<AVAudioPCMBuffer>)
    public var pauseRecording: @Sendable () async throws -> Void
    public var resumeRecording: @Sendable () async throws -> Void
    public var stopRecording: @Sendable () async throws -> RecordingResult
    public var isRecording: @Sendable () -> Bool
    public var isPaused: @Sendable () -> Bool
    public var requestPermission: @Sendable () async -> Bool

    public init(
        startRecording: @escaping @Sendable () async throws -> (levels: AsyncStream<AudioLevelUpdate>, pcmBuffers: AsyncStream<AVAudioPCMBuffer>),
        pauseRecording: @escaping @Sendable () async throws -> Void,
        resumeRecording: @escaping @Sendable () async throws -> Void,
        stopRecording: @escaping @Sendable () async throws -> RecordingResult,
        isRecording: @escaping @Sendable () -> Bool,
        isPaused: @escaping @Sendable () -> Bool,
        requestPermission: @escaping @Sendable () async -> Bool
    ) {
        self.startRecording = startRecording
        self.pauseRecording = pauseRecording
        self.resumeRecording = resumeRecording
        self.stopRecording = stopRecording
        self.isRecording = isRecording
        self.isPaused = isPaused
        self.requestPermission = requestPermission
    }
}

// MARK: - DependencyKey

extension AudioRecorderClient: TestDependencyKey {
    public static let testValue = AudioRecorderClient(
        startRecording: unimplemented("AudioRecorderClient.startRecording"),
        pauseRecording: unimplemented("AudioRecorderClient.pauseRecording"),
        resumeRecording: unimplemented("AudioRecorderClient.resumeRecording"),
        stopRecording: unimplemented("AudioRecorderClient.stopRecording"),
        isRecording: unimplemented("AudioRecorderClient.isRecording"),
        isPaused: unimplemented("AudioRecorderClient.isPaused"),
        requestPermission: unimplemented("AudioRecorderClient.requestPermission")
    )
}

extension DependencyValues {
    public var audioRecorder: AudioRecorderClient {
        get { self[AudioRecorderClient.self] }
        set { self[AudioRecorderClient.self] = newValue }
    }
}
