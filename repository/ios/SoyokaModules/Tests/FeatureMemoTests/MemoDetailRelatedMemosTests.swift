import ComposableArchitecture
import Domain
import XCTest

@testable import FeatureMemo

/// TASK-0043: つながるきおく（関連メモ）のReducerテスト
@MainActor
final class MemoDetailRelatedMemosTests: XCTestCase {

    // MARK: - Test Helpers

    private let testMemoID = UUID()
    private let testDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEntity(
        id: UUID? = nil,
        title: String = "テストメモ",
        createdAt: Date? = nil,
        transcription: TranscriptionEntity? = nil,
        tags: [TagEntity] = []
    ) -> VoiceMemoEntity {
        VoiceMemoEntity(
            id: id ?? testMemoID,
            title: title,
            createdAt: createdAt ?? testDate,
            durationSeconds: 180,
            audioFilePath: "Audio/test.m4a",
            transcription: transcription,
            aiSummary: nil,
            emotionAnalysis: nil,
            tags: tags
        )
    }

    /// 共通のDependency設定
    private func configureDependencies(
        _ deps: inout DependencyValues,
        entity: VoiceMemoEntity,
        isPro: Bool = true,
        relatedMemos: [RelatedMemo] = []
    ) {
        deps.voiceMemoRepository.fetchMemoDetail = { _ in entity }
        deps.aiProcessingQueue.observeStatus = { _ in AsyncStream { $0.finish() } }
        deps.aiQuota.remainingCount = { 10 }
        deps.aiQuota.monthlyLimit = { 10 }
        deps.subscriptionClient.currentSubscription = {
            isPro ? .pro(expiresAt: Date.distantFuture) : .free
        }
        deps.relatedMemo.findRelated = { _, _, _ in relatedMemos }
    }

    // MARK: - Test 1: Pro ユーザーで関連メモが取得される

    func test_loadRelatedMemos_Pro_関連メモが取得される() async {
        let relatedID1 = UUID()
        let relatedID2 = UUID()
        let relatedMemos = [
            RelatedMemo(
                id: relatedID1,
                title: "関連メモ1",
                createdAt: Date(timeIntervalSince1970: 1_700_000_100),
                emotion: .joy,
                tags: ["テスト"],
                relevanceScore: 0.9
            ),
            RelatedMemo(
                id: relatedID2,
                title: "関連メモ2",
                createdAt: Date(timeIntervalSince1970: 1_700_000_200),
                emotion: nil,
                tags: [],
                relevanceScore: 0.5
            ),
        ]

        let tagID = UUID()
        let store = TestStore(
            initialState: MemoDetailReducer.State(
                memoID: testMemoID,
                title: "テストメモ",
                tags: [MemoDetailReducer.State.TagItem(id: tagID, name: "テスト", source: "ai")],
                isPro: true
            )
        ) {
            MemoDetailReducer()
        } withDependencies: {
            $0.relatedMemo.findRelated = { _, _, _ in relatedMemos }
        }

        await store.send(.loadRelatedMemos) {
            $0.isLoadingRelated = true
        }

        await store.receive(\.relatedMemosLoaded.success) {
            $0.isLoadingRelated = false
            $0.relatedMemos = relatedMemos
        }
    }

    // MARK: - Test 2: Free ユーザーで関連メモが取得されない

    func test_loadRelatedMemos_Free_関連メモが取得されない() async {
        let store = TestStore(
            initialState: MemoDetailReducer.State(
                memoID: testMemoID,
                title: "テストメモ",
                isPro: false
            )
        ) {
            MemoDetailReducer()
        }

        // isPro = false なので、Effect は発行されず State も変化しない
        await store.send(.loadRelatedMemos)
    }

    // MARK: - Test 3: relatedMemoTapped アクション送信

    func test_relatedMemoTapped_アクション送信() async {
        let tappedID = UUID()
        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        }

        // relatedMemoTapped は親 Reducer に伝播するだけなので State 変更なし
        await store.send(.relatedMemoTapped(tappedID))
    }

    // MARK: - Test 4: エラー時に画面が壊れない

    func test_relatedMemosLoaded_failure_エラーでも画面が壊れない() async {
        let store = TestStore(
            initialState: MemoDetailReducer.State(
                memoID: testMemoID,
                isLoadingRelated: true,
                isPro: true
            )
        ) {
            MemoDetailReducer()
        }

        // failure を受信しても relatedMemos は空のまま、isLoadingRelated が false に戻る
        await store.send(.relatedMemosLoaded(.failure(EquatableError("検索エラー")))) {
            $0.isLoadingRelated = false
        }

        XCTAssertTrue(store.state.relatedMemos.isEmpty)
    }

    // MARK: - Test 5: subscriptionStateChecked で isPro がセットされる

    func test_subscriptionStateChecked_isProが更新される() async {
        let store = TestStore(
            initialState: MemoDetailReducer.State(
                memoID: testMemoID,
                isPro: false
            )
        ) {
            MemoDetailReducer()
        }

        await store.send(.subscriptionStateChecked(true)) {
            $0.isPro = true
        }
    }

    // MARK: - Test 6: onAppear で subscriptionStateChecked が呼ばれる

    func test_onAppear_subscriptionStateが確認される() async {
        let entity = makeEntity(
            transcription: TranscriptionEntity(fullText: "テスト")
        )

        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        } withDependencies: {
            self.configureDependencies(&$0, entity: entity, isPro: true)
        }
        // exhaustivity = .off: onAppear が複数の並行エフェクトを .merge で起動し、受信順序が非決定的なため
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        // subscriptionStateChecked(true) が受信されることを確認（isPro = true）
        await store.receive(\.subscriptionStateChecked) {
            XCTAssertTrue($0.isPro)
        }
    }
}
