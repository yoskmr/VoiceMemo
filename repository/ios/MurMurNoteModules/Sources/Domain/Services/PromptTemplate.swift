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
    /// - Parameters:
    ///   - text: 文字起こしテキスト
    ///   - customDictionary: カスタム辞書（固有名詞リスト）。空でなければプロンプトに注入
    /// - Returns: LLMに送信するプロンプト文字列
    public func buildUserPrompt(text: String, customDictionary: [String] = []) -> String {
        var prompt = userPromptTemplate.replacingOccurrences(of: "{transcribed_text}", with: text)
        prompt = prompt.replacingOccurrences(of: "{custom_dictionary}", with: formatDictionary(customDictionary))
        return prompt
    }

    private func formatDictionary(_ words: [String]) -> String {
        if words.isEmpty {
            return ""
        }
        let list = words.prefix(30).joined(separator: "、")
        return """

        重要 - 固有名詞の修正:
        以下はユーザーが登録した正しい固有名詞です。音声認識で似た音の別の漢字に誤変換されている場合、必ずこのリストの表記に修正してください。
        例: 「鈴鹿」→「鈴香」、「宿待っている」→「城間という」
        正しい固有名詞: \(list)
        """
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
        version: "3.0.0",
        userPromptTemplate: """
        以下は音声メモの文字起こしです。音声認識の特性上、言い間違い・繰り返し・フィラーが含まれています。これを読みやすい1つの文章に清書してください。

        清書のルール:
        - 要約しない。話した内容を省略せず、全て残す
        - 「えっと」「あの」「まあ」などのフィラーワードを除去する
        - 同じことを二度言っている箇所（言い直し）は、正しい方を1つだけ残す
        - 音声認識の誤変換と思われる箇所は、文脈から推測して自然な言葉に直す
        - 句読点を適切に入れ、読みやすくする
        - 話者の言葉遣いや雰囲気はできるだけそのまま残す
        - 堅い文体にしない。話していた時の自然なトーンを大切にする
        - タイトルは「音声メモの文字起こし」のような汎用的なものにせず、内容に基づいた具体的なものにする
        {custom_dictionary}

        メモ: {transcribed_text}

        JSON形式で出力:
        {"title": "内容を表す短いタイトル（20文字以内）", "cleaned": "清書した文章（全内容を含む）", "tags": ["タグ1", "タグ2", "タグ3"]}
        """
    )
}
