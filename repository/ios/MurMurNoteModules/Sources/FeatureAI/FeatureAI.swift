/// FeatureAI - AI要約・タグ付け・感情分析
/// Domain, SharedUI に依存。Infra直接依存禁止（Domain層プロトコル経由でアクセス）
///
/// Phase 3a Wave 3: AIProcessingReducer を追加
/// - AI処理の開始・ステータス監視・リトライ・キャンセルを管理
/// - AIProcessingQueueClient、AIQuotaClient を Dependency として利用
public enum FeatureAIModule {
    public static let version = "0.2.0"
}
