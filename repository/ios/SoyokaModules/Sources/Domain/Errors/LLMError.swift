import Foundation

/// LLMプロバイダに関するエラー
/// Phase 3a 詳細設計 DES-PHASE3A-001 セクション5.2 準拠
public enum LLMError: Error, Equatable, Sendable {
    /// モデルファイル未ダウンロード
    case modelNotFound
    /// モデルロード失敗
    case modelLoadFailed(String)
    /// メモリ不足（LLMモデルのロードに必要なメモリが確保できない）
    case memoryInsufficient
    /// 入力テキストが短すぎる（10文字未満）
    case inputTooShort
    /// 入力テキストが長すぎる（500文字超、オンデバイス制限）
    case inputTooLong
    /// LLM出力のJSONパース失敗
    case invalidOutput
    /// LLM推論中のエラー
    case processingFailed(String)
    /// 月10回制限到達
    case quotaExceeded
    /// 非対応デバイス（A16 Bionic 未満またはメモリ6GB未満）
    case deviceNotSupported
    /// ユーザーキャンセル
    case cancelled
}
