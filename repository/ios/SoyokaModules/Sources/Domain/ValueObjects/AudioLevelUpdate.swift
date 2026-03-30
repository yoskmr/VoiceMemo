import Foundation

/// 音量レベル更新情報
/// 録音中のリアルタイム音量メーター表示に使用する
public struct AudioLevelUpdate: Sendable, Equatable {
    /// 平均パワー（dB値）。無音時は -160.0 に近い値
    public let averagePower: Float
    /// ピークパワー（dB値）。無音時は -160.0 に近い値
    public let peakPower: Float
    /// 録音開始からの経過時間（秒）
    public let timestamp: TimeInterval

    public init(averagePower: Float, peakPower: Float, timestamp: TimeInterval) {
        self.averagePower = averagePower
        self.peakPower = peakPower
        self.timestamp = timestamp
    }
}
