import ComposableArchitecture
import Domain
import Foundation

/// カスタム辞書管理のTCA Reducer
/// TASK-0018: カスタム辞書（STT精度向上）
/// REQ-025: SFSpeechRecognizerのcontextualStrings連携
/// 設計書 01-system-architecture.md セクション5.2 UserSettings.customDictionary
@Reducer
public struct CustomDictionaryReducer {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        public var entries: IdentifiedArrayOf<DictionaryEntry>
        public var newReading: String
        public var newDisplay: String
        public var isAdding: Bool
        public var validationError: String?
        public var errorMessage: String?

        public init(
            entries: IdentifiedArrayOf<DictionaryEntry> = [],
            newReading: String = "",
            newDisplay: String = "",
            isAdding: Bool = false,
            validationError: String? = nil,
            errorMessage: String? = nil
        ) {
            self.entries = entries
            self.newReading = newReading
            self.newDisplay = newDisplay
            self.isAdding = isAdding
            self.validationError = validationError
            self.errorMessage = errorMessage
        }
    }

    // MARK: - Action

    public enum Action: Equatable, Sendable {
        case onAppear
        case entriesLoaded(EntriesResult)
        case newReadingChanged(String)
        case newDisplayChanged(String)
        case addButtonTapped
        case addCompleted(AddResult)
        case deleteEntry(id: UUID)
        case deleteCompleted(DeleteResult)
        case dismissError
    }

    /// エントリロード結果のEquatable準拠ラッパー
    public enum EntriesResult: Equatable, Sendable {
        case success([DictionaryEntry])
        case failure(String)
    }

    /// エントリ追加結果のEquatable準拠ラッパー
    public enum AddResult: Equatable, Sendable {
        case success(DictionaryEntry)
        case failure(String)
    }

    /// エントリ削除結果のEquatable準拠ラッパー
    public enum DeleteResult: Equatable, Sendable {
        case success(UUID)
        case failure(String)
    }

    // MARK: - Dependencies

    @Dependency(\.customDictionaryClient) var dictionaryClient
    @Dependency(\.uuid) var uuid

    // MARK: - Reducer Body

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    do {
                        let entries = try await dictionaryClient.loadEntries()
                        await send(.entriesLoaded(.success(entries)))
                    } catch {
                        await send(.entriesLoaded(.failure(error.localizedDescription)))
                    }
                }

            case let .entriesLoaded(.success(entries)):
                state.entries = IdentifiedArrayOf(uniqueElements: entries)
                return .none

            case let .entriesLoaded(.failure(errorMessage)):
                state.errorMessage = errorMessage
                return .none

            case let .newReadingChanged(reading):
                state.newReading = reading
                state.validationError = nil
                return .none

            case let .newDisplayChanged(display):
                state.newDisplay = display
                state.validationError = nil
                return .none

            case .addButtonTapped:
                let reading = state.newReading.trimmingCharacters(in: .whitespaces)
                let display = state.newDisplay.trimmingCharacters(in: .whitespaces)

                // バリデーション: 空入力チェック
                if reading.isEmpty || display.isEmpty {
                    state.validationError = "読みと表記の両方を入力してください"
                    return .none
                }

                // バリデーション: 重複チェック
                if state.entries.contains(where: { $0.reading == reading && $0.display == display }) {
                    state.validationError = "この単語は既に登録されています"
                    return .none
                }

                state.isAdding = true
                state.validationError = nil
                let entry = DictionaryEntry(
                    id: uuid(),
                    reading: reading,
                    display: display
                )

                return .run { send in
                    do {
                        try await dictionaryClient.addEntry(entry)
                        await send(.addCompleted(.success(entry)))
                    } catch {
                        await send(.addCompleted(.failure(error.localizedDescription)))
                    }
                }

            case let .addCompleted(.success(entry)):
                state.isAdding = false
                state.entries.append(entry)
                state.newReading = ""
                state.newDisplay = ""
                return .none

            case let .addCompleted(.failure(errorMessage)):
                state.isAdding = false
                state.errorMessage = errorMessage
                return .none

            case let .deleteEntry(id):
                return .run { send in
                    do {
                        try await dictionaryClient.deleteEntry(id)
                        await send(.deleteCompleted(.success(id)))
                    } catch {
                        await send(.deleteCompleted(.failure(error.localizedDescription)))
                    }
                }

            case let .deleteCompleted(.success(id)):
                state.entries.remove(id: id)
                return .none

            case let .deleteCompleted(.failure(errorMessage)):
                state.errorMessage = errorMessage
                return .none

            case .dismissError:
                state.errorMessage = nil
                state.validationError = nil
                return .none
            }
        }
    }
}
