import AVFoundation
import Domain
import Foundation
@preconcurrency import WhisperKit

/// WhisperKit を使用したオンデバイスSTTエンジン実装
/// 統合仕様書 INT-SPEC-001 セクション3.1 準拠
/// WhisperKit (whisper.cpp Swift wrapper) によるリアルタイムストリーミング認識
///
/// - Whisper Small モデル（約600MB）のダウンロード/ロード管理
/// - モデル保存先: Library/Caches/Models/whisperkit/
/// - AsyncStreamベースのリアルタイム認識（STTEngineProtocol準拠）
/// - 日本語(ja)デフォルト対応
/// - メモリ管理: モデルのロード/アンロード
public final class WhisperKitEngine: @unchecked Sendable {

    // MARK: - Properties

    public let engineType: STTEngineType = .whisperKit

    /// WhisperKit インスタンス（モデルロード後に非nil）
    private var whisperKit: WhisperKit?
    /// モデル保存先ディレクトリ
    public let modelDirectoryURL: URL
    /// 使用するモデル名
    private let modelName: String
    /// カスタム辞書の初期プロンプト
    private var initialPrompt: String = ""
    /// 最終確定結果を保持
    private var lastResult: Domain.TranscriptionResult?
    /// 現在のトランスクリプションタスク
    private var transcriptionTask: Task<Void, Never>?
    /// 現在認識中の言語
    private var currentLanguage: String = "ja"
    /// スレッドセーフのためのロック
    private let lock = NSLock()

    // MARK: - Constants

    /// チャンク処理の秒数
    private static let chunkDurationSeconds: Double = 3.0
    /// サンプルレート（WhisperKit標準: 16kHz）
    private static let sampleRate: Int = 16000

    // MARK: - Init

    /// WhisperKit エンジンを初期化する
    /// - Parameters:
    ///   - modelDirectory: モデル保存先ディレクトリ（デフォルト: Library/Caches/Models/whisperkit/）
    ///   - modelName: 使用するモデル名（デフォルト: "openai_whisper-small"）
    public init(
        modelDirectory: URL? = nil,
        modelName: String = "openai_whisper-small"
    ) {
        self.modelDirectoryURL = modelDirectory ?? Self.defaultModelDirectory()
        self.modelName = modelName
    }

    // MARK: - Private Helpers

    /// デフォルトのモデル保存先ディレクトリを取得する
    private static func defaultModelDirectory() -> URL {
        let cachesDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!
        return cachesDirectory
            .appendingPathComponent("Models")
            .appendingPathComponent("whisperkit")
    }

    /// ロックを取得してクリティカルセクションを実行する
    @discardableResult
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    /// AVAudioPCMBuffer から Float 配列を抽出する
    private func extractFloatData(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frameLength = Int(buffer.frameLength)
        let data = Array(UnsafeBufferPointer(
            start: channelData[0],
            count: frameLength
        ))
        return data
    }

    /// avgLogprob を 0.0-1.0 の信頼度に正規化する
    /// WhisperKit の avgLogprob は通常 -inf ~ 0 の範囲
    private func normalizeConfidence(_ avgLogprob: Float) -> Double {
        let clamped = max(min(Double(avgLogprob), 0.0), -10.0)
        return 1.0 / (1.0 + exp(-clamped - 1.0))
    }

    /// WhisperKit の認識結果を Domain.TranscriptionResult に変換する
    /// WhisperKit.TranscriptionResult の text / segments プロパティから
    /// Domain 層の型へマッピングする。
    private func toDomainResult(
        text: String,
        segmentTexts: [String],
        segmentStarts: [Float],
        segmentEnds: [Float],
        segmentAvgLogprobs: [Float],
        language: String,
        isFinal: Bool
    ) -> Domain.TranscriptionResult {
        let confidence = segmentAvgLogprobs.first.map { normalizeConfidence($0) } ?? 0.0

        var domainSegments: [Domain.TranscriptionSegment] = []
        for i in 0..<segmentTexts.count {
            domainSegments.append(
                Domain.TranscriptionSegment(
                    text: segmentTexts[i],
                    startTime: TimeInterval(segmentStarts[i]),
                    endTime: TimeInterval(segmentEnds[i]),
                    confidence: normalizeConfidence(segmentAvgLogprobs[i])
                )
            )
        }

        return Domain.TranscriptionResult(
            text: text,
            confidence: confidence,
            isFinal: isFinal,
            language: language,
            segments: domainSegments
        )
    }

    /// 認識リソースをクリーンアップする
    private func cleanupTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
    }
}

// MARK: - STTEngineProtocol

extension WhisperKitEngine: STTEngineProtocol {

    public var supportedLanguages: [String] {
        [
            "ja", "en", "zh", "ko", "fr", "de", "es", "it", "pt", "ru",
            "ar", "hi", "nl", "pl", "sv", "tr", "uk", "vi", "th", "id",
        ]
    }

    public func startTranscription(
        audioStream: AsyncStream<AVAudioPCMBuffer>,
        language: String
    ) -> AsyncStream<Domain.TranscriptionResult> {
        // 既存の認識があればクリーンアップ
        withLock {
            cleanupTranscription()
            lastResult = nil
            currentLanguage = language
        }

        return AsyncStream<Domain.TranscriptionResult> { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                // モデルがロードされていなければロードを試みる
                if !self.isModelLoaded {
                    do {
                        try await self.loadModel()
                    } catch {
                        continuation.finish()
                        return
                    }
                }

                guard let whisperKit = self.withLock({ self.whisperKit }) else {
                    continuation.finish()
                    return
                }

                // 音声バッファを蓄積して3秒間隔でチャンク認識
                var audioBuffer: [Float] = []
                let chunkSize = Int(Self.chunkDurationSeconds) * Self.sampleRate

                for await pcmBuffer in audioStream {
                    guard !Task.isCancelled else { break }

                    let floatData = self.extractFloatData(from: pcmBuffer)
                    audioBuffer.append(contentsOf: floatData)

                    // チャンクサイズ分溜まったら認識実行
                    if audioBuffer.count >= chunkSize {
                        if let domainResult = await self.processChunk(
                            audioBuffer,
                            language: language,
                            isFinal: false,
                            whisperKit: whisperKit
                        ) {
                            self.withLock { self.lastResult = domainResult }
                            continuation.yield(domainResult)
                        }
                        audioBuffer.removeAll()
                    }
                }

                // 残りのバッファを処理して最終結果を生成
                if !audioBuffer.isEmpty, !Task.isCancelled {
                    if let domainResult = await self.processChunk(
                        audioBuffer,
                        language: language,
                        isFinal: true,
                        whisperKit: whisperKit
                    ) {
                        self.withLock { self.lastResult = domainResult }
                        continuation.yield(domainResult)
                    }
                }

                continuation.finish()
            }

            self.withLock {
                self.transcriptionTask = task
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public func finishTranscription() async throws -> Domain.TranscriptionResult {
        let hasTask = withLock { self.transcriptionTask != nil }

        guard hasTask else {
            throw STTError.engineNotInitialized
        }

        // 現在のタスクの完了を少し待つ
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3秒

        let result = withLock { self.lastResult }

        // リソースクリーンアップ
        withLock {
            cleanupTranscription()
        }

        return result ?? .empty(language: currentLanguage)
    }

    public func stopTranscription() async {
        withLock {
            cleanupTranscription()
            lastResult = nil
        }
    }

    public func isAvailable() async -> Bool {
        let modelPath = modelDirectoryURL.appendingPathComponent(modelName)
        return FileManager.default.fileExists(atPath: modelPath.path)
    }

    public func setCustomDictionary(_ dictionary: [String: String]) async {
        withLock {
            if dictionary.isEmpty {
                self.initialPrompt = ""
            } else {
                let customTerms = dictionary.values.joined(separator: "、")
                self.initialPrompt = "以下の用語を含む可能性があります: \(customTerms)"
            }
        }
    }
}

// MARK: - Chunk Processing

extension WhisperKitEngine {

    /// 音声チャンクを WhisperKit で認識し Domain.TranscriptionResult に変換する
    private func processChunk(
        _ audioBuffer: [Float],
        language: String,
        isFinal: Bool,
        whisperKit: WhisperKit
    ) async -> Domain.TranscriptionResult? {
        do {
            let options = DecodingOptions(
                language: language,
                wordTimestamps: true
            )

            // whisperKit.transcribe の戻り値型は WhisperKit モジュールの [TranscriptionResult]
            // 型注釈なしで推論させて名前衝突を回避する
            let results = try await whisperKit.transcribe(
                audioArray: audioBuffer,
                decodeOptions: options
            )

            guard let first = results.first else { return nil }

            // WhisperKit の TranscriptionResult から必要なプロパティを抽出
            let text: String = first.text
            let segments = first.segments
            let segTexts = segments.map(\.text)
            let segStarts = segments.map(\.start)
            let segEnds = segments.map(\.end)
            let segLogprobs = segments.map(\.avgLogprob)

            return toDomainResult(
                text: text,
                segmentTexts: segTexts,
                segmentStarts: segStarts,
                segmentEnds: segEnds,
                segmentAvgLogprobs: segLogprobs,
                language: language,
                isFinal: isFinal
            )
        } catch {
            return nil
        }
    }
}

// MARK: - Model Management

extension WhisperKitEngine {

    /// モデルがロード済みかどうか
    public var isModelLoaded: Bool {
        withLock { whisperKit != nil }
    }

    /// モデルのロード
    /// - Throws: モデルのロードに失敗した場合
    public func loadModel() async throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: modelDirectoryURL.path) {
            try fileManager.createDirectory(
                at: modelDirectoryURL,
                withIntermediateDirectories: true
            )
        }

        let config = WhisperKitConfig(
            model: modelName,
            modelFolder: modelDirectoryURL.path,
            verbose: false,
            logLevel: .none,
            download: true
        )

        do {
            let kit = try await WhisperKit(config)
            withLock {
                self.whisperKit = kit
            }
        } catch {
            throw STTError.recognitionFailed(
                "WhisperKit model load failed: \(error.localizedDescription)"
            )
        }
    }

    /// モデルのアンロード（メモリ解放）
    public func unloadModel() {
        withLock {
            whisperKit = nil
        }
    }

    /// モデルがダウンロード済みか確認
    public func isModelDownloaded() -> Bool {
        let modelPath = modelDirectoryURL.appendingPathComponent(modelName)
        return FileManager.default.fileExists(atPath: modelPath.path)
    }

    /// モデルファイルの削除
    /// - Throws: ファイル削除に失敗した場合
    public func deleteModel() throws {
        let modelPath = modelDirectoryURL.appendingPathComponent(modelName)
        if FileManager.default.fileExists(atPath: modelPath.path) {
            try FileManager.default.removeItem(at: modelPath)
        }
    }

    /// メモリ使用量の確認
    public func currentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size
        ) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}
