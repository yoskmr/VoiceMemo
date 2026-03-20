/// InfraLLM - LLMプロバイダ具象実装（Apple Intelligence, llama.cpp, Cloud）
/// Domain に依存。LLMProviderClient を実装する
///
/// Phase 3a 構成:
/// - DeviceCapabilityChecker: デバイス能力判定（SoC世代・メモリ容量）
/// - LLMModelManager: モデルダウンロード・キャッシュ管理（スタブ）
/// - LLMResponseParser: LLM出力のJSONパース
/// - MockLLMProvider: テスト用モック実装
public enum InfraLLMModule {
    public static let version = "0.2.0"
}
