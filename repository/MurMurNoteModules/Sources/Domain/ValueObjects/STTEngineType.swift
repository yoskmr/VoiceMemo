import Foundation

/// STTエンジンの識別子（統一enum）
/// 統合仕様書 v1.0 準拠（セクション3.1）
/// - `.speechAnalyzer`: iOS 26+ Apple SpeechAnalyzer
/// - `.whisperKit`: iOS 17+ WhisperKit (whisper.cpp Swift wrapper)
/// - `.cloudSTT`: Pro限定クラウドSTT
public enum STTEngineType: String, Codable, Sendable, Equatable {
    case speechAnalyzer = "speech_analyzer"
    case whisperKit     = "whisper_kit"
    case cloudSTT       = "cloud_stt"
}
