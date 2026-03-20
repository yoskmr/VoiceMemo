import XCTest
@testable import Domain
@testable import InfraSTT

/// STTEngineFactory のフォールバックロジックをテストする
/// テスト対象: resolveEngine のフォールバックチェーン
///
/// 注意: InfraSTTTests では実際のエンジン（AppleSpeechEngine, WhisperKitEngine）の
/// isAvailable() はデバイス依存のため、STTEngineSelector のロジックテストは
/// DomainTests/STTEngineSelectorTests で実施する。
/// ここでは STTEngineFactory.createEngine の型マッチングと
/// STTEngineSelector のインテグレーションをテストする。
final class STTEngineFactoryTests: XCTestCase {

    // MARK: - createEngine

    func test_createEngine_speechAnalyzer_returns_appleSpeechEngine() {
        let factory = STTEngineFactory()
        let engine = factory.createEngine(type: .speechAnalyzer)
        XCTAssertEqual(engine.engineType, .speechAnalyzer)
    }

    func test_createEngine_whisperKit_returns_whisperKitEngine() {
        let factory = STTEngineFactory()
        let engine = factory.createEngine(type: .whisperKit)
        XCTAssertEqual(engine.engineType, .whisperKit)
    }

    func test_createEngine_cloudSTT_falls_back_to_appleSpeech() {
        // クラウドSTTは未実装のためAppleSpeechEngineにフォールバック
        let factory = STTEngineFactory()
        let engine = factory.createEngine(type: .cloudSTT)
        XCTAssertEqual(engine.engineType, .speechAnalyzer)
    }

    // MARK: - STTEngineSelector integration through Factory

    func test_selector_integration_userPreference_respected() {
        let selector = STTEngineSelector()
        let context = STTEngineSelectionContext(
            userPreference: .whisperKit,
            subscriptionPlan: .pro,
            isNetworkAvailable: true,
            isDeviceCapable: true,
            isIOS26OrLater: true
        )
        let selectedType = selector.selectEngine(context: context)
        XCTAssertEqual(selectedType, .whisperKit)
    }
}
