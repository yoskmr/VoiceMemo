import Foundation

/// 音声メモリポジトリプロトコル
/// CRUD + 検索機能を提供する
public protocol VoiceMemoRepositoryProtocol: Sendable {
    /// メモの保存（新規作成・更新兼用）
    func save(_ memo: VoiceMemoEntity) async throws

    /// IDによるメモ取得
    func fetchByID(_ id: UUID) async throws -> VoiceMemoEntity?

    /// 全メモの取得（作成日降順）
    func fetchAll() async throws -> [VoiceMemoEntity]

    /// メモの削除（カスケードでTranscription/AISummary/EmotionAnalysisも削除）
    func delete(_ id: UUID) async throws

    /// お気に入りメモの取得
    func fetchFavorites() async throws -> [VoiceMemoEntity]

    /// タグによるメモ検索
    func fetchByTag(_ tagName: String) async throws -> [VoiceMemoEntity]

    /// ステータスによるメモ検索
    func fetchByStatus(_ status: MemoStatus) async throws -> [VoiceMemoEntity]

    /// メモ数の取得
    func count() async throws -> Int
}
