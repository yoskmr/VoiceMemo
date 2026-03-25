import ComposableArchitecture
import XCTest
@testable import Domain
@testable import FeatureSettings

@MainActor
final class CustomDictionaryReducerTests: XCTestCase {

    // MARK: - Test 1: onAppear で辞書エントリのロード

    func test_onAppear_辞書エントリのロード() async {
        let entries = [
            DictionaryEntry(id: UUID(), reading: "てすと", display: "テスト"),
            DictionaryEntry(id: UUID(), reading: "こんぽーざぶる", display: "Composable"),
        ]

        let store = TestStore(
            initialState: CustomDictionaryReducer.State()
        ) {
            CustomDictionaryReducer()
        } withDependencies: {
            $0.customDictionaryClient.loadEntries = { entries }
        }

        await store.send(.onAppear)

        await store.receive(.entriesLoaded(.success(entries))) {
            $0.entries = IdentifiedArrayOf(uniqueElements: entries)
        }
    }

    // MARK: - Test 2: addButtonTapped で正常追加

    func test_addButtonTapped_正常追加() async {
        var addedEntry: DictionaryEntry?
        let testUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        let store = TestStore(
            initialState: CustomDictionaryReducer.State(
                newReading: "こんぽーざぶる",
                newDisplay: "Composable"
            )
        ) {
            CustomDictionaryReducer()
        } withDependencies: {
            $0.uuid = .constant(testUUID)
            $0.customDictionaryClient.addEntry = { entry in
                addedEntry = entry
            }
        }

        await store.send(.addButtonTapped) {
            $0.isAdding = true
            $0.validationError = nil
        }

        let expectedEntry = DictionaryEntry(
            id: testUUID,
            reading: "こんぽーざぶる",
            display: "Composable"
        )

        await store.receive(.addCompleted(.success(expectedEntry))) {
            $0.isAdding = false
            $0.entries.append(expectedEntry)
            $0.newReading = ""
            $0.newDisplay = ""
        }

        XCTAssertNotNil(addedEntry)
        XCTAssertEqual(addedEntry?.reading, "こんぽーざぶる")
        XCTAssertEqual(addedEntry?.display, "Composable")
    }

    // MARK: - Test 3: 追加後に入力欄クリア

    func test_addButtonTapped_追加後に入力欄クリア() async {
        let testUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        let store = TestStore(
            initialState: CustomDictionaryReducer.State(
                newReading: "てすと",
                newDisplay: "テスト"
            )
        ) {
            CustomDictionaryReducer()
        } withDependencies: {
            $0.uuid = .constant(testUUID)
            $0.customDictionaryClient.addEntry = { _ in }
        }

        await store.send(.addButtonTapped) {
            $0.isAdding = true
            $0.validationError = nil
        }

        let expectedEntry = DictionaryEntry(
            id: testUUID,
            reading: "てすと",
            display: "テスト"
        )

        await store.receive(.addCompleted(.success(expectedEntry))) {
            $0.isAdding = false
            $0.entries.append(expectedEntry)
            $0.newReading = ""
            $0.newDisplay = ""
        }
    }

    // MARK: - Test 4: 空入力バリデーション

    func test_addButtonTapped_空入力バリデーション() async {
        let store = TestStore(
            initialState: CustomDictionaryReducer.State(
                newReading: "",
                newDisplay: ""
            )
        ) {
            CustomDictionaryReducer()
        }

        await store.send(.addButtonTapped) {
            $0.validationError = "読みと表記の両方を入力してください"
        }
    }

    // MARK: - Test 5: 表記空バリデーション

    func test_addButtonTapped_表記空バリデーション() async {
        let store = TestStore(
            initialState: CustomDictionaryReducer.State(
                newReading: "てすと",
                newDisplay: ""
            )
        ) {
            CustomDictionaryReducer()
        }

        await store.send(.addButtonTapped) {
            $0.validationError = "読みと表記の両方を入力してください"
        }
    }

    // MARK: - Test 6: 重複バリデーション

    func test_addButtonTapped_重複バリデーション() async {
        let existingEntry = DictionaryEntry(
            id: UUID(), reading: "てすと", display: "テスト"
        )

        let store = TestStore(
            initialState: CustomDictionaryReducer.State(
                entries: [existingEntry],
                newReading: "てすと",
                newDisplay: "テスト"
            )
        ) {
            CustomDictionaryReducer()
        }

        await store.send(.addButtonTapped) {
            $0.validationError = "この単語は既に登録されています"
        }
    }

    // MARK: - Test 7: deleteEntry でエントリ削除

    func test_deleteEntry_エントリ削除() async {
        let entryID = UUID()
        let entry = DictionaryEntry(id: entryID, reading: "てすと", display: "テスト")

        let store = TestStore(
            initialState: CustomDictionaryReducer.State(
                entries: [entry]
            )
        ) {
            CustomDictionaryReducer()
        } withDependencies: {
            $0.customDictionaryClient.deleteEntry = { _ in }
        }

        await store.send(.deleteEntry(id: entryID))

        await store.receive(.deleteCompleted(.success(entryID))) {
            $0.entries = []
        }
    }

    // MARK: - Test 8: deleteEntry失敗でエラー表示

    func test_deleteEntry_failure_エラー表示() async {
        let entryID = UUID()
        let entry = DictionaryEntry(id: entryID, reading: "てすと", display: "テスト")

        let store = TestStore(
            initialState: CustomDictionaryReducer.State(
                entries: [entry]
            )
        ) {
            CustomDictionaryReducer()
        } withDependencies: {
            $0.customDictionaryClient.deleteEntry = { _ in
                throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "削除エラー"])
            }
        }

        await store.send(.deleteEntry(id: entryID))

        await store.receive(.deleteCompleted(.failure("削除エラー"))) {
            $0.errorMessage = "削除エラー"
        }
    }

    // MARK: - Test 9: addCompleted失敗でエラー表示

    func test_addCompleted_failure_エラー表示() async {
        let store = TestStore(
            initialState: CustomDictionaryReducer.State(
                newReading: "てすと",
                newDisplay: "テスト"
            )
        ) {
            CustomDictionaryReducer()
        } withDependencies: {
            $0.uuid = .constant(UUID())
            $0.customDictionaryClient.addEntry = { _ in
                throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "追加エラー"])
            }
        }

        await store.send(.addButtonTapped) {
            $0.isAdding = true
            $0.validationError = nil
        }

        await store.receive(.addCompleted(.failure("追加エラー"))) {
            $0.isAdding = false
            $0.errorMessage = "追加エラー"
        }
    }

    // MARK: - Test 10: newReadingChanged でバリデーションエラークリア

    func test_newReadingChanged_バリデーションエラークリア() async {
        let store = TestStore(
            initialState: CustomDictionaryReducer.State(
                validationError: "読みと表記の両方を入力してください"
            )
        ) {
            CustomDictionaryReducer()
        }

        await store.send(.newReadingChanged("てすと")) {
            $0.newReading = "てすと"
            $0.validationError = nil
        }
    }

    // MARK: - Test 11: dismissError

    func test_dismissError() async {
        let store = TestStore(
            initialState: CustomDictionaryReducer.State(
                validationError: "エラー1",
                errorMessage: "エラー2"
            )
        ) {
            CustomDictionaryReducer()
        }

        await store.send(.dismissError) {
            $0.errorMessage = nil
            $0.validationError = nil
        }
    }
}
