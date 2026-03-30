import XCTest
@testable import Domain

final class STTEngineSelectorTests: XCTestCase {

    private var selector: STTEngineSelector!

    override func setUp() {
        super.setUp()
        selector = STTEngineSelector()
    }

    override func tearDown() {
        selector = nil
        super.tearDown()
    }

    // MARK: - 正常系: ユーザー手動設定が最優先

    func test_userPreference_overrides_all_other_conditions() {
        // ユーザーが手動で whisperKit を指定した場合、
        // Pro + ネットワーク接続でもユーザー設定が優先される
        let context = STTEngineSelectionContext(
            userPreference: .whisperKit,
            subscriptionPlan: .pro,
            isNetworkAvailable: true,
            isDeviceCapable: true,
            isIOS26OrLater: true
        )
        let result = selector.selectEngine(context: context)
        XCTAssertEqual(result, .whisperKit)
    }

    func test_userPreference_speechAnalyzer_is_respected() {
        let context = STTEngineSelectionContext(
            userPreference: .speechAnalyzer,
            subscriptionPlan: .free,
            isNetworkAvailable: false,
            isDeviceCapable: true,
            isIOS26OrLater: false
        )
        let result = selector.selectEngine(context: context)
        XCTAssertEqual(result, .speechAnalyzer)
    }

    func test_userPreference_cloudSTT_is_respected() {
        let context = STTEngineSelectionContext(
            userPreference: .cloudSTT,
            subscriptionPlan: .free,
            isNetworkAvailable: false,
            isDeviceCapable: false,
            isIOS26OrLater: false
        )
        let result = selector.selectEngine(context: context)
        XCTAssertEqual(result, .cloudSTT)
    }

    // MARK: - 正常系: Proプラン + ネットワーク接続 -> cloudSTT

    func test_pro_plan_with_network_returns_cloudSTT() {
        let context = STTEngineSelectionContext(
            userPreference: nil,
            subscriptionPlan: .pro,
            isNetworkAvailable: true,
            isDeviceCapable: true,
            isIOS26OrLater: false
        )
        let result = selector.selectEngine(context: context)
        XCTAssertEqual(result, .cloudSTT)
    }

    // MARK: - 正常系: iOS 26+ -> speechAnalyzer

    func test_iOS26_returns_speechAnalyzer() {
        let context = STTEngineSelectionContext(
            userPreference: nil,
            subscriptionPlan: .free,
            isNetworkAvailable: false,
            isDeviceCapable: true,
            isIOS26OrLater: true
        )
        let result = selector.selectEngine(context: context)
        XCTAssertEqual(result, .speechAnalyzer)
    }

    // MARK: - 正常系: iOS 17-25 + A16+ -> whisperKit

    func test_iOS17_25_capable_device_returns_whisperKit() {
        let context = STTEngineSelectionContext(
            userPreference: nil,
            subscriptionPlan: .free,
            isNetworkAvailable: false,
            isDeviceCapable: true,
            isIOS26OrLater: false
        )
        let result = selector.selectEngine(context: context)
        XCTAssertEqual(result, .whisperKit)
    }

    // MARK: - 正常系: フォールバック -> speechAnalyzer

    func test_incapable_device_falls_back_to_speechAnalyzer() {
        let context = STTEngineSelectionContext(
            userPreference: nil,
            subscriptionPlan: .free,
            isNetworkAvailable: false,
            isDeviceCapable: false,
            isIOS26OrLater: false
        )
        let result = selector.selectEngine(context: context)
        XCTAssertEqual(result, .speechAnalyzer)
    }

    // MARK: - 異常系: ネットワーク切断時に cloudSTT が選択されない

    func test_pro_plan_without_network_does_not_return_cloudSTT() {
        let context = STTEngineSelectionContext(
            userPreference: nil,
            subscriptionPlan: .pro,
            isNetworkAvailable: false,
            isDeviceCapable: true,
            isIOS26OrLater: false
        )
        let result = selector.selectEngine(context: context)
        XCTAssertNotEqual(result, .cloudSTT)
        // Pro + ネットワーク無し + capable device -> whisperKit
        XCTAssertEqual(result, .whisperKit)
    }

    func test_free_plan_with_network_does_not_return_cloudSTT() {
        let context = STTEngineSelectionContext(
            userPreference: nil,
            subscriptionPlan: .free,
            isNetworkAvailable: true,
            isDeviceCapable: true,
            isIOS26OrLater: false
        )
        let result = selector.selectEngine(context: context)
        XCTAssertNotEqual(result, .cloudSTT)
    }

    // MARK: - 優先度の確認: Pro + ネットワーク + iOS 26+ の場合

    func test_pro_network_iOS26_prefers_cloudSTT_over_speechAnalyzer() {
        // Pro + ネットワークが iOS 26 より優先度が高い
        let context = STTEngineSelectionContext(
            userPreference: nil,
            subscriptionPlan: .pro,
            isNetworkAvailable: true,
            isDeviceCapable: true,
            isIOS26OrLater: true
        )
        let result = selector.selectEngine(context: context)
        XCTAssertEqual(result, .cloudSTT)
    }
}
