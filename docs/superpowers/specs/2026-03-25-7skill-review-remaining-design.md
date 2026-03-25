# 7スキルレビュー残件対応 設計書

## 概要

Phase 2.5完了後の7スキル統合レビュー（SwiftUI Pro / Performance / Concurrency / Security / Architecture / Accessibility / Testing）で検出された全39件の指摘のうち、未対応の6件を完了させ、Phase 2をクローズする。

## 背景

- 元プラン: `.claude/plans/20260320232916_7スキル統合レビュー指摘_全39件対応プラン.md`
- 対応済み: 33件（84%）
- 残件: 6件（本設計書の対象）
- 対応不要と判定: B-3（MainActor軽減・iOS制約で限界）、F-2（エラーパステスト・実装済み）

## チーム体制

```
Team 1: UI/Performance + Accessibility（3件）
  C-1, C-2+E-2, C-3
  → RecordingCompletionView.swift の変更が重なるため1チームで

Team 2: Architecture（2件）
  D-2, F-3
  → Reducer層で完結

Team 3: Testing（1件）← Team 1,2 完了後
  F-1
  → 修正後コードに対して正確なテストを書くため後発
```

---

## Team 1: UI/Performance + Accessibility

### C-1. WaveformView cachedHeightsメモ化（🟡 Performance）

**ファイル**: `Sources/SharedUI/Components/WaveformView.swift`

**現状**: `barHeight(for:)` が毎フレーム（30fps）× 40バー = 毎秒1,200回呼ばれる。audioLevelが変化しない間は無駄な再計算。

**変更内容**:
1. `@State private var cachedHeights: [CGFloat]` を追加（初期値: 40個の最小高さ）
2. `onChange(of: audioLevel)` で `recalculateHeights()` を呼び出し、cachedHeightsを更新
3. `ForEach` 内で `barHeight(for:)` → `cachedHeights[index]` に置換
4. `recalculateHeights()` 内で既存の `barHeight(for:)` ロジックを使用

**受入基準**:
- audioLevel未変化時にbarHeight計算が走らないこと
- 波形アニメーションの見た目が変わらないこと
- ビルド成功、既存テストパス

### C-2 + E-2. RecordingCompletionView Reducer接続 + reduceMotion（🔴 Architecture + 🟡 Accessibility）

**ファイル**: `Sources/FeatureRecording/Views/RecordingCompletionView.swift`

**現状**:
- Reducer側（RecordingFeature.swift）に `CompletionStage` enum + 段階的遷移ロジックは実装済み
- View側は `@State private var showContent = false` で独自アニメーション制御のまま → Reducer状態と乖離
- reduceMotion未対応

**変更内容**:
1. `@State private var showContent = false` を削除
2. `store.completionStage` を参照して各要素の表示/非表示を制御:
   - `.initial`: 全非表示
   - `.checkmark`: アイコン表示
   - `.preview`: アイコン + メッセージ表示
   - `.cta`: 全表示（ボタン含む）
3. `@Environment(\.accessibilityReduceMotion) private var reduceMotion` を追加
4. reduceMotion == true の場合、`.spring()` → `.none` (即時表示)
5. `.onAppear` の `withAnimation` ブロックを削除（Reducer側のタイマーで制御）

**受入基準**:
- CompletionStageの各段階で対応するUI要素のみ表示されること
- reduceMotion有効時にアニメーションがスキップされること
- RecordingFeatureTests の completionStage テストがパスすること

### C-3. EmotionCategory.color プロパティ一元化（🟡 Architecture）

**ファイル**: `Sources/Domain/ValueObjects/EmotionCategoryUI.swift`

**現状**: `EmotionCategoryUI.swift` に `label` / `iconName` は定義済み。`color` プロパティの定義場所を確認し、未定義なら追加。EmotionBadge.swift が `emotion.color` を参照しているため、どこかに定義が存在する可能性あり。

**変更内容**:
1. `EmotionCategoryUI.swift` に `color` プロパティが未定義の場合:
   - `import SwiftUI` を追加
   - `public var color: Color` を switch 文で8カテゴリ分定義
   - EmotionBadge.swift / MemoDetailView.swift の重複色定義があれば削除
2. 既に定義済みの場合: 確認のみ（対応不要）

**受入基準**:
- EmotionCategory.color が1箇所のみで定義されていること
- EmotionBadge、MemoDetailView から正しく参照できること

---

## Team 2: Architecture

### D-2. MemoListReducer.State 分割（🟡 Architecture）

**ファイル**: `Sources/FeatureMemo/MemoList/MemoListReducer.swift`

**現状**: State に26プロパティが平坦に並ぶ。TODO コメント（L14-16）で分割が示唆済み。

**変更内容**:
1. `SearchState` 子Stateを定義:
   ```swift
   public struct SearchState: Equatable {
       public var query: String = ""
       public var results: [SearchResultItem] = []
       public var isSearching: Bool = false
       public var isActive: Bool { !query.isEmpty }
   }
   ```
2. `DeletionState` 子Stateを定義:
   ```swift
   public struct DeletionState: Equatable {
       public var pendingID: UUID? = nil
       public var showConfirmation: Bool = false
   }
   ```
3. State本体の `searchQuery`/`searchResults`/`isSearching` → `search: SearchState` に置換
4. State本体の `pendingDeleteID`/`showDeleteConfirmation` → `deletion: DeletionState` に置換
5. Reducer body 内の参照を `state.search.query` / `state.deletion.pendingID` 等に更新
6. MemoListView.swift の参照も更新
7. MemoListReducerTests.swift の State 生成を更新
8. TODO コメント（L14-16）を削除
9. init パラメータを更新（子State をまとめて受け取る形式）

**受入基準**:
- State のトップレベルプロパティ数が減少すること（26 → 20以下）
- 全既存テストがパスすること
- MemoListView の検索・削除が正常動作すること

### F-3. Divider accessibilityHidden（🟢 Accessibility）

**ファイル**: `Sources/FeatureMemo/MemoDetail/MemoDetailView.swift`

**現状**: MemoDetailAIOnboardingSheet 内の Divider にアクセシビリティ属性なし。

**変更内容**:
- デコレーション用 Divider に `.accessibilityHidden(true)` を追加

**受入基準**:
- VoiceOverで Divider が読み上げられないこと

---

## Team 3: Testing

### F-1. exhaustivity = .off 解消（🟡 Testing）

**対象ファイル**（5ファイル）:
1. `Tests/FeatureRecordingTests/RecordingFeatureTests.swift`
2. `Tests/FeatureAITests/AIProcessingReducerTests.swift`
3. `Tests/FeatureMemoTests/MemoDetailAIIntegrationTests.swift`
4. `Tests/FeatureMemoTests/MemoDetailReducerTests.swift`
5. `Tests/FeatureMemoTests/MemoListReducerTests.swift`

**方針**:
- `.off` を除去し、全アクションを明示的にassert
- 非決定的エフェクト順序がある場合は `store.receive` の順序を整理するか、`store.skipReceivedActions()` でスキップ
- 完全解消が困難な箇所（非同期エフェクトの実行順が本質的に非決定的）は `.off` を残しつつ理由コメントを明記

**受入基準**:
- `.off` の使用箇所が可能な限り削減されていること
- 残存する `.off` には理由コメントが付いていること
- 全テストがパスすること

---

## 実装順序

```
Phase 1（並列）:
├── Team 1: C-1 → C-2+E-2 → C-3
└── Team 2: D-2 → F-3

Phase 2（Team 1,2完了後）:
└── Team 3: F-1
```

## 検証方法

1. **ビルド**: Xcode MCPでビルド成功
2. **テスト**: `swift test` で全テストパス
3. **UI確認**: 録音→完了画面のアニメーション段階表示、波形の滑らかさ
4. **アクセシビリティ**: VoiceOverで Divider 非読み上げ、reduceMotion有効時の即時表示
5. **コードレビュー**: spec-gate + code-reviewer（新規spawn）
