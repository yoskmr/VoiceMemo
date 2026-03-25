import SwiftUI

/// リアルタイム音声波形アニメーションビュー
/// 設計書 04-ui-design-system.md セクション8 準拠
/// AudioLevelUpdate（0.0 - 1.0 正規化済み）を入力として波形を描画する
public struct WaveformView: View {

    /// 正規化された音声レベル（0.0 - 1.0）
    let audioLevel: Float
    /// 録音中かどうか（trueの場合アニメーション動作）
    let isRecording: Bool

    /// 波形のフェーズ（アニメーション駆動）
    @State private var wavePhase: Double = 0
    /// 前回の音声レベル（変化時のみbarHeight再計算用）
    @State private var lastAudioLevel: Float = 0
    /// 計算済みバー高さキャッシュ（audioLevel変化時のみ再計算）
    @State private var cachedHeights: [CGFloat] = Array(repeating: VMDesignTokens.Spacing.xs, count: 40)

    /// 波形バーの本数
    private let barCount = 40
    /// 波形の高さ
    private let waveHeight: CGFloat = 60

    public init(audioLevel: Float, isRecording: Bool) {
        self.audioLevel = audioLevel
        self.isRecording = isRecording
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            HStack(spacing: VMDesignTokens.Spacing.xxs) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: VMDesignTokens.Spacing.xxs)
                        .fill(barColor(for: index))
                        .frame(
                            width: 4,
                            height: cachedHeights[index]
                        )
                }
            }
            .frame(height: waveHeight)
            .onChange(of: timeline.date) { _, _ in
                if isRecording {
                    wavePhase += 0.1
                    if audioLevel != lastAudioLevel {
                        lastAudioLevel = audioLevel
                        recalculateHeights()
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("音声波形")
        .accessibilityValue(isRecording ? "音声レベル: \(Int(audioLevel * 100))%" : "停止中")
    }

    // MARK: - Bar Calculations

    /// 各バーの高さを計算する
    /// 音声レベルとsin波を組み合わせて自然な波形を生成
    private func barHeight(for index: Int) -> CGFloat {
        guard isRecording else {
            // 録音中でなければ最小高さ
            return VMDesignTokens.Spacing.xs
        }

        let normalizedLevel = CGFloat(lastAudioLevel)
        let wave = sin(Double(index) * 0.3 + wavePhase)
        let baseHeight: CGFloat = VMDesignTokens.Spacing.xs
        let maxAmplitude: CGFloat = 50

        return max(baseHeight, normalizedLevel * maxAmplitude * CGFloat(wave + 1) / 2 + baseHeight)
    }

    /// audioLevel変化時に全バーの高さを一括再計算
    private func recalculateHeights() {
        var heights = [CGFloat]()
        heights.reserveCapacity(barCount)
        for index in 0..<barCount {
            heights.append(barHeight(for: index))
        }
        cachedHeights = heights
    }

    /// 各バーの色（中央に近いほど濃い暖色）
    private func barColor(for index: Int) -> Color {
        let center = Double(barCount) / 2.0
        let distance = abs(Double(index) - center) / center
        let opacity = 0.4 + (1.0 - distance) * 0.5
        return Color.vmPrimary.opacity(opacity)
    }
}
