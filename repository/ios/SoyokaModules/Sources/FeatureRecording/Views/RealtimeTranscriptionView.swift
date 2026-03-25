import SharedUI
import SwiftUI

/// リアルタイム文字起こしテキスト表示ビュー
/// スクロール可能なテキスト領域に部分結果を表示する
/// 設計書 TASK-0008 セクション5 準拠
struct RealtimeTranscriptionView: View {
    let text: String
    let confidenceLevel: ConfidenceLevel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(displayText)
                    .font(.vmBody())
                    .foregroundColor(text.isEmpty ? .vmTextTertiary : .vmTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(VMDesignTokens.Spacing.lg)

                // スクロール先アンカー
                Color.clear
                    .frame(height: 1)
                    .id("bottom")
            }
            .onChange(of: text) {
                // テキスト更新時に最下部へ自動スクロール
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: 300)
        .background(Color.vmSurfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: VMDesignTokens.CornerRadius.small))
        .overlay(alignment: .topTrailing) {
            if !text.isEmpty {
                ConfidenceIndicator(level: confidenceLevel)
                    .padding(VMDesignTokens.Spacing.sm)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("文字起こし: \(displayText)")
    }

    private var displayText: String {
        text.isEmpty ? "話し始めると文字が表示されます..." : text
    }
}
