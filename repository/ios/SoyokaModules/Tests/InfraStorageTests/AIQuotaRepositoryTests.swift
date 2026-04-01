import XCTest
import SwiftData
import Domain
@testable import InfraStorage

/// AIQuotaRepository の統合テスト
/// Phase 3a: 月次AI処理回数の制限管理をテスト
final class AIQuotaRepositoryTests: XCTestCase {

    var container: ModelContainer!
    var repository: AIQuotaRepository!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! ModelContainerConfiguration.create(inMemory: true)
        repository = AIQuotaRepository(modelContainer: container, monthlyLimit: 10)
    }

    override func tearDown() {
        repository = nil
        container = nil
        super.tearDown()
    }

    // MARK: - canProcess テスト

    func test_canProcess_0件ならtrue() async throws {
        let result = try await repository.canProcess()
        XCTAssertTrue(result)
    }

    func test_canProcess_9件ならtrue() async throws {
        // 9件の使用記録を追加
        for _ in 0..<9 {
            try await repository.recordUsage()
        }

        let result = try await repository.canProcess()
        XCTAssertTrue(result)
    }

    func test_canProcess_10件ならfalse() async throws {
        // 10件の使用記録を追加
        for _ in 0..<10 {
            try await repository.recordUsage()
        }

        let result = try await repository.canProcess()
        XCTAssertFalse(result)
    }

    // MARK: - recordUsage テスト

    func test_recordUsage_カウント増加() async throws {
        let before = try await repository.currentUsage()
        XCTAssertEqual(before, 0)

        try await repository.recordUsage()
        let after = try await repository.currentUsage()
        XCTAssertEqual(after, 1)
    }

    func test_recordUsage_複数回記録() async throws {
        try await repository.recordUsage()
        try await repository.recordUsage()
        try await repository.recordUsage()

        let usage = try await repository.currentUsage()
        XCTAssertEqual(usage, 3)
    }

    // MARK: - 月跨ぎテスト

    @MainActor
    func test_月跨ぎ_先月のレコードは今月にカウントされない() async throws {
        let jst = TimeZone(identifier: "Asia/Tokyo")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jst

        // 先月の日付を生成
        let now = Date()
        guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) else {
            XCTFail("先月の日付を生成できませんでした")
            return
        }

        // 先月の記録を直接挿入
        let lastMonthRecord = AIQuotaRecordModel(processedAt: lastMonth)
        container.mainContext.insert(lastMonthRecord)
        try container.mainContext.save()

        // 今月の使用回数は0であること
        let usage = try await repository.currentUsage()
        XCTAssertEqual(usage, 0)

        // canProcessはtrueであること
        let canProcess = try await repository.canProcess()
        XCTAssertTrue(canProcess)
    }

    @MainActor
    func test_月跨ぎ_今月と先月のレコードが混在しても今月分のみカウント() async throws {
        let jst = TimeZone(identifier: "Asia/Tokyo")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jst

        // 先月の日付
        let now = Date()
        guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) else {
            XCTFail("先月の日付を生成できませんでした")
            return
        }

        // 先月の記録を5件追加
        for _ in 0..<5 {
            let record = AIQuotaRecordModel(processedAt: lastMonth)
            container.mainContext.insert(record)
        }
        try container.mainContext.save()

        // 今月の記録を3件追加
        for _ in 0..<3 {
            try await repository.recordUsage()
        }

        // 今月分のみ3件であること
        let usage = try await repository.currentUsage()
        XCTAssertEqual(usage, 3)
    }

    // MARK: - remainingCount テスト

    func test_remainingCount_0件なら10() async throws {
        let remaining = try await repository.remainingCount()
        XCTAssertEqual(remaining, 10)
    }

    func test_remainingCount_5件なら5() async throws {
        for _ in 0..<5 {
            try await repository.recordUsage()
        }

        let remaining = try await repository.remainingCount()
        XCTAssertEqual(remaining, 5)
    }

    func test_remainingCount_10件なら0() async throws {
        for _ in 0..<10 {
            try await repository.recordUsage()
        }

        let remaining = try await repository.remainingCount()
        XCTAssertEqual(remaining, 0)
    }

    // MARK: - monthlyLimit テスト

    func test_monthlyLimit_デフォルト10() {
        XCTAssertEqual(repository.monthlyLimit(), 10)
    }

    func test_monthlyLimit_カスタム値() {
        let customRepo = AIQuotaRepository(modelContainer: container, monthlyLimit: 30)
        XCTAssertEqual(customRepo.monthlyLimit(), 30)
    }

    // MARK: - nextResetDate テスト

    func test_nextResetDate_翌月1日0時JSTを返す() {
        let jst = TimeZone(identifier: "Asia/Tokyo")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jst

        let resetDate = repository.nextResetDate()
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: resetDate)

        // 翌月1日であること
        let nowComponents = calendar.dateComponents([.year, .month], from: Date())
        let expectedMonth: Int
        let expectedYear: Int
        if nowComponents.month == 12 {
            expectedMonth = 1
            expectedYear = (nowComponents.year ?? 2026) + 1
        } else {
            expectedMonth = (nowComponents.month ?? 1) + 1
            expectedYear = nowComponents.year ?? 2026
        }

        XCTAssertEqual(components.year, expectedYear)
        XCTAssertEqual(components.month, expectedMonth)
        XCTAssertEqual(components.day, 1)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(components.second, 0)
    }

    func test_nextResetDate_常に未来の日付を返す() {
        let resetDate = repository.nextResetDate()
        XCTAssertTrue(resetDate > Date())
    }

    // MARK: - toClient テスト

    func test_toClient_AIQuotaClientを生成できる() async throws {
        let client = repository.toClient()

        // canProcess が動作すること
        let canProcess = try await client.canProcess()
        XCTAssertTrue(canProcess)

        // monthlyLimit が正しいこと
        XCTAssertEqual(client.monthlyLimit(), 10)

        // recordUsage + currentUsage が動作すること
        try await client.recordUsage()
        let usage = try await client.currentUsage()
        XCTAssertEqual(usage, 1)

        // remainingCount が動作すること
        let remaining = try await client.remainingCount()
        XCTAssertEqual(remaining, 9)
    }

    // MARK: - AIQuotaRecordModel yearMonth キー テスト

    func test_yearMonthKey_JST基準で正しく生成される() {
        let jst = TimeZone(identifier: "Asia/Tokyo")!

        // 2026年3月15日 15:30 JST
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jst
        let components = DateComponents(
            calendar: calendar,
            timeZone: jst,
            year: 2026, month: 3, day: 15,
            hour: 15, minute: 30
        )
        let date = calendar.date(from: components)!

        let key = AIQuotaRecordModel.makeYearMonthKey(from: date, timeZone: jst)
        XCTAssertEqual(key, "2026-03")
    }

    func test_yearMonthKey_UTC深夜はJSTでは翌日の月になる場合がある() {
        let jst = TimeZone(identifier: "Asia/Tokyo")!
        let utc = TimeZone(identifier: "UTC")!

        // UTC 2026年3月31日 23:00 = JST 2026年4月1日 08:00
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = utc
        let utcComponents = DateComponents(
            calendar: utcCalendar,
            timeZone: utc,
            year: 2026, month: 3, day: 31,
            hour: 23, minute: 0
        )
        let date = utcCalendar.date(from: utcComponents)!

        // JST基準では4月
        let jstKey = AIQuotaRecordModel.makeYearMonthKey(from: date, timeZone: jst)
        XCTAssertEqual(jstKey, "2026-04")

        // UTC基準では3月
        let utcKey = AIQuotaRecordModel.makeYearMonthKey(from: date, timeZone: utc)
        XCTAssertEqual(utcKey, "2026-03")
    }
}
