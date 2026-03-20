import ComposableArchitecture
import XCTest
@testable import Domain
@testable import FeatureMemo

@MainActor
final class MemoDeleteReducerTests: XCTestCase {

    // MARK: - Test 1: deleteRequested で確認ダイアログ表示

    func test_deleteRequested_確認ダイアログ表示() async {
        let memoID = UUID()
        let store = TestStore(
            initialState: MemoDeleteReducer.State()
        ) {
            MemoDeleteReducer()
        }

        await store.send(.deleteRequested(id: memoID)) {
            $0.pendingDeleteID = memoID
            $0.showDeleteConfirmation = true
        }
    }

    // MARK: - Test 2: deleteCancelled でダイアログ閉じる

    func test_deleteCancelled_ダイアログ閉じる() async {
        let memoID = UUID()
        let store = TestStore(
            initialState: MemoDeleteReducer.State(
                pendingDeleteID: memoID,
                showDeleteConfirmation: true
            )
        ) {
            MemoDeleteReducer()
        }

        await store.send(.deleteCancelled) {
            $0.pendingDeleteID = nil
            $0.showDeleteConfirmation = false
        }
    }

    // MARK: - Test 3: deleteConfirmed で全リソース削除

    func test_deleteConfirmed_全リソース削除() async {
        let memoID = UUID()
        var deletedMemoID: UUID?
        var deletedAudioPath: String?
        var deletedFTSID: String?

        let store = TestStore(
            initialState: MemoDeleteReducer.State(
                pendingDeleteID: memoID,
                showDeleteConfirmation: true
            )
        ) {
            MemoDeleteReducer()
        } withDependencies: {
            $0.voiceMemoRepository.getAudioFilePath = { _ in "Audio/test.m4a" }
            $0.voiceMemoRepository.delete = { id in deletedMemoID = id }
            $0.audioFileStore.deleteAudioFile = { path in deletedAudioPath = path }
            $0.fts5IndexManager.removeIndex = { id in deletedFTSID = id }
        }

        await store.send(.deleteConfirmed(id: memoID)) {
            $0.showDeleteConfirmation = false
            $0.isDeleting = true
        }

        await store.receive(.deleteCompleted(.success(memoID))) {
            $0.isDeleting = false
            $0.pendingDeleteID = nil
        }

        XCTAssertEqual(deletedMemoID, memoID)
        XCTAssertEqual(deletedAudioPath, "Audio/test.m4a")
        XCTAssertEqual(deletedFTSID, memoID.uuidString)
    }

    // MARK: - Test 4: SwiftData削除が呼ばれる

    func test_deleteConfirmed_SwiftData削除() async {
        let memoID = UUID()
        var swiftDataDeleteCalled = false

        let store = TestStore(
            initialState: MemoDeleteReducer.State(
                pendingDeleteID: memoID,
                showDeleteConfirmation: true
            )
        ) {
            MemoDeleteReducer()
        } withDependencies: {
            $0.voiceMemoRepository.getAudioFilePath = { _ in "" }
            $0.voiceMemoRepository.delete = { _ in swiftDataDeleteCalled = true }
            $0.audioFileStore.deleteAudioFile = { _ in }
            $0.fts5IndexManager.removeIndex = { _ in }
        }

        await store.send(.deleteConfirmed(id: memoID)) {
            $0.showDeleteConfirmation = false
            $0.isDeleting = true
        }

        await store.receive(.deleteCompleted(.success(memoID))) {
            $0.isDeleting = false
            $0.pendingDeleteID = nil
        }

        XCTAssertTrue(swiftDataDeleteCalled)
    }

    // MARK: - Test 5: 音声ファイル物理削除が呼ばれる

    func test_deleteConfirmed_音声ファイル物理削除() async {
        let memoID = UUID()
        var audioDeleteCalled = false

        let store = TestStore(
            initialState: MemoDeleteReducer.State(
                pendingDeleteID: memoID,
                showDeleteConfirmation: true
            )
        ) {
            MemoDeleteReducer()
        } withDependencies: {
            $0.voiceMemoRepository.getAudioFilePath = { _ in "Audio/test.m4a" }
            $0.voiceMemoRepository.delete = { _ in }
            $0.audioFileStore.deleteAudioFile = { _ in audioDeleteCalled = true }
            $0.fts5IndexManager.removeIndex = { _ in }
        }

        await store.send(.deleteConfirmed(id: memoID)) {
            $0.showDeleteConfirmation = false
            $0.isDeleting = true
        }

        await store.receive(.deleteCompleted(.success(memoID))) {
            $0.isDeleting = false
            $0.pendingDeleteID = nil
        }

        XCTAssertTrue(audioDeleteCalled)
    }

    // MARK: - Test 6: FTS5インデックス削除が呼ばれる

    func test_deleteConfirmed_FTS5インデックス削除() async {
        let memoID = UUID()
        var ftsDeleteCalled = false

        let store = TestStore(
            initialState: MemoDeleteReducer.State(
                pendingDeleteID: memoID,
                showDeleteConfirmation: true
            )
        ) {
            MemoDeleteReducer()
        } withDependencies: {
            $0.voiceMemoRepository.getAudioFilePath = { _ in "" }
            $0.voiceMemoRepository.delete = { _ in }
            $0.audioFileStore.deleteAudioFile = { _ in }
            $0.fts5IndexManager.removeIndex = { _ in ftsDeleteCalled = true }
        }

        await store.send(.deleteConfirmed(id: memoID)) {
            $0.showDeleteConfirmation = false
            $0.isDeleting = true
        }

        await store.receive(.deleteCompleted(.success(memoID))) {
            $0.isDeleting = false
            $0.pendingDeleteID = nil
        }

        XCTAssertTrue(ftsDeleteCalled)
    }

    // MARK: - Test 7: 削除失敗でエラー表示

    func test_deleteCompleted_failure_エラー表示() async {
        let memoID = UUID()
        let store = TestStore(
            initialState: MemoDeleteReducer.State(
                pendingDeleteID: memoID,
                showDeleteConfirmation: true
            )
        ) {
            MemoDeleteReducer()
        } withDependencies: {
            $0.voiceMemoRepository.getAudioFilePath = { _ in
                throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "ファイルパス取得エラー"])
            }
        }

        await store.send(.deleteConfirmed(id: memoID)) {
            $0.showDeleteConfirmation = false
            $0.isDeleting = true
        }

        await store.receive(.deleteCompleted(.failure("ファイルパス取得エラー"))) {
            $0.isDeleting = false
            $0.deleteError = "ファイルパス取得エラー"
        }
    }

    // MARK: - Test 8: 音声ファイル不存在でも続行

    func test_deleteConfirmed_音声ファイル不存在でも続行() async {
        let memoID = UUID()
        let store = TestStore(
            initialState: MemoDeleteReducer.State(
                pendingDeleteID: memoID,
                showDeleteConfirmation: true
            )
        ) {
            MemoDeleteReducer()
        } withDependencies: {
            $0.voiceMemoRepository.getAudioFilePath = { _ in "Audio/nonexistent.m4a" }
            $0.voiceMemoRepository.delete = { _ in }
            $0.audioFileStore.deleteAudioFile = { _ in
                throw NSError(domain: "FileNotFound", code: -1)
            }
            $0.fts5IndexManager.removeIndex = { _ in }
        }

        await store.send(.deleteConfirmed(id: memoID)) {
            $0.showDeleteConfirmation = false
            $0.isDeleting = true
        }

        // 音声ファイル不存在でも成功として返る
        await store.receive(.deleteCompleted(.success(memoID))) {
            $0.isDeleting = false
            $0.pendingDeleteID = nil
        }
    }

    // MARK: - Test 9: FTS5失敗でも続行

    func test_deleteConfirmed_FTS5失敗でも続行() async {
        let memoID = UUID()
        let store = TestStore(
            initialState: MemoDeleteReducer.State(
                pendingDeleteID: memoID,
                showDeleteConfirmation: true
            )
        ) {
            MemoDeleteReducer()
        } withDependencies: {
            $0.voiceMemoRepository.getAudioFilePath = { _ in "" }
            $0.voiceMemoRepository.delete = { _ in }
            $0.audioFileStore.deleteAudioFile = { _ in }
            $0.fts5IndexManager.removeIndex = { _ in
                throw NSError(domain: "FTS5Error", code: -1)
            }
        }

        await store.send(.deleteConfirmed(id: memoID)) {
            $0.showDeleteConfirmation = false
            $0.isDeleting = true
        }

        // FTS5エラーでも成功として返る
        await store.receive(.deleteCompleted(.success(memoID))) {
            $0.isDeleting = false
            $0.pendingDeleteID = nil
        }
    }

    // MARK: - Test 10: スワイプ削除から確認ダイアログ

    func test_swipeDelete_スワイプから確認ダイアログ() async {
        let memoID = UUID()
        let store = TestStore(
            initialState: MemoDeleteReducer.State()
        ) {
            MemoDeleteReducer()
        }

        // スワイプ = deleteRequested
        await store.send(.deleteRequested(id: memoID)) {
            $0.pendingDeleteID = memoID
            $0.showDeleteConfirmation = true
        }
    }
}
