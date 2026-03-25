import Foundation

/// STTエンジンのファクトリプロトコル
/// TCA の @Dependency 経由でSTTエンジンを解決する
/// 01-Arch セクション4.2 準拠
public protocol STTEngineFactoryProtocol: Sendable {
    /// 指定された種別のSTTエンジンを生成する
    /// - Parameter type: STTエンジン種別
    /// - Returns: STTエンジンインスタンス
    func createEngine(type: STTEngineType) -> any STTEngineProtocol

    /// 環境情報に基づいて最適なSTTエンジンを解決する
    /// フォールバック付きでエンジンの利用可否もチェックする
    /// - Parameter context: エンジン選択に必要な環境情報
    /// - Returns: 利用可能なSTTエンジンと実際の種別のタプル。全エンジン利用不可の場合は nil
    func resolveEngine(
        context: STTEngineSelectionContext
    ) async -> (engine: any STTEngineProtocol, actualType: STTEngineType)?
}
