import Foundation

/// ビルド環境フラグ
/// DEBUG / STAGING / RELEASE のビルド設定に基づいて環境を判定する
public enum AppEnvironment: String, Sendable {
    case production
    case staging
    case development

    public static var current: AppEnvironment {
        #if DEBUG
        return .development
        #elseif STAGING
        return .staging
        #else
        return .production
        #endif
    }

    public var isDebugMenuEnabled: Bool {
        self != .production
    }
}
