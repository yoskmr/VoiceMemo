import Foundation

/// LLMプロバイダの識別子（統一enum）
/// 統合仕様書 v1.0 準拠（セクション3.2）
public enum LLMProviderType: String, Codable, Sendable, Equatable {
    case onDeviceAppleIntelligence = "on_device_apple_intelligence"
    case onDeviceLlamaCpp          = "on_device_llama_cpp"
    case cloudGPT4oMini            = "cloud_gpt4o_mini"
    case cloudClaude               = "cloud_claude"
}
