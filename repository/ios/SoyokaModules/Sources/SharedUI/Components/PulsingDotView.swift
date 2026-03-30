import SwiftUI

/// AI整理の待機中に表示するパルスアニメーション
/// 3つのドットが順番に拡大・縮小するローディングインジケータ
public struct PulsingDotView: View {
    @State private var isAnimating = false

    private let dotCount = 3
    private let dotSize: CGFloat = 8
    private let spacing: CGFloat = 6

    public init() {}

    public var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(Color.vmPrimary.opacity(0.6))
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .opacity(isAnimating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}
