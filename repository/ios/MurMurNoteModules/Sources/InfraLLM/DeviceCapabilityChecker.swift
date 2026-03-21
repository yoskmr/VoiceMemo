import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(UIKit)
import UIKit
#endif

/// デバイス能力チェッカー
/// P3A-REQ-004, P3A-REQ-005, P3A-REQ-014 準拠
///
/// オンデバイスLLM実行に必要なハードウェア条件を判定する:
/// - A16 Bionic 以降の SoC
/// - 6GB 以上の物理メモリ
/// - LLM 実行時に 2GB 以上の空きメモリ
public final class DeviceCapabilityChecker: Sendable {
    public static let shared = DeviceCapabilityChecker()

    /// テスト用に外部から値を注入できるように構造体で環境情報を保持
    public struct Environment: Sendable {
        public let physicalMemory: UInt64
        public let machineIdentifier: String
        public let availableMemoryProvider: @Sendable () -> UInt64
        /// テスト用: Apple Intelligence 利用可否をオーバーライド（nil = 実際のAPI判定を使用）
        public let appleIntelligenceAvailableOverride: Bool?

        public init(
            physicalMemory: UInt64,
            machineIdentifier: String,
            availableMemoryProvider: @escaping @Sendable () -> UInt64,
            appleIntelligenceAvailableOverride: Bool? = nil
        ) {
            self.physicalMemory = physicalMemory
            self.machineIdentifier = machineIdentifier
            self.availableMemoryProvider = availableMemoryProvider
            self.appleIntelligenceAvailableOverride = appleIntelligenceAvailableOverride
        }

        /// 実行環境のデフォルト値
        public static let live = Environment(
            physicalMemory: ProcessInfo.processInfo.physicalMemory,
            machineIdentifier: Self.currentMachineIdentifier(),
            availableMemoryProvider: {
                #if os(iOS) || os(tvOS) || os(watchOS)
                return UInt64(os_proc_available_memory())
                #else
                return 0
                #endif
            },
            appleIntelligenceAvailableOverride: nil
        )

        private static func currentMachineIdentifier() -> String {
            var systemInfo = utsname()
            uname(&systemInfo)
            return withUnsafePointer(to: &systemInfo.machine) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                    String(cString: $0)
                }
            }
        }
    }

    private let environment: Environment

    public init(environment: Environment = .live) {
        self.environment = environment
    }

    // MARK: - Public API

    /// REQ-021: A16 Bionic以降かつメモリ6GB以上
    public var supportsOnDeviceLLM: Bool {
        chipGeneration >= 16 && totalMemoryGB >= 6
    }

    /// Apple Intelligence 利用可否
    /// iOS 26+ かつ FoundationModels フレームワークが利用可能な環境で動的判定する
    ///
    /// 判定優先順位:
    /// 1. テスト用オーバーライド（`Environment.appleIntelligenceAvailableOverride`）
    /// 2. FoundationModels API の実際の利用可否チェック
    /// 3. FoundationModels が import 不可の環境では常に false
    public var supportsAppleIntelligence: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            // テスト用オーバーライドがあればそれを使用
            if let override = environment.appleIntelligenceAvailableOverride {
                return override
            }
            return _checkFoundationModelsAvailability()
        }
        return false
        #else
        // FoundationModels が import できない環境（SPM swift test 等）
        return false
        #endif
    }

    /// STT実行中のメモリ余裕チェック（LLM実行に2GB以上必要）
    public var hasMemoryHeadroomForLLM: Bool {
        let availableMemory = environment.availableMemoryProvider()
        return availableMemory > 2 * 1024 * 1024 * 1024  // 2GB以上
    }

    /// 物理メモリ合計（GB、切り上げ）
    /// 注意: OSがメモリの一部を予約するため、8GBデバイスでも physicalMemory が
    /// 約7.7GBと報告される。切り上げで実際のハードウェア仕様に合わせる。
    public var totalMemoryGB: UInt64 {
        let bytes = environment.physicalMemory
        let gb = bytes / (1024 * 1024 * 1024)
        let remainder = bytes % (1024 * 1024 * 1024)
        return remainder > 0 ? gb + 1 : gb
    }

    /// チップ世代番号（A16 -> 16, A17 -> 17 等）
    public var chipGeneration: Int {
        parseChipGeneration(from: environment.machineIdentifier)
    }

    // MARK: - Internal

    /// マシン識別子からチップ世代を解析する
    ///
    /// iPhone の識別子パターン:
    /// - "iPhone15,x" -> A16 Bionic (iPhone 14 Pro系)
    /// - "iPhone16,x" -> A17 Pro (iPhone 15 Pro系)
    /// - "arm64" -> Simulator (macOS)
    func parseChipGeneration(from machineIdentifier: String) -> Int {
        // Simulator 判定
        if machineIdentifier == "arm64" || machineIdentifier == "x86_64" {
            // Simulator ではホスト Mac の性能に依存するため、
            // 常にサポートありと判定する（開発時の利便性）
            return 99
        }

        // "iPhoneXX,Y" パターンを解析
        if machineIdentifier.hasPrefix("iPhone") {
            let numberPart = machineIdentifier.dropFirst("iPhone".count)
            if let commaIndex = numberPart.firstIndex(of: ",") {
                let majorStr = String(numberPart[numberPart.startIndex..<commaIndex])
                if let major = Int(majorStr) {
                    // iPhone15,x = A16 Bionic
                    // iPhone16,x = A17 Pro
                    // iPhone17,x = A18
                    return major + 1
                }
            }
        }

        // iPad の識別子パターン
        if machineIdentifier.hasPrefix("iPad") {
            let numberPart = machineIdentifier.dropFirst("iPad".count)
            if let commaIndex = numberPart.firstIndex(of: ",") {
                let majorStr = String(numberPart[numberPart.startIndex..<commaIndex])
                if let major = Int(majorStr) {
                    // iPad14,x = M2 チップ搭載（A16相当以上）
                    if major >= 14 {
                        return 16
                    }
                    // iPad13,x = M1 チップ搭載（A15相当）
                    if major >= 13 {
                        return 15
                    }
                }
            }
        }

        // 不明なデバイスは非サポートとして扱う
        return 0
    }

    // MARK: - FoundationModels 判定

    #if canImport(FoundationModels)
    /// FoundationModels (Apple Intelligence) の利用可否をチェック
    ///
    /// - A17 Pro 以降（iPhone 15 Pro+, 8GB+ RAM）で利用可能
    /// - OS 内蔵モデルのため、別途ダウンロード不要
    @available(iOS 26.0, macOS 26.0, *)
    private func _checkFoundationModelsAvailability() -> Bool {
        // FoundationModels が import できる環境 = Xcode 26+ / iOS 26+ SDK
        // LanguageModelSession の静的な利用可否チェック
        // 非対応デバイスでは LanguageModelSession の初期化自体は可能だが、
        // respond(to:) 呼び出し時にエラーとなるため、ここではデバイス条件で判定する
        //
        // Apple Intelligence 対応条件: A17 Pro 以降 (iPhone15 Pro = iPhone16,x) + 8GB RAM
        return chipGeneration >= 17 && totalMemoryGB >= 8
    }
    #endif
}
