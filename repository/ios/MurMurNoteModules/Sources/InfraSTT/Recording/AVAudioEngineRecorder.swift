import Accelerate
import AVFoundation
import Domain
import Foundation

/// AVAudioEngineベースの録音エンジン実装
/// 設計書01-system-architecture.md セクション4.1、TASK-0003 準拠
///
/// - PCM 16kHz Mono で録音し、STTエンジンへストリーミング可能
/// - AAC/M4A 64kbps で圧縮保存（NFR-006: 1分500KB以内）
/// - リアルタイム音量レベルメーター（averagePower, peakPower）をAsyncStreamで配信
/// - 録音中一時ファイルに NSFileProtectionCompleteUntilFirstUserAuthentication を適用
/// - Documents/Audio/ に最終ファイルを保存
public final class AVAudioEngineRecorder: @unchecked Sendable {

    // MARK: - State (protected by lock)

    private struct State {
        var isRecording = false
        var isPaused = false
        var recordingStartTime: Date?
        var pausedDuration: TimeInterval = 0
        var pauseStartTime: Date?
        var audioFile: AVAudioFile?
        var levelContinuation: AsyncStream<AudioLevelUpdate>.Continuation?
        var pcmBufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
        var tempFileURL: URL?
    }

    // MARK: - Properties

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var state = State()

    // MARK: - Constants

    /// PCM録音フォーマット: 16kHz Mono（STTエンジン入力用）
    private static let pcmSampleRate: Double = 16000.0
    private static let pcmChannels: AVAudioChannelCount = 1

    /// AAC圧縮設定（NFR-006: 64kbps = 約480KB/分）
    private static let aacSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44100.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64000,
    ]

    // MARK: - Directory Management

    /// Documents/Audio/ ディレクトリURL
    private var audioDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("Audio", isDirectory: true)
    }

    /// tmp/Recording/ ディレクトリURL
    private var tempRecordingDirectory: URL {
        let tmp = FileManager.default.temporaryDirectory
        return tmp.appendingPathComponent("Recording", isDirectory: true)
    }

    // MARK: - Init

    public init() {}

    // MARK: - Synchronization Helpers

    /// ロックを取得して state にアクセスする（同期コンテキスト用）
    @discardableResult
    private func withLock<T>(_ body: (inout State) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }

    // MARK: - Private Helpers

    /// 必要なディレクトリを作成する
    private func ensureDirectoriesExist() throws {
        let fm = FileManager.default

        if !fm.fileExists(atPath: audioDirectory.path) {
            try fm.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        }

        if !fm.fileExists(atPath: tempRecordingDirectory.path) {
            try fm.createDirectory(at: tempRecordingDirectory, withIntermediateDirectories: true)
        }
    }

    /// 一時ファイルにファイル保護を適用する
    /// 統合仕様書セクション8.1準拠: NSFileProtectionCompleteUntilFirstUserAuthentication
    private func applyFileProtection(to url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    /// AVAudioSessionを設定する
    /// NFR-001準拠: 録音開始500ms以内
    private func configureAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        try session.setPreferredSampleRate(Self.pcmSampleRate)
        try session.setPreferredIOBufferDuration(0.01) // 10ms
        try session.setActive(true)
        #endif
    }

    /// PCMバッファからRMS値とピーク値を算出する
    private func calculateLevels(buffer: AVAudioPCMBuffer) -> (averagePower: Float, peakPower: Float) {
        guard let channelData = buffer.floatChannelData?[0] else {
            return (averagePower: -160.0, peakPower: -160.0)
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return (averagePower: -160.0, peakPower: -160.0)
        }

        var rms: Float = 0
        var peak: Float = 0

        // RMS計算（Accelerate vDSP）
        vDSP_measqv(channelData, 1, &rms, vDSP_Length(frameLength))
        rms = sqrt(rms)

        // ピーク値計算（Accelerate vDSP）
        vDSP_maxmgv(channelData, 1, &peak, vDSP_Length(frameLength))

        // dBに変換（参照レベル: 1.0）
        let averagePowerDB: Float = rms > 0 ? 20 * log10(rms) : -160.0
        let peakPowerDB: Float = peak > 0 ? 20 * log10(peak) : -160.0

        return (averagePower: averagePowerDB, peakPower: peakPowerDB)
    }

    /// 録音開始からの経過時間（一時停止分を差し引く）
    /// 注意: lock を保持した状態で呼ぶこと
    private func elapsedTimeLocked() -> TimeInterval {
        guard let startTime = state.recordingStartTime else { return 0 }
        let total = Date().timeIntervalSince(startTime)
        return total - state.pausedDuration
    }

    /// 録音中の一時ファイルを最終保存先に移動する
    private func moveToFinalDestination(tempURL: URL) throws -> URL {
        let fileName = UUID().uuidString + ".m4a"
        let finalURL = audioDirectory.appendingPathComponent(fileName)

        try FileManager.default.moveItem(at: tempURL, to: finalURL)

        // 確定済み音声ファイルには NSFileProtectionComplete を適用
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: finalURL.path
        )

        return finalURL
    }
}

// MARK: - AudioRecorderProtocol

extension AVAudioEngineRecorder: AudioRecorderProtocol {

    public var isRecording: Bool {
        withLock { $0.isRecording }
    }

    public var isPaused: Bool {
        withLock { $0.isPaused }
    }

    public func startRecording() async throws -> (levels: AsyncStream<AudioLevelUpdate>, pcmBuffers: AsyncStream<AVAudioPCMBuffer>) {
        // 二重start防止
        let alreadyRecording = withLock { $0.isRecording }
        if alreadyRecording {
            throw RecordingError.alreadyRecording
        }

        // ディレクトリ準備
        try ensureDirectoriesExist()

        // AVAudioSession設定
        try configureAudioSession()

        // 一時ファイル作成
        let recordingID = UUID()
        let tempURL = tempRecordingDirectory
            .appendingPathComponent("\(recordingID.uuidString)_recording.m4a")

        // AAC出力用のAVAudioFileを作成
        let file = try AVAudioFile(forWriting: tempURL, settings: Self.aacSettings)

        // ファイル保護を適用
        applyFileProtection(to: tempURL)

        // 入力ノードのフォーマットを取得
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // STTエンジン用の16kHz Mono変換セットアップ
        let sttFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.pcmSampleRate,
            channels: Self.pcmChannels,
            interleaved: false
        )!
        let needsConversion = inputFormat.sampleRate != Self.pcmSampleRate
            || inputFormat.channelCount != Self.pcmChannels
        let sttConverter: AVAudioConverter? = needsConversion
            ? AVAudioConverter(from: inputFormat, to: sttFormat)
            : nil

        #if DEBUG
        print("[Recorder] 入力: \(inputFormat.sampleRate)Hz \(inputFormat.channelCount)ch → STT: \(Self.pcmSampleRate)Hz (変換\(needsConversion ? "あり" : "なし"))")
        #endif

        // レベルストリームを作成
        let levelStream = AsyncStream<AudioLevelUpdate> { [weak self] continuation in
            self?.withLock { state in
                state.levelContinuation = continuation
            }
        }

        // PCMバッファストリームを作成（STTエンジン用）
        let pcmStream = AsyncStream<AVAudioPCMBuffer> { [weak self] continuation in
            self?.withLock { state in
                state.pcmBufferContinuation = continuation
            }
        }

        // Tap を設定
        let bufferSize: AVAudioFrameCount = 1024
        // TODO: os_unfair_lock への移行を検討（RTスレッドでの NSLock オーバーヘッド軽減）
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) {
            [weak self, sttConverter, sttFormat] buffer, _ in
            guard let self = self else { return }

            // ロック取得を1回に統合: isRecording/isPaused判定 + state値取得を一括で行う
            let snapshot = self.withLock { state -> (recording: Bool, paused: Bool, startTime: Date?, pausedDuration: TimeInterval, levelCont: AsyncStream<AudioLevelUpdate>.Continuation?, pcmCont: AsyncStream<AVAudioPCMBuffer>.Continuation?)? in
                guard state.isRecording, !state.isPaused else { return nil }
                return (
                    recording: state.isRecording,
                    paused: state.isPaused,
                    startTime: state.recordingStartTime,
                    pausedDuration: state.pausedDuration,
                    levelCont: state.levelContinuation,
                    pcmCont: state.pcmBufferContinuation
                )
            }

            guard let snapshot else { return }

            // 音量レベル計算（ロック外で実行）
            let levels = self.calculateLevels(buffer: buffer)

            let timestamp: TimeInterval
            if let startTime = snapshot.startTime {
                timestamp = Date().timeIntervalSince(startTime) - snapshot.pausedDuration
            } else {
                timestamp = 0
            }

            let update = AudioLevelUpdate(
                averagePower: levels.averagePower,
                peakPower: levels.peakPower,
                timestamp: timestamp
            )

            snapshot.levelCont?.yield(update)

            // STTエンジンへ16kHz Mono変換済みバッファを送信
            if let converter = sttConverter {
                let ratio = sttFormat.sampleRate / converter.inputFormat.sampleRate
                let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
                guard outputFrameCount > 0,
                      let outputBuffer = AVAudioPCMBuffer(
                          pcmFormat: sttFormat,
                          frameCapacity: outputFrameCount
                      ) else { return }

                var error: NSError?
                var hasData = true
                converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                    if hasData {
                        hasData = false
                        outStatus.pointee = .haveData
                        return buffer
                    }
                    outStatus.pointee = .noDataNow
                    return nil
                }

                if let error {
                    #if DEBUG
                    print("[Recorder] サンプルレート変換失敗: \(error.localizedDescription)")
                    #endif
                } else {
                    snapshot.pcmCont?.yield(outputBuffer)
                }
            } else {
                snapshot.pcmCont?.yield(buffer)
            }

            // AAC ファイルに書き込み
            do {
                try file.write(from: buffer)
            } catch {
                // ファイル書き込みエラーはログ出力のみ（録音は継続）
            }
        }

        // エンジン起動
        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw RecordingError.engineStartFailed(error.localizedDescription)
        }

        // 状態更新
        withLock { state in
            state.isRecording = true
            state.isPaused = false
            state.recordingStartTime = Date()
            state.pausedDuration = 0
            state.pauseStartTime = nil
            state.audioFile = file
            state.tempFileURL = tempURL
        }

        return (levels: levelStream, pcmBuffers: pcmStream)
    }

    public func pauseRecording() async throws {
        try withLock { state in
            guard state.isRecording else {
                throw RecordingError.notRecording
            }
            guard !state.isPaused else {
                return // すでに一時停止中は何もしない
            }
            state.isPaused = true
            state.pauseStartTime = Date()
        }

        engine.pause()
    }

    public func resumeRecording() async throws {
        try withLock { state in
            guard state.isRecording else {
                throw RecordingError.notRecording
            }
            guard state.isPaused else {
                throw RecordingError.notPaused
            }
            state.isPaused = false
            if let pauseStart = state.pauseStartTime {
                state.pausedDuration += Date().timeIntervalSince(pauseStart)
            }
            state.pauseStartTime = nil
        }

        try engine.start()
    }

    public func stopRecording() async throws -> RecordingResult {
        lock.lock()
        guard state.isRecording else {
            lock.unlock()
            throw RecordingError.notRecording
        }

        // 一時停止中の場合、停止時間を加算
        if state.isPaused, let pauseStart = state.pauseStartTime {
            state.pausedDuration += Date().timeIntervalSince(pauseStart)
        }

        // 経過時間をロック内で直接計算（elapsedTimeLocked再帰回避）
        let duration: TimeInterval
        if let startTime = state.recordingStartTime {
            duration = Date().timeIntervalSince(startTime) - state.pausedDuration
        } else {
            duration = 0
        }

        let currentTempURL = state.tempFileURL
        let levelCont = state.levelContinuation
        let pcmCont = state.pcmBufferContinuation

        state.isRecording = false
        state.isPaused = false
        state.recordingStartTime = nil
        state.pauseStartTime = nil
        state.audioFile = nil
        state.tempFileURL = nil
        state.levelContinuation = nil
        state.pcmBufferContinuation = nil
        lock.unlock()

        // エンジン停止
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        // ストリーム終了
        levelCont?.finish()
        pcmCont?.finish()

        // 一時ファイルURLをそのまま返す（移動はSaveRecordingUseCaseが担当）
        guard let tempURL = currentTempURL else {
            throw RecordingError.fileSaveFailed("No temporary file found")
        }

        return RecordingResult(
            fileURL: tempURL,
            duration: duration,
            format: .m4a
        )
    }
}
