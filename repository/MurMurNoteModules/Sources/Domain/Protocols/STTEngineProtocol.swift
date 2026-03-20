import AVFoundation

/// STTエンジンの抽象化プロトコル（統一版）
/// 統合仕様書 INT-SPEC-001 セクション3.1 準拠
/// 【正】AsyncStream ベース。callbacks 方式（onPartialResult / onFinalResult）は使用しない。
public protocol STTEngineProtocol: Sendable {
    /// エンジンの識別子
    var engineType: STTEngineType { get }

    /// リアルタイム文字起こしのストリーミング開始
    /// - Parameters:
    ///   - audioStream: PCM 16kHz Mono の音声バッファストリーム
    ///   - language: 認識言語（例: "ja-JP"）
    /// - Returns: 認識結果のAsyncStream（部分結果 + 最終結果）
    func startTranscription(
        audioStream: AsyncStream<AVAudioPCMBuffer>,
        language: String
    ) -> AsyncStream<TranscriptionResult>

    /// 文字起こしの停止・確定
    /// - Returns: 最終確定結果
    /// - Throws: `STTError.engineNotInitialized` 等
    func finishTranscription() async throws -> TranscriptionResult

    /// 文字起こしを即座に停止する（結果は破棄）
    func stopTranscription() async

    /// エンジンの利用可否チェック（デバイス性能・権限・言語パック）
    func isAvailable() async -> Bool

    /// 対応言語一覧
    var supportedLanguages: [String] { get }

    /// カスタム辞書の設定（REQ-025）
    func setCustomDictionary(_ dictionary: [String: String]) async
}
