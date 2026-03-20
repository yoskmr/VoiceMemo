import XCTest
@testable import Domain

/// SaveRecordingUseCase のテスト
/// TDD: 録音完了フロー（ファイル移動 → 保護レベル設定 → SwiftData保存 → クリーンアップ）
final class SaveRecordingUseCaseTests: XCTestCase {

    // MARK: - テストヘルパー

    private var movedFiles: [(from: URL, id: UUID)]!
    private var protectedFiles: [URL]!
    private var savedMemos: [VoiceMemoEntity]!
    private var cleanedUpIDs: [UUID]!
    private var shouldFailMove: Bool!
    private var shouldFailProtection: Bool!
    private var shouldFailSave: Bool!
    private var shouldFailCleanup: Bool!

    override func setUp() {
        super.setUp()
        movedFiles = []
        protectedFiles = []
        savedMemos = []
        cleanedUpIDs = []
        shouldFailMove = false
        shouldFailProtection = false
        shouldFailSave = false
        shouldFailCleanup = false
    }

    override func tearDown() {
        movedFiles = nil
        protectedFiles = nil
        savedMemos = nil
        cleanedUpIDs = nil
        shouldFailMove = nil
        shouldFailProtection = nil
        shouldFailSave = nil
        shouldFailCleanup = nil
        super.tearDown()
    }

    private func makeUseCase() -> SaveRecordingUseCase {
        let audioFileStore = AudioFileStoreClient(
            moveToDocuments: { [self] tempURL, id in
                if self.shouldFailMove {
                    throw SaveRecordingError.fileMoveFailed("ストレージ不足")
                }
                self.movedFiles.append((from: tempURL, id: id))
                let docsURL = URL(fileURLWithPath: "/Documents/Audio/\(id.uuidString).m4a")
                return docsURL
            },
            setFileProtection: { [self] url in
                if self.shouldFailProtection {
                    throw SaveRecordingError.fileProtectionFailed("保護設定失敗")
                }
                self.protectedFiles.append(url)
            }
        )

        let voiceMemoRepository = VoiceMemoRepositoryClient(
            save: { [self] memo in
                if self.shouldFailSave {
                    throw SaveRecordingError.persistenceFailed("DB保存失敗")
                }
                self.savedMemos.append(memo)
            },
            fetchByID: { _ in nil },
            fetchAll: { [] },
            delete: { _ in }
        )

        let temporaryRecordingStore = TemporaryRecordingStoreClient(
            cleanup: { [self] recordingID in
                if self.shouldFailCleanup {
                    throw SaveRecordingError.cleanupFailed("クリーンアップ失敗")
                }
                self.cleanedUpIDs.append(recordingID)
            }
        )

        return SaveRecordingUseCase(
            audioFileStore: audioFileStore,
            voiceMemoRepository: voiceMemoRepository,
            temporaryRecordingStore: temporaryRecordingStore
        )
    }

    private func makeInput(
        recordingID: UUID = UUID(),
        durationSeconds: Double = 30.0,
        text: String = "テスト文字起こし結果",
        confidence: Double = 0.85,
        language: String = "ja-JP"
    ) -> SaveRecordingUseCase.Input {
        SaveRecordingUseCase.Input(
            recordingID: recordingID,
            tempAudioURL: URL(fileURLWithPath: "/tmp/Recording/\(recordingID.uuidString)_final.m4a"),
            durationSeconds: durationSeconds,
            transcriptionResult: TranscriptionResult(
                text: text,
                confidence: confidence,
                isFinal: true,
                language: language
            )
        )
    }

    // MARK: - 正常系テスト

    /// 録音停止後にVoiceMemoがリポジトリに保存されること
    func test_正常系_VoiceMemoが保存される() async throws {
        let useCase = makeUseCase()
        let recordingID = UUID()
        let input = makeInput(recordingID: recordingID)

        let output = try await useCase.execute(input)

        XCTAssertEqual(output.memoID, recordingID)
        XCTAssertEqual(savedMemos.count, 1)
        XCTAssertEqual(savedMemos.first?.id, recordingID)
    }

    /// VoiceMemoにTranscriptionが正しく紐付けられていること
    func test_正常系_Transcriptionが正しく紐付けられる() async throws {
        let useCase = makeUseCase()
        let input = makeInput(
            text: "こんにちは世界",
            confidence: 0.92,
            language: "ja-JP"
        )

        let output = try await useCase.execute(input)

        let savedMemo = output.memo
        XCTAssertNotNil(savedMemo.transcription)
        XCTAssertEqual(savedMemo.transcription?.fullText, "こんにちは世界")
        XCTAssertEqual(savedMemo.transcription?.confidence, 0.92)
        XCTAssertEqual(savedMemo.transcription?.language, "ja-JP")
        XCTAssertEqual(savedMemo.transcription?.engineType, .whisperKit)
    }

    /// 音声ファイルがDocuments/Audio/{UUID}.m4aに移動されていること
    func test_正常系_音声ファイルがDocumentsに移動される() async throws {
        let useCase = makeUseCase()
        let recordingID = UUID()
        let input = makeInput(recordingID: recordingID)

        _ = try await useCase.execute(input)

        XCTAssertEqual(movedFiles.count, 1)
        XCTAssertEqual(movedFiles.first?.id, recordingID)
    }

    /// 確定ファイルにNSFileProtectionCompleteが適用されていること
    func test_正常系_ファイル保護レベルが適用される() async throws {
        let useCase = makeUseCase()
        let recordingID = UUID()
        let input = makeInput(recordingID: recordingID)

        _ = try await useCase.execute(input)

        XCTAssertEqual(protectedFiles.count, 1)
        let expectedURL = URL(fileURLWithPath: "/Documents/Audio/\(recordingID.uuidString).m4a")
        XCTAssertEqual(protectedFiles.first, expectedURL)
    }

    /// 一時ファイル（tmp/Recording/）が削除されていること
    func test_正常系_一時ファイルがクリーンアップされる() async throws {
        let useCase = makeUseCase()
        let recordingID = UUID()
        let input = makeInput(recordingID: recordingID)

        _ = try await useCase.execute(input)

        XCTAssertEqual(cleanedUpIDs.count, 1)
        XCTAssertEqual(cleanedUpIDs.first, recordingID)
    }

    /// durationSecondsが録音経過時間と一致すること
    func test_正常系_durationSecondsが正しく設定される() async throws {
        let useCase = makeUseCase()
        let input = makeInput(durationSeconds: 45.5)

        let output = try await useCase.execute(input)

        XCTAssertEqual(output.memo.durationSeconds, 45.5)
    }

    /// audioFilePathが正しい相対パスであること
    func test_データ整合性_audioFilePathが正しい相対パス() async throws {
        let useCase = makeUseCase()
        let recordingID = UUID()
        let input = makeInput(recordingID: recordingID)

        let output = try await useCase.execute(input)

        XCTAssertEqual(output.memo.audioFilePath, "Audio/\(recordingID.uuidString).m4a")
    }

    /// audioFormatがm4aであること
    func test_データ整合性_audioFormatがm4a() async throws {
        let useCase = makeUseCase()
        let input = makeInput()

        let output = try await useCase.execute(input)

        XCTAssertEqual(output.memo.audioFormat, .m4a)
    }

    /// ステータスがcompletedであること
    func test_データ整合性_statusがcompleted() async throws {
        let useCase = makeUseCase()
        let input = makeInput()

        let output = try await useCase.execute(input)

        XCTAssertEqual(output.memo.status, .completed)
    }

    // MARK: - 異常系テスト

    /// ファイル移動失敗時にfileMoveFailed エラーがスローされること
    func test_異常系_ファイル移動失敗時にエラーがスローされる() async {
        shouldFailMove = true
        let useCase = makeUseCase()
        let input = makeInput()

        do {
            _ = try await useCase.execute(input)
            XCTFail("エラーがスローされるべき")
        } catch let error as SaveRecordingError {
            if case .fileMoveFailed = error {
                // 期待通り
            } else {
                XCTFail("fileMoveFailed エラーが期待されたが \(error) を受信")
            }
        } catch {
            XCTFail("SaveRecordingError が期待されたが \(error) を受信")
        }
    }

    /// SwiftData保存失敗時にpersistenceFailed エラーがスローされること
    func test_異常系_SwiftData保存失敗時にエラーがスローされる() async {
        shouldFailSave = true
        let useCase = makeUseCase()
        let input = makeInput()

        do {
            _ = try await useCase.execute(input)
            XCTFail("エラーがスローされるべき")
        } catch let error as SaveRecordingError {
            if case .persistenceFailed = error {
                // 期待通り
            } else {
                XCTFail("persistenceFailed エラーが期待されたが \(error) を受信")
            }
        } catch {
            XCTFail("SaveRecordingError が期待されたが \(error) を受信")
        }
    }

    /// クリーンアップ失敗時でもメモ保存は成功すること（非致命的）
    func test_異常系_クリーンアップ失敗時でもメモ保存は成功する() async throws {
        shouldFailCleanup = true
        let useCase = makeUseCase()
        let input = makeInput()

        // クリーンアップ失敗でもエラーはスローされない
        let output = try await useCase.execute(input)

        XCTAssertEqual(savedMemos.count, 1)
        XCTAssertEqual(output.memo.status, .completed)
    }

    /// ファイル保護設定失敗時にfileProtectionFailed エラーがスローされること
    func test_異常系_ファイル保護設定失敗時にエラーがスローされる() async {
        shouldFailProtection = true
        let useCase = makeUseCase()
        let input = makeInput()

        do {
            _ = try await useCase.execute(input)
            XCTFail("エラーがスローされるべき")
        } catch let error as SaveRecordingError {
            if case .fileProtectionFailed = error {
                // 期待通り
            } else {
                XCTFail("fileProtectionFailed エラーが期待されたが \(error) を受信")
            }
        } catch {
            XCTFail("SaveRecordingError が期待されたが \(error) を受信")
        }
    }
}
