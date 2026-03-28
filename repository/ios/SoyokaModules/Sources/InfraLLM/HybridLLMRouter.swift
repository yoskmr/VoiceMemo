import Domain
import Foundation
import InfraNetwork
import os.log

private let logger = Logger(subsystem: "app.soyoka", category: "HybridLLMRouter")

/// ハイブリッド LLM ルーター（オンデバイス優先 → クラウドフォールバック）
///
/// 統合仕様書 INT-SPEC-001 セクション3.2 準拠。
/// 処理の優先順位:
/// 1. Apple Intelligence（オンデバイス）で要約・タグ生成
/// 2. 感情分析はクラウド（GPT-4o mini）で追加実行（オプトイン時）
/// 3. オンデバイス失敗時はクラウドにフォールバック（EC-010）
/// 4. 全プロバイダ不可時はエラー
public final class HybridLLMRouter: @unchecked Sendable {

    // MARK: - Properties

    /// オンデバイス LLM プロバイダ（Apple Intelligence / llama.cpp）
    private let onDeviceProvider: OnDeviceLLMProvider

    /// llama.cpp プロバイダ（Apple Intelligence 非対応デバイス向けフォールバック）
    /// Phase 4 で llama.cpp SPM 統合後に有効化
    private let llamaCppProvider: LlamaCppProvider?

    /// クラウド LLM プロバイダ（Backend Proxy 経由 GPT-4o mini）
    private let cloudProvider: CloudLLMProvider

    // MARK: - Initialization

    /// イニシャライザ
    /// - Parameters:
    ///   - onDeviceProvider: オンデバイス LLM プロバイダ
    ///   - llamaCppProvider: llama.cpp プロバイダ（nil の場合はスキップ）
    ///   - cloudProvider: クラウド LLM プロバイダ
    public init(
        onDeviceProvider: OnDeviceLLMProvider,
        llamaCppProvider: LlamaCppProvider? = nil,
        cloudProvider: CloudLLMProvider
    ) {
        self.onDeviceProvider = onDeviceProvider
        self.llamaCppProvider = llamaCppProvider
        self.cloudProvider = cloudProvider
    }

    // MARK: - Public API

    /// LLM処理を実行する（オンデバイス優先 → クラウドフォールバック）
    ///
    /// 処理フロー:
    /// 1. オンデバイスプロバイダが利用可能なら、オンデバイスで要約・タグ生成を実行
    /// 2. 感情分析タスクが含まれ、かつクラウドが利用可能なら、感情分析のみクラウドで追加実行
    /// 3. オンデバイス処理失敗時はクラウドにフォールバック（EC-010 準拠）
    /// 4. オンデバイス不可かつクラウド利用可能なら、クラウドで全処理を実行
    /// 5. 全プロバイダ不可の場合はエラーをスロー
    ///
    /// - Parameter request: LLM処理リクエスト
    /// - Returns: LLM処理レスポンス（感情分析結果がマージされる場合あり）
    /// - Throws: `LLMError` 各種エラー
    public func process(_ request: LLMRequest) async throws -> LLMResponse {
        // 1. オンデバイス処理を試行
        if await onDeviceProvider.isAvailable() {
            do {
                let onDeviceResult = try await onDeviceProvider.process(request)
                logger.info("オンデバイス処理成功: provider=\(onDeviceResult.provider.rawValue)")

                // 2. 感情分析はクラウドで追加実行（オンライン時 + タスクに含まれる場合）
                if request.tasks.contains(.sentimentAnalysis),
                   await cloudProvider.isAvailable() {
                    do {
                        let sentimentResult = try await cloudProvider.processSentimentOnly(request)
                        logger.info("クラウド感情分析成功: primary=\(sentimentResult.primary.rawValue)")

                        // onDeviceResult に感情分析結果をマージして返す
                        return LLMResponse(
                            summary: onDeviceResult.summary,
                            tags: onDeviceResult.tags,
                            sentiment: sentimentResult,
                            processingTimeMs: onDeviceResult.processingTimeMs,
                            provider: onDeviceResult.provider
                        )
                    } catch {
                        // 感情分析失敗でもオンデバイス結果は返す
                        logger.warning("クラウド感情分析失敗（オンデバイス結果を返却）: \(error.localizedDescription)")
                        return onDeviceResult
                    }
                }
                return onDeviceResult

            } catch {
                // オンデバイス処理失敗 → llama.cpp → クラウドにフォールバック（EC-010）
                logger.warning("オンデバイス処理失敗: \(error.localizedDescription)")

                // 2.5. llama.cpp フォールバック
                if let llamaCpp = llamaCppProvider, await llamaCpp.isAvailable() {
                    do {
                        let result = try await llamaCpp.process(request)
                        logger.info("llama.cpp フォールバック成功")
                        return result
                    } catch {
                        logger.warning("llama.cpp フォールバック失敗: \(error.localizedDescription)")
                    }
                }

                if await cloudProvider.isAvailable() {
                    logger.info("クラウドフォールバックに移行")
                    return try await cloudProvider.process(request)
                }
                throw error
            }
        }

        // 2.5. オンデバイス不可 → llama.cpp を試行
        if let llamaCpp = llamaCppProvider, await llamaCpp.isAvailable() {
            do {
                let result = try await llamaCpp.process(request)
                logger.info("llama.cpp 処理成功（オンデバイス不可のため）")
                return result
            } catch {
                logger.warning("llama.cpp 処理失敗 → クラウドフォールバック: \(error.localizedDescription)")
            }
        }

        // 3. オンデバイス不可 → クラウドで全処理
        if await cloudProvider.isAvailable() {
            logger.info("オンデバイス不可 → クラウドで全処理を実行")
            return try await cloudProvider.process(request)
        }

        // 4. 全て不可
        logger.error("全プロバイダ不可: オンデバイスLLM非対応かつネットワーク不達")
        throw LLMError.processingFailed("オンデバイスLLM非対応かつネットワーク不達")
    }

    /// プロバイダの利用可否チェック
    ///
    /// オンデバイスまたはクラウドのいずれかが利用可能であれば true
    public func isAvailable() async -> Bool {
        let onDeviceAvailable = await onDeviceProvider.isAvailable()
        if onDeviceAvailable { return true }
        return await cloudProvider.isAvailable()
    }

    /// プロバイダ種別を返す
    ///
    /// 実際のプロバイダ種別は `process()` 結果の `provider` フィールドで返されるため、
    /// ここではデフォルトとしてオンデバイスを返す
    public func providerType() -> LLMProviderType {
        .onDeviceAppleIntelligence
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
                await self.onDeviceProvider.unloadModel()
                await self.llamaCppProvider?.unloadModel()
            }
        )
    }
}
