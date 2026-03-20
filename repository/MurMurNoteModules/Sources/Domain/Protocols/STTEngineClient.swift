import AVFoundation
import Dependencies
import Foundation

/// STTEngineProtocol の TCA Dependency ラッパー
/// @Dependency(\.sttEngine) でReducerから注入可能にする
public struct STTEngineClient: Sendable {
    public var startTranscription: @Sendable (AsyncStream<AVAudioPCMBuffer>, String) -> AsyncStream<TranscriptionResult>
    public var finishTranscription: @Sendable () async throws -> TranscriptionResult
    public var stopTranscription: @Sendable () async -> Void
    public var isAvailable: @Sendable () async -> Bool

    public init(
        startTranscription: @escaping @Sendable (AsyncStream<AVAudioPCMBuffer>, String) -> AsyncStream<TranscriptionResult>,
        finishTranscription: @escaping @Sendable () async throws -> TranscriptionResult,
        stopTranscription: @escaping @Sendable () async -> Void,
        isAvailable: @escaping @Sendable () async -> Bool
    ) {
        self.startTranscription = startTranscription
        self.finishTranscription = finishTranscription
        self.stopTranscription = stopTranscription
        self.isAvailable = isAvailable
    }
}

// MARK: - DependencyKey

extension STTEngineClient: TestDependencyKey {
    public static let testValue = STTEngineClient(
        startTranscription: unimplemented("STTEngineClient.startTranscription"),
        finishTranscription: unimplemented("STTEngineClient.finishTranscription"),
        stopTranscription: unimplemented("STTEngineClient.stopTranscription"),
        isAvailable: unimplemented("STTEngineClient.isAvailable")
    )
}

extension DependencyValues {
    public var sttEngine: STTEngineClient {
        get { self[STTEngineClient.self] }
        set { self[STTEngineClient.self] = newValue }
    }
}
