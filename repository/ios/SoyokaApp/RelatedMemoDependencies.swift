import Dependencies
import Domain
import Foundation

// MARK: - Related Memo Dependencies
// TASK-0043: きおくのつながり Phase 1（FTS5 + タグスコアリング方式）

extension RelatedMemoClient: DependencyKey {
    public static let liveValue: RelatedMemoClient = {
        @Dependency(\.fts5IndexManager) var fts5IndexManager
        @Dependency(\.voiceMemoRepository) var voiceMemoRepository

        return RelatedMemoClient(
            findRelated: { memoID, title, tags in
                // 1. FTS5でタイトルをクエリとして検索（snippetColumn=1: title列, maxTokens=32）
                let ftsResults = try fts5IndexManager.searchWithSnippets(title, 1, 32)

                // 2. 自分自身を除外
                let otherResults = ftsResults.filter { UUID(uuidString: $0.memoID) != memoID }

                // 3. memoIDリストからメモ情報を一括取得
                let memoIDs = otherResults.compactMap { UUID(uuidString: $0.memoID) }
                guard !memoIDs.isEmpty else { return [] }
                let memosDict = try await voiceMemoRepository.fetchMemosByIDs(memoIDs)

                // 4. スコアリング（FTS5ランク + タグ一致ボーナス）
                var scored: [(RelatedMemo, Double)] = []
                for (index, ftsResult) in otherResults.enumerated() {
                    guard let id = UUID(uuidString: ftsResult.memoID),
                          let memo = memosDict[id] else { continue }

                    // FTS5の検索順位をスコアに変換（先頭ほど高スコア）
                    let ftsScore = 1.0 / Double(index + 1)

                    // タグ一致ボーナス
                    let commonTags = Set(tags).intersection(Set(memo.tags))
                    let tagBonus = Double(commonTags.count) * 0.2

                    let totalScore = min(ftsScore + tagBonus, 1.0)

                    scored.append((
                        RelatedMemo(
                            id: id,
                            title: memo.title,
                            createdAt: memo.createdAt,
                            emotion: memo.emotion,
                            tags: memo.tags,
                            relevanceScore: totalScore
                        ),
                        totalScore
                    ))
                }

                // 5. スコア降順でソート、上位5件を返す
                return scored
                    .sorted { $0.1 > $1.1 }
                    .prefix(5)
                    .map(\.0)
            }
        )
    }()
}
