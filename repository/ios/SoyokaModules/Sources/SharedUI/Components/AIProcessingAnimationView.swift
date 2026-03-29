import SwiftUI

/// AI整理中に表示する呼吸パーティクルアニメーション
/// Soyokaの暖色系パレットを使用し、やわらかく回転する光の粒子を描画する
/// Canvas + TimelineView による30fpsアニメーション
/// reduceMotion対応: アニメーション無効時は静的表示にフォールバック
public struct AIProcessingAnimationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    // MARK: - vmPrimary の RGB 値（Canvas 内では Color.vmPrimary が使えないため）
    // HSB(0.0556, 0.54, 0.91) → RGB 近似値
    private let primaryRed: Double = 0.91
    private let primaryGreen: Double = 0.64
    private let primaryBlue: Double = 0.42

    public var body: some View {
        VStack(spacing: VMDesignTokens.Spacing.lg) {
            if reduceMotion {
                staticView
            } else {
                animatedView
            }

            Text("ことばを整えています…")
                .font(.vmCallout)
                .foregroundColor(.vmTextSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI整理中")
    }

    // MARK: - 静的表示（reduceMotion時）

    private var staticView: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 40))
            .foregroundColor(.vmPrimary)
            .frame(width: 120, height: 120)
    }

    // MARK: - アニメーション表示

    private var animatedView: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let time = timeline.date.timeIntervalSinceReferenceDate

                drawParticles(context: context, center: center, time: time)
                drawCenterSparkle(context: context, center: center, time: time)
            }
            .frame(width: 120, height: 120)
        }
    }

    // MARK: - パーティクル描画

    private func drawParticles(
        context: GraphicsContext,
        center: CGPoint,
        time: TimeInterval
    ) {
        let particleCount = 7
        for i in 0..<particleCount {
            let angle = Double(i) / Double(particleCount) * .pi * 2 + time * 0.3
            let breathOffset = sin(time * 0.5 + Double(i)) * 10
            let radius: CGFloat = 35 + CGFloat(breathOffset)

            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius

            let particleSize = CGFloat(6 + sin(time * 0.8 + Double(i) * 0.5) * 3)
            let opacity = 0.3 + sin(time * 0.6 + Double(i) * 0.7) * 0.3

            let rect = CGRect(
                x: x - particleSize / 2,
                y: y - particleSize / 2,
                width: particleSize,
                height: particleSize
            )

            let color = Color(
                red: primaryRed,
                green: primaryGreen,
                blue: primaryBlue,
                opacity: opacity
            )
            context.fill(Circle().path(in: rect), with: .color(color))
        }
    }

    // MARK: - 中央スパークル描画

    private func drawCenterSparkle(
        context: GraphicsContext,
        center: CGPoint,
        time: TimeInterval
    ) {
        let sparkleSize: CGFloat = 24 + CGFloat(sin(time * 0.4)) * 4
        let sparkleRect = CGRect(
            x: center.x - sparkleSize / 2,
            y: center.y - sparkleSize / 2,
            width: sparkleSize,
            height: sparkleSize
        )

        // Canvas の resolve() は Image 型のみ受け付けるため、
        // opacity は context レベルで設定し、Image を直接 resolve する
        var tintedContext = context
        tintedContext.opacity = 0.6
        let sparkleImage = tintedContext.resolve(Image(systemName: "sparkles"))
        tintedContext.draw(sparkleImage, in: sparkleRect)
    }
}
