import XCTest
@testable import Domain

/// VoiceMemoRepositoryProtocol のモック実装
/// テスト用にインメモリで動作する
final class MockVoiceMemoRepository: VoiceMemoRepositoryProtocol, @unchecked Sendable {
    private var storage: [UUID: VoiceMemoEntity] = [:]

    func save(_ memo: VoiceMemoEntity) async throws {
        storage[memo.id] = memo
    }

    func fetchByID(_ id: UUID) async throws -> VoiceMemoEntity? {
        storage[id]
    }

    func fetchAll() async throws -> [VoiceMemoEntity] {
        Array(storage.values).sorted { $0.createdAt > $1.createdAt }
    }

    func delete(_ id: UUID) async throws {
        storage.removeValue(forKey: id)
    }

    func fetchFavorites() async throws -> [VoiceMemoEntity] {
        storage.values.filter(\.isFavorite).sorted { $0.createdAt > $1.createdAt }
    }

    func fetchByTag(_ tagName: String) async throws -> [VoiceMemoEntity] {
        storage.values.filter { memo in
            memo.tags.contains { $0.name == tagName }
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func fetchByStatus(_ status: MemoStatus) async throws -> [VoiceMemoEntity] {
        storage.values.filter { $0.status == status }.sorted { $0.createdAt > $1.createdAt }
    }

    func count() async throws -> Int {
        storage.count
    }
}

final class MockVoiceMemoRepositoryTests: XCTestCase {

    var repository: MockVoiceMemoRepository!

    override func setUp() {
        super.setUp()
        repository = MockVoiceMemoRepository()
    }

    override func tearDown() {
        repository = nil
        super.tearDown()
    }

    // MARK: - CRUD テスト

    func test_save_andFetchByID() async throws {
        let memo = VoiceMemoEntity(
            title: "テストメモ",
            audioFilePath: "Audio/test.m4a"
        )

        try await repository.save(memo)
        let fetched = try await repository.fetchByID(memo.id)

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, memo.id)
        XCTAssertEqual(fetched?.title, "テストメモ")
    }

    func test_fetchByID_nonExistent_returnsNil() async throws {
        let result = try await repository.fetchByID(UUID())
        XCTAssertNil(result)
    }

    func test_fetchAll_returnsSortedByCreatedAtDesc() async throws {
        let date1 = Date().addingTimeInterval(-100)
        let date2 = Date()

        try await repository.save(VoiceMemoEntity(createdAt: date1, audioFilePath: "Audio/1.m4a"))
        try await repository.save(VoiceMemoEntity(createdAt: date2, audioFilePath: "Audio/2.m4a"))

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all[0].createdAt >= all[1].createdAt)
    }

    func test_delete() async throws {
        let memo = VoiceMemoEntity(audioFilePath: "Audio/test.m4a")
        try await repository.save(memo)

        try await repository.delete(memo.id)
        let fetched = try await repository.fetchByID(memo.id)

        XCTAssertNil(fetched)
    }

    func test_update_existingMemo() async throws {
        var memo = VoiceMemoEntity(
            title: "初期タイトル",
            audioFilePath: "Audio/test.m4a"
        )

        try await repository.save(memo)

        memo.title = "更新タイトル"
        memo.isFavorite = true
        try await repository.save(memo)

        let fetched = try await repository.fetchByID(memo.id)
        XCTAssertEqual(fetched?.title, "更新タイトル")
        XCTAssertEqual(fetched?.isFavorite, true)
    }

    // MARK: - フィルタリングテスト

    func test_fetchFavorites() async throws {
        try await repository.save(VoiceMemoEntity(audioFilePath: "Audio/1.m4a", isFavorite: true))
        try await repository.save(VoiceMemoEntity(audioFilePath: "Audio/2.m4a", isFavorite: false))
        try await repository.save(VoiceMemoEntity(audioFilePath: "Audio/3.m4a", isFavorite: true))

        let favorites = try await repository.fetchFavorites()
        XCTAssertEqual(favorites.count, 2)
        XCTAssertTrue(favorites.allSatisfy(\.isFavorite))
    }

    func test_fetchByTag() async throws {
        let tag = TagEntity(name: "仕事")
        try await repository.save(VoiceMemoEntity(audioFilePath: "Audio/1.m4a", tags: [tag]))
        try await repository.save(VoiceMemoEntity(audioFilePath: "Audio/2.m4a"))

        let tagged = try await repository.fetchByTag("仕事")
        XCTAssertEqual(tagged.count, 1)
    }

    func test_fetchByStatus() async throws {
        try await repository.save(VoiceMemoEntity(audioFilePath: "Audio/1.m4a", status: .completed))
        try await repository.save(VoiceMemoEntity(audioFilePath: "Audio/2.m4a", status: .recording))
        try await repository.save(VoiceMemoEntity(audioFilePath: "Audio/3.m4a", status: .completed))

        let completed = try await repository.fetchByStatus(.completed)
        XCTAssertEqual(completed.count, 2)
        XCTAssertTrue(completed.allSatisfy { $0.status == .completed })

        let recording = try await repository.fetchByStatus(.recording)
        XCTAssertEqual(recording.count, 1)
    }

    // MARK: - カウントテスト

    func test_count() async throws {
        let count0 = try await repository.count()
        XCTAssertEqual(count0, 0)

        try await repository.save(VoiceMemoEntity(audioFilePath: "Audio/1.m4a"))
        let count1 = try await repository.count()
        XCTAssertEqual(count1, 1)

        try await repository.save(VoiceMemoEntity(audioFilePath: "Audio/2.m4a"))
        let count2 = try await repository.count()
        XCTAssertEqual(count2, 2)
    }
}
