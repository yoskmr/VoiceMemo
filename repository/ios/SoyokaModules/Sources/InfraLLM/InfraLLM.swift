/// InfraLLM - LLMプロバイダ具象実装（Apple Intelligence, llama.cpp, Cloud）
/// Domain に依存。LLMProviderClient を実装する
///
/// 構成:
/// - OnDeviceLLMProvider: メインプロバイダ（Apple Intelligence → Mock フォールバック）
/// - DeviceCapabilityChecker: デバイス能力判定（SoC世代・メモリ容量・Apple Intelligence 対応）
/// - LLMModelManager: モデルダウンロード・キャッシュ管理（llama.cpp 用、スタブ）
/// - LLMResponseParser: LLM出力のJSONパース
/// - MockLLMProvider: テスト・フォールバック用モック実装
///
/// T17: Apple Intelligence Foundation Models API 統合
/// - iOS 26+ / A17 Pro 以降で FoundationModels.LanguageModelSession を使用
/// - `#if canImport(FoundationModels)` で非対応環境との共存を実現
public enum InfraLLMModule {
    public static let version = "0.3.0"
}
