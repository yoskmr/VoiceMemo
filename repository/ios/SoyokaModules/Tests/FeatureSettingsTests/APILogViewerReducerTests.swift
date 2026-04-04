#if DEBUG
import ComposableArchitecture
@testable import FeatureSettings
import InfraLogging
import XCTest

@MainActor
final class APILogViewerReducerTests: XCTestCase {

    private func makeLog(
        source: LogSource = .network,
        endpoint: String = "/api/v1/test",
        status: LogStatus = .success(statusCode: 200)
    ) -> APIRequestLog {
        APIRequestLog(
            source: source,
            endpoint: endpoint,
            method: "POST",
            status: status,
            duration: 1.0,
            request: RequestDetail(body: "{}"),
            response: ResponseDetail(body: "{}")
        )
    }

    func test_onAppear_ログが読み込まれる() async {
        let logs = [makeLog(endpoint: "/api/1"), makeLog(endpoint: "/api/2")]
        let store = TestStore(initialState: APILogViewer.State()) {
            APILogViewer()
        } withDependencies: {
            $0.apiRequestLog.getAll = { logs }
        }
        await store.send(.onAppear)
        await store.receive(\.logsLoaded) {
            $0.logs = logs
        }
    }

    func test_filterChanged_Networkのみ表示される() async {
        let store = TestStore(initialState: APILogViewer.State()) {
            APILogViewer()
        }
        await store.send(.filterChanged(.network)) {
            $0.filter = .network
        }
    }

    func test_filterChanged_nilで全件表示に戻る() async {
        var state = APILogViewer.State()
        state.filter = .network
        let store = TestStore(initialState: state) {
            APILogViewer()
        }
        await store.send(.filterChanged(nil)) {
            $0.filter = nil
        }
    }

    func test_filteredLogs_フィルタなし_全件返す() {
        var state = APILogViewer.State()
        state.logs = [makeLog(source: .network), makeLog(source: .llm)]
        state.filter = nil
        XCTAssertEqual(state.filteredLogs.count, 2)
    }

    func test_filteredLogs_Networkフィルタ_networkのみ返す() {
        var state = APILogViewer.State()
        state.logs = [
            makeLog(source: .network, endpoint: "/net"),
            makeLog(source: .llm, endpoint: "/llm"),
        ]
        state.filter = .network
        XCTAssertEqual(state.filteredLogs.count, 1)
        XCTAssertEqual(state.filteredLogs.first?.endpoint, "/net")
    }

    func test_clearTapped_確認アラートが表示される() async {
        let store = TestStore(initialState: APILogViewer.State()) {
            APILogViewer()
        }
        await store.send(.clearTapped) {
            $0.showClearConfirmation = true
        }
    }

    func test_clearConfirmed_ログがクリアされる() async {
        var initialState = APILogViewer.State()
        initialState.logs = [makeLog()]
        initialState.showClearConfirmation = true
        let store = TestStore(initialState: initialState) {
            APILogViewer()
        } withDependencies: {
            $0.apiRequestLog.clear = {}
        }
        await store.send(.clearConfirmed) {
            $0.logs = []
            $0.showClearConfirmation = false
        }
    }

    func test_clearDismissed_アラートが閉じる() async {
        var initialState = APILogViewer.State()
        initialState.showClearConfirmation = true
        let store = TestStore(initialState: initialState) {
            APILogViewer()
        }
        await store.send(.clearDismissed) {
            $0.showClearConfirmation = false
        }
    }

    func test_exportTapped_エフェクトが発火する() async {
        let store = TestStore(initialState: APILogViewer.State()) {
            APILogViewer()
        } withDependencies: {
            $0.apiRequestLog.export = { "{}" }
        }
        // TODO: exportTapped はエフェクト内で UIKit を呼ぶため exhaustivity をオフにする
        store.exhaustivity = .off
        await store.send(.exportTapped)
    }

    func test_refreshRequested_ログが再読み込みされる() async {
        let logs = [makeLog(endpoint: "/refreshed")]
        let store = TestStore(initialState: APILogViewer.State()) {
            APILogViewer()
        } withDependencies: {
            $0.apiRequestLog.getAll = { logs }
        }
        await store.send(.refreshRequested)
        await store.receive(\.logsLoaded) {
            $0.logs = logs
        }
    }
}
#endif
