import Domain
import Foundation

/// LLMの生テキスト出力をパースして LLMResponse に変換する
/// P3A-EC-003（不正JSON時のリトライ）対応
///
/// パース戦略:
/// 1. ```json ... ``` フェンスドコードブロックからJSON抽出
/// 2. { ... } の直接抽出（ネストされたブレース対応）
/// 3. 不正JSON検出時はフォールバック結果を返す
public struct LLMResponseParser: Sendable {

    public init() {}

    // MARK: - Public API

    /// LLMの生テキスト出力をパースして LLMResponse に変換する
    ///
    /// - Parameters:
    ///   - rawOutput: LLMからの生テキスト出力
    ///   - processingTimeMs: 処理時間（ミリ秒）
    ///   - provider: 使用したプロバイダ種別
    /// - Returns: パース済みの LLMResponse
    /// - Throws: `LLMError.invalidOutput` パースに完全に失敗した場合
    public func parse(
        _ rawOutput: String,
        processingTimeMs: Int,
        provider: LLMProviderType
    ) throws -> LLMResponse {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw LLMError.invalidOutput
        }

        // JSON部分を抽出
        guard let jsonString = extractJSON(from: trimmed) else {
            throw LLMError.invalidOutput
        }

        // JSONデコード
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw LLMError.invalidOutput
        }

        do {
            let decoded = try JSONDecoder().decode(OnDeviceLLMOutput.self, from: jsonData)
            return convertToResponse(decoded, processingTimeMs: processingTimeMs, provider: provider)
        } catch {
            // 部分的なパースを試みる
            if let partial = tryPartialParse(jsonData, processingTimeMs: processingTimeMs, provider: provider) {
                return partial
            }
            throw LLMError.invalidOutput
        }
    }

    // MARK: - JSON抽出

    /// テキストからJSON部分を抽出する
    ///
    /// 以下の順序で試行する:
    /// 1. ```json ... ``` フェンスドコードブロック
    /// 2. ``` ... ``` フェンスドコードブロック（言語指定なし）
    /// 3. { ... } の直接抽出（最外側のブレースペア）
    func extractJSON(from text: String) -> String? {
        // 1. ```json ... ``` パターン
        if let jsonBlock = extractFencedCodeBlock(from: text, language: "json") {
            return jsonBlock
        }

        // 2. ``` ... ``` パターン（言語指定なし）
        if let codeBlock = extractFencedCodeBlock(from: text, language: nil) {
            return codeBlock
        }

        // 3. { ... } の直接抽出（最外側のブレースペア）
        if let braceContent = extractOutermostBraces(from: text) {
            return braceContent
        }

        return nil
    }

    /// フェンスドコードブロックを抽出する
    private func extractFencedCodeBlock(from text: String, language: String?) -> String? {
        let pattern: String
        if let lang = language {
            pattern = "```\(lang)\\s*\\n([\\s\\S]*?)\\n?```"
        } else {
            pattern = "```\\s*\\n([\\s\\S]*?)\\n?```"
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let extracted = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return extracted.isEmpty ? nil : extracted
    }

    /// 最外側の { ... } を抽出する（ネストされたブレース対応）
    private func extractOutermostBraces(from text: String) -> String? {
        guard let openIndex = text.firstIndex(of: "{") else { return nil }

        var depth = 0
        var index = openIndex

        while index < text.endIndex {
            let char = text[index]
            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    let endIndex = text.index(after: index)
                    return String(text[openIndex..<endIndex])
                }
            }
            index = text.index(after: index)
        }

        return nil
    }

    // MARK: - レスポンス変換

    /// デコード結果を LLMResponse に変換する
    private func convertToResponse(
        _ output: OnDeviceLLMOutput,
        processingTimeMs: Int,
        provider: LLMProviderType
    ) -> LLMResponse {
        let summary = LLMSummaryResult(
            title: String(output.title.prefix(20)),
            brief: output.brief,
            keyPoints: []  // Phase 3a オンデバイス版ではキーポイント省略
        )

        let tags = output.tags.prefix(3).map { tag in
            LLMTagResult(
                label: String(tag.prefix(15)),
                confidence: 0.8  // オンデバイスでは固定信頼度
            )
        }

        return LLMResponse(
            summary: summary,
            tags: Array(tags),
            processingTimeMs: processingTimeMs,
            provider: provider
        )
    }

    /// 部分的なパースを試みる（title/brief/tags の一部が欠けても結果を返す）
    private func tryPartialParse(
        _ jsonData: Data,
        processingTimeMs: Int,
        provider: LLMProviderType
    ) -> LLMResponse? {
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        let title = (json["title"] as? String) ?? ""
        let brief = (json["brief"] as? String) ?? ""
        let tags = (json["tags"] as? [String]) ?? []

        // title と brief の両方が空なら部分パースも失敗とする
        if title.isEmpty && brief.isEmpty {
            return nil
        }

        let summary = LLMSummaryResult(
            title: String(title.prefix(20)),
            brief: brief,
            keyPoints: []
        )

        let tagResults = tags.prefix(3).map { tag in
            LLMTagResult(label: String(tag.prefix(15)), confidence: 0.6)
        }

        return LLMResponse(
            summary: summary,
            tags: Array(tagResults),
            processingTimeMs: processingTimeMs,
            provider: provider
        )
    }
}

// MARK: - 内部デコード用型

/// オンデバイスLLMの出力JSON形式
struct OnDeviceLLMOutput: Decodable, Sendable {
    let title: String
    let brief: String
    let tags: [String]
}
