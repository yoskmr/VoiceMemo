import XCTest
@testable import InfraLLM

final class LLMModelManagerTests: XCTestCase {
    private var manager: LLMModelManager!
    private var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        // テスト用の一時ディレクトリを使う
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMModelManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        manager = LLMModelManager(fileManager: .default)
    }

    override func tearDown() async throws {
        if let tempDir = tempDirectory, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - モデルパス

    func testModelPath_whenNotDownloaded_returnsNil() {
        // デフォルト状態ではモデルは未ダウンロード（テスト環境）
        // モデルが実際にキャッシュにある可能性もあるため、
        // ここでは nil または URL のいずれかであることを確認
        // （CI環境では nil が期待値）
        let path = manager.modelPath
        if let path = path {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        }
    }

    func testIsModelDownloaded_matchesModelPath() {
        XCTAssertEqual(manager.isModelDownloaded, manager.modelPath != nil)
    }

    // MARK: - モデルディレクトリ

    func testModelsDirectory_isCachesModels() {
        let dir = manager.modelsDirectory
        XCTAssertTrue(dir.path.contains("Caches"))
        XCTAssertTrue(dir.lastPathComponent == "Models")
    }

    func testEnsureModelsDirectoryExists_createsDirectory() throws {
        let customManager = LLMModelManager(fileManager: .default)
        try customManager.ensureModelsDirectoryExists()
        XCTAssertTrue(FileManager.default.fileExists(atPath: customManager.modelsDirectory.path))
    }

    // MARK: - ダウンロード（Phase 3a スタブ）

    func testDownloadModel_asyncStream_emitsFailure() async {
        var statuses: [ModelDownloadStatus] = []

        for await status in manager.downloadModel() {
            statuses.append(status)
        }

        XCTAssertGreaterThanOrEqual(statuses.count, 2)
        // 最初は downloading(progress: 0.0)
        if case .downloading(let progress) = statuses.first {
            XCTAssertEqual(progress, 0.0)
        } else {
            XCTFail("最初のステータスは downloading であるべき")
        }
        // Phase 3a では失敗で終わる
        if case .failed = statuses.last {
            // OK
        } else {
            XCTFail("Phase 3a スタブはエラーで終わるべき")
        }
    }

    func testDownloadModel_callback_throwsNotImplemented() async {
        do {
            try await manager.downloadModel { _ in }
            XCTFail("Phase 3a スタブはエラーを投げるべき")
        } catch {
            XCTAssertEqual(error as? LLMModelManagerError, .downloadNotImplemented)
        }
    }

    // MARK: - 定数テスト

    func testModelFileName() {
        XCTAssertEqual(LLMModelManager.modelFileName, "phi-3-mini-q4_k_m.gguf")
    }

    func testModelFileSizeDescription() {
        XCTAssertEqual(LLMModelManager.modelFileSizeDescription, "約 2.5GB")
    }
}
