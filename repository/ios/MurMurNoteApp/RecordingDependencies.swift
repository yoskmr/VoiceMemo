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

// MARK: STTEngineClient → WhisperKit (base) with Apple Speech fallback

extension STTEngineClient: DependencyKey {
    // エンジンインスタンスを保持（遅延初期化）
    private static let whisperEngine = WhisperKitEngine(modelName: "openai_whisper-base")
    private static let appleEngine = AppleSpeechEngine()

    /// 呼び出し時に動的にエンジンを選択（ウェルカム画面でダウンロード完了後に切り替わる）
    private static func resolveEngine() -> any STTEngineProtocol {
        let useWhisper = whisperEngine.isModelDownloaded()
        #if DEBUG
        print("[STT] エンジン選択: \(useWhisper ? "WhisperKit (base)" : "Apple Speech")")
        #endif
        return useWhisper ? whisperEngine : appleEngine
    }

    public static let liveValue: STTEngineClient = {
        return STTEngineClient(
            startTranscription: { audioStream, language in
                resolveEngine().startTranscription(audioStream: audioStream, language: language)
            },
            finishTranscription: { try await resolveEngine().finishTranscription() },
            stopTranscription: { await resolveEngine().stopTranscription() },
            isAvailable: { await resolveEngine().isAvailable() },
            setCustomDictionary: { dictionary in
                await resolveEngine().setCustomDictionary(dictionary)
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
