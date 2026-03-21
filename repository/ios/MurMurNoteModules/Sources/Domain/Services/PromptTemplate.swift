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

    /// Phase 3a: オンデバイス簡易プロンプト（整形+タグ統合）
    ///
    /// 設計判断:
    /// - 「要約」ではなく「日記風の整形・清書」として位置づけ
    /// - 話し言葉のニュアンスや感情を残しつつ、読みやすく整理する
    /// - 競合差別化: 「温かみ+ジャーナル風」トーン（04-ui-design-system.md 原則2準拠）
    /// - プロンプト言語: 日本語（入出力ともに日本語のため）
    /// - 出力形式: JSON（構造化データ抽出のため）
    public static let onDeviceSimple = PromptTemplate(
        version: "2.0.0",
        userPromptTemplate: """
        あなたは日記の整理を手伝う温かいアシスタントです。
        以下は音声メモの文字起こしです。話し言葉のまま記録されているので、読みやすい日記風の文章に整理してください。

        ルール:
        - 話者の気持ちやニュアンスを大切に残すこと
        - 「えっと」「あの」などのフィラーは除く
        - 堅い文章にせず、日記を書くような自然な文体にする
        - 内容を省略せず、話していたことを全て含める
        - タイトルは内容を温かく表現する短いフレーズにする

        メモ: {transcribed_text}

        JSON形式で出力:
        {"title": "温かみのあるタイトル（20文字以内）", "brief": "日記風に整理した文章", "tags": ["タグ1", "タグ2", "タグ3"]}
        """
    )
}
