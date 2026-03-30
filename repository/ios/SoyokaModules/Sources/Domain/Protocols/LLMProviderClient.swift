import Dependencies
import Foundation

// MARK: - LLM処理タスク種別

/// LLM処理タスクの種別
/// Phase 3a 詳細設計 DES-PHASE3A-001 セクション3.1 準拠
public enum LLMTask: String, CaseIterable, Sendable {
    /// テキスト要約（タイトル + 1行要約）
    case summarize
    /// タグ自動生成（最大3件）
    case tagging
    /// 感情分析（8カテゴリ）
    case sentimentAnalysis
}

// MARK: - LLMリクエスト・レスポンス型

/// LLM処理リクエスト
public struct LLMRequest: Sendable, Equatable {
    /// 文字起こしテキスト
    public let text: String
    /// 実行するタスクのセット
    public let tasks: Set<LLMTask>
    /// 言語コード（デフォルト: 日本語）
    public let language: String
    /// 最大入力トークン数（オンデバイス制限）
    public let maxTokens: Int
    /// カスタム辞書（固有名詞リスト、音声認識の誤変換修正に使用）
    public let customDictionary: [String]
    /// クラウドプロバイダの使用を許可するか（Free プランでは false）
    public let allowCloud: Bool
    /// AI整理の文体（ユーザー選択）
    public let writingStyle: WritingStyle

    public init(
        text: String,
        tasks: Set<LLMTask>,
        language: String = "ja",
        maxTokens: Int = 650,
        customDictionary: [String] = [],
        allowCloud: Bool = true,
        writingStyle: WritingStyle = .soft
    ) {
        self.text = text
        self.tasks = tasks
        self.language = language
        self.customDictionary = customDictionary
        self.maxTokens = maxTokens
        self.allowCloud = allowCloud
        self.writingStyle = writingStyle
    }
}

/// LLM処理レスポンス
public struct LLMResponse: Sendable, Equatable {
    /// 要約結果（.summarize タスク実行時）
    public let summary: LLMSummaryResult?
    /// タグ結果（.tagging タスク実行時）
    public let tags: [LLMTagResult]
    /// 感情分析結果（.sentimentAnalysis タスク実行時）
    public let sentiment: LLMSentimentResult?
    /// 処理時間（ミリ秒）
    public let processingTimeMs: Int
    /// 使用したプロバイダ種別
    public let provider: LLMProviderType

    public init(
        summary: LLMSummaryResult?,
        tags: [LLMTagResult],
        sentiment: LLMSentimentResult? = nil,
        processingTimeMs: Int,
        provider: LLMProviderType
    ) {
        self.summary = summary
        self.tags = tags
        self.sentiment = sentiment
        self.processingTimeMs = processingTimeMs
        self.provider = provider
    }
}

/// 要約結果
public struct LLMSummaryResult: Sendable, Equatable {
    /// 20文字以内のタイトル
    public let title: String
    /// 1行の要約文
    public let brief: String
    /// キーポイント（Phase 3a オンデバイス版では空配列）
    public let keyPoints: [String]

    public init(title: String, brief: String, keyPoints: [String] = []) {
        self.title = title
        self.brief = brief
        self.keyPoints = keyPoints
    }
}

/// タグ結果
public struct LLMTagResult: Sendable, Equatable {
    /// タグラベル（15文字以内）
    public let label: String
    /// 信頼度（0.0〜1.0）
    public let confidence: Double

    public init(label: String, confidence: Double) {
        self.label = label
        self.confidence = confidence
    }
}

/// 感情分析結果（LLMレスポンス用）
/// Phase 3b 感情分析機能（DES-PHASE3A-001 セクション3.1 準拠）
/// 既存の `SentimentEvidence`（EmotionAnalysisEntity.swift）を再利用
public struct LLMSentimentResult: Equatable, Sendable {
    /// 主要な感情カテゴリ
    public let primary: EmotionCategory
    /// 各感情カテゴリのスコア（0.0〜1.0）
    public let scores: [EmotionCategory: Double]
    /// 根拠テキスト（感情が検出されたテキスト断片）
    public let evidence: [SentimentEvidence]

    public init(primary: EmotionCategory, scores: [EmotionCategory: Double], evidence: [SentimentEvidence]) {
        self.primary = primary
        self.scores = scores
        self.evidence = evidence
    }
}

// MARK: - TCA Dependency Client

/// LLMプロバイダの TCA Dependency クライアント
/// テキストに対するAI処理（要約・タグ生成）を実行する
public struct LLMProviderClient: Sendable {
    /// テキストに対してLLM処理を実行
    public var process: @Sendable (LLMRequest) async throws -> LLMResponse
    /// プロバイダの利用可否チェック
    public var isAvailable: @Sendable () async -> Bool
    /// 現在のプロバイダ種別
    public var providerType: @Sendable () -> LLMProviderType
    /// モデルのアンロード（メモリ解放）
    public var unloadModel: @Sendable () async -> Void

    public init(
        process: @escaping @Sendable (LLMRequest) async throws -> LLMResponse,
        isAvailable: @escaping @Sendable () async -> Bool,
        providerType: @escaping @Sendable () -> LLMProviderType,
        unloadModel: @escaping @Sendable () async -> Void
    ) {
        self.process = process
        self.isAvailable = isAvailable
        self.providerType = providerType
        self.unloadModel = unloadModel
    }
}

// MARK: - DependencyKey

extension LLMProviderClient: TestDependencyKey {
    public static let testValue = LLMProviderClient(
        process: unimplemented("LLMProviderClient.process"),
        isAvailable: unimplemented("LLMProviderClient.isAvailable", placeholder: false),
        providerType: unimplemented("LLMProviderClient.providerType", placeholder: .onDeviceLlamaCpp),
        unloadModel: unimplemented("LLMProviderClient.unloadModel")
    )
}

extension DependencyValues {
    public var llmProvider: LLMProviderClient {
        get { self[LLMProviderClient.self] }
        set { self[LLMProviderClient.self] = newValue }
    }
}
