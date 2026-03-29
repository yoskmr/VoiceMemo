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

// MARK: STTEngineClient → SpeechAnalyzer (iOS 26+) via Factory

extension STTEngineClient: DependencyKey {
    private static let factory = STTEngineFactory()

    private static func resolveEngine() -> any STTEngineProtocol {
        #if DEBUG
        // デバッグメニュー: STT エンジン強制選択
        if let forcedEngine = UserDefaults.standard.string(forKey: "debug_forceSTTEngine"),
           forcedEngine != "auto" {
            switch forcedEngine {
            case "speech_analyzer":
                if #available(iOS 26.0, *) {
                    print("[STT] デバッグ強制: SpeechAnalyzer")
                    return SpeechAnalyzerEngine()
                }
                print("[STT] デバッグ強制: SpeechAnalyzer 要求だが iOS 26 未満 → Apple Speech にフォールバック")
                return AppleSpeechEngine()
            case "whisper_kit":
                print("[STT] デバッグ強制: Apple Speech")
                return AppleSpeechEngine()
            default:
                print("[STT] デバッグ: 未知のエンジン '\(forcedEngine)' → 自動選択にフォールバック")
            }
        }
        #endif

        if #available(iOS 26.0, *) {
            let engine = SpeechAnalyzerEngine()
            #if DEBUG
            print("[STT] エンジン選択: SpeechAnalyzer")
            #endif
            return engine
        } else {
            let engine = AppleSpeechEngine()
            #if DEBUG
            print("[STT] エンジン選択: Apple Speech (フォールバック)")
            #endif
            return engine
        }
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
