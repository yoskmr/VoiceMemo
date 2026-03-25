import Foundation

/// STT認識結果（統一型）
/// 統合仕様書 INT-SPEC-001 セクション3.1 準拠
public struct TranscriptionResult: Sendable, Equatable {
    /// 認識されたテキスト全文
    public let text: String
    /// 認識の信頼度 (0.0 - 1.0)
    public let confidence: Double
    /// 最終結果かどうか（false = 部分結果）
    public let isFinal: Bool
    /// 認識言語
    public let language: String
    /// 認識セグメント（タイムスタンプ付き）
    public let segments: [TranscriptionSegment]

    public init(
        text: String,
        confidence: Double,
        isFinal: Bool,
        language: String,
        segments: [TranscriptionSegment] = []
    ) {
        self.text = text
        self.confidence = confidence
        self.isFinal = isFinal
        self.language = language
        self.segments = segments
    }

    /// 空の結果を生成するファクトリメソッド
    public static func empty(language: String = "ja-JP") -> TranscriptionResult {
        TranscriptionResult(
            text: "",
            confidence: 0.0,
            isFinal: true,
            language: language,
            segments: []
        )
    }
}
