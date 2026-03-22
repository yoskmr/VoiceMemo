import AVFoundation
import Domain
import Foundation
@preconcurrency import WhisperKit

/// WhisperKit を使用したオンデバイスSTTエンジン実装
/// 統合仕様書 INT-SPEC-001 セクション3.1 準拠
/// WhisperKit (whisper.cpp Swift wrapper) によるリアルタイムストリーミング認識
///
/// - Whisper Base モデル（約140MB）のダウンロード/ロード管理
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

    /// 認識を実行するストライド（この間隔で認識が走る）
    private static let strideDurationSeconds: Double = 3.0
    /// 認識ウィンドウの最大長（Whisper推奨30秒）
    private static let windowMaxDurationSeconds: Double = 30.0
    /// サンプルレート（WhisperKit標準: 16kHz）
    private static let sampleRate: Int = 16000

    /// Whisperモデルの既知hallucination パターン（日本語）
    // WORKAROUND: [WhisperKit/Whisper-base] hallucinationフィルタリング
    private static let hallucinationPatterns: Set<String> = [
        "(笑)", "(音楽)", "(拍手)", "(歌)",
        "[音楽]", "[笑]", "[拍手]",
        "ご視聴ありがとうございました",
        "チャンネル登録", "高評価",
    ]

    /// 信頼度閾値（avgLogprobがこの値未満のセグメントは除外）
    // WORKAROUND: [WhisperKit/Whisper-base] 低確信度セグメント除外
    private static let confidenceThreshold: Float = -1.0

    // MARK: - Init

    /// WhisperKit エンジンを初期化する
    /// - Parameters:
    ///   - modelDirectory: モデル保存先ディレクトリ（デフォルト: Library/Caches/Models/whisperkit/）
    ///   - modelName: 使用するモデル名（デフォルト: "openai_whisper-base"）
    public init(
        modelDirectory: URL? = nil,
        modelName: String = "openai_whisper-base"
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
        // WhisperKitはISO 639-1（"ja"）を要求。"ja-JP"等のロケール形式を変換
        let whisperLanguage = String(language.prefix(2))

        // 既存の認識があればクリーンアップ
        withLock {
            cleanupTranscription()
            lastResult = nil
            currentLanguage = whisperLanguage
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

                // 音声バッファを蓄積してストライド間隔でスライディングウィンドウ認識
                var audioBuffer: [Float] = []
                var pendingSamples = 0
                let strideSize = Int(Self.strideDurationSeconds) * Self.sampleRate
                let windowMaxSize = Int(Self.windowMaxDurationSeconds) * Self.sampleRate

                for await pcmBuffer in audioStream {
                    guard !Task.isCancelled else { break }

                    let floatData = self.extractFloatData(from: pcmBuffer)
                    audioBuffer.append(contentsOf: floatData)
                    pendingSamples += floatData.count

                    // ストライド分の新データが溜まったら認識実行（ウィンドウ全体を渡す）
                    if pendingSamples >= strideSize {
                        pendingSamples = 0
                        if let domainResult = await self.processChunk(
                            audioBuffer,
                            language: whisperLanguage,
                            isFinal: false,
                            whisperKit: whisperKit
                        ) {
                            self.withLock { self.lastResult = domainResult }
                            continuation.yield(domainResult)
                        }

                        // ウィンドウがmaxを超えたら先頭を削除してスライド
                        if audioBuffer.count > windowMaxSize {
                            audioBuffer.removeFirst(audioBuffer.count - windowMaxSize)
                        }
                    }
                }

                // 残りのバッファを処理して最終結果を生成
                if !audioBuffer.isEmpty, !Task.isCancelled {
                    if let domainResult = await self.processChunk(
                        audioBuffer,
                        language: whisperLanguage,
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
            // NOTE: カスタム辞書のpromptTokens注入は whisper-base のコンテキスト上限
            // (224トークン) を圧迫するため無効化。whisper-large 以上で再有効化を検討
            let options = DecodingOptions(
                task: .transcribe,
                language: language,
                temperatureFallbackCount: 3,
                detectLanguage: false,
                wordTimestamps: true,
                suppressBlank: true
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

            // WORKAROUND: [WhisperKit/Whisper-base] hallucinationフィルタリング
            let filteredSegments = segments.filter { segment in
                guard segment.avgLogprob >= Self.confidenceThreshold else {
                    #if DEBUG
                    print("[WhisperKit] 低確信度除外: \"\(segment.text)\" (avgLogprob: \(segment.avgLogprob))")
                    #endif
                    return false
                }
                return true
            }

            let segTexts = filteredSegments.map(\.text)
            let segStarts = filteredSegments.map(\.start)
            let segEnds = filteredSegments.map(\.end)
            let segLogprobs = filteredSegments.map(\.avgLogprob)

            // hallucinationパターンをテキストから除去
            var filteredText = text
            for pattern in Self.hallucinationPatterns {
                filteredText = filteredText.replacingOccurrences(of: pattern, with: "")
            }
            filteredText = filteredText.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !filteredText.isEmpty else {
                #if DEBUG
                print("[WhisperKit] hallucination除去後テキスト空: 元=\"\(text)\"")
                #endif
                return nil
            }

            return toDomainResult(
                text: filteredText,
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

    /// モデルのダウンロード+ロード（ウェルカム画面から呼び出し用）
    /// WhisperKitConfig の download: true により自動ダウンロード → ロードが一括で行われる。
    /// 進捗取得はWhisperKit APIの制約上難しいため、完了時に1.0を通知する。
    /// - Parameter progress: ダウンロード進捗コールバック（0.0〜1.0）
    /// - Throws: モデルのダウンロード/ロードに失敗した場合
    public func downloadModel(progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0.0)
        try await loadModel()
        progress(1.0)
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

        #if DEBUG
        print("[WhisperKit] loadModel開始: model=\(modelName), modelDir=\(modelDirectoryURL.path)")
        #endif

        let config = WhisperKitConfig(
            model: modelName,
            verbose: true,
            logLevel: .debug,
            download: true
        )

        do {
            let kit = try await WhisperKit(config)
            withLock {
                self.whisperKit = kit
            }
            // ダウンロード成功フラグを永続化（別インスタンスからも参照可能に）
            UserDefaults.standard.set(true, forKey: "whisperkit_model_downloaded")
            #if DEBUG
            print("[WhisperKit] loadModel成功")
            #endif
        } catch {
            #if DEBUG
            print("[WhisperKit] loadModel失敗: \(error)")
            #endif
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
        // UserDefaultsフラグ（loadModel成功時に保存）
        if UserDefaults.standard.bool(forKey: "whisperkit_model_downloaded") {
            return true
        }
        // isModelLoaded でも判定（既にロード済みの場合）
        return isModelLoaded
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
