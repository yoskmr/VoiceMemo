import XCTest
@testable import InfraLLM

final class DeviceCapabilityCheckerTests: XCTestCase {

    // MARK: - チップ世代解析テスト

    func testParseChipGeneration_iPhone15_returnsA16() {
        let checker = makeChecker(machine: "iPhone15,2")
        XCTAssertEqual(checker.chipGeneration, 16)
    }

    func testParseChipGeneration_iPhone16_returnsA17() {
        let checker = makeChecker(machine: "iPhone16,1")
        XCTAssertEqual(checker.chipGeneration, 17)
    }

    func testParseChipGeneration_iPhone17_returnsA18() {
        let checker = makeChecker(machine: "iPhone17,3")
        XCTAssertEqual(checker.chipGeneration, 18)
    }

    func testParseChipGeneration_iPhone14_returnsA15() {
        let checker = makeChecker(machine: "iPhone14,7")
        XCTAssertEqual(checker.chipGeneration, 15)
    }

    func testParseChipGeneration_simulator_returns99() {
        let checker = makeChecker(machine: "arm64")
        XCTAssertEqual(checker.chipGeneration, 99)
    }

    func testParseChipGeneration_x86Simulator_returns99() {
        let checker = makeChecker(machine: "x86_64")
        XCTAssertEqual(checker.chipGeneration, 99)
    }

    func testParseChipGeneration_iPad14_returnsA16() {
        let checker = makeChecker(machine: "iPad14,1")
        XCTAssertEqual(checker.chipGeneration, 16)
    }

    func testParseChipGeneration_iPad13_returnsA15() {
        let checker = makeChecker(machine: "iPad13,4")
        XCTAssertEqual(checker.chipGeneration, 15)
    }

    func testParseChipGeneration_unknownDevice_returns0() {
        let checker = makeChecker(machine: "UnknownDevice1,1")
        XCTAssertEqual(checker.chipGeneration, 0)
    }

    // MARK: - メモリ判定テスト

    func testTotalMemoryGB_8GB() {
        let checker = makeChecker(physicalMemory: 8 * 1024 * 1024 * 1024)
        XCTAssertEqual(checker.totalMemoryGB, 8)
    }

    func testTotalMemoryGB_6GB() {
        let checker = makeChecker(physicalMemory: 6 * 1024 * 1024 * 1024)
        XCTAssertEqual(checker.totalMemoryGB, 6)
    }

    func testTotalMemoryGB_4GB() {
        let checker = makeChecker(physicalMemory: 4 * 1024 * 1024 * 1024)
        XCTAssertEqual(checker.totalMemoryGB, 4)
    }

    // MARK: - supportsOnDeviceLLM 総合テスト

    func testSupportsOnDeviceLLM_A16_8GB_true() {
        let checker = makeChecker(machine: "iPhone15,2", physicalMemory: 8 * 1024 * 1024 * 1024)
        XCTAssertTrue(checker.supportsOnDeviceLLM)
    }

    func testSupportsOnDeviceLLM_A16_6GB_true() {
        let checker = makeChecker(machine: "iPhone15,2", physicalMemory: 6 * 1024 * 1024 * 1024)
        XCTAssertTrue(checker.supportsOnDeviceLLM)
    }

    func testSupportsOnDeviceLLM_A15_6GB_false() {
        let checker = makeChecker(machine: "iPhone14,7", physicalMemory: 6 * 1024 * 1024 * 1024)
        XCTAssertFalse(checker.supportsOnDeviceLLM)
    }

    func testSupportsOnDeviceLLM_A16_4GB_false() {
        let checker = makeChecker(machine: "iPhone15,2", physicalMemory: 4 * 1024 * 1024 * 1024)
        XCTAssertFalse(checker.supportsOnDeviceLLM)
    }

    func testSupportsOnDeviceLLM_unknown_false() {
        let checker = makeChecker(machine: "UnknownDevice1,1", physicalMemory: 8 * 1024 * 1024 * 1024)
        XCTAssertFalse(checker.supportsOnDeviceLLM)
    }

    // MARK: - メモリヘッドルームテスト

    func testHasMemoryHeadroomForLLM_3GB_true() {
        let checker = makeChecker(availableMemory: 3 * 1024 * 1024 * 1024)
        XCTAssertTrue(checker.hasMemoryHeadroomForLLM)
    }

    func testHasMemoryHeadroomForLLM_1GB_false() {
        let checker = makeChecker(availableMemory: 1 * 1024 * 1024 * 1024)
        XCTAssertFalse(checker.hasMemoryHeadroomForLLM)
    }

    func testHasMemoryHeadroomForLLM_exactly2GB_false() {
        // 2GB ちょうどは「> 2GB」を満たさないため false
        let checker = makeChecker(availableMemory: 2 * 1024 * 1024 * 1024)
        XCTAssertFalse(checker.hasMemoryHeadroomForLLM)
    }

    // MARK: - Apple Intelligence テスト

    func testSupportsAppleIntelligence_withoutFoundationModels_returnsFalse() {
        // swift test (SPM macOS CLI) では FoundationModels が import 不可のため false
        #if !canImport(FoundationModels)
        let checker = makeChecker()
        XCTAssertFalse(checker.supportsAppleIntelligence)
        #endif
    }

    func testSupportsAppleIntelligence_overrideFalse_returnsFalse() {
        let checker = makeChecker(appleIntelligenceOverride: false)
        XCTAssertFalse(checker.supportsAppleIntelligence)
    }

    func testSupportsAppleIntelligence_overrideTrue_returnsTrue() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let checker = makeChecker(appleIntelligenceOverride: true)
            XCTAssertTrue(checker.supportsAppleIntelligence)
        }
        #endif
    }

    func testSupportsAppleIntelligence_A17Pro8GB_conditionMet() {
        // A17 Pro + 8GB は Apple Intelligence のハードウェア条件を満たす
        // FoundationModels import 可否で結果が異なる
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let checker = makeChecker(machine: "iPhone16,1", physicalMemory: 8 * 1024 * 1024 * 1024)
            XCTAssertTrue(checker.supportsAppleIntelligence)
        }
        #else
        let checker = makeChecker(machine: "iPhone16,1", physicalMemory: 8 * 1024 * 1024 * 1024)
        XCTAssertFalse(checker.supportsAppleIntelligence)
        #endif
    }

    func testSupportsAppleIntelligence_A16_6GB_notMet() {
        // A16 + 6GB は Apple Intelligence のハードウェア条件を満たさない
        // （A17 Pro 以降 + 8GB 必要）
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let checker = makeChecker(machine: "iPhone15,2", physicalMemory: 6 * 1024 * 1024 * 1024)
            XCTAssertFalse(checker.supportsAppleIntelligence)
        }
        #else
        let checker = makeChecker(machine: "iPhone15,2", physicalMemory: 6 * 1024 * 1024 * 1024)
        XCTAssertFalse(checker.supportsAppleIntelligence)
        #endif
    }

    // MARK: - Helper

    private func makeChecker(
        machine: String = "iPhone16,1",
        physicalMemory: UInt64 = 8 * 1024 * 1024 * 1024,
        availableMemory: UInt64 = 3 * 1024 * 1024 * 1024,
        appleIntelligenceOverride: Bool? = nil
    ) -> DeviceCapabilityChecker {
        let env = DeviceCapabilityChecker.Environment(
            physicalMemory: physicalMemory,
            machineIdentifier: machine,
            availableMemoryProvider: { availableMemory },
            appleIntelligenceAvailableOverride: appleIntelligenceOverride
        )
        return DeviceCapabilityChecker(environment: env)
    }
}
