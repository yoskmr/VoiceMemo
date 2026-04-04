import ComposableArchitecture
import Domain
import Foundation

/// きおくに聞く（AI対話）画面の TCA Reducer
/// TASK-0041: AI対話機能（REQ-031 / US-309 / AC-309）
/// 設計書 01-system-architecture.md セクション2.2 TCA適用方針準拠
@Reducer
public struct ChatReducer {

    // MARK: - Constants

    /// サジェスチョン（初回表示用の定型質問）
    static let suggestions = [
        "先週何に悩んでいた?",
        "最近よく考えていることは?",
        "今月の気分の変化は?",
    ]

    /// RAG検索で取得するメモの最大件数
    private static let maxContextMemos = 10

    /// チャット機能利用に必要な最小メモ件数
    static let minimumMemoCount = 3

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        public var messages: [ChatMessage] = []
        public var inputText: String = ""
        public var isStreaming: Bool = false
        public var isPro: Bool
        public var memoCount: Int = 0
        public var showProSheet: Bool
        public var errorMessage: String?

        public init(
            messages: [ChatMessage] = [],
            inputText: String = "",
            isStreaming: Bool = false,
            isPro: Bool = false,
            memoCount: Int = 0,
            showProSheet: Bool = false,
            errorMessage: String? = nil
        ) {
            self.messages = messages
            self.inputText = inputText
            self.isStreaming = isStreaming
            self.isPro = isPro
            self.memoCount = memoCount
            self.showProSheet = showProSheet
            self.errorMessage = errorMessage
        }
    }

    // MARK: - Action

    public enum Action: Equatable, Sendable {
        /// 画面表示時: メモ件数チェック
        case onAppear
        /// メモ件数の読み込み完了
        case memoCountLoaded(Int)
        /// 入力テキスト変更
        case inputTextChanged(String)
        /// 送信ボタンタップ
        case sendButtonTapped
        /// サジェスチョンタップ
        case suggestionTapped(String)
        /// AI応答受信
        case responseReceived(Result<ChatResponse, EquatableError>)
        /// 参照きおくタップ（親に委譲）
        case referencedMemoTapped(UUID)
        /// 会話クリア
        case clearConversation
        /// Proシート非表示
        case dismissProSheet
        /// 生成停止ボタンタップ
        case stopGenerationTapped
    }

    // MARK: - Dependencies

    @Dependency(\.memoConversation) var memoConversation
    @Dependency(\.voiceMemoRepository) var voiceMemoRepository
    @Dependency(\.fts5IndexManager) var fts5IndexManager
    @Dependency(\.uuid) var uuid
    @Dependency(\.date) var date

    // MARK: - Cancellation IDs

    private enum CancelID { case chat }

    public init() {}

    // MARK: - Reducer Body

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    let memos = try await voiceMemoRepository.fetchAll()
                    await send(.memoCountLoaded(memos.count))
                }

            case let .memoCountLoaded(count):
                state.memoCount = count
                return .none

            case let .inputTextChanged(text):
                state.inputText = text
                return .none

            case .sendButtonTapped:
                return sendQuestion(&state)

            case let .suggestionTapped(text):
                state.inputText = text
                return sendQuestion(&state)

            case let .responseReceived(.success(response)):
                state.isStreaming = false
                let referencedIDs = response.referencedMemoIDs.compactMap { UUID(uuidString: $0) }
                let assistantMessage = ChatMessage(
                    id: uuid(),
                    role: .assistant,
                    text: response.answer,
                    referencedMemoIDs: referencedIDs,
                    createdAt: date.now
                )
                state.messages.append(assistantMessage)
                return .none

            case let .responseReceived(.failure(error)):
                state.isStreaming = false
                state.errorMessage = error.localizedDescription
                return .none

            case .referencedMemoTapped:
                // 親Reducer（MemoListReducer）に委譲
                return .none

            case .clearConversation:
                state.messages = []
                state.inputText = ""
                state.errorMessage = nil
                return .none

            case .dismissProSheet:
                state.showProSheet = false
                return .none

            case .stopGenerationTapped:
                state.isStreaming = false
                return .cancel(id: CancelID.chat)
            }
        }
    }

    // MARK: - Effects

    /// 質問送信の共通ロジック
    private func sendQuestion(_ state: inout State) -> Effect<Action> {
        let question = state.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return .none }

        // ユーザーメッセージを追加
        let userMessage = ChatMessage(
            id: uuid(),
            role: .user,
            text: question,
            createdAt: date.now
        )
        state.messages.append(userMessage)
        state.inputText = ""
        state.isStreaming = true
        state.errorMessage = nil

        return .run { [fts5IndexManager, voiceMemoRepository, memoConversation] send in
            // 1. FTS5で関連メモを検索（上位10件）
            let ftsResults = try fts5IndexManager.search(question)
            let memoIDs = ftsResults
                .prefix(Self.maxContextMemos)
                .compactMap { UUID(uuidString: $0.memoID) }

            // 2. メモの詳細を取得
            var contextMemos: [MemoContext] = []
            if !memoIDs.isEmpty {
                let entities = try await voiceMemoRepository.fetchMemosByIDs(memoIDs)
                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale(identifier: "ja_JP")
                dateFormatter.dateFormat = "yyyy年M月d日"

                for memoID in memoIDs {
                    guard let memo = entities[memoID] else { continue }
                    contextMemos.append(MemoContext(
                        id: memoID,
                        title: memo.title,
                        text: memo.title, // SearchableMemo にはフルテキストがないため title を使用
                        date: dateFormatter.string(from: memo.createdAt),
                        emotion: memo.emotion?.rawValue,
                        tags: memo.tags
                    ))
                }
            }

            // 3. AI対話APIを呼び出し
            let result = await Result {
                try await memoConversation.sendQuestion(question, contextMemos)
            }.mapError { EquatableError($0) }

            await send(.responseReceived(result))
        }
        .cancellable(id: CancelID.chat, cancelInFlight: true)
    }
}
