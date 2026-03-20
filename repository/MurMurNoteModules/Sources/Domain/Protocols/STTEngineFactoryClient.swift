import Dependencies
import Foundation

/// STTEngineFactoryProtocol の TCA Dependency ラッパー
/// @Dependency(\.sttEngineFactory) でReducerから注入可能にする
public struct STTEngineFactoryClient: Sendable {
    /// 指定された種別のSTTエンジンを生成する
    public var createEngine: @Sendable (STTEngineType) -> any STTEngineProtocol
    /// 環境情報に基づいて最適なSTTエンジンを解決する（フォールバック付き）
    public var resolveEngine: @Sendable (STTEngineSelectionContext) async -> (engine: any STTEngineProtocol, actualType: STTEngineType)?
    /// 環境情報に基づいて最適なSTTエンジン種別のみを取得する（エンジン生成なし）
    public var selectEngineType: @Sendable (STTEngineSelectionContext) -> STTEngineType

    public init(
        createEngine: @escaping @Sendable (STTEngineType) -> any STTEngineProtocol,
        resolveEngine: @escaping @Sendable (STTEngineSelectionContext) async -> (engine: any STTEngineProtocol, actualType: STTEngineType)?,
        selectEngineType: @escaping @Sendable (STTEngineSelectionContext) -> STTEngineType
    ) {
        self.createEngine = createEngine
        self.resolveEngine = resolveEngine
        self.selectEngineType = selectEngineType
    }
}

// MARK: - DependencyKey

extension STTEngineFactoryClient: TestDependencyKey {
    public static let testValue = STTEngineFactoryClient(
        createEngine: unimplemented("STTEngineFactoryClient.createEngine"),
        resolveEngine: unimplemented("STTEngineFactoryClient.resolveEngine"),
        selectEngineType: unimplemented("STTEngineFactoryClient.selectEngineType")
    )
}

extension DependencyValues {
    public var sttEngineFactory: STTEngineFactoryClient {
        get { self[STTEngineFactoryClient.self] }
        set { self[STTEngineFactoryClient.self] = newValue }
    }
}
