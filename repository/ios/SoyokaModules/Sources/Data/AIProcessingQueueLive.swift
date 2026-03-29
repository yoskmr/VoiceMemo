import Dependencies
import Domain
import Foundation
import InfraStorage
import os.log
import SwiftData

private let logger = Logger(subsystem: "app.soyoka", category: "AIProcessingQueueLive")

/// AIProcessingQueueClient の Live 実装
/// 設計書 DES-PHASE3A-001 セクション2.1, 2.2 準拠
///
/// 責務:
/// - AI処理タスクのキュー管理（SwiftData永続化）
/// - LLMProvider呼び出し → 結果のSwiftData保存
/// - AIQuotaClient との連携（月次制限チェック・使用記録）
/// - ステータス変化の AsyncStream 通知
/// - メモリ排他制御（STTアンロード → LLMロード → 推論 → LLMアンロード）
///
/// 処理フロー:
/// enqueueProcessing → canProcess確認 → LLM推論 → 結果保存 → recordUsage → ステータス通知
public final class AIProcessingQueueLive: @unchecked Sendable {

    // MARK: - Properties

    private let modelContainer: ModelContainer
    private let llmProvider: LLMProviderClient
    private let aiQuota: AIQuotaClient
    private let voiceMemoRepository: VoiceMemoRepositoryClient
    private let customDictionaryClient: CustomDictionaryClient
    private let fts5IndexManager: FTS5IndexManagerClient
    private let subscriptionClient: SubscriptionClient

    /// メモID → ステータス通知用の continuation マップ
    private var statusContinuations: [UUID: [UUID: AsyncStream<AIProcessingStatus>.Continuation]] = [:]

    /// 排他制御用ロック
    private let lock = NSLock()

    /// 処理中のタスク（キャンセル用）
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Initialization

    public init(
        modelContainer: ModelContainer,
        llmProvider: LLMProviderClient,
        aiQuota: AIQuotaClient,
        voiceMemoRepository: VoiceMemoRepositoryClient,
        customDictionaryClient: CustomDictionaryClient = CustomDictionaryClient(
            loadEntries: { [] }, addEntry: { _ in }, deleteEntry: { _ in }, getContextualStrings: { [] }
        ),
        fts5IndexManager: FTS5IndexManagerClient = FTS5IndexManagerClient(
            createIndex: {}, upsertIndex: { _, _, _, _, _ in }, removeIndex: { _ in },
            search: { _ in [] }, searchWithSnippets: { _, _, _ in [] }
        ),
        subscriptionClient: SubscriptionClient = SubscriptionClient(
            fetchProducts: { [] },
            purchase: { _ in .cancelled },
            currentSubscription: { .free },
            observeTransactionUpdates: { AsyncStream { $0.finish() } },
            restorePurchases: {}
        )
    ) {
        self.modelContainer = modelContainer
        self.llmProvider = llmProvider
        self.aiQuota = aiQuota
        self.voiceMemoRepository = voiceMemoRepository
        self.customDictionaryClient = customDictionaryClient
        self.fts5IndexManager = fts5IndexManager
        self.subscriptionClient = subscriptionClient
    }

    @MainActor
    private var context: ModelContext {
        modelContainer.mainContext
    }

    // MARK: - Public API

    /// メモIDを指定してAI処理をキューに追加し、処理を開始する
    ///
    /// 処理フロー:
    /// 1. SwiftDataにタスクを永続化（status: queued）
    /// 2. AIQuotaClient で月次制限チェック
    /// 3. LLMProviderClient で推論実行
    /// 4. 結果を VoiceMemoEntity に反映（AISummary + Tags）
    /// 5. AIQuotaClient に使用記録
    ///
    /// - Parameter memoId: 処理対象のメモID
    /// - Throws: 月次制限超過、メモ未発見等のエラー
    public func enqueueProcessing(_ memoId: UUID) async throws {
        // 1. タスクをSwiftDataに永続化
        let taskId = UUID()
        try await createTask(id: taskId, memoId: memoId)
        logger.info("AI処理タスクをキューに追加: memoId=\(memoId), taskId=\(taskId)")

        // ステータス通知: queued
        notifyStatus(memoId: memoId, status: .queued)

        // 2. バックグラウンドで処理を開始
        let task = Task { [weak self] in
            guard let self else { return }
            await self.processTask(taskId: taskId, memoId: memoId)
        }

        registerActiveTask(memoId: memoId, task: task)
    }

    /// メモIDの処理ステータスを監視する AsyncStream
    ///
    /// - Parameter memoId: 監視対象のメモID
    /// - Returns: ステータス変化を通知する AsyncStream
    public func observeStatus(_ memoId: UUID) -> AsyncStream<AIProcessingStatus> {
        AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            let streamId = UUID()

            self.lock.lock()
            if self.statusContinuations[memoId] == nil {
                self.statusContinuations[memoId] = [:]
            }
            self.statusContinuations[memoId]?[streamId] = continuation
            self.lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.statusContinuations[memoId]?[streamId] = nil
                if self?.statusContinuations[memoId]?.isEmpty == true {
                    self?.statusContinuations[memoId] = nil
                }
                self?.lock.unlock()
            }
        }
    }

    /// メモIDの処理をキャンセルする
    ///
    /// - Parameter memoId: キャンセル対象のメモID
    public func cancelProcessing(_ memoId: UUID) async throws {
        // 実行中のタスクをキャンセル
        let task = removeActiveTask(memoId: memoId)
        task?.cancel()

        // SwiftData のステータスを更新
        try await updateTaskStatus(memoId: memoId, status: AIProcessingTaskModel.Status.cancelled)

        // ステータス通知
        notifyStatus(memoId: memoId, status: .failed(.processingFailed("キャンセルされました")))

        // LLMモデルをアンロード
        await llmProvider.unloadModel()

        logger.info("AI処理をキャンセル: memoId=\(memoId)")
    }

    // MARK: - LLMProviderClient 変換

    /// TCA Dependency として使用するための AIProcessingQueueClient を生成する
    public func toClient() -> AIProcessingQueueClient {
        AIProcessingQueueClient(
            enqueueProcessing: { [self] memoId in
                try await self.enqueueProcessing(memoId)
            },
            observeStatus: { [self] memoId in
                self.observeStatus(memoId)
            },
            cancelProcessing: { [self] memoId in
                try await self.cancelProcessing(memoId)
            }
        )
    }

    // MARK: - Internal Processing

    /// タスクの実処理を行う
    private func processTask(taskId: UUID, memoId: UUID) async {
        do {
            // キャンセルチェック
            try Task.checkCancellation()

            // ステータス通知: processing (0%)
            notifyStatus(memoId: memoId, status: .processing(progress: 0.0, description: "AI処理を準備中..."))

            // サブスクリプション状態の確認（Proプランはクォータ制限をスキップ）
            let currentSubscriptionState = await subscriptionClient.currentSubscription()
            let isPro: Bool
            if case .pro = currentSubscriptionState {
                isPro = true
            } else {
                isPro = false
            }

            // 月次制限チェック（Proプランはスキップ）
            if !isPro {
                let canProcess = try await aiQuota.canProcess()
                guard canProcess else {
                    let remaining = try await aiQuota.remainingCount()
                    let resetDate = aiQuota.nextResetDate()
                    try await updateTaskStatus(
                        memoId: memoId,
                        status: AIProcessingTaskModel.Status.failed,
                        errorMessage: "月次制限に到達しました"
                    )
                    notifyStatus(
                        memoId: memoId,
                        status: .failed(.quotaExceeded(remaining: remaining, resetDate: resetDate))
                    )
                    logger.warning("月次制限超過: memoId=\(memoId)")
                    return
                }
            }

            // キャンセルチェック
            try Task.checkCancellation()

            // メモの文字起こしテキストを取得
            let memo = try await voiceMemoRepository.fetchMemoDetail(memoId)
            guard let transcriptionText = memo.transcription?.fullText,
                  !transcriptionText.isEmpty else {
                try await updateTaskStatus(
                    memoId: memoId,
                    status: AIProcessingTaskModel.Status.failed,
                    errorMessage: "文字起こしテキストがありません"
                )
                notifyStatus(
                    memoId: memoId,
                    status: .failed(.processingFailed("文字起こしテキストがありません"))
                )
                logger.error("文字起こしテキスト未発見: memoId=\(memoId)")
                return
            }

            // ステータス通知: processing (30%)
            notifyStatus(memoId: memoId, status: .processing(progress: 0.3, description: "LLMモデルを準備中..."))

            // SwiftData ステータス更新: processing
            try await updateTaskStatus(memoId: memoId, status: AIProcessingTaskModel.Status.processing)

            // キャンセルチェック
            try Task.checkCancellation()

            // カスタム辞書: ルールベース後処理でSTTテキストを補正してからLLMに渡す
            // LLMプロンプトへの辞書注入は無効化（過剰適用でテキスト破壊の問題あり）
            let dictionaryPairs = (try? await customDictionaryClient.getDictionaryPairs()) ?? []
            let postProcessor = DictionaryPostProcessor()
            let correctedText = postProcessor.apply(text: transcriptionText, entries: dictionaryPairs)

            // ユーザーが選択した文体を取得
            let writingStyle = WritingStyle.current

            var tasks: Set<LLMTask> = [.summarize, .tagging]

            #if DEBUG
            // デバッグメニュー: 感情分析強制ON（Pro でなくても実行）
            if UserDefaults.standard.bool(forKey: "debug_forceSentimentAnalysis") {
                tasks.insert(.sentimentAnalysis)
            }
            #endif

            let request = LLMRequest(
                text: correctedText,
                tasks: tasks,
                customDictionary: [],
                writingStyle: writingStyle
            )

            // ステータス通知: processing (50%)
            notifyStatus(memoId: memoId, status: .processing(progress: 0.5, description: "きおくを整理中..."))

            // LLM推論実行（リトライ付き）
            let response = try await executeWithRetry(
                request: request,
                taskId: taskId,
                memoId: memoId,
                maxRetries: 2
            )

            // キャンセルチェック
            try Task.checkCancellation()

            // ステータス通知: processing (80%)
            notifyStatus(memoId: memoId, status: .processing(progress: 0.8, description: "結果を保存中..."))

            // 結果を VoiceMemoEntity に反映
            try await saveResults(memoId: memoId, response: response)

            // 使用記録（Proプランはクォータ消費なし）
            if !isPro {
                try await aiQuota.recordUsage()
            }

            // SwiftData ステータス更新: completed
            try await updateTaskStatus(
                memoId: memoId,
                status: AIProcessingTaskModel.Status.completed,
                providerUsed: response.provider.rawValue
            )

            // LLMモデルをアンロード（メモリ解放）
            await llmProvider.unloadModel()

            // ステータス通知: completed
            let isOnDevice = response.provider == .onDeviceLlamaCpp
                || response.provider == .onDeviceAppleIntelligence
            notifyStatus(memoId: memoId, status: .completed(isOnDevice: isOnDevice))

            // FTS5インデックスにAI整理テキストを反映（検索でヒットするように）
            if let memo = try? await voiceMemoRepository.fetchByID(memoId) {
                try? fts5IndexManager.upsertIndex(
                    memoId.uuidString,
                    memo.title,
                    memo.transcription?.fullText ?? "",
                    memo.aiSummary?.summaryText ?? "",
                    memo.tags.map(\.name).joined(separator: " ")
                )
            }

            logger.info("AI処理完了: memoId=\(memoId), provider=\(response.provider.rawValue), time=\(response.processingTimeMs)ms")

        } catch is CancellationError {
            logger.info("AI処理がキャンセルされました: memoId=\(memoId)")
        } catch {
            logger.error("AI処理失敗: memoId=\(memoId), error=\(error.localizedDescription)")

            // LLMモデルをアンロード（エラー時もメモリ解放）
            await llmProvider.unloadModel()

            try? await updateTaskStatus(
                memoId: memoId,
                status: AIProcessingTaskModel.Status.failed,
                errorMessage: error.localizedDescription
            )
            notifyStatus(
                memoId: memoId,
                status: .failed(.processingFailed(error.localizedDescription))
            )
        }

        // activeTasks からクリーンアップ
        cleanupActiveTask(memoId: memoId)
    }

    /// リトライ付きLLM推論実行
    ///
    /// invalidOutput エラーの場合のみ自動リトライする（最大2回）
    private func executeWithRetry(
        request: LLMRequest,
        taskId: UUID,
        memoId: UUID,
        maxRetries: Int
    ) async throws -> LLMResponse {
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                try Task.checkCancellation()
                let response = try await llmProvider.process(request)
                return response
            } catch let error as LLMError where error == .invalidOutput && attempt < maxRetries {
                lastError = error
                logger.warning("LLM出力パース失敗 (リトライ \(attempt + 1)/\(maxRetries)): memoId=\(memoId)")

                // リトライステータス更新
                try await updateTaskRetryCount(memoId: memoId, retryCount: attempt + 1)
                notifyStatus(
                    memoId: memoId,
                    status: .processing(
                        progress: 0.5,
                        description: "再整理中... (リトライ\(attempt + 1)/\(maxRetries))"
                    )
                )
            } catch {
                throw error
            }
        }

        throw lastError ?? LLMError.invalidOutput
    }

    // MARK: - SwiftData Operations

    /// タスクを SwiftData に作成
    private func createTask(id: UUID, memoId: UUID) async throws {
        try await MainActor.run {
            let task = AIProcessingTaskModel(
                id: id,
                memoId: memoId,
                status: AIProcessingTaskModel.Status.queued
            )
            context.insert(task)
            try context.save()
        }
    }

    /// タスクのステータスを更新
    private func updateTaskStatus(
        memoId: UUID,
        status: String,
        errorMessage: String? = nil,
        providerUsed: String? = nil
    ) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<AIProcessingTaskModel>(
                predicate: #Predicate { $0.memoId == memoId },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            guard let task = try context.fetch(descriptor).first else { return }

            task.status = status
            if let errorMessage {
                task.errorMessage = errorMessage
            }
            if let providerUsed {
                task.providerUsed = providerUsed
            }

            if status == AIProcessingTaskModel.Status.processing {
                task.startedAt = Date()
            }
            if status == AIProcessingTaskModel.Status.completed
                || status == AIProcessingTaskModel.Status.failed
                || status == AIProcessingTaskModel.Status.cancelled
            {
                task.completedAt = Date()
            }

            try context.save()
        }
    }

    /// タスクのリトライ回数を更新
    private func updateTaskRetryCount(memoId: UUID, retryCount: Int) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<AIProcessingTaskModel>(
                predicate: #Predicate { $0.memoId == memoId },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            guard let task = try context.fetch(descriptor).first else { return }

            task.retryCount = retryCount
            task.status = AIProcessingTaskModel.Status.retrying
            try context.save()
        }
    }

    /// LLMレスポンスをメモエンティティに保存する
    ///
    /// AISummary と Tags を VoiceMemoModel に反映する
    private func saveResults(memoId: UUID, response: LLMResponse) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<VoiceMemoModel>(
                predicate: #Predicate { $0.id == memoId }
            )
            guard let memoModel = try context.fetch(descriptor).first else {
                logger.error("メモが見つかりません: \(memoId)")
                return
            }

            // AISummary の保存
            if let summaryResult = response.summary {
                // 既存の AISummary があれば更新、なければ新規作成
                if let existingSummary = memoModel.aiSummary {
                    existingSummary.title = summaryResult.title
                    existingSummary.summaryText = summaryResult.brief
                    existingSummary.keyPoints = summaryResult.keyPoints
                    existingSummary.providerType = response.provider
                    existingSummary.isOnDevice = response.provider == .onDeviceLlamaCpp
                        || response.provider == .onDeviceAppleIntelligence
                    existingSummary.generatedAt = Date()
                } else {
                    let summaryModel = AISummaryModel(
                        title: summaryResult.title,
                        summaryText: summaryResult.brief,
                        keyPoints: summaryResult.keyPoints,
                        providerType: response.provider,
                        isOnDevice: response.provider == .onDeviceLlamaCpp
                            || response.provider == .onDeviceAppleIntelligence,
                        generatedAt: Date()
                    )
                    summaryModel.memo = memoModel
                    context.insert(summaryModel)
                }

                // メモのタイトルも更新（AI生成タイトル）
                // 再生成時もタイトルを上書きする（ユーザー要望）
                memoModel.title = summaryResult.title
            }

            // EmotionAnalysis の保存（感情分析オプトイン時のみ結果が存在）
            if let sentimentResult = response.sentiment {
                let emotionScoresDict: [String: Double] = Dictionary(
                    uniqueKeysWithValues: sentimentResult.scores.map { ($0.key.rawValue, $0.value) }
                )
                let evidenceArray: [[String: String]] = sentimentResult.evidence.map { ev in
                    ["text": ev.text, "emotion": ev.emotion.rawValue]
                }

                if let existingAnalysis = memoModel.emotionAnalysis {
                    existingAnalysis.primaryEmotion = sentimentResult.primary
                    existingAnalysis.confidence = sentimentResult.scores[sentimentResult.primary] ?? 0.0
                    existingAnalysis.emotionScores = emotionScoresDict
                    existingAnalysis.evidence = evidenceArray
                    existingAnalysis.analyzedAt = Date()
                } else {
                    let analysisModel = EmotionAnalysisModel(
                        primaryEmotion: sentimentResult.primary,
                        confidence: sentimentResult.scores[sentimentResult.primary] ?? 0.0,
                        emotionScores: emotionScoresDict,
                        evidence: evidenceArray,
                        analyzedAt: Date()
                    )
                    analysisModel.memo = memoModel
                    context.insert(analysisModel)
                }
            }

            // Tags の保存
            for tagResult in response.tags {
                let tagName = tagResult.label
                // 同名タグの重複チェック
                let tagDescriptor = FetchDescriptor<TagModel>(
                    predicate: #Predicate { $0.name == tagName }
                )
                let existingTag = try context.fetch(tagDescriptor).first

                if let existingTag {
                    // 既存タグをメモに関連付け（未関連付けの場合のみ）
                    if !memoModel.tags.contains(where: { $0.id == existingTag.id }) {
                        memoModel.tags.append(existingTag)
                    }
                } else {
                    // 新規タグ作成
                    let tagModel = TagModel(
                        name: tagResult.label,
                        source: .ai
                    )
                    context.insert(tagModel)
                    memoModel.tags.append(tagModel)
                }
            }

            memoModel.updatedAt = Date()
            try context.save()
        }

        logger.info("AI処理結果を保存: memoId=\(memoId)")
    }

    // MARK: - Thread-Safe State Access

    /// activeTasks にタスクを登録する（同期メソッド: NSLock を async コンテキストから分離）
    private func registerActiveTask(memoId: UUID, task: Task<Void, Never>) {
        lock.lock()
        activeTasks[memoId] = task
        lock.unlock()
    }

    /// activeTasks からタスクを取り出して削除する（同期メソッド）
    private func removeActiveTask(memoId: UUID) -> Task<Void, Never>? {
        lock.lock()
        let task = activeTasks.removeValue(forKey: memoId)
        lock.unlock()
        return task
    }

    /// activeTasks をクリーンアップする（同期メソッド）
    private func cleanupActiveTask(memoId: UUID) {
        lock.lock()
        activeTasks.removeValue(forKey: memoId)
        lock.unlock()
    }

    // MARK: - Status Notification

    /// ステータス変化を全リスナーに通知
    private func notifyStatus(memoId: UUID, status: AIProcessingStatus) {
        lock.lock()
        let continuations = statusContinuations[memoId]
        lock.unlock()

        guard let continuations else { return }

        for (_, continuation) in continuations {
            continuation.yield(status)
        }
    }
}
