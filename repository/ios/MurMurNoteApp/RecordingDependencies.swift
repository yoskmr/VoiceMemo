import AVFoundation
import Dependencies
import Domain
import InfraSTT

// MARK: - Recording Dependencies
// 録音・文字起こし・一時ファイル管理のDependency実装

// MARK: AudioRecorderClient → AVAudioEngineRecorder

extension AudioRecorderClient: DependencyKey {
    public static let liveValue: AudioRecorderClient = {
        let recorder = AVAudioEngineRecorder()
        return AudioRecorderClient(
            startRecording: { try await recorder.startRecording() },
            pauseRecording: { try await recorder.pauseRecording() },
            resumeRecording: { try await recorder.resumeRecording() },
            stopRecording: { try await recorder.stopRecording() },
            isRecording: { recorder.isRecording },
            isPaused: { recorder.isPaused },
            requestPermission: {
                await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }
        )
    }()
}

// MARK: STTEngineClient → AppleSpeechEngine

extension STTEngineClient: DependencyKey {
    public static let liveValue: STTEngineClient = {
        let engine = AppleSpeechEngine()
        return STTEngineClient(
            startTranscription: { audioStream, language in
                engine.startTranscription(audioStream: audioStream, language: language)
            },
            finishTranscription: { try await engine.finishTranscription() },
            stopTranscription: { await engine.stopTranscription() },
            isAvailable: { await engine.isAvailable() },
            setCustomDictionary: { dictionary in
                await engine.setCustomDictionary(dictionary)
            }
        )
    }()
}

// MARK: TemporaryRecordingStoreClient → 一時ファイル削除

extension TemporaryRecordingStoreClient: DependencyKey {
    public static let liveValue = TemporaryRecordingStoreClient(
        cleanup: { recordingID in
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("Recording", isDirectory: true)
            let fm = FileManager.default

            guard fm.fileExists(atPath: tmpDir.path),
                  let files = try? fm.contentsOfDirectory(atPath: tmpDir.path) else {
                return
            }

            let prefix = recordingID.uuidString
            for file in files where file.hasPrefix(prefix) {
                try? fm.removeItem(at: tmpDir.appendingPathComponent(file))
            }
        }
    )
}
