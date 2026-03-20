import AVFoundation
import Domain
import Foundation

/// WhisperKitEngine のモック実装（テスト用）
/// 実デバイスでないとモデルロードが動作しないため、テストではこのモックを使用する。
/// STTEngineProtocol に準拠し、固定の結果を返す。
public final class MockWhisperKitEngine: @unchecked Sendable {

    // MARK: - Properties

    public let engineType: STTEngineType = .whisperKit

    /// カスタム辞書の用語（テスト検証用に公開）
    public private(set) var customDictionaryTerms: [String: String] = [:]
    /// 認識中かどうか（テスト検証用に公開）
    public private(set) var isTranscribing: Bool = false
    /// 最終確定結果
    private var lastResult: Domain.TranscriptionResult?
    /// 現在の認識言語
    private var currentLanguage: String = "ja"
    /// スレッドセーフのためのロック
    private let lock = NSLock()

    // MARK: - Mock Configuration

    /// Mock が返す部分結果テキスト
    public var mockPartialText: String = "テスト音声認識中..."
    /// Mock が返す最終結果テキスト
    public var mockFinalText: String = "テスト音声認識が完了しました。"
    /// Mock が返す信頼度
    public var mockConfidence: Double = 0.95

    // MARK: - Init

    public init() {}

    // MARK: - Private Helpers

    @discardableResult
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

// MARK: - STTEngineProtocol

extension MockWhisperKitEngine: STTEngineProtocol {

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
        withLock {
            isTranscribing = true
            currentLanguage = language
            lastResult = nil
        }

        return AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                // 音声ストリームを消費（実際の認識は行わない）
                for await _ in audioStream {
                    guard !Task.isCancelled else { break }
                }

                // 部分結果を yield
                let partialResult = Domain.TranscriptionResult(
                    text: self.mockPartialText,
                    confidence: self.mockConfidence * 0.8,
                    isFinal: false,
                    language: language
                )
                self.withLock {
                    self.lastResult = partialResult
                }
                continuation.yield(partialResult)

                // 最終結果を yield
                let finalResult = Domain.TranscriptionResult(
                    text: self.mockFinalText,
                    confidence: self.mockConfidence,
                    isFinal: true,
                    language: language
                )
                self.withLock {
                    self.lastResult = finalResult
                }
                continuation.yield(finalResult)

                continuation.finish()

                self.withLock {
                    self.isTranscribing = false
                }
            }
        }
    }

    public func finishTranscription() async throws -> Domain.TranscriptionResult {
        let result = withLock { self.lastResult }
        let language = withLock { self.currentLanguage }

        withLock {
            isTranscribing = false
        }

        if let result {
            return result
        }

        // 認識を開始していた場合は最終結果を返す
        return Domain.TranscriptionResult(
            text: mockFinalText,
            confidence: mockConfidence,
            isFinal: true,
            language: language
        )
    }

    public func stopTranscription() async {
        withLock {
            isTranscribing = false
            lastResult = nil
        }
    }

    public func isAvailable() async -> Bool {
        true
    }

    public func setCustomDictionary(_ dictionary: [String: String]) async {
        withLock {
            self.customDictionaryTerms = dictionary
        }
    }
}
