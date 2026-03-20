import Domain
import SwiftUI

/// メモカードで表示するデータ
/// SharedUI層はFeature層に依存しないため、独自のデータモデルを持つ
public struct MemoCardData: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let createdAt: Date
    public let durationSeconds: Double
    public let transcriptPreview: String
    public let emotion: EmotionCategory?
    public let tags: [String]

    public init(
        id: UUID,
        title: String,
        createdAt: Date,
        durationSeconds: Double,
        transcriptPreview: String,
        emotion: EmotionCategory?,
        tags: [String]
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.transcriptPreview = transcriptPreview
        self.emotion = emotion
        self.tags = tags
    }
}

/// メモカードコンポーネント
/// 設計書 04-ui-design-system.md セクション4.2 準拠
public struct MemoCard: View {
    public let data: MemoCardData

    public init(data: MemoCardData) {
        self.data = data
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.sm) {
            // ヘッダー: 日時 + 録音時間
            HStack {
                Label(formattedDate, systemImage: "calendar")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextSecondary)
                Spacer()
                Label(formattedDuration, systemImage: "mic.fill")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)
            }

            // タイトル
            Text(data.title)
                .font(.vmTitle3)
                .foregroundColor(.vmTextPrimary)
                .lineLimit(1)

            // プレビューテキスト（最大60文字、2行制限）
            Text(previewText)
                .font(.vmCallout)
                .foregroundColor(.vmTextSecondary)
                .lineLimit(2)

            // フッター: 感情バッジ + タグチップ
            HStack(spacing: VMDesignTokens.Spacing.sm) {
                if let emotion = data.emotion {
                    EmotionBadge(emotion: emotion)
                }
                ForEach(data.tags.prefix(3), id: \.self) { tag in
                    TagChip(text: tag)
                }
            }
        }
        .padding(VMDesignTokens.Spacing.lg)
        .background(Color.vmSurface)
        .cornerRadius(VMDesignTokens.CornerRadius.medium)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(data.title), \(formattedDate), \(formattedDuration)の録音")
        .accessibilityHint("ダブルタップで詳細を表示します")
        .accessibilityValue(data.emotion?.label ?? "感情分析なし")
    }

    // MARK: - Computed Properties

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: data.createdAt)
    }

    private var formattedDuration: String {
        let minutes = Int(data.durationSeconds) / 60
        let seconds = Int(data.durationSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var previewText: String {
        if data.transcriptPreview.count > 60 {
            return String(data.transcriptPreview.prefix(60)) + "..."
        }
        return data.transcriptPreview
    }
}
