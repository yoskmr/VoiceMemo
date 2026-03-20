import Foundation

/// ユーザー設定リポジトリプロトコル
public protocol UserSettingsRepositoryProtocol: Sendable {
    /// 設定の保存（新規作成・更新兼用）
    func save(_ settings: UserSettingsEntity) async throws

    /// 現在の設定を取得（存在しなければデフォルト設定を返す）
    func fetch() async throws -> UserSettingsEntity

    /// AI処理カウントのインクリメント
    func incrementAIProcessingCount() async throws

    /// 月次カウントのリセット
    func resetMonthlyCount() async throws
}
