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

    // MARK: - デフォルトモックデータ

    /// リクエストに基づいたデフォルトのモックレスポンスを生成する
    public static func defaultMockResponse(for request: LLMRequest) -> LLMResponse {
        let summary: LLMSummaryResult? = request.tasks.contains(.summarize)
            ? LLMSummaryResult(
                title: "会議メモの要約",
                brief: "本日の会議で議論された主要なトピックのまとめです。",
                keyPoints: []
            )
            : nil

        let tags: [LLMTagResult] = request.tasks.contains(.tagging)
            ? [
                LLMTagResult(label: "会議", confidence: 0.9),
                LLMTagResult(label: "議事録", confidence: 0.85),
                LLMTagResult(label: "TODO", confidence: 0.7),
            ]
            : []

        return LLMResponse(
            summary: summary,
            tags: tags,
            processingTimeMs: 150,
            provider: .onDeviceLlamaCpp
        )
    }
}
