import ComposableArchitecture
import Domain
import XCTest

@testable import FeatureMemo

@MainActor
final class ChatReducerTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeEntity(
        id: UUID = UUID(),
        title: String = "テストきおく",
        createdAt: Date = Date(),
        durationSeconds: Double = 60,
        transcription: TranscriptionEntity? = TranscriptionEntity(fullText: "テスト文字起こし"),
        tags: [TagEntity] = []
    ) -> VoiceMemoEntity {
        VoiceMemoEntity(
            id: id,
            title: title,
            createdAt: createdAt,
            durationSeconds: durationSeconds,
            audioFilePath: "Audio/test.m4a",
            transcription: transcription,
            tags: tags
        )
    }

    // MARK: - Test 1: onAppear Pro + メモ3件以上でチャット画面表示

    func test_onAppear_Pro_チャット画面が表示される() async {
        let entities = (0..<5).map { i in makeEntity(title: "きおく\(i)") }

        let store = TestStore(
            initialState: ChatReducer.State(isPro: true)
        ) {
            ChatReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchAll = { entities }
            $0.uuid = .constant(UUID())
            $0.date = .constant(Date())
        }

        await store.send(.onAppear)
        await store.receive(\.memoCountLoaded) {
            $0.memoCount = 5
        }
    }

    // MARK: - Test 2: onAppear Free + showProSheet が true

    func test_onAppear_Free_ProシートがshowProSheetでtrue() async {
        let entities = (0..<5).map { i in makeEntity(title: "きおく\(i)") }

        let store = TestStore(
            initialState: ChatReducer.State(isPro: false, showProSheet: true)
        ) {
            ChatReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchAll = { entities }
            $0.uuid = .constant(UUID())
            $0.date = .constant(Date())
        }

        await store.send(.onAppear)
        await store.receive(\.memoCountLoaded) {
            $0.memoCount = 5
        }

        // showProSheet は初期値 true のまま
        XCTAssertTrue(store.state.showProSheet)
    }

    // MARK: - Test 3: onAppear メモ3件未満でエンプティステート

    func test_onAppear_メモ3件未満_エンプティステート() async {
        let entities = [makeEntity(title: "きおく1"), makeEntity(title: "きおく2")]

        let store = TestStore(
            initialState: ChatReducer.State(isPro: true)
        ) {
            ChatReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchAll = { entities }
            $0.uuid = .constant(UUID())
            $0.date = .constant(Date())
        }

        await store.send(.onAppear)
        await store.receive(\.memoCountLoaded) {
            $0.memoCount = 2
        }

        // memoCount < 3 でエンプティステート表示
        XCTAssertTrue(store.state.memoCount < ChatReducer.minimumMemoCount)
    }

    // MARK: - Test 4: sendButtonTapped 質問送信と回答受信

    func test_sendButtonTapped_質問送信と回答受信() async {
        let userUUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let assistantUUID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let testDate = Date(timeIntervalSince1970: 1_700_000_000)
        var uuidCallCount = 0

        let memoID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let searchableMemo = SearchableMemo(
            title: "テストきおく",
            createdAt: testDate,
            emotion: .joy,
            durationSeconds: 60,
            tags: ["テスト"]
        )

        let store = TestStore(
            initialState: ChatReducer.State(
                inputText: "先週何に悩んでいた?",
                isPro: true,
                memoCount: 5
            )
        ) {
            ChatReducer()
        } withDependencies: {
            $0.uuid = .init {
                uuidCallCount += 1
                return uuidCallCount == 1 ? userUUID : assistantUUID
            }
            $0.date = .constant(testDate)
            $0.fts5IndexManager.search = { _ in
                [FTS5SearchResult(memoID: memoID.uuidString, snippet: "", rank: 1.0)]
            }
            $0.voiceMemoRepository.fetchMemosByIDs = { _ in
                [memoID: searchableMemo]
            }
            $0.memoConversation.sendQuestion = { _, _ in
                ChatResponse(
                    answer: "先週はプロジェクトの締め切りについて悩んでいたようです。",
                    referencedMemoIDs: [memoID.uuidString]
                )
            }
        }

        await store.send(.sendButtonTapped) {
            $0.messages = [
                ChatMessage(
                    id: userUUID,
                    role: .user,
                    text: "先週何に悩んでいた?",
                    createdAt: testDate
                ),
            ]
            $0.inputText = ""
            $0.isStreaming = true
            $0.errorMessage = nil
        }

        await store.receive(\.responseReceived.success) {
            $0.isStreaming = false
            $0.messages.append(
                ChatMessage(
                    id: assistantUUID,
                    role: .assistant,
                    text: "先週はプロジェクトの締め切りについて悩んでいたようです。",
                    referencedMemoIDs: [memoID],
                    createdAt: testDate
                )
            )
        }
    }

    // MARK: - Test 5: suggestionTapped サジェスチョンで送信

    func test_suggestionTapped_サジェスチョンで送信() async {
        let userUUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let assistantUUID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let testDate = Date(timeIntervalSince1970: 1_700_000_000)
        var uuidCallCount = 0

        let store = TestStore(
            initialState: ChatReducer.State(isPro: true, memoCount: 5)
        ) {
            ChatReducer()
        } withDependencies: {
            $0.uuid = .init {
                uuidCallCount += 1
                return uuidCallCount == 1 ? userUUID : assistantUUID
            }
            $0.date = .constant(testDate)
            $0.fts5IndexManager.search = { _ in [] }
            $0.voiceMemoRepository.fetchMemosByIDs = { _ in [:] }
            $0.memoConversation.sendQuestion = { _, _ in
                ChatResponse(answer: "まだきおくが少ないようです。", referencedMemoIDs: [])
            }
        }

        await store.send(.suggestionTapped("最近よく考えていることは?")) {
            $0.inputText = "最近よく考えていることは?"
            // sendQuestion が即座に実行されるため inputText はクリアされ、ユーザーメッセージが追加される
            $0.messages = [
                ChatMessage(
                    id: userUUID,
                    role: .user,
                    text: "最近よく考えていることは?",
                    createdAt: testDate
                ),
            ]
            $0.inputText = ""
            $0.isStreaming = true
            $0.errorMessage = nil
        }

        await store.receive(\.responseReceived.success) {
            $0.isStreaming = false
            $0.messages.append(
                ChatMessage(
                    id: assistantUUID,
                    role: .assistant,
                    text: "まだきおくが少ないようです。",
                    referencedMemoIDs: [],
                    createdAt: testDate
                )
            )
        }
    }

    // MARK: - Test 6: responseReceived failure でも壊れない

    func test_responseReceived_failure_エラーでも壊れない() async {
        let userUUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let testDate = Date(timeIntervalSince1970: 1_700_000_000)

        let store = TestStore(
            initialState: ChatReducer.State(
                inputText: "テスト質問",
                isPro: true,
                memoCount: 5
            )
        ) {
            ChatReducer()
        } withDependencies: {
            $0.uuid = .constant(userUUID)
            $0.date = .constant(testDate)
            $0.fts5IndexManager.search = { _ in [] }
            $0.voiceMemoRepository.fetchMemosByIDs = { _ in [:] }
            $0.memoConversation.sendQuestion = { _, _ in
                throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "ネットワークエラー"])
            }
        }

        await store.send(.sendButtonTapped) {
            $0.messages = [
                ChatMessage(
                    id: userUUID,
                    role: .user,
                    text: "テスト質問",
                    createdAt: testDate
                ),
            ]
            $0.inputText = ""
            $0.isStreaming = true
            $0.errorMessage = nil
        }

        await store.receive(\.responseReceived.failure) {
            $0.isStreaming = false
            $0.errorMessage = "ネットワークエラー"
        }
    }

    // MARK: - Test 7: clearConversation 会話がクリアされる

    func test_clearConversation_会話がクリアされる() async {
        let store = TestStore(
            initialState: ChatReducer.State(
                messages: [
                    ChatMessage(id: UUID(), role: .user, text: "テスト"),
                    ChatMessage(id: UUID(), role: .assistant, text: "回答"),
                ],
                inputText: "入力中",
                isPro: true,
                memoCount: 5,
                errorMessage: "過去のエラー"
            )
        ) {
            ChatReducer()
        }

        await store.send(.clearConversation) {
            $0.messages = []
            $0.inputText = ""
            $0.errorMessage = nil
        }
    }

    // MARK: - Test 8: referencedMemoTapped は State を変更しない（親に委譲）

    func test_referencedMemoTapped_親に委譲() async {
        let memoID = UUID()

        let store = TestStore(
            initialState: ChatReducer.State(isPro: true, memoCount: 5)
        ) {
            ChatReducer()
        }

        await store.send(.referencedMemoTapped(memoID))
        // State は変更されない（親Reducerで処理される）
    }

    // MARK: - Test 9: 空文字での送信は無視される

    func test_sendButtonTapped_空文字は無視される() async {
        let store = TestStore(
            initialState: ChatReducer.State(
                inputText: "  ",
                isPro: true,
                memoCount: 5
            )
        ) {
            ChatReducer()
        }

        await store.send(.sendButtonTapped)
        // 空文字ではメッセージが追加されない
    }

    // MARK: - Test 10: dismissProSheet は親 Reducer に委譲（State 変更なし）

    func test_dismissProSheet_親Reducerに委譲() async {
        let store = TestStore(
            initialState: ChatReducer.State(isPro: false, showProSheet: true)
        ) {
            ChatReducer()
        }

        // dismissProSheet は State を変更せず、親 Reducer（MemoListReducer）で chatState = nil にする
        await store.send(.dismissProSheet)
    }

    // MARK: - Test 11: stopGenerationTapped でストリーミングが停止する

    func test_stopGenerationTapped_ストリーミングが停止する() async {
        let store = TestStore(
            initialState: ChatReducer.State(isStreaming: true, isPro: true, memoCount: 5)
        ) {
            ChatReducer()
        }

        await store.send(.stopGenerationTapped) {
            $0.isStreaming = false
        }
    }
}
