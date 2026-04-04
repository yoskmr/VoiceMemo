import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct APIRequestLogClient: Sendable {
    public var append: @Sendable (APIRequestLog) async -> Void
    public var getAll: @Sendable () async -> [APIRequestLog] = { [] }
    public var clear: @Sendable () async -> Void
    public var export: @Sendable () async -> String = { "" }
}

extension APIRequestLogClient: DependencyKey {
    public static let liveValue = APIRequestLogClient(
        append: { log in await APIRequestLogStore.shared.append(log) },
        getAll: { await APIRequestLogStore.shared.getAll() },
        clear: { await APIRequestLogStore.shared.clear() },
        export: { await APIRequestLogStore.shared.export() }
    )
}

extension DependencyValues {
    public var apiRequestLog: APIRequestLogClient {
        get { self[APIRequestLogClient.self] }
        set { self[APIRequestLogClient.self] = newValue }
    }
}
