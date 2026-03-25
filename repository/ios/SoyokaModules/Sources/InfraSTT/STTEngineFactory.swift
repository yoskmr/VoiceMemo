import Domain
import Foundation

/// STTエンジンのファクトリ実装
/// 01-Arch セクション4.2: STTエンジン切替フロー準拠
/// iOS 26+ では SpeechAnalyzer を主エンジンとして使用する
public final class STTEngineFactory: STTEngineFactoryProtocol, @unchecked Sendable {

    private let selector: STTEngineSelector
    private let lock = NSLock()

    public init(selector: STTEngineSelector = STTEngineSelector()) {
        self.selector = selector
    }

    // MARK: - STTEngineFactoryProtocol

    public func createEngine(type: STTEngineType) -> any STTEngineProtocol {
        switch type {
        case .speechAnalyzer, .whisperKit, .cloudSTT:
            if #available(iOS 26.0, macOS 26.0, *) {
                return SpeechAnalyzerEngine()
            } else {
                return AppleSpeechEngine()
            }
        }
    }

    public func resolveEngine(
        context: STTEngineSelectionContext
    ) async -> (engine: any STTEngineProtocol, actualType: STTEngineType)? {
        let preferredType = selector.selectEngine(context: context)
        let engine = createEngine(type: preferredType)
        if await engine.isAvailable() {
            return (engine, .speechAnalyzer)
        }
        // フォールバック: AppleSpeechEngine
        let fallback = AppleSpeechEngine()
        if await fallback.isAvailable() {
            return (fallback, .speechAnalyzer)
        }
        return nil
    }
}
