import Domain
import Foundation

/// テスト・開発用のモックLLMプロバイダ
/// Phase 3a ではllama.cpp統合前のため、固定レスポンスを返すモック実装を使用する
///
/// 用途:
/// - ユニットテスト・UIテストでのLLM処理シミュレーション
/// - llama.cpp 統合前の開発時のEnd-to-End動作確認
public final class MockLLMProvider: @unchecked Sendable {

    /// モックの応答遅延（推論時間のシミュレーション用）
    public var simulatedDelay: Duration

    /// モックが返すレスポンス（カスタマイズ可能）
    public var mockResponse: LLMResponse?

    /// モックが返すエラー（設定時はエラーを投げる）
    public var mockError: LLMError?

    /// process が呼ばれた回数（テスト検証用）
    public private(set) var processCallCount: Int = 0

    /// 最後に受け取ったリクエスト（テスト検証用）
    public private(set) var lastRequest: LLMRequest?

    public init(
        simulatedDelay: Duration = .milliseconds(100),
        mockResponse: LLMResponse? = nil,
        mockError: LLMError? = nil
    ) {
        self.simulatedDelay = simulatedDelay
        self.mockResponse = mockResponse
        self.mockError = mockError
    }

    // MARK: - LLMProviderClient 互換 API

    /// LLM処理を実行（モック: 固定レスポンスを返す）
    public func process(_ request: LLMRequest) async throws -> LLMResponse {
        processCallCount += 1
        lastRequest = request

        // シミュレーション遅延
        try await Task.sleep(for: simulatedDelay)

        // エラーが設定されている場合
        if let error = mockError {
            throw error
        }

        // カスタムレスポンスが設定されている場合
        if let response = mockResponse {
            return response
        }

        // デフォルトのモックレスポンス
        return Self.defaultMockResponse(for: request)
    }

    /// プロバイダ利用可否（モック: 常に true）
    public func isAvailable() async -> Bool {
        true
    }

    /// プロバイダ種別
    public var providerType: LLMProviderType {
        .onDeviceLlamaCpp
    }

    /// モデルアンロード（モック: no-op）
    public func unloadModel() async {
        // モックでは何もしない
    }

    // MARK: - LLMProviderClient への変換

    /// TCA Dependency として使用するための LLMProviderClient を生成する
    public func asClient() -> LLMProviderClient {
        LLMProviderClient(
            process: { [self] request in
                try await self.process(request)
            },
            isAvailable: { [self] in
                await self.isAvailable()
            },
            providerType: { [self] in
                self.providerType
            },
            unloadModel: { [self] in
                await self.unloadModel()
            }
        )
    }

    // MARK: - フィラー除去・簡易清書

    /// 除去対象のフィラーワード一覧
    private static let fillerWords: [String] = [
        "えっと", "えーっと", "えーと", "えっ", "えー",
        "あの", "あのー", "あのう",
        "まあ", "まぁ",
        "なんか", "なんていうか",
        "そのー", "その",
        "うーん", "うん",
        "ほら",
    ]

    /// テキストからフィラーワードを除去する
    static func removeFillers(from text: String) -> String {
        var result = text
        for filler in fillerWords {
            result = result.replacingOccurrences(of: filler, with: "")
        }
        // 連続する空白を1つにまとめ、前後の空白を除去
        result = result.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// フィラー除去後のテキストから簡易タイトルを生成（先頭20文字）
    static func generateTitle(from cleanedText: String) -> String {
        let trimmed = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "無題のメモ" }
        if trimmed.count <= 20 {
            return trimmed
        }
        return String(trimmed.prefix(20))
    }

    /// 清書テキストを生成（フィラー除去 + 末尾句点補完）
    static func generateCleanedText(from text: String) -> String {
        let cleaned = removeFillers(from: text)
        guard !cleaned.isEmpty else { return text }
        // 末尾に句点がなければ追加
        if !cleaned.hasSuffix("。") && !cleaned.hasSuffix("！") && !cleaned.hasSuffix("？") {
            return cleaned + "。"
        }
        return cleaned
    }

    // MARK: - デフォルトモックデータ

    /// リクエストに基づいたデフォルトのモックレスポンスを生成する
    /// 入力テキストの内容に基づいて、簡易的な清書・タイトル生成を行う
    public static func defaultMockResponse(for request: LLMRequest) -> LLMResponse {
        let inputText = request.text
        let cleanedText = generateCleanedText(from: inputText)
        let title = generateTitle(from: removeFillers(from: inputText))

        let summary: LLMSummaryResult? = request.tasks.contains(.summarize)
            ? LLMSummaryResult(
                title: title,
                brief: cleanedText,
                keyPoints: []
            )
            : nil

        let tags: [LLMTagResult] = request.tasks.contains(.tagging)
            ? generateSimpleTags(from: cleanedText)
            : []

        return LLMResponse(
            summary: summary,
            tags: tags,
            processingTimeMs: 150,
            provider: .onDeviceLlamaCpp
        )
    }

    /// 入力テキストから簡易タグを生成する
    private static func generateSimpleTags(from text: String) -> [LLMTagResult] {
        var tags: [LLMTagResult] = []

        let tagKeywords: [(keyword: String, tag: String)] = [
            ("会議", "会議"),
            ("ミーティング", "会議"),
            ("買い物", "買い物"),
            ("料理", "料理"),
            ("出かけ", "お出かけ"),
            ("行く", "お出かけ"),
            ("勉強", "勉強"),
            ("仕事", "仕事"),
            ("TODO", "TODO"),
            ("やること", "TODO"),
            ("アイデア", "アイデア"),
            ("思いつ", "アイデア"),
            ("電話", "連絡"),
            ("メール", "連絡"),
        ]

        var addedTags: Set<String> = []
        for (keyword, tag) in tagKeywords {
            if text.contains(keyword) && !addedTags.contains(tag) {
                tags.append(LLMTagResult(label: tag, confidence: 0.8))
                addedTags.insert(tag)
                if tags.count >= 3 { break }
            }
        }

        // タグが1つも見つからなければ「メモ」を返す
        if tags.isEmpty {
            tags.append(LLMTagResult(label: "メモ", confidence: 0.5))
        }

        return tags
    }
}
