import Domain
import Foundation
import os.log

private let logger = Logger(subsystem: "app.soyoka", category: "LlamaCppProvider")

/// llama.cpp ベースのオンデバイス LLM プロバイダ
///
/// Apple Intelligence 非対応デバイス（A16 Bionic / 6GB RAM）向けの
/// オンデバイス推論エンジン。Phi-3-mini Q4_K_M モデルを使用する。
///
/// Phase 4: llama.cpp SPM バインディング統合後に `process()` を実装予定。
/// 現在は MockLLMProvider にフォールバックする。
///
/// フォールバック優先順位（HybridLLMRouter から見た場合）:
/// 1. Apple Intelligence（iOS 26+, A17 Pro+, 8GB+ RAM）
/// 2. llama.cpp（A16+, 6GB+ RAM, モデル DL 済み） ← このプロバイダ
/// 3. Cloud（Backend Proxy 経由）
public final class LlamaCppProvider: @unchecked Sendable {

    // MARK: - Properties

    /// モデルダウンロード・キャッシュ管理
    private let modelManager: LLMModelManager

    /// デバイス能力チェッカー
    private let deviceChecker: DeviceCapabilityChecker

    /// フォールバック用モック（llama.cpp 統合前の暫定実装）
    private let mockProvider: MockLLMProvider

    // MARK: - Initialization

    public init(
        modelManager: LLMModelManager = LLMModelManager(),
        deviceChecker: DeviceCapabilityChecker = .shared
    ) {
        self.modelManager = modelManager
        self.deviceChecker = deviceChecker
        self.mockProvider = MockLLMProvider(simulatedDelay: .milliseconds(300))
    }

    // MARK: - Public API

    /// llama.cpp が利用可能か（モデル DL 済み + デバイス対応 + Apple Intelligence 非対応）
    ///
    /// Apple Intelligence 対応デバイスでは Apple Intelligence を優先するため false を返す。
    /// llama.cpp は Apple Intelligence 非対応かつオンデバイス LLM サポートデバイスでのみ利用。
    public func isAvailable() async -> Bool {
        guard deviceChecker.supportsOnDeviceLLM else {
            logger.debug("デバイスがオンデバイス LLM をサポートしていません")
            return false
        }
        guard !deviceChecker.supportsAppleIntelligence else {
            logger.debug("Apple Intelligence 対応デバイスのため llama.cpp は不使用")
            return false
        }
        guard modelManager.isModelDownloaded else {
            logger.debug("llama.cpp モデル未ダウンロード")
            return false
        }
        return true
    }

    /// テキスト処理（llama.cpp 統合後に実装）
    ///
    /// Phase 4 で llama.cpp SPM パッケージを統合し、実際のオンデバイス推論を実行する。
    /// 現在は MockLLMProvider にフォールバックし、固定レスポンスを返す。
    ///
    /// - Parameter request: LLM処理リクエスト
    /// - Returns: LLM処理レスポンス
    /// - Throws: `LLMError.deviceNotSupported` デバイス非対応時
    public func process(_ request: LLMRequest) async throws -> LLMResponse {
        guard await isAvailable() else {
            throw LLMError.deviceNotSupported
        }

        logger.info("llama.cpp 処理開始（現在はモックフォールバック）")

        // TODO: Phase 4 — llama.cpp SPM パッケージ統合後に実際の推論に差し替え
        // let context = try LlamaContext(modelPath: modelManager.modelPath!)
        // let result = try await context.generate(prompt: prompt, maxTokens: request.maxTokens)
        let response = try await mockProvider.process(request)

        logger.info("llama.cpp 処理完了（モックフォールバック）: \(response.processingTimeMs)ms")
        return response
    }

    /// プロバイダ種別
    public func providerType() -> LLMProviderType {
        .onDeviceLlamaCpp
    }

    /// モデルのアンロード（メモリ解放）
    ///
    /// Phase 4: llama.cpp コンテキストを解放し、GPU メモリを回収する
    public func unloadModel() async {
        // TODO: Phase 4 — llama.cpp コンテキスト解放
        // llamaContext?.free()
        // llamaContext = nil
        logger.info("llama.cpp モデルをアンロードしました（現在は no-op）")
    }

    // MARK: - LLMProviderClient 変換

    /// TCA Dependency として使用するための LLMProviderClient を生成する
    public func asClient() -> LLMProviderClient {
        LLMProviderClient(
            process: { [self] request in try await self.process(request) },
            isAvailable: { [self] in await self.isAvailable() },
            providerType: { [self] in self.providerType() },
            unloadModel: { [self] in await self.unloadModel() }
        )
    }
}
