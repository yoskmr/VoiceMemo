import XCTest
import SwiftData
import Domain
@testable import InfraStorage

/// T14: AI処理キューテスト
/// AIProcessingTaskModel の状態遷移と AIQuotaRepository 連携をテスト
final class AIProcessingQueueTests: XCTestCase {

    var container: ModelContainer!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! ModelContainerConfiguration.create(inMemory: true)
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    // MARK: - タスク作成テスト

    @MainActor
    func test_タスク作成_初期ステータスはqueued() throws {
        let memoId = UUID()
        let task = AIProcessingTaskModel(memoId: memoId)
        container.mainContext.insert(task)
        try container.mainContext.save()

        let descriptor = FetchDescriptor<AIProcessingTaskModel>()
        let tasks = try container.mainContext.fetch(descriptor)

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.status, AIProcessingTaskModel.Status.queued)
        XCTAssertEqual(tasks.first?.memoId, memoId)
        XCTAssertEqual(tasks.first?.retryCount, 0)
        XCTAssertNil(tasks.first?.startedAt)
        XCTAssertNil(tasks.first?.completedAt)
    }

    // MARK: - ステータス遷移テスト: queued → processing → completed

    @MainActor
    func test_正常フロー_queued_processing_completed() throws {
        let memoId = UUID()
        let task = AIProcessingTaskModel(memoId: memoId)
        container.mainContext.insert(task)
        try container.mainContext.save()

        // queued → processing
        task.status = AIProcessingTaskModel.Status.processing
        task.startedAt = Date()
        try container.mainContext.save()

        XCTAssertEqual(task.status, AIProcessingTaskModel.Status.processing)
        XCTAssertNotNil(task.startedAt)

        // processing → completed
        task.status = AIProcessingTaskModel.Status.completed
        task.completedAt = Date()
        task.providerUsed = "on_device_llama_cpp"
        try container.mainContext.save()

        XCTAssertEqual(task.status, AIProcessingTaskModel.Status.completed)
        XCTAssertNotNil(task.completedAt)
        XCTAssertEqual(task.providerUsed, "on_device_llama_cpp")
    }

    // MARK: - ステータス遷移テスト: queued → processing → retrying → processing → completed

    @MainActor
    func test_リトライフロー_queued_processing_retrying_processing_completed() throws {
        let memoId = UUID()
        let task = AIProcessingTaskModel(memoId: memoId)
        container.mainContext.insert(task)
        try container.mainContext.save()

        // queued → processing
        task.status = AIProcessingTaskModel.Status.processing
        task.startedAt = Date()
        try container.mainContext.save()

        // processing → retrying (1回目)
        task.status = AIProcessingTaskModel.Status.retrying
        task.retryCount = 1
        try container.mainContext.save()

        XCTAssertEqual(task.status, AIProcessingTaskModel.Status.retrying)
        XCTAssertEqual(task.retryCount, 1)

        // retrying → processing
        task.status = AIProcessingTaskModel.Status.processing
        try container.mainContext.save()

        // processing → completed
        task.status = AIProcessingTaskModel.Status.completed
        task.completedAt = Date()
        try container.mainContext.save()

        XCTAssertEqual(task.status, AIProcessingTaskModel.Status.completed)
        XCTAssertEqual(task.retryCount, 1)
    }

    // MARK: - ステータス遷移テスト: queued → processing → failed

    @MainActor
    func test_失敗フロー_queued_processing_failed() throws {
        let memoId = UUID()
        let task = AIProcessingTaskModel(memoId: memoId)
        container.mainContext.insert(task)
        try container.mainContext.save()

        // queued → processing
        task.status = AIProcessingTaskModel.Status.processing
        task.startedAt = Date()
        try container.mainContext.save()

        // processing → failed
        task.status = AIProcessingTaskModel.Status.failed
        task.errorMessage = "LLM推論に失敗しました"
        task.completedAt = Date()
        try container.mainContext.save()

        XCTAssertEqual(task.status, AIProcessingTaskModel.Status.failed)
        XCTAssertEqual(task.errorMessage, "LLM推論に失敗しました")
        XCTAssertNotNil(task.completedAt)
    }

    // MARK: - キャンセルテスト

    @MainActor
    func test_キャンセル_queued_cancelled() throws {
        let memoId = UUID()
        let task = AIProcessingTaskModel(memoId: memoId)
        container.mainContext.insert(task)
        try container.mainContext.save()

        // queued → cancelled
        task.status = AIProcessingTaskModel.Status.cancelled
        task.completedAt = Date()
        try container.mainContext.save()

        XCTAssertEqual(task.status, AIProcessingTaskModel.Status.cancelled)
        XCTAssertNotNil(task.completedAt)
    }

    @MainActor
    func test_キャンセル_processing_cancelled() throws {
        let memoId = UUID()
        let task = AIProcessingTaskModel(memoId: memoId)
        container.mainContext.insert(task)
        try container.mainContext.save()

        // queued → processing → cancelled
        task.status = AIProcessingTaskModel.Status.processing
        task.startedAt = Date()
        try container.mainContext.save()

        task.status = AIProcessingTaskModel.Status.cancelled
        task.completedAt = Date()
        try container.mainContext.save()

        XCTAssertEqual(task.status, AIProcessingTaskModel.Status.cancelled)
    }

    // MARK: - リトライ上限テスト

    @MainActor
    func test_リトライ上限到達_retrying_failed() throws {
        let memoId = UUID()
        let task = AIProcessingTaskModel(memoId: memoId, maxRetries: 2)
        container.mainContext.insert(task)
        try container.mainContext.save()

        // 1回目のリトライ
        task.status = AIProcessingTaskModel.Status.processing
        task.startedAt = Date()
        try container.mainContext.save()

        task.status = AIProcessingTaskModel.Status.retrying
        task.retryCount = 1
        try container.mainContext.save()

        // 2回目のリトライ
        task.status = AIProcessingTaskModel.Status.processing
        try container.mainContext.save()

        task.status = AIProcessingTaskModel.Status.retrying
        task.retryCount = 2
        try container.mainContext.save()

        // maxRetries 到達 → failed
        XCTAssertEqual(task.retryCount, task.maxRetries)

        task.status = AIProcessingTaskModel.Status.failed
        task.errorMessage = "リトライ上限に到達"
        task.completedAt = Date()
        try container.mainContext.save()

        XCTAssertEqual(task.status, AIProcessingTaskModel.Status.failed)
        XCTAssertEqual(task.retryCount, 2)
    }

    // MARK: - 複数タスクの管理

    @MainActor
    func test_複数メモのタスク_独立して管理される() throws {
        let memoId1 = UUID()
        let memoId2 = UUID()

        let task1 = AIProcessingTaskModel(memoId: memoId1)
        let task2 = AIProcessingTaskModel(memoId: memoId2)
        container.mainContext.insert(task1)
        container.mainContext.insert(task2)
        try container.mainContext.save()

        // task1 を completed にする
        task1.status = AIProcessingTaskModel.Status.completed
        task1.completedAt = Date()
        try container.mainContext.save()

        // task2 は queued のまま
        XCTAssertEqual(task1.status, AIProcessingTaskModel.Status.completed)
        XCTAssertEqual(task2.status, AIProcessingTaskModel.Status.queued)
    }

    @MainActor
    func test_同一メモの複数タスク_最新のタスクが取得できる() throws {
        let memoId = UUID()

        let task1 = AIProcessingTaskModel(
            memoId: memoId,
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        task1.status = AIProcessingTaskModel.Status.failed
        container.mainContext.insert(task1)

        let task2 = AIProcessingTaskModel(
            memoId: memoId,
            createdAt: Date(timeIntervalSince1970: 2000)
        )
        container.mainContext.insert(task2)
        try container.mainContext.save()

        // createdAt 降順で最新を取得
        let descriptor = FetchDescriptor<AIProcessingTaskModel>(
            predicate: #Predicate { $0.memoId == memoId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let latest = try container.mainContext.fetch(descriptor).first

        XCTAssertEqual(latest?.status, AIProcessingTaskModel.Status.queued)
    }

    // MARK: - 優先度テスト

    @MainActor
    func test_タスク優先度_デフォルトは1() throws {
        let task = AIProcessingTaskModel(memoId: UUID())
        XCTAssertEqual(task.priority, 1)
    }

    @MainActor
    func test_タスク優先度_カスタム値() throws {
        let task = AIProcessingTaskModel(memoId: UUID(), priority: 0)
        XCTAssertEqual(task.priority, 0)
    }

    // MARK: - 月次クォータ連携テスト

    @MainActor
    func test_クォータ連携_処理完了後に使用記録が増える() async throws {
        let repository = AIQuotaRepository(modelContainer: container, monthlyLimit: 15)

        // 初期状態: 使用回数0
        let beforeUsage = try await repository.currentUsage()
        XCTAssertEqual(beforeUsage, 0)

        // タスク完了を模擬してクォータ記録
        let memoId = UUID()
        let task = AIProcessingTaskModel(memoId: memoId)
        container.mainContext.insert(task)
        try container.mainContext.save()

        task.status = AIProcessingTaskModel.Status.completed
        task.completedAt = Date()
        try container.mainContext.save()

        // クォータ記録
        try await repository.recordUsage()

        let afterUsage = try await repository.currentUsage()
        XCTAssertEqual(afterUsage, 1)
    }

    @MainActor
    func test_クォータ連携_月次上限到達でcanProcessがfalse() async throws {
        let repository = AIQuotaRepository(modelContainer: container, monthlyLimit: 3)

        // 3件使用記録
        for _ in 0..<3 {
            try await repository.recordUsage()
        }

        let canProcess = try await repository.canProcess()
        XCTAssertFalse(canProcess)
    }

    @MainActor
    func test_クォータ連携_失敗タスクは使用回数にカウントしない() async throws {
        let repository = AIQuotaRepository(modelContainer: container, monthlyLimit: 15)

        // タスクが失敗したケースではrecordUsageを呼ばないため、
        // 使用回数は増えない
        let memoId = UUID()
        let task = AIProcessingTaskModel(memoId: memoId)
        container.mainContext.insert(task)
        try container.mainContext.save()

        task.status = AIProcessingTaskModel.Status.failed
        task.errorMessage = "テストエラー"
        try container.mainContext.save()

        // recordUsage は呼ばない（失敗時はクォータ消費しない仕様）
        let usage = try await repository.currentUsage()
        XCTAssertEqual(usage, 0)
    }

    // MARK: - ステータス文字列定数テスト

    func test_ステータス定数_値が正しい() {
        XCTAssertEqual(AIProcessingTaskModel.Status.queued, "queued")
        XCTAssertEqual(AIProcessingTaskModel.Status.processing, "processing")
        XCTAssertEqual(AIProcessingTaskModel.Status.completed, "completed")
        XCTAssertEqual(AIProcessingTaskModel.Status.failed, "failed")
        XCTAssertEqual(AIProcessingTaskModel.Status.cancelled, "cancelled")
        XCTAssertEqual(AIProcessingTaskModel.Status.retrying, "retrying")
    }
}
