import Foundation
import SwiftData

/// SwiftData @Model: カスタム辞書エントリの永続化モデル
/// TASK-0018: カスタム辞書（STT精度向上）
/// UserDefaults からの移行: アプリ再インストール時にデータが消えない永続ストレージ
@Model
public final class CustomDictionaryEntryModel {
    @Attribute(.unique) public var id: UUID
    /// 読み仮名（ひらがな/カタカナ）
    public var reading: String
    /// 表示テキスト（漢字/英語等、SFSpeechRecognizer の contextualStrings にセット）
    public var display: String
    /// 作成日時
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        reading: String,
        display: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.reading = reading
        self.display = display
        self.createdAt = createdAt
    }
}
