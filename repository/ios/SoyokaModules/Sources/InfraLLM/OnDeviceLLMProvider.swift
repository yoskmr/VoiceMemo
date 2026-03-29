import Domain
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import os.log

private let logger = Logger(subsystem: "app.soyoka", category: "OnDeviceLLMProvider")

/// オンデバイス LLM プロバイダ
/// P3A-REQ-004 準拠
///
/// 推論バックエンドの優先順位:
/// 1. Apple Intelligence Foundation Models（iOS 26+, A17 Pro 以降, 8GB+ RAM）
/// 2. フォールバック: MockLLMProvider（非対応デバイス・環境）
///
/// Apple Intelligence 利用時:
/// - `FoundationModels.LanguageModelSession` でプロンプト実行
/// - OS 内蔵モデルのためダウンロード不要
/// - プロバイダ種別: `.onDeviceAppleIntelligence`
///
/// フォールバック時:
/// - MockLLMProvider による固定レスポンス（将来 llama.cpp に差し替え予定）
/// - プロバイダ種別: `.onDeviceLlamaCpp`
public final class OnDeviceLLMProvider: @unchecked Sendable {

    // MARK: - Properties

    /// デバイス能力チェッカー
    private let capabilityChecker: DeviceCapabilityChecker

    /// モデル管理
    private let modelManager: LLMModelManager

    /// レスポンスパーサー
    private let responseParser: LLMResponseParser

    /// フォールバック用モック（Apple Intelligence 非対応環境で使用）
    private let mockProvider: MockLLMProvider

    /// モデルがロード済みか
    private var isModelLoaded: Bool = false

    /// メモリ排他制御用ロック
    private let lock = NSLock()

    /// プロバイダ種別（Apple Intelligence 利用可否に応じて動的に決定）
    public var currentProviderType: LLMProviderType {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), capabilityChecker.supportsAppleIntelligence {
            return .onDeviceAppleIntelligence
        }
        #endif
        return .onDeviceLlamaCpp
    }

    /// 最大入力文字数
    /// Apple Intelligence Foundation Models: 4096トークン対応（日本語約3000文字）
    /// llama.cpp (Phi-3-mini): ~650トークン（日本語約500文字）
    /// 現在はApple Intelligence優先のため3000文字に設定
    public let maxInputCharacters: Int = 3000

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

        // 3. プロンプト構築（文体指示を含む）
        let prompt = PromptTemplate.onDeviceSimple.buildUserPrompt(text: request.text, customDictionary: request.customDictionary, style: request.writingStyle)
        logger.debug("プロンプト構築完了: \(prompt.prefix(100))...")
        #if DEBUG
        if !request.customDictionary.isEmpty {
            print("[LLM] カスタム辞書をプロンプトに注入: \(request.customDictionary.prefix(10))")
        } else {
            print("[LLM] カスタム辞書: なし")
        }
        #endif

        // 4. 推論実行
        let startTime = CFAbsoluteTimeGetCurrent()
        var response = try await internalProcess(request, prompt: prompt)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        logger.info("LLM推論完了: \(Int(elapsed * 1000))ms")

        // 5. カスタム辞書による後処理（LLMが修正しきれなかった固有名詞を置換）
        if !request.customDictionary.isEmpty {
            response = applyDictionaryPostProcessing(response, dictionary: request.customDictionary)
        }

        return response
    }

    /// プロバイダの利用可否チェック
    ///
    /// Apple Intelligence 利用可能時: 常に true（OS 内蔵モデル）
    /// フォールバック時: デバイスが A16+ / 6GB+ であれば true
    public func isAvailable() async -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), capabilityChecker.supportsAppleIntelligence {
            return true
        }
        #endif
        return capabilityChecker.supportsOnDeviceLLM
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

    // MARK: - カスタム辞書による後処理

    /// LLMが修正しきれなかった固有名詞をカスタム辞書で置換する
    ///
    /// カスタム辞書の各語句について、テキスト中に「読みが似ているが異なる漢字」で
    /// 書かれている箇所を検出し、正しい表記に置換する。
    ///
    /// 方針: 辞書の各語句のひらがな読みを生成し、テキスト中の同じ読みの箇所を置換
    /// ただしオンデバイスで読み変換は重いため、よくある誤変換パターンをハードコードで対応
    private func applyDictionaryPostProcessing(_ response: LLMResponse, dictionary: [String]) -> LLMResponse {
        guard let summary = response.summary else { return response }
        var text = summary.brief
        var title = summary.title

        // 辞書の各語句がテキストに含まれていない場合、
        // 似た文字列（部分一致）を辞書の正しい表記に置換
        for word in dictionary {
            // 既にテキストに含まれていればスキップ
            if text.contains(word) { continue }

            // 辞書語句の各文字を含む別の単語を探して置換
            // 例: 辞書「城間」→テキスト中の「城島」「城区」「城待」を「城間」に
            if word.count >= 2 {
                let firstChar = String(word.prefix(1))
                // テキスト中に先頭文字が含まれ、かつ辞書語句と同じ長さの別表記を検出
                let wordLen = word.count
                var searchStart = text.startIndex
                while let range = text.range(of: firstChar, range: searchStart..<text.endIndex) {
                    let endIdx = text.index(range.lowerBound, offsetBy: wordLen, limitedBy: text.endIndex) ?? text.endIndex
                    if endIdx <= text.endIndex {
                        let candidate = String(text[range.lowerBound..<endIdx])
                        // 先頭文字が同じで、長さが同じで、辞書語句と異なる場合に置換
                        if candidate != word && candidate.count == word.count {
                            text = text.replacingOccurrences(of: candidate, with: word)
                            title = title.replacingOccurrences(of: candidate, with: word)
                            break
                        }
                    }
                    searchStart = range.upperBound
                }
            }
        }

        let updatedSummary = LLMSummaryResult(
            title: title,
            brief: text,
            keyPoints: summary.keyPoints
        )

        return LLMResponse(
            summary: updatedSummary,
            tags: response.tags,
            processingTimeMs: response.processingTimeMs,
            provider: response.provider
        )
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
    /// Apple Intelligence 利用時: OS 内蔵モデルのためロード不要（即座に準備完了）
    /// フォールバック時: メモリチェック後にモック準備
    private func loadModel() async throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isModelLoaded else { return }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), capabilityChecker.supportsAppleIntelligence {
            // Apple Intelligence はOS内蔵モデルのため、モデルロード不要
            isModelLoaded = true
            logger.info("Apple Intelligence Foundation Models 準備完了")
            return
        }
        #endif

        // フォールバック: メモリ余裕チェック
        if !capabilityChecker.hasMemoryHeadroomForLLM {
            logger.error("LLMモデルロードに必要なメモリが不足しています")
            throw LLMError.memoryInsufficient
        }

        isModelLoaded = true
        logger.info("LLMモデルをロードしました (フォールバック: モック)")
    }

    /// 内部推論実行
    ///
    /// Apple Intelligence 利用可能時: FoundationModels API で推論実行
    /// フォールバック時: MockLLMProvider に委譲
    private func internalProcess(_ request: LLMRequest, prompt: String) async throws -> LLMResponse {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let aiSupported = capabilityChecker.supportsAppleIntelligence
            logger.info("[LLM] canImport(FoundationModels)=true, supportsAppleIntelligence=\(aiSupported), chip=\(self.capabilityChecker.chipGeneration), mem=\(self.capabilityChecker.totalMemoryGB)GB")
            if aiSupported {
                return try await processWithFoundationModels(request, prompt: prompt)
            }
        }
        #else
        logger.info("[LLM] canImport(FoundationModels)=false → Mockフォールバック")
        #endif
        // フォールバック: MockLLMProvider を使用
        logger.info("[LLM] Mockフォールバックを使用")
        return try await mockProvider.process(request)
    }

    // MARK: - Apple Intelligence Foundation Models

    #if canImport(FoundationModels)
    /// Apple Intelligence Foundation Models API を使用して推論を実行する
    ///
    /// - Parameters:
    ///   - request: LLM処理リクエスト
    ///   - prompt: 構築済みプロンプト文字列
    /// - Returns: パース済みの LLMResponse
    /// - Throws: `LLMError.processingFailed` 推論エラー時、`LLMError.invalidOutput` パース失敗時
    @available(iOS 26.0, macOS 26.0, *)
    private func processWithFoundationModels(_ request: LLMRequest, prompt: String) async throws -> LLMResponse {
        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let responseText = response.content
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let processingTimeMs = Int(elapsed * 1000)

            logger.info("Apple Intelligence 推論完了: \(processingTimeMs)ms, 出力: \(responseText.prefix(100))...")

            return try responseParser.parse(
                responseText,
                processingTimeMs: processingTimeMs,
                provider: .onDeviceAppleIntelligence
            )
        } catch let error as LLMError {
            throw error
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            logger.error("Apple Intelligence 推論エラー (\(Int(elapsed * 1000))ms): \(error.localizedDescription)")
            throw LLMError.processingFailed(error.localizedDescription)
        }
    }
    #endif
}
