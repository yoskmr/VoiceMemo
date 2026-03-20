import Foundation

/// LLMプロンプトテンプレート
/// Phase 3a 詳細設計 DES-PHASE3A-001 セクション4 準拠
///
/// オンデバイスLLMの制約（トークン上限 ~650 入力トークン）を考慮し、
/// 簡潔なプロンプトで要約+タグ生成を行う。
public struct PromptTemplate: Sendable, Equatable {
    /// プロンプトのバージョン（品質追跡用）
    public let version: String
    /// プロンプトテンプレート（{transcribed_text} プレースホルダーを含む）
    public let userPromptTemplate: String

    public init(version: String, userPromptTemplate: String) {
        self.version = version
        self.userPromptTemplate = userPromptTemplate
    }

    /// プレースホルダーをテキストで置換してプロンプトを構築する
    /// - Parameter text: 文字起こしテキスト
    /// - Returns: LLMに送信するプロンプト文字列
    public func buildUserPrompt(text: String) -> String {
        userPromptTemplate.replacingOccurrences(of: "{transcribed_text}", with: text)
    }

    // MARK: - 定義済みテンプレート

    /// Phase 3a: オンデバイス簡易プロンプト（要約+タグ統合）
    ///
    /// 設計判断:
    /// - プロンプト言語: 日本語（入出力ともに日本語のため）
    /// - システムプロンプト: なし（トークン節約）
    /// - Few-shot例示: なし（トークン節約）
    /// - 出力形式: JSON（構造化データ抽出のため）
    /// - キーポイント: 省略（オンデバイスの安定性考慮、Phase 3bで追加）
    public static let onDeviceSimple = PromptTemplate(
        version: "1.0.0",
        userPromptTemplate: """
        以下のメモを要約し、タグを付けてください。JSON形式で出力してください。

        メモ: {transcribed_text}

        出力形式:
        {"title": "20文字以内のタイトル", "brief": "1行の要約", "tags": ["タグ1", "タグ2"]}
        """
    )
}
