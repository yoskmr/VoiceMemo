import AVFoundation
import Domain
import Foundation
import Speech

/// Apple SpeechAnalyzer (iOS 26+) を使用したSTTエンジン実装
/// 統合仕様書 INT-SPEC-001 セクション3.1 準拠
///
/// - 日本語(ja_JP)デフォルト対応、42ロケール対応
/// - 完全オンデバイス処理（マイク権限のみ、音声認識権限不要）
/// - AsyncStreamベース（STTEngineProtocol準拠）
/// - 1分制限なし（長時間録音対応）
@available(iOS 26.0, macOS 26.0, *)
public final class SpeechAnalyzerEngine: @unchecked Sendable {

    // MARK: - Properties

    public let engineType: STTEngineType = .speechAnalyzer

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var lastResult: TranscriptionResult?
    private var resultTask: Task<Void, Never>?
    private var feedTask: Task<Void, Never>?
    private var audioConverter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private let lock = NSLock()

    // MARK: - Init

    public init() {}

    // MARK: - Private Helpers

    @discardableResult
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        to targetFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format

        if inputFormat.sampleRate == targetFormat.sampleRate
            && inputFormat.channelCount == targetFormat.channelCount
            && inputFormat.commonFormat == targetFormat.commonFormat
        {
            return buffer
        }

        if audioConverter == nil || audioConverter?.outputFormat != targetFormat {
            guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                throw STTError.recognitionFailed("AVAudioConverter生成失敗")
            }
            converter.primeMethod = .none
            audioConverter = converter
        }

        guard let converter = audioConverter else {
            throw STTError.recognitionFailed("AVAudioConverter が nil")
        }

        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let frameCapacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))

        guard let conversionBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: frameCapacity
        ) else {
            throw STTError.recognitionFailed("変換バッファ生成失敗")
        }

        var nsError: NSError?
        var consumed = false
        let status = converter.convert(to: conversionBuffer, error: &nsError) { _, outStatus in
            defer { consumed = true }
            outStatus.pointee = consumed ? .noDataNow : .haveData
            return consumed ? nil : buffer
        }

        if status == .error {
            throw STTError.recognitionFailed(nsError?.localizedDescription ?? "変換エラー")
        }

        return conversionBuffer
    }

    private func cleanupRecognition() {
        resultTask?.cancel()
        resultTask = nil
        feedTask?.cancel()
        feedTask = nil
        inputBuilder?.finish()
        inputBuilder = nil
        analyzer = nil
        transcriber = nil
        audioConverter = nil
        analyzerFormat = nil
    }
}

// MARK: - STTEngineProtocol

@available(iOS 26.0, macOS 26.0, *)
extension SpeechAnalyzerEngine: STTEngineProtocol {

    public var supportedLanguages: [String] {
        ["ja-JP", "en-US", "en-GB", "zh-Hans", "zh-Hant", "ko-KR",
         "fr-FR", "de-DE", "es-ES", "it-IT", "pt-BR", "ru-RU"]
    }

    public func startTranscription(
        audioStream: AsyncStream<AVAudioPCMBuffer>,
        language: String
    ) -> AsyncStream<TranscriptionResult> {
        withLock {
            cleanupRecognition()
            lastResult = nil
        }

        return AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                do {
                    let locale = Locale(identifier: language)
                    let newTranscriber = SpeechTranscriber(
                        locale: locale,
                        transcriptionOptions: [],
                        reportingOptions: [.volatileResults],
                        attributeOptions: []
                    )
                    let newAnalyzer = SpeechAnalyzer(modules: [newTranscriber])
                    let format = await SpeechAnalyzer.bestAvailableAudioFormat(
                        compatibleWith: [newTranscriber]
                    )
                    let (inputSequence, builder) = AsyncStream<AnalyzerInput>.makeStream()

                    self.withLock {
                        self.transcriber = newTranscriber
                        self.analyzer = newAnalyzer
                        self.inputBuilder = builder
                        self.analyzerFormat = format
                    }

                    // 結果消費タスク
                    let consumeTask = Task { [weak self] in
                        guard let self else { return }
                        do {
                            for try await result in newTranscriber.results {
                                guard !Task.isCancelled else { break }
                                let text = String(result.text.characters)
                                guard !text.isEmpty else { continue }

                                let transcriptionResult = TranscriptionResult(
                                    text: text,
                                    confidence: result.isFinal ? 0.9 : 0.7,
                                    isFinal: result.isFinal,
                                    language: language,
                                    segments: []
                                )
                                self.withLock { self.lastResult = transcriptionResult }
                                continuation.yield(transcriptionResult)

                                #if DEBUG
                                let tag = result.isFinal ? "final" : "volatile"
                                print("[SpeechAnalyzer] \(tag): \(text.prefix(60))")
                                #endif
                            }
                        } catch {
                            #if DEBUG
                            print("[SpeechAnalyzer] 結果エラー: \(error.localizedDescription)")
                            #endif
                        }
                        continuation.finish()
                    }
                    self.withLock { self.resultTask = consumeTask }

                    try await newAnalyzer.start(inputSequence: inputSequence)

                    // 音声バッファフィードループ
                    for await buffer in audioStream {
                        guard !Task.isCancelled else { break }
                        let currentBuilder = self.withLock { self.inputBuilder }
                        let currentFormat = self.withLock { self.analyzerFormat }
                        guard let currentBuilder, let currentFormat else { break }

                        do {
                            let converted = try self.convertBuffer(buffer, to: currentFormat)
                            currentBuilder.yield(AnalyzerInput(buffer: converted))
                        } catch {
                            #if DEBUG
                            print("[SpeechAnalyzer] バッファ変換失敗（ドロップ）")
                            #endif
                            continue
                        }
                    }

                    self.withLock { self.inputBuilder?.finish() }
                    try? await newAnalyzer.finalizeAndFinishThroughEndOfInput()
                } catch {
                    #if DEBUG
                    print("[SpeechAnalyzer] セッション開始エラー: \(error.localizedDescription)")
                    #endif
                    continuation.finish()
                }
            }

            self.withLock { self.feedTask = task }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
                self.withLock {
                    self.resultTask?.cancel()
                    self.inputBuilder?.finish()
                }
                Task {
                    await self.withLock { self.analyzer }?.cancelAndFinishNow()
                    self.withLock { self.cleanupRecognition() }
                }
            }
        }
    }

    public func finishTranscription() async throws -> TranscriptionResult {
        let currentAnalyzer = withLock { self.analyzer }
        let hasTask = withLock { self.resultTask != nil }

        guard hasTask else {
            if let result = withLock({ self.lastResult }) { return result }
            throw STTError.engineNotInitialized
        }

        withLock {
            self.inputBuilder?.finish()
            self.inputBuilder = nil
        }
        try? await currentAnalyzer?.finalizeAndFinishThroughEndOfInput()

        // 結果が安定するまで待つ（最大10秒、1秒間変化なしで安定と判断）
        var lastText = ""
        var stableCount = 0
        for _ in 0..<20 {  // 最大10秒 (20 × 0.5秒)
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5秒
            let currentText = withLock { self.lastResult?.text ?? "" }
            if currentText == lastText && !currentText.isEmpty {
                stableCount += 1
                if stableCount >= 2 {  // 1秒間変化なし = 安定
                    break
                }
            } else {
                stableCount = 0
                lastText = currentText
            }
        }

        let result = withLock { self.lastResult }
        withLock { cleanupRecognition() }
        return result ?? .empty()
    }

    public func stopTranscription() async {
        let currentAnalyzer = withLock { self.analyzer }
        withLock {
            inputBuilder?.finish()
            cleanupRecognition()
            lastResult = nil
        }
        await currentAnalyzer?.cancelAndFinishNow()
    }

    public func isAvailable() async -> Bool {
        let locale = Locale(identifier: "ja-JP")
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }) else { return false }

        let installed = await SpeechTranscriber.installedLocales
        return installed.contains {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }
    }

    public func setCustomDictionary(_ dictionary: [String: String]) async {
        // SpeechAnalyzer はカスタム辞書非対応（no-op）
        // 固有名詞対応は LLM 後処理で補完する
    }
}

// MARK: - Language Pack Management

@available(iOS 26.0, macOS 26.0, *)
extension SpeechAnalyzerEngine {

    public func downloadLanguagePack(locale: Locale) async throws {
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }) else {
            throw STTError.languageNotSupported(locale.identifier)
        }

        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }) { return }

        let tempTranscriber = SpeechTranscriber(
            locale: locale, transcriptionOptions: [],
            reportingOptions: [], attributeOptions: []
        )
        if let downloader = try await AssetInventory.assetInstallationRequest(
            supporting: [tempTranscriber]
        ) {
            try await downloader.downloadAndInstall()
        }
    }
}
