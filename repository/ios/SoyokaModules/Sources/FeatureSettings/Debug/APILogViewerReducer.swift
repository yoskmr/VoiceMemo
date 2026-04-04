#if DEBUG
import ComposableArchitecture
import Foundation
import InfraLogging

/// デバッグ用 API リクエストログビューア Reducer
/// InfraLogging の APIRequestLogClient を通じてログの取得・フィルタ・クリア・エクスポートを担う
@Reducer
public struct APILogViewer {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        public var logs: [APIRequestLog] = []
        public var filter: LogSource? = nil
        public var showClearConfirmation = false

        /// フィルタ適用後のログ一覧（`filter == nil` のとき全件返す）
        public var filteredLogs: [APIRequestLog] {
            guard let filter else { return logs }
            return logs.filter { $0.source == filter }
        }

        public init() {}
    }

    // MARK: - Action

    public enum Action: Equatable, Sendable {
        case onAppear
        case logsLoaded([APIRequestLog])
        case filterChanged(LogSource?)
        case clearTapped
        case clearConfirmed
        case clearDismissed
        case exportTapped
        case copyTapped(APIRequestLog)
        case refreshRequested
    }

    // MARK: - Dependencies

    @Dependency(\.apiRequestLog) var apiRequestLog

    // MARK: - Reducer Body

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear, .refreshRequested:
                return .run { send in
                    let logs = await apiRequestLog.getAll()
                    await send(.logsLoaded(logs))
                }

            case let .logsLoaded(logs):
                state.logs = logs
                return .none

            case let .filterChanged(source):
                state.filter = source
                return .none

            case .clearTapped:
                state.showClearConfirmation = true
                return .none

            case .clearConfirmed:
                state.logs = []
                state.showClearConfirmation = false
                return .run { _ in
                    await apiRequestLog.clear()
                }

            case .clearDismissed:
                state.showClearConfirmation = false
                return .none

            case .exportTapped:
                return .run { _ in
                    let json = await apiRequestLog.export()
                    await MainActor.run {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = json
                        #endif
                    }
                }

            case let .copyTapped(log):
                return .run { _ in
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                    encoder.dateEncodingStrategy = .iso8601
                    if let data = try? encoder.encode(log),
                       let json = String(data: data, encoding: .utf8) {
                        await MainActor.run {
                            #if canImport(UIKit)
                            UIPasteboard.general.string = json
                            #endif
                        }
                    }
                }
            }
        }
    }
}
#endif
