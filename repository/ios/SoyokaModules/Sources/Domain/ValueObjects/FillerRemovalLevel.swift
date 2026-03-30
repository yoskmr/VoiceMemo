import Foundation

/// フィラー除去レベル設定
/// 音声認識結果から除去するフィラーワードの範囲を制御する。
///
/// - `none`: 除去なし（フィラーを一切除去しない）
/// - `light`: 軽度除去（思考中フィラーのみ: えーと、あのー、うーん等）
/// - `aggressive`: 完全除去（口癖系・相槌系も含めて除去）
public enum FillerRemovalLevel: String, Codable, CaseIterable, Sendable {
    case none
    case light
    case aggressive
}
