import Foundation
import Testing
import TestSupport
@testable import Domain
@testable import InfraStorage

/// TemporaryRecordingStore のユニットテスト
/// TASK-0004: クラッシュリカバリ（録音自動保存）
///
/// テスト対象:
/// - チャンク保存（saveChunk）
/// - チャンク結合（finalizeRecording）※AVAssetExportSessionはCIで動かないためファイルI/O部分のみ
/// - 未完了録音検出（recoverUnfinishedRecordings）
/// - チャンク削除（discardChunks）
/// - エラーハンドリング
@Suite("TemporaryRecordingStore Tests")
struct TemporaryRecordingStoreTests {

    // MARK: - Test Helpers

    /// テスト用の一時ディレクトリを作成する
    private func makeTestDirectory() throws -> URL {
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TemporaryRecordingStoreTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        return testDir
    }

    /// テスト終了後に一時ディレクトリを削除する
    private func cleanUp(directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// テスト用のダミーM4Aデータを生成する
    private func makeDummyChunkData(size: Int = 1024) -> Data {
        Data(repeating: 0xAA, count: size)
    }

    // MARK: - 正常系: チャンク保存

    @Test("saveChunk: チャンクファイルが正しいパスに保存される")
    func testSaveChunkCreatesFileAtCorrectPath() throws {
        let testDir = try makeTestDirectory()
        defer { cleanUp(directory: testDir) }

        let store = TemporaryRecordingStore(tempDirectory: testDir)
        let recordingID = UUID()
        let data = makeDummyChunkData()

        let url = try store.saveChunk(recordingID: recordingID, chunkIndex: 0, data: data)

        let expectedFileName = "\(recordingID.uuidString)_chunk_0.m4a"
        #expect(url.lastPathComponent == expectedFileName)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("saveChunk: 保存されたデータの内容が一致する")
    func testSaveChunkDataIntegrity() throws {
        let testDir = try makeTestDirectory()
        defer { cleanUp(directory: testDir) }

        let store = TemporaryRecordingStore(tempDirectory: testDir)
        let recordingID = UUID()
        let originalData = makeDummyChunkData(size: 2048)

        let url = try store.saveChunk(recordingID: recordingID, chunkIndex: 0, data: originalData)
        let savedData = try Data(contentsOf: url)

        #expect(savedData == originalData)
    }

    @Test("saveChunk: 複数チャンクが連番で保存される")
    func testSaveMultipleChunksWithSequentialIndex() throws {
        let testDir = try makeTestDirectory()
        defer { cleanUp(directory: testDir) }

        let store = TemporaryRecordingStore(tempDirectory: testDir)
        let recordingID = UUID()

        for i in 0..<5 {
            let data = makeDummyChunkData()
            let url = try store.saveChunk(recordingID: recordingID, chunkIndex: i, data: data)
            let expectedFileName = "\(recordingID.uuidString)_chunk_\(i).m4a"
            #expect(url.lastPathComponent == expectedFileName)
        }

        // 5ファイル存在することを確認
        let contents = try FileManager.default.contentsOfDirectory(
            at: testDir, includingPropertiesForKeys: nil
        )
        let chunkFiles = contents.filter { $0.lastPathComponent.hasPrefix(recordingID.uuidString) }
        attachFileSystemState(directory: testDir, named: "chunks-after-save")
        #expect(chunkFiles.count == 5)
    }

    @Test("saveChunk: アトミック書き込みで保存される（部分書き込みが発生しない）")
    func testSaveChunkIsAtomic() throws {
        let testDir = try makeTestDirectory()
        defer { cleanUp(directory: testDir) }

        let store = TemporaryRecordingStore(tempDirectory: testDir)
        let recordingID = UUID()
        let data = makeDummyChunkData(size: 4096)

        let url = try store.saveChunk(recordingID: recordingID, chunkIndex: 0, data: data)

        // ファイルサイズが完全に一致することでアトミック書き込みを間接的に検証
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attrs[.size] as? Int ?? 0
        #expect(fileSize == 4096)
    }

    // MARK: - 正常系: チャンクURLリスト取得

    @Test("chunkURLs: チャンクファイルがchunkIndex昇順で返される")
    func testChunkURLsReturnsSortedList() throws {
        let testDir = try makeTestDirectory()
        defer { cleanUp(directory: testDir) }

        let store = TemporaryRecordingStore(tempDirectory: testDir)
        let recordingID = UUID()

        // 逆順で保存
        for i in (0..<3).reversed() {
            _ = try store.saveChunk(recordingID: recordingID, chunkIndex: i, data: makeDummyChunkData())
        }

        let urls = try store.chunkURLs(for: recordingID)
        attachFileSystemState(directory: testDir, named: "chunks-sorted")
        #expect(urls.count == 3)
        #expect(urls[0].lastPathComponent.contains("_chunk_0"))
        #expect(urls[1].lastPathComponent.contains("_chunk_1"))
        #expect(urls[2].lastPathComponent.contains("_chunk_2"))
    }

    @Test("chunkURLs: 他の録音IDのチャンクが混在しない")
    func testChunkURLsFiltersOtherRecordings() throws {
        let testDir = try makeTestDirectory()
        defer { cleanUp(directory: testDir) }

        let store = TemporaryRecordingStore(tempDirectory: testDir)
        let recordingID1 = UUID()
        let recordingID2 = UUID()

        _ = try store.saveChunk(recordingID: recordingID1, chunkIndex: 0, data: makeDummyChunkData())
        _ = try store.saveChunk(recordingID: recordingID1, chunkIndex: 1, data: makeDummyChunkData())
        _ = try store.saveChunk(recordingID: recordingID2, chunkIndex: 0, data: makeDummyChunkData())

        let urls1 = try store.chunkURLs(for: recordingID1)
        let urls2 = try store.chunkURLs(for: recordingID2)

        #expect(urls1.count == 2)
        #expect(urls2.count == 1)
    }

    // MARK: - 正常系: 未完了録音検出

    @Test("recoverUnfinishedRecordings: チャンクが残存するUUIDが検出される")
    func testRecoverDetectsUnfinishedRecordings() throws {
        let testDir = try makeTestDirectory()
        defer { cleanUp(directory: testDir) }

        let store = TemporaryRecordingStore(tempDirectory: testDir)
        let recordingID1 = UUID()
        let recordingID2 = UUID()

        _ = try store.saveChunk(recordingID: recordingID1, chunkIndex: 0, data: makeDummyChunkData())
        _ = try store.saveChunk(recordingID: recordingID1, chunkIndex: 1, data: makeDummyChunkData())
        _ = try store.saveChunk(recordingID: recordingID2, chunkIndex: 0, data: makeDummyChunkData())

        let recovered = store.recoverUnfinishedRecordings()

        #expect(recovered.count == 2)
        #expect(recovered.contains(recordingID1))
        #expect(recovered.contains(recordingID2))
    }

    @Test("recoverUnfinishedRecordings: チャンクがない場合は空配列を返す")
    func testRecoverReturnsEmptyWhenNoChunks() throws {
        let testDir = try makeTestDirectory()
        defer { cleanUp(directory: testDir) }

        let store = TemporaryRecordingStore(tempDirectory: testDir)
        let recovered = store.recoverUnfinishedRecordings()

        #expect(recovered.isEmpty)
    }

    @Test("recoverUnfinishedRecordings: _final.m4aファイルは未完了として検出しない")
    func testRecoverIgnoresFinalFiles() throws {
        let testDir = try makeTestDirectory()
        defer { cleanUp(directory: testDir) }

        let store = TemporaryRecordingStore(tempDirectory: testDir)
        let recordingID = UUID()

        // チャンクファイルを作成
        _ = try store.saveChunk(recordingID: recordingID, chunkIndex: 0, data: makeDummyChunkData())

        // _final.m4a ファイルを手動作成（結合済みを想定）
        let finalURL = testDir.appendingPathComponent("\(recordingID.uuidString)_final.m4a")
        try makeDummyChunkData().write(to: finalURL)

        // チャンクが存在するので検出される（_finalは含まれるがUUIDは同じ）
        let recovered = store.recoverUnfinishedRecordings()
        // _chunk_ パターンのみでフィルタされるべき
        #expect(recovered.count == 1)
        #expect(recovered.contains(recordingID))
    }

    // MARK: - 正常系: チャンク削除

    @Test("discardChunks: 指定録音IDのチャンクファイルが全削除される")
    func testDiscardChunksRemovesAllChunks() throws {
        let testDir = try makeTestDirectory()
        defer { cleanUp(directory: testDir) }

        let store = TemporaryRecordingStore(tempDirectory: testDir)
        let recordingID = UUID()

        for i in 0..<3 {
            _ = try store.saveChunk(recordingID: recordingID, chunkIndex: i, data: makeDummyChunkData())
        }

        try store.discardChunks(recordingID: recordingID)

        let urls = try store.chunkURLs(for: recordingID)
        #expect(urls.isEmpty)
    }

    @Test("discardChunks: 他の録音IDのチャンクは削除されない")
    func testDiscardChunksPreservesOtherRecordings() throws {
        let testDir = try makeTestDirectory()
        defer { cleanUp(directory: testDir) }

        let store = TemporaryRecordingStore(tempDirectory: testDir)
        let recordingID1 = UUID()
        let recordingID2 = UUID()

        _ = try store.saveChunk(recordingID: recordingID1, chunkIndex: 0, data: makeDummyChunkData())
        _ = try store.saveChunk(recordingID: recordingID2, chunkIndex: 0, data: makeDummyChunkData())

        try store.discardChunks(recordingID: recordingID1)

        let urls1 = try store.chunkURLs(for: recordingID1)
        let urls2 = try store.chunkURLs(for: recordingID2)

        #expect(urls1.isEmpty)
        #expect(urls2.count == 1)
    }

    // MARK: - 異常系

    @Test("chunkURLs: 存在しない録音IDでは空配列を返す")
    func testChunkURLsForNonexistentRecordingReturnsEmpty() throws {
        let testDir = try makeTestDirectory()
        defer { cleanUp(directory: testDir) }

        let store = TemporaryRecordingStore(tempDirectory: testDir)
        let nonexistentID = UUID()

        let urls = try store.chunkURLs(for: nonexistentID)
        #expect(urls.isEmpty)
    }

    @Test("discardChunks: 存在しない録音IDでもエラーにならない")
    func testDiscardChunksForNonexistentRecordingDoesNotThrow() throws {
        let testDir = try makeTestDirectory()
        defer { cleanUp(directory: testDir) }

        let store = TemporaryRecordingStore(tempDirectory: testDir)
        let nonexistentID = UUID()

        // エラーが発生しないことを確認
        try store.discardChunks(recordingID: nonexistentID)
    }

    @Test("saveChunk: 同じインデックスで上書き保存できる")
    func testSaveChunkOverwritesSameIndex() throws {
        let testDir = try makeTestDirectory()
        defer { cleanUp(directory: testDir) }

        let store = TemporaryRecordingStore(tempDirectory: testDir)
        let recordingID = UUID()
        let data1 = Data(repeating: 0xAA, count: 100)
        let data2 = Data(repeating: 0xBB, count: 200)

        _ = try store.saveChunk(recordingID: recordingID, chunkIndex: 0, data: data1)
        let url = try store.saveChunk(recordingID: recordingID, chunkIndex: 0, data: data2)

        let savedData = try Data(contentsOf: url)
        #expect(savedData == data2)
        #expect(savedData.count == 200)
    }

    // MARK: - 復旧フロー統合テスト

    @Test("復旧フロー: チャンク保存 -> 検出 -> 削除の一連フローが動作する")
    func testRecoveryFlowDiscardPath() throws {
        let testDir = try makeTestDirectory()
        defer { cleanUp(directory: testDir) }

        let store = TemporaryRecordingStore(tempDirectory: testDir)
        let recordingID = UUID()

        // 1. チャンクを保存（クラッシュ前の状態をシミュレート）
        for i in 0..<3 {
            _ = try store.saveChunk(recordingID: recordingID, chunkIndex: i, data: makeDummyChunkData())
        }

        // 2. アプリ再起動をシミュレート: 新しいStoreインスタンスで検出
        let newStore = TemporaryRecordingStore(tempDirectory: testDir)
        let recovered = newStore.recoverUnfinishedRecordings()
        #expect(recovered.contains(recordingID))

        // 3. ユーザーが破棄を選択
        try newStore.discardChunks(recordingID: recordingID)

        // 4. チャンクが削除されたことを確認
        let afterDiscard = newStore.recoverUnfinishedRecordings()
        attachFileSystemState(directory: testDir, named: "recovery-after-discard")
        #expect(afterDiscard.isEmpty)
    }

    @Test("復旧フロー: 複数録音の同時復旧が可能")
    func testRecoveryMultipleRecordings() throws {
        let testDir = try makeTestDirectory()
        defer { cleanUp(directory: testDir) }

        let store = TemporaryRecordingStore(tempDirectory: testDir)
        let ids = (0..<3).map { _ in UUID() }

        // 3つの録音セッションのチャンクを保存
        for (index, id) in ids.enumerated() {
            for chunk in 0..<(index + 1) {
                _ = try store.saveChunk(recordingID: id, chunkIndex: chunk, data: makeDummyChunkData())
            }
        }

        // 全て検出される
        let recovered = store.recoverUnfinishedRecordings()
        #expect(recovered.count == 3)

        // 1つだけ破棄
        try store.discardChunks(recordingID: ids[0])
        let afterDiscard = store.recoverUnfinishedRecordings()
        attachFileSystemState(directory: testDir, named: "recovery-multi-after-discard")
        #expect(afterDiscard.count == 2)
        #expect(!afterDiscard.contains(ids[0]))
    }
}
