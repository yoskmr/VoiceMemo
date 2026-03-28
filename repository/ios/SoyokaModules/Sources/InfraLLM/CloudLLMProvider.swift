import Domain
import Foundation
import InfraNetwork
import os.log

private let logger = Logger(subsystem: "app.soyoka", category: "CloudLLMProvider")

/// Cloud LLM プロバイダ（Backend Proxy 経由 GPT-4o mini）
///
/// 統合仕様書 INT-SPEC-001 セクション3.3 準拠。
/// BackendProxyClient を通じてサーバーサイドの GPT-4o mini にリクエストを送信し、
/// CloudAIResponse を Domain 層の LLMResponse に変換する。
///
/// 用途:
/// - オンデバイスLLMでは処理できない高度な要約・タグ付け・感情分析
/// - サブスクリプション（有料プラン）ユーザー向けのクラウドAI処理
public final class CloudLLMProvider: @unchecked Sendable {

    // MARK: - Properties

    /// Backend Proxy クライアント
    private let proxyClient: BackendProxyClient

    // MARK: - Initialization

    /// イニシャライザ
    /// - Parameter proxyClient: Backend Proxy クライアント
    public init(proxyClient: BackendProxyClient) {
        self.proxyClient = proxyClient
    }

    // MARK: - Public API

    /// LLM処理を実行する
    ///
    /// LLMRequest の tasks に基づいて Backend Proxy にリクエストを送信し、
    /// CloudAIResponse を LLMResponse に変換して返す。
    ///
    /// - Parameter request: LLM処理リクエスト
    /// - Returns: 変換済みの LLMResponse
    /// - Throws: `BackendProxyError` 通信エラー時、`LLMError` 変換エラー時
    public func process(_ request: LLMRequest) async throws -> LLMResponse {
        let startTime = CFAbsoluteTimeGetCurrent()

        let options = AIRequestOptions(
            summary: request.tasks.contains(.summarize),
            tags: request.tasks.contains(.tagging),
            sentiment: request.tasks.contains(.sentimentAnalysis)
        )

        let cloudResponse = try await proxyClient.processAI(
            request.text,
            request.language,
            options
        )

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let processingTimeMs = cloudResponse.metadata?.processingTimeMs ?? Int(elapsed * 1000)

        let response = convertToLLMResponse(cloudResponse, processingTimeMs: processingTimeMs)
        logger.info("Cloud LLM処理完了: \(processingTimeMs)ms")
        return response
    }

    /// 感情分析のみを実行する
    ///
    /// summary=false, tags=false, sentiment=true でリクエストし、
    /// LLMSentimentResult のみを返す。
    ///
    /// - Parameter request: LLM処理リクエスト（tasks は無視される）
    /// - Returns: 感情分析結果
    /// - Throws: `BackendProxyError` 通信エラー時、`LLMError.invalidOutput` 感情分析結果なし
    public func processSentimentOnly(_ request: LLMRequest) async throws -> LLMSentimentResult {
        let options = AIRequestOptions(summary: false, tags: false, sentiment: true)

        let cloudResponse = try await proxyClient.processAI(
            request.text,
            request.language,
            options
        )

        guard let cloudSentiment = cloudResponse.sentiment else {
            throw LLMError.invalidOutput
        }

        guard let result = convertSentiment(cloudSentiment) else {
            throw LLMError.invalidOutput
        }

        logger.info("Cloud 感情分析完了: primary=\(result.primary.rawValue)")
        return result
    }

    /// プロバイダの利用可否チェック（簡易ネットワーク到達性）
    ///
    /// 現在は常に true を返す（ネットワーク到達性は実際のリクエスト時に確認）
    public func isAvailable() async -> Bool {
        // 簡易チェック: ネットワーク到達性は URLSession のリクエスト時に確認される
        // 将来: NWPathMonitor によるリアルタイム監視に置き換え
        true
    }

    /// プロバイダ種別を返す
    public func providerType() -> LLMProviderType {
        .cloudGPT4oMini
    }

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
                self.providerType()
            },
            unloadModel: {
                // クラウドプロバイダはモデルアンロード不要（no-op）
            }
        )
    }

    // MARK: - Response Conversion

    /// CloudAIResponse を LLMResponse に変換する
    private func convertToLLMResponse(
        _ cloudResponse: CloudAIResponse,
        processingTimeMs: Int
    ) -> LLMResponse {
        // Summary 変換
        let summary: LLMSummaryResult? = cloudResponse.summary.map { cloudSummary in
            LLMSummaryResult(
                title: String(cloudSummary.title.prefix(20)),
                brief: cloudSummary.brief,
                keyPoints: cloudSummary.keyPoints
            )
        }

        // Tags 変換
        let tags: [LLMTagResult] = (cloudResponse.tags ?? []).prefix(3).map { cloudTag in
            LLMTagResult(
                label: String(cloudTag.label.prefix(15)),
                confidence: cloudTag.confidence
            )
        }

        // Sentiment 変換
        let sentiment: LLMSentimentResult? = cloudResponse.sentiment.flatMap { cloudSentiment in
            convertSentiment(cloudSentiment)
        }

        return LLMResponse(
            summary: summary,
            tags: tags,
            sentiment: sentiment,
            processingTimeMs: processingTimeMs,
            provider: .cloudGPT4oMini
        )
    }

    /// CloudSentiment を LLMSentimentResult に変換する
    ///
    /// Backend Proxy の感情分析レスポンスは文字列（"joy", "calm" 等）で返されるため、
    /// EmotionCategory enum に変換する。未知のカテゴリは無視する。
    private func convertSentiment(_ cloudSentiment: CloudSentiment) -> LLMSentimentResult? {
        // primary の変換
        guard let primaryEmotion = EmotionCategory(rawValue: cloudSentiment.primary) else {
            logger.warning("未知の感情カテゴリ: \(cloudSentiment.primary) → neutral にフォールバック")
            // フォールバック: neutral
            return LLMSentimentResult(
                primary: .neutral,
                scores: convertScores(cloudSentiment.scores),
                evidence: convertEvidence(cloudSentiment.evidence)
            )
        }

        return LLMSentimentResult(
            primary: primaryEmotion,
            scores: convertScores(cloudSentiment.scores),
            evidence: convertEvidence(cloudSentiment.evidence)
        )
    }

    /// スコア辞書を [String: Double] → [EmotionCategory: Double] に変換する
    private func convertScores(_ cloudScores: [String: Double]) -> [EmotionCategory: Double] {
        var scores: [EmotionCategory: Double] = [:]
        for (key, value) in cloudScores {
            if let emotion = EmotionCategory(rawValue: key) {
                scores[emotion] = value
            } else {
                logger.debug("未知の感情スコアキー: \(key) → スキップ")
            }
        }
        return scores
    }

    /// CloudSentimentEvidence を [SentimentEvidence] に変換する
    private func convertEvidence(_ cloudEvidence: [CloudSentimentEvidence]) -> [SentimentEvidence] {
        cloudEvidence.compactMap { item in
            guard let emotion = EmotionCategory(rawValue: item.emotion) else {
                logger.debug("未知の感情カテゴリ（evidence）: \(item.emotion) → スキップ")
                return nil
            }
            return SentimentEvidence(text: item.text, emotion: emotion)
        }
    }
}
