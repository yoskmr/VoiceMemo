import AVFoundation
import Foundation

/// 音声録音エンジンのプロトコル
/// Domain層で定義し、InfraSTT層（またはData層）で具象実装を提供する
/// 設計書01-system-architecture.md セクション4.1 準拠
public protocol AudioRecorderProtocol: Sendable {
    /// 録音を開始し、音量レベルストリームとPCMバッファストリーム（STT用）を返却する
    func startRecording() async throws -> (levels: AsyncStream<AudioLevelUpdate>, pcmBuffers: AsyncStream<AVAudioPCMBuffer>)

    /// 録音を一時停止する
    /// - Throws: `RecordingError.notRecording`
    func pauseRecording() async throws

    /// 一時停止中の録音を再開する
    /// - Throws: `RecordingError.notPaused`
    func resumeRecording() async throws

    /// 録音を停止し、録音結果を返却する
    /// - Returns: 録音結果（ファイルURL、録音時間、フォーマット）
    /// - Throws: `RecordingError.notRecording`, `RecordingError.fileSaveFailed`
    func stopRecording() async throws -> RecordingResult

    /// 録音中かどうか
    var isRecording: Bool { get }

    /// 一時停止中かどうか
    var isPaused: Bool { get }
}
