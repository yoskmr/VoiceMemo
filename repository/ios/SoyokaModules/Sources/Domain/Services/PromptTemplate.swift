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
    ///   - style: AI整理の文体（デフォルト: `.soft`＝既存プロンプトそのまま）
    /// - Returns: LLMに送信するプロンプト文字列
    public func buildUserPrompt(text: String, customDictionary: [String] = [], style: WritingStyle = .soft) -> String {
        var prompt = userPromptTemplate.replacingOccurrences(of: "{transcribed_text}", with: text)
        prompt = prompt.replacingOccurrences(of: "{custom_dictionary}", with: formatDictionary(customDictionary))
        prompt += Self.styleInstruction(for: style)
        return prompt
    }

    /// 読みペア付きカスタム辞書でプロンプトを構築する（SpeechAnalyzer後処理用）
    public func buildUserPrompt(text: String, dictionaryPairs: [(reading: String, display: String)], style: WritingStyle = .soft) -> String {
        var prompt = userPromptTemplate.replacingOccurrences(of: "{transcribed_text}", with: text)
        prompt = prompt.replacingOccurrences(of: "{custom_dictionary}", with: formatDictionaryPairs(dictionaryPairs))
        prompt += Self.styleInstruction(for: style)
        return prompt
    }

    /// 文体に応じたプロンプト追加指示を返す
    public static func styleInstruction(for style: WritingStyle) -> String {
        switch style {
        case .soft:
            return ""  // デフォルト（既存プロンプトそのまま）
        case .formal:
            return """

            追加指示 - 文体「きちんと」:
            - 「です」「ます」調で統一する
            - 主語と述語を明確にする
            - 感情的な表現は残しつつ、丁寧な言葉遣いに整える
            - カジュアルすぎる表現（「～じゃん」「マジで」等）は自然な丁寧語に言い換える
            """
        case .casual:
            return """

            追加指示 - 文体「ひとりごと」:
            - 短い文で区切る。一文は長くても30文字程度
            - 体言止めを積極的に使う
            - 「。」より「。」を省略した改行を多用
            - SNSに投稿するような気軽さで
            - 感嘆や独り言のニュアンスを大切にする
            """
        case .reflection:
            return """

            追加指示 - 文体「ふりかえり」:
            - 「あなた」に語りかける手紙のような文体にする
            - 「今日のあなたは〜」「〜したんだね」のように、やさしく見守るトーンで
            - 内容を要約するのではなく、体験に共感し、小さな気づきを添える
            - 最後に一言、励ましや問いかけを加える
            """
        case .essay:
            return """

            追加指示 - 文体「エッセイ」:
            - 短い随筆・エッセイのように書き直す
            - 冒頭に情景描写を加える（天気、季節、場所の雰囲気など、文脈から推測して自然に）
            - 思考の流れに文学的なリズムを持たせる
            - 体言止め、倒置法、比喩を適度に使う
            - 日常のひとコマが作品のように感じられる文章に
            """
        }
    }

    private func formatDictionary(_ words: [String]) -> String {
        if words.isEmpty { return "" }
        let list = words.prefix(30).joined(separator: "、")
        return """

        固有名詞の参考リスト（控えめに使うこと）:
        以下はユーザーが登録した固有名詞です。元のテキストに明らかに該当する箇所がある場合のみ修正してください。
        無理にリストの単語を当てはめないこと。元のテキストにない単語を挿入しないこと。読みがなを括弧で付けないこと。
        登録語: \(list)
        """
    }

    private func formatDictionaryPairs(_ pairs: [(reading: String, display: String)]) -> String {
        if pairs.isEmpty { return "" }
        let pairList = pairs.prefix(30).map { "\($0.display)（\($0.reading)）" }.joined(separator: "、")
        return """

        重要 - 固有名詞の修正:
        以下はユーザーが登録した正しい固有名詞です。読みを参考に、音声認識で似た音の別の漢字に誤変換されている箇所を必ず修正してください。
        正しい固有名詞（読み）: \(pairList)
        """
    }

    // MARK: - リモートプロンプト変換

    /// リモート配信レスポンスから文体指示マップを構築する
    /// アプリ起動時にリモートから取得 → キャッシュ更新 → 次回以降はキャッシュ利用
    public static func styleInstructionsFromRemote(_ templates: [String: String]) -> [WritingStyle: String] {
        var map: [WritingStyle: String] = [:]
        for style in WritingStyle.allCases {
            map[style] = templates[style.rawValue] ?? ""
        }
        return map
    }

    /// UserDefaultsにキャッシュされた文体指示マップを取得する（なければnil）
    public static var cachedStyleInstructions: [WritingStyle: String]? {
        guard let data = UserDefaults.standard.data(forKey: "cachedRemoteStyleInstructions") else {
            return nil
        }
        // [String: String] → [WritingStyle: String] に変換
        guard let raw = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        var map: [WritingStyle: String] = [:]
        for (key, value) in raw {
            if let style = WritingStyle(rawValue: key) {
                map[style] = value
            }
        }
        return map
    }

    /// 文体指示マップをUserDefaultsにキャッシュする
    public static func cacheStyleInstructions(_ templates: [String: String]) {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        UserDefaults.standard.set(data, forKey: "cachedRemoteStyleInstructions")
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
        version: "3.2.0",
        userPromptTemplate: """
        以下は音声メモの文字起こしです。音声認識の特性上、言い間違い・繰り返し・フィラーが含まれています。これを読みやすい1つの文章に清書してください。

        清書のルール:
        - 要約しない。話した内容を省略せず、全て残す
        - 「えっと」「あの」「まあ」などのフィラーワードを除去する
        - 同じことを二度言っている箇所（言い直し）は、正しい方を1つだけ残す
        - 音声認識の誤変換と思われる箇所は、文脈から推測して自然な言葉に直す。日本語として意味が通らない単語は、前後の文脈から正しい言葉を推測すること（例: 「余命家族」→文脈が家族人数の話なら「4名家族」）
        - 句読点を適切に入れ、読みやすくする
        - 話者の言葉遣いや雰囲気はできるだけそのまま残す
        - 堅い文体にしない。話していた時の自然なトーンを大切にする
        - タイトルは「音声メモの文字起こし」のような汎用的なものにせず、内容に基づいた具体的なものにする
        - 話題が複数ある場合は、話題ごとに「## 見出し」で区切る（Markdown形式）。話題が1つしかなければ見出しは不要
        - 清書テキストは必ず最後まで書ききること。途中で終わらないこと
        - 出力はJSON形式のみ。JSON以外のテキスト（説明文やプロンプトの繰り返し）を出力しないこと
        {custom_dictionary}

        メモ: {transcribed_text}

        JSON形式で出力:
        {"title": "内容を表す短いタイトル（20文字以内）", "cleaned": "清書した文章（話題が複数あれば## 見出しで区切る）", "tags": ["タグ1", "タグ2", "タグ3"]}
        """
    )
}
