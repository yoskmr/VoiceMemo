import Domain
import Foundation
import os.log

private let logger = Logger(subsystem: "app.soyoka", category: "AIProcessingQueue")

/// AI処理キュー（actor ベース実装）
///
/// 統合仕様書 INT-SPEC-001 セクション2.1, 2.2 準拠。
/// 録音完了後のバックグラウンドAI処理（要約・タグ生成・感情分析）をキュー管理する。
///
/// 感情分析はオプトイン制:
/// - `UserDefaults.standard.bool(forKey: "sentimentAnalysisEnabled")` が true の場合のみ実行
/// - デフォルトは false（感情分析はスキップ）
///
/// クォータ管理:
/// - クラウドプロバイダ使用時のみ `quotaClient.recordUsage()` を呼び出す
/// - オンデバイス処理はクォータ消費なし
public actor AIProcessingQueue {

    // MARK: - Properties

    /// LLM プロバイダクライアント
    private let llmProvider: LLMProviderClient

    /// メモ取得用リポジトリクライアント
    private let voiceMemoRepository: VoiceMemoRepositoryClient

    /// AI処理クォータ管理クライアント
    private let quotaClient: AIQuotaClient

    /// メモID → ステータス通知用 continuation マップ
    /// キー: memoID, 値: (streamID → continuation)
    private var statusContinuations: [UUID: [UUID: AsyncStream<AIProcessingStatus>.Continuation]] = [:]

    /// 処理中の Task（キャンセル用）
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Initialization

    /// イニシャライザ
    /// - Parameters:
    ///   - llmProvider: LLM プロバイダクライアント
    ///   - voiceMemoRepository: メモ取得用リポジトリクライアント
    ///   - quotaClient: AI処理クォータ管理クライアント
    public init(
        llmProvider: LLMProviderClient,
        voiceMemoRepository: VoiceMemoRepositoryClient,
        quotaClient: AIQuotaClient
    ) {
        self.llmProvider = llmProvider
        self.voiceMemoRepository = voiceMemoRepository
        self.quotaClient = quotaClient
    }

    // MARK: - Public API

    /// メモIDを指定してAI処理をキューに追加し、処理を開始する
    ///
    /// 処理フロー:
    /// 1. ステータスを `.queued` に遷移
    /// 2. メモの文字起こしテキストを取得
    /// 3. 感情分析オプトイン設定を確認し、LLMRequest を構築
    /// 4. LLM プロバイダで処理を実行
    /// 5. 結果を保存（VoiceMemoRepository 経由）
    /// 6. クラウド利用時のみ quotaClient.recordUsage()
    /// 7. ステータスを `.completed(isOnDevice:)` に遷移
    ///
    /// - Parameter memoID: 処理対象のメモID
    /// - Throws: メモ未発見、クォータ超過等のエラー
    public func enqueueProcessing(_ memoID: UUID) async throws {
        // ステータス通知: queued
        notifyStatus(memoID: memoID, status: .queued)
        logger.info("AI処理をキューに追加: memoID=\(memoID)")

        // バックグラウンドで処理を開始
        let task = Task { [weak self] in
            guard let self else { return }
            await self.processTask(memoID: memoID)
        }

        activeTasks[memoID] = task
    }

    /// メモIDの処理ステータスを監視する AsyncStream
    ///
    /// 注意: actor 外部から同期的に呼び出せるよう nonisolated で実装。
    /// statusContinuations への書き込みは Task 内で actor-isolated なメソッドに委譲する。
    ///
    /// - Parameter memoID: 監視対象のメモID
    /// - Returns: ステータス変化を通知する AsyncStream
    nonisolated public func observeStatus(_ memoID: UUID) -> AsyncStream<AIProcessingStatus> {
        AsyncStream { continuation in
            let streamID = UUID()

            Task {
                await self.registerContinuation(memoID: memoID, streamID: streamID, continuation: continuation)
            }

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task {
                    await self.removeContinuation(memoID: memoID, streamID: streamID)
                }
            }
        }
    }

    /// メモIDの処理をキャンセルする
    ///
    /// - Parameter memoID: キャンセル対象のメモID
    public func cancelProcessing(_ memoID: UUID) async throws {
        // 実行中のタスクをキャンセル
        if let task = activeTasks.removeValue(forKey: memoID) {
            task.cancel()
        }

        // LLMモデルをアンロード（メモリ解放）
        await llmProvider.unloadModel()

        // ステータス通知
        notifyStatus(memoID: memoID, status: .failed(.processingFailed("キャンセルされました")))

        logger.info("AI処理をキャンセル: memoID=\(memoID)")
    }

    // MARK: - AIProcessingQueueClient 変換

    /// TCA Dependency として使用するための AIProcessingQueueClient を生成する
    nonisolated public func asClient() -> AIProcessingQueueClient {
        AIProcessingQueueClient(
            enqueueProcessing: { [self] memoID in
                try await self.enqueueProcessing(memoID)
            },
            observeStatus: { [self] memoID in
                self.observeStatus(memoID)
            },
            cancelProcessing: { [self] memoID in
                try await self.cancelProcessing(memoID)
            }
        )
    }

    // MARK: - Internal Processing

    /// タスクの実処理を行う
    private func processTask(memoID: UUID) async {
        do {
            try Task.checkCancellation()

            // ステータス通知: processing (0%)
            notifyStatus(memoID: memoID, status: .processing(progress: 0.0, description: "AI処理を準備中..."))

            // メモの文字起こしテキストを取得
            guard let memo = try await voiceMemoRepository.fetchByID(memoID),
                  let transcriptionText = memo.transcription?.fullText,
                  !transcriptionText.isEmpty else {
                notifyStatus(
                    memoID: memoID,
                    status: .failed(.processingFailed("文字起こしテキストがありません"))
                )
                logger.error("文字起こしテキスト未発見: memoID=\(memoID)")
                cleanupActiveTask(memoID: memoID)
                return
            }

            // ステータス通知: processing (30%)
            notifyStatus(memoID: memoID, status: .processing(progress: 0.3, description: "LLMモデルを準備中..."))

            try Task.checkCancellation()

            // 感情分析オプトイン設定の確認
            let sentimentEnabled = UserDefaults.standard.bool(forKey: "sentimentAnalysisEnabled")

            // LLMRequest 構築
            var tasks: Set<LLMTask> = [.summarize, .tagging]
            if sentimentEnabled {
                tasks.insert(.sentimentAnalysis)
            }

            let request = LLMRequest(
                text: transcriptionText,
                tasks: tasks
            )

            // ステータス通知: processing (50%)
            notifyStatus(memoID: memoID, status: .processing(progress: 0.5, description: "メモを整理中..."))

            // LLM推論実行
            let response = try await llmProvider.process(request)

            try Task.checkCancellation()

            // ステータス通知: processing (80%)
            notifyStatus(memoID: memoID, status: .processing(progress: 0.8, description: "結果を保存中..."))

            // 結果保存
            // TODO: VoiceMemoRepositoryClient にAI処理結果を一括保存するメソッドが必要
            // 現在は updateMemoText で部分的に対応。感情分析結果・タグの保存は別途対応が必要
            if let summary = response.summary {
                try await voiceMemoRepository.updateMemoText(
                    memoID,
                    summary.title,
                    summary.brief
                )
            }

            // クラウドプロバイダ使用時のみクォータ消費を記録
            let isOnDevice = response.provider == .onDeviceLlamaCpp
                || response.provider == .onDeviceAppleIntelligence
            if !isOnDevice {
                try await quotaClient.recordUsage()
                logger.info("クラウドAI使用を記録: memoID=\(memoID)")
            }

            // LLMモデルをアンロード（メモリ解放）
            await llmProvider.unloadModel()

            // ステータス通知: completed
            notifyStatus(memoID: memoID, status: .completed(isOnDevice: isOnDevice))

            logger.info("AI処理完了: memoID=\(memoID), provider=\(response.provider.rawValue), time=\(response.processingTimeMs)ms")

        } catch is CancellationError {
            logger.info("AI処理がキャンセルされました: memoID=\(memoID)")
        } catch {
            logger.error("AI処理失敗: memoID=\(memoID), error=\(error.localizedDescription)")

            // LLMモデルをアンロード（エラー時もメモリ解放）
            await llmProvider.unloadModel()

            notifyStatus(
                memoID: memoID,
                status: .failed(.processingFailed(error.localizedDescription))
            )
        }

        cleanupActiveTask(memoID: memoID)
    }

    // MARK: - Continuation Management

    /// continuation を登録する（actor-isolated）
    private func registerContinuation(
        memoID: UUID,
        streamID: UUID,
        continuation: AsyncStream<AIProcessingStatus>.Continuation
    ) {
        if statusContinuations[memoID] == nil {
            statusContinuations[memoID] = [:]
        }
        statusContinuations[memoID]?[streamID] = continuation
    }

    /// continuation を削除する（actor-isolated）
    private func removeContinuation(memoID: UUID, streamID: UUID) {
        statusContinuations[memoID]?[streamID] = nil
        if statusContinuations[memoID]?.isEmpty == true {
            statusContinuations[memoID] = nil
        }
    }

    // MARK: - Status Notification

    /// ステータス変化を全リスナーに通知
    private func notifyStatus(memoID: UUID, status: AIProcessingStatus) {
        guard let continuations = statusContinuations[memoID] else { return }

        for (_, continuation) in continuations {
            continuation.yield(status)
        }
    }

    // MARK: - Cleanup

    /// activeTasks をクリーンアップする
    private func cleanupActiveTask(memoID: UUID) {
        activeTasks.removeValue(forKey: memoID)
    }
}
