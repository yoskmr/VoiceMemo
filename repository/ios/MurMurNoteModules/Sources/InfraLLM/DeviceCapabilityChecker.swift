import Foundation
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

        public init(
            physicalMemory: UInt64,
            machineIdentifier: String,
            availableMemoryProvider: @escaping @Sendable () -> UInt64
        ) {
            self.physicalMemory = physicalMemory
            self.machineIdentifier = machineIdentifier
            self.availableMemoryProvider = availableMemoryProvider
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
            }
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

    /// Apple Intelligence 利用可否（Phase 3a では常に false）
    public var supportsAppleIntelligence: Bool {
        // Phase 3a 初版では false 固定
        // iOS 26 正式版の API 確定後に有効化する
        false
    }

    /// STT実行中のメモリ余裕チェック（LLM実行に2GB以上必要）
    public var hasMemoryHeadroomForLLM: Bool {
        let availableMemory = environment.availableMemoryProvider()
        return availableMemory > 2 * 1024 * 1024 * 1024  // 2GB以上
    }

    /// 物理メモリ合計（GB）
    public var totalMemoryGB: UInt64 {
        environment.physicalMemory / (1024 * 1024 * 1024)
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
}
