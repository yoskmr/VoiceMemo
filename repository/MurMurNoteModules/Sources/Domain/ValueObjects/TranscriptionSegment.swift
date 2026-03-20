import Foundation

/// STT認識セグメント（タイムスタンプ付き部分結果）
/// 統合仕様書 INT-SPEC-001 セクション3.1 準拠
public struct TranscriptionSegment: Sendable, Equatable {
    /// セグメントのテキスト
    public let text: String
    /// セグメント開始時刻（秒）
    public let startTime: TimeInterval
    /// セグメント終了時刻（秒）
    public let endTime: TimeInterval
    /// セグメントの認識信頼度 (0.0 - 1.0)
    public let confidence: Double

    public init(
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Double
    ) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
}
