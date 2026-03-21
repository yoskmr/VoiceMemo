import Domain
import Foundation
import os.log

private let logger = Logger(subsystem: "com.murmurnote", category: "OnDeviceLLMProvider")

/// llama.cpp ベースのオンデバイス LLM プロバイダ
/// P3A-REQ-004 準拠
///
/// Phase 3a では llama.cpp の実統合は行わず、内部的に MockLLMProvider を使用する。
/// インターフェースは将来の llama.cpp 差し替えを前提に設計されている。
///
/// 将来の差し替え時の変更箇所:
/// 1. `internalProcess(_:)` メソッドを llama.cpp コンテキスト呼び出しに置換
/// 2. `loadModel()` で llama.cpp モデルを Metal GPU オフロードでロード
/// 3. `unloadModel()` で llama.cpp コンテキストを破棄
public final class OnDeviceLLMProvider: @unchecked Sendable {

    // MARK: - Properties

    /// デバイス能力チェッカー
    private let capabilityChecker: DeviceCapabilityChecker

    /// モデル管理
    private let modelManager: LLMModelManager

    /// レスポンスパーサー
    private let responseParser: LLMResponseParser

    /// Phase 3a: 内部的に使用するモック（将来 llama.cpp コンテキストに差し替え）
    private let mockProvider: MockLLMProvider

    /// モデルがロード済みか（将来: llama.cpp コンテキストの有無で判定）
    private var isModelLoaded: Bool = false

    /// メモリ排他制御用ロック
    private let lock = NSLock()

    /// プロバイダ種別
    public let currentProviderType: LLMProviderType = .onDeviceLlamaCpp

    /// 最大入力文字数（オンデバイス制限: ~500日本語文字 ≈ 650トークン）
    public let maxInputCharacters: Int = 500

    /// 最小入力文字数（短すぎるテキストはスキップ）
    public let minInputCharacters: Int = 10

    // MARK: - Initialization

    public init(
        capabilityChecker: DeviceCapabilityChecker = .shared,
        modelManager: LLMModelManager = LLMModelManager(),
        responseParser: LLMResponseParser = LLMResponseParser()
    ) {
        self.capabilityChecker = capabilityChecker
        self.modelManager = modelManager
        self.responseParser = responseParser
        self.mockProvider = MockLLMProvider(
            simulatedDelay: .milliseconds(500)
        )
    }

    // MARK: - Public API

    /// LLM処理を実行する
    ///
    /// 処理フロー:
    /// 1. 入力バリデーション（文字数チェック）
    /// 2. モデルロード（未ロード時）
    /// 3. プロンプト構築
    /// 4. 推論実行
    /// 5. レスポンスパース
    ///
    /// - Parameter request: LLM処理リクエスト
    /// - Returns: パース済みのLLMレスポンス
    /// - Throws: `LLMError` 各種エラー
    public func process(_ request: LLMRequest) async throws -> LLMResponse {
        // 1. 入力バリデーション
        try validateInput(request.text)

        // 2. モデルロード確認
        if !isModelLoaded {
            try await loadModel()
        }

        // 3. プロンプト構築
        let prompt = PromptTemplate.onDeviceSimple.buildUserPrompt(text: request.text)
        logger.debug("プロンプト構築完了: \(prompt.prefix(100))...")

        // 4. 推論実行
        let startTime = CFAbsoluteTimeGetCurrent()
        let response = try await internalProcess(request, prompt: prompt)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        logger.info("LLM推論完了: \(Int(elapsed * 1000))ms")

        return response
    }

    /// プロバイダの利用可否チェック
    ///
    /// 以下を全て満たす場合に true:
    /// - デバイスがオンデバイスLLMをサポート（A16+, 6GB+）
    /// - Phase 3a: モック使用のため常に true（実 llama.cpp 時は `modelManager.isModelDownloaded` も条件に追加）
    public func isAvailable() async -> Bool {
        let deviceSupported = capabilityChecker.supportsOnDeviceLLM
        // Phase 3a: モック使用のため、デバイスサポートのみで判定
        // 将来: deviceSupported && modelManager.isModelDownloaded
        return deviceSupported
    }

    /// プロバイダ種別を返す
    public func providerType() -> LLMProviderType {
        currentProviderType
    }

    /// モデルのアンロード（メモリ解放）
    ///
    /// 将来: llama.cpp コンテキストを破棄し、GPUメモリを解放する
    public func unloadModel() async {
        lock.lock()
        defer { lock.unlock() }

        isModelLoaded = false
        await mockProvider.unloadModel()
        logger.info("LLMモデルをアンロードしました")
    }

    // MARK: - LLMProviderClient 変換

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
            unloadModel: { [self] in
                await self.unloadModel()
            }
        )
    }

    // MARK: - Internal

    /// 入力テキストのバリデーション
    private func validateInput(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.count < minInputCharacters {
            logger.warning("入力テキストが短すぎます: \(trimmed.count)文字 (最低\(self.minInputCharacters)文字)")
            throw LLMError.inputTooShort
        }

        if trimmed.count > maxInputCharacters {
            logger.warning("入力テキストが長すぎます: \(trimmed.count)文字 (最大\(self.maxInputCharacters)文字)")
            throw LLMError.inputTooLong
        }
    }

    /// モデルロード
    ///
    /// 将来: llama.cpp コンテキストを Metal GPU オフロードで作成する
    /// ```swift
    /// let params = LlamaModelParams.default()
    /// params.n_gpu_layers = 99  // Metal GPU全レイヤーオフロード
    /// llamaContext = try LlamaContext(modelPath: modelPath.path, params: params)
    /// ```
    private func loadModel() async throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isModelLoaded else { return }

        // メモリ余裕チェック
        if !capabilityChecker.hasMemoryHeadroomForLLM {
            logger.error("LLMモデルロードに必要なメモリが不足しています")
            throw LLMError.memoryInsufficient
        }

        // Phase 3a: モック使用のため即座にロード完了とする
        // 将来: llama.cpp モデルファイルの存在チェック + コンテキスト作成
        isModelLoaded = true
        logger.info("LLMモデルをロードしました (Phase 3a: モック)")
    }

    /// 内部推論実行
    ///
    /// Phase 3a: MockLLMProvider に委譲する
    /// 将来: llama.cpp コンテキストで推論を実行し、LLMResponseParser でパースする
    /// ```swift
    /// let rawOutput = try await llamaContext!.generate(
    ///     prompt: prompt,
    ///     maxTokens: 512,
    ///     temperature: 0.3,
    ///     stopTokens: ["```", "</json>"]
    /// )
    /// return try responseParser.parse(rawOutput, processingTimeMs: elapsed, provider: currentProviderType)
    /// ```
    private func internalProcess(_ request: LLMRequest, prompt: String) async throws -> LLMResponse {
        // Phase 3a: MockLLMProvider を使用
        return try await mockProvider.process(request)
    }
}
