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
/// ミニマルデザイン: タイトル → プレビュー → 日付・時間のシンプルな3段構成
public struct MemoCard: View {
    public let data: MemoCardData

    public init(data: MemoCardData) {
        self.data = data
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.sm) {
            // タイトル（最上部 — 最も重要な情報を先頭に）
            Text(data.title)
                .font(.vmHeadline)
                .foregroundColor(.vmTextPrimary)
                .lineLimit(1)

            // プレビューテキスト（最大60文字、2行制限）
            if !previewText.isEmpty {
                Text(previewText)
                    .font(.vmFootnote)
                    .foregroundColor(.vmTextSecondary)
                    .lineLimit(2)
            }

            // フッター: 日付とデュレーションをプレーンテキストで
            HStack {
                Text(formattedDate)
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)
                Spacer()
                Text(formattedDuration)
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)
            }
        }
        .padding(VMDesignTokens.Spacing.lg)
        .background(Color.vmSurface)
        .cornerRadius(VMDesignTokens.CornerRadius.medium)
        .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(data.title), \(formattedDate), \(formattedDuration)")
        .accessibilityHint("ダブルタップで詳細を表示します")
    }

    // MARK: - Computed Properties

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d"
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
