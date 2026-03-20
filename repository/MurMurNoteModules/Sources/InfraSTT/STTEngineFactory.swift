import Domain
import Foundation

/// STTエンジンのファクトリ実装
/// 01-Arch セクション4.2: STTエンジン切替フロー準拠
/// STTEngineSelector による自動選択 + フォールバックチェーンを提供する
public final class STTEngineFactory: STTEngineFactoryProtocol, @unchecked Sendable {

    private let selector: STTEngineSelector
    private let lock = NSLock()

    public init(selector: STTEngineSelector = STTEngineSelector()) {
        self.selector = selector
    }

    // MARK: - STTEngineFactoryProtocol

    public func createEngine(type: STTEngineType) -> any STTEngineProtocol {
        switch type {
        case .speechAnalyzer:
            return AppleSpeechEngine()
        case .whisperKit:
            return WhisperKitEngine()
        case .cloudSTT:
            // クラウドSTTは将来実装。現時点ではAppleSpeechEngineにフォールバック
            return AppleSpeechEngine()
        }
    }

    public func resolveEngine(
        context: STTEngineSelectionContext
    ) async -> (engine: any STTEngineProtocol, actualType: STTEngineType)? {
        let preferredType = selector.selectEngine(context: context)
        return await resolveEngineWithFallback(preferredType: preferredType)
    }

    // MARK: - Fallback Chain

    /// 優先エンジンを試行し、利用不可の場合はフォールバックチェーンを辿る
    /// フォールバック順: whisperKit -> speechAnalyzer
    private func resolveEngineWithFallback(
        preferredType: STTEngineType
    ) async -> (engine: any STTEngineProtocol, actualType: STTEngineType)? {
        // 優先エンジンを試行
        let preferred = createEngine(type: preferredType)
        if await preferred.isAvailable() {
            return (preferred, preferredType)
        }

        // フォールバックチェーン
        let fallbackOrder: [STTEngineType] = [.whisperKit, .speechAnalyzer]
        for type in fallbackOrder where type != preferredType {
            let engine = createEngine(type: type)
            if await engine.isAvailable() {
                return (engine, type)
            }
        }

        return nil // 全エンジン利用不可
    }
}
