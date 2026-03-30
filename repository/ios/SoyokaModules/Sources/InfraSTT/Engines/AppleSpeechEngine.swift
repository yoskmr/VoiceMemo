import AVFoundation
import Domain
import Foundation
import Speech

/// Apple Speech Framework を使用したSTTエンジン実装
/// 統合仕様書 INT-SPEC-001 セクション3.1 準拠
/// SFSpeechRecognizer + SFSpeechAudioBufferRecognitionRequest によるリアルタイムストリーミング認識
///
/// - 日本語(ja-JP)デフォルト対応
/// - オフライン認識モード(requiresOnDeviceRecognition = true)
/// - AsyncStreamベース（callbacks方式は使用しない）
///
/// 蓄積ロジックはRecordingFeature（TCA Reducer）側で管理する。
/// このエンジンは各認識セッションの生テキストをそのままyieldする。
public final class AppleSpeechEngine: @unchecked Sendable {

    // MARK: - Properties

    public let engineType: STTEngineType = .speechAnalyzer

    private let recognizer: SFSpeechRecognizer
    private let requiresOnDevice: Bool

    /// 認識リクエスト（認識中のみ非nil）
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    /// 認識タスク（認識中のみ非nil）
    private var recognitionTask: SFSpeechRecognitionTask?
    /// 最終確定結果を保持するためのプロパティ
    private var lastResult: TranscriptionResult?
    /// カスタム辞書のコンテキスト文字列
    private var contextualStrings: [String] = []
    /// スレッドセーフのためのロック
    private let lock = NSLock()

    // MARK: - Init

    /// Apple Speech エンジンを初期化する
    /// - Parameters:
    ///   - locale: 認識対象のロケール（デフォルト: ja-JP）
    ///   - requiresOnDeviceRecognition: オンデバイス認識を強制するか（デフォルト: true）
    public init(
        locale: Locale = Locale(identifier: "ja-JP"),
        requiresOnDeviceRecognition: Bool = true
    ) {
        self.recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()!
        self.requiresOnDevice = requiresOnDeviceRecognition
    }

    // MARK: - Private Helpers

    /// ロックを取得してクリティカルセクションを実行する
    @discardableResult
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    /// 認識リソースをクリーンアップする
    private func cleanupRecognition() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }
}

// MARK: - STTEngineProtocol

extension AppleSpeechEngine: STTEngineProtocol {

    public var supportedLanguages: [String] {
        SFSpeechRecognizer.supportedLocales().map { $0.identifier }
    }

    public func startTranscription(
        audioStream: AsyncStream<AVAudioPCMBuffer>,
        language: String
    ) -> AsyncStream<TranscriptionResult> {
        // 既存の認識がある場合はクリーンアップ
        withLock {
            cleanupRecognition()
        }

        return AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            // 音声バッファを保持し続けるため、共有バッファストリームを作成
            let bufferRelay = BufferRelay()

            // 音声バッファを中継するタスク
            let feedTask = Task { [weak self] in
                for await buffer in audioStream {
                    guard !Task.isCancelled else { break }
                    // 現在の認識リクエストにバッファを供給
                    self?.withLock {
                        self?.recognitionRequest?.append(buffer)
                    }
                    bufferRelay.latestBuffer = buffer
                }
                // 音声ストリームが終了したら endAudio
                self?.withLock {
                    self?.recognitionRequest?.endAudio()
                }
            }

            // 認識セッションを開始（再帰的に再起動可能）
            self.startRecognitionSession(
                language: language,
                continuation: continuation,
                feedTask: feedTask
            )

            // AsyncStream 終了時のクリーンアップ
            continuation.onTermination = { @Sendable _ in
                feedTask.cancel()
                self.withLock {
                    self.cleanupRecognition()
                }
            }
        }
    }

    /// 認識セッションを開始する。isFinalまたはエラー時に自動再起動する。
    /// 蓄積は行わず、各セッションの生テキストをそのままyieldする。
    private func startRecognitionSession(
        language: String,
        continuation: AsyncStream<TranscriptionResult>.Continuation,
        feedTask: Task<Void, Never>
    ) {
        // 古いセッションをキャンセル
        withLock {
            self.recognitionTask?.cancel()
            self.recognitionRequest?.endAudio()
            self.recognitionRequest = nil
            self.recognitionTask = nil
        }

        print("[STT] セッション開始")

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation           // 音声メモに最適な認識モード
        request.addsPunctuation = true          // 句読点自動挿入（iOS 16+）

        if requiresOnDevice {
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        }

        let strings = withLock { contextualStrings }
        if !strings.isEmpty {
            request.contextualStrings = strings
        }

        withLock {
            self.recognitionRequest = request
        }

        let task = recognizer.recognitionTask(with: request) {
            [weak self] result, error in
            guard let self else { return }

            if let result {
                let currentText = result.bestTranscription.formattedString
                let currentSegments = result.bestTranscription.segments.map { segment in
                    TranscriptionSegment(
                        text: segment.substring,
                        startTime: segment.timestamp,
                        endTime: segment.timestamp + segment.duration,
                        confidence: Double(segment.confidence)
                    )
                }

                // 生テキストをそのままyield（蓄積はReducer側で行う）
                let transcriptionResult = TranscriptionResult(
                    text: currentText,
                    confidence: Double(result.bestTranscription.segments.last?.confidence ?? 0),
                    isFinal: result.isFinal,
                    language: language,
                    segments: currentSegments
                )

                self.withLock { self.lastResult = transcriptionResult }
                continuation.yield(transcriptionResult)

                if result.isFinal {
                    print("[STT] isFinal: \(currentText.prefix(30))... → 再開")
                    // isFinal後、feedTaskがまだ動いていれば新しいセッションを開始
                    if !feedTask.isCancelled {
                        self.startRecognitionSession(
                            language: language,
                            continuation: continuation,
                            feedTask: feedTask
                        )
                    }
                    return
                } else {
                    print("[STT] partial: \(currentText.prefix(30))...")
                }
            }

            if let error, result == nil || result?.isFinal == false {
                // エラー時（無音タイムアウト等）も再開
                print("[STT] エラー: \(error.localizedDescription) → 再開")
                guard !feedTask.isCancelled else { return }

                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !feedTask.isCancelled else { return }
                    print("[STT] セッション再開")
                    self?.startRecognitionSession(
                        language: language,
                        continuation: continuation,
                        feedTask: feedTask
                    )
                }
            }
        }

        withLock {
            self.recognitionTask = task
        }
    }

    public func finishTranscription() async throws -> TranscriptionResult {
        let (request, hasTask) = withLock {
            (self.recognitionRequest, self.recognitionTask != nil)
        }

        guard hasTask else {
            // タスクが終了していても蓄積テキストがあれば返す
            let result = withLock { self.lastResult }
            if let result { return result }
            throw STTError.engineNotInitialized
        }

        // endAudio を呼んで認識を確定させる
        request?.endAudio()

        // 最終結果が確定するまで少し待つ
        try await Task.sleep(nanoseconds: 800_000_000) // 0.8秒

        let result = withLock { self.lastResult }

        // リソースクリーンアップ
        withLock { cleanupRecognition() }

        return result ?? .empty()
    }

    public func stopTranscription() async {
        withLock {
            cleanupRecognition()
            lastResult = nil
        }
    }

    public func isAvailable() async -> Bool {
        guard recognizer.isAvailable else { return false }
        let status = SFSpeechRecognizer.authorizationStatus()
        return status == .authorized
    }

    public func setCustomDictionary(_ dictionary: [String: String]) async {
        withLock {
            self.contextualStrings = Array(dictionary.values)
        }
        // 認識中の場合は現在のリクエストにも反映
        withLock {
            if let request = self.recognitionRequest {
                request.contextualStrings = self.contextualStrings
            }
        }
    }
}

// MARK: - BufferRelay

/// PCMバッファの最新値を保持するヘルパー（認識再開時の参照用）
private final class BufferRelay: @unchecked Sendable {
    var latestBuffer: AVAudioPCMBuffer?
}

// MARK: - Authorization Helper

extension AppleSpeechEngine {
    /// 音声認識権限をリクエストする
    /// - Returns: 権限が許可されたかどうか
    public static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
