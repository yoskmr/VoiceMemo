import Foundation

/// WidgetKit Extension に提供するデータ
/// Widget Extension（Xcode ターゲット）とアプリ本体間の共有データ構造
public struct WidgetMemoData: Sendable, Equatable {
    public let latestMemoTitle: String?
    public let todayMemoCount: Int
    public let todayRecordingDuration: TimeInterval

    public init(
        latestMemoTitle: String?,
        todayMemoCount: Int,
        todayRecordingDuration: TimeInterval
    ) {
        self.latestMemoTitle = latestMemoTitle
        self.todayMemoCount = todayMemoCount
        self.todayRecordingDuration = todayRecordingDuration
    }
}

/// Widget の Deep Link URL 定義
/// Widget タップ時にアプリ内の特定画面へ遷移するための URL スキーム
public enum WidgetDeepLink {
    /// 録音画面を直接開く
    public static let record = URL(string: "soyoka://record")!

    /// 特定メモの詳細画面を開く
    public static func memo(id: UUID) -> URL {
        URL(string: "soyoka://memo/\(id.uuidString)")!
    }
}
