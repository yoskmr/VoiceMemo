# 7スキルレビュー残件対応 設計書

## 概要

Phase 2.5完了後の7スキル統合レビュー（SwiftUI Pro / Performance / Concurrency / Security / Architecture / Accessibility / Testing）で検出された全39件の指摘のうち、未対応の5件を完了させ、Phase 2をクローズする。

## 背景

- 元プラン: `.claude/plans/20260320232916_7スキル統合レビュー指摘_全39件対応プラン.md`
- 対応済み: 34件（87%） — C-3含む（EmotionCategoryColor.swiftに実装済み）
- 残件: 5件（本設計書の対象）
- 対応不要と判定:
  - B-3（MainActor軽減）: TODO追加済み、iOS 17のSwiftData制約で限界
  - F-2（エラーパステスト）: 複数モジュール（InfraSTT, InfraLLM, FeatureRecording等）で実装済み
  - C-3（EmotionCategory.color一元化）: `SharedUI/DesignTokens/EmotionCategoryColor.swift` に実装済み。Domain層はSwiftUI非依存のため、SharedUI層での色定義が正しい設計
  - C-5（highlightedTextキャッシュ化）: `MemoListView.swift` L244-277で `parseSnippet()` → `[(String, Bool)]` タプル配列方式で実装済み。元プランの「init内1回実行」ではなくView描画時に呼び出す形だが、`parseSnippet`は軽量な文字列分割のみでパフォーマンス上許容可能

## チーム体制

```
Team 1: UI/Performance + Accessibility（2件）
  C-1, C-2+E-2
  → RecordingCompletionView.swift と WaveformView.swift を担当

Team 2: Architecture（2件）
  D-2, F-3
  → MemoListReducer.swift + MemoListView.swift + MemoListReducerTests.swift + MemoDetailView.swift

Team 3: Testing（1件）← Team 1,2 完了後
  F-1
  → D-2のState変更後にMemoListReducerTests.swiftを書き直す必要があるため後発
```

---

## Team 1: UI/Performance + Accessibility

### C-1. WaveformView cachedHeightsメモ化（🟡 Performance）

**ファイル**: `Sources/SharedUI/Components/WaveformView.swift`

**現状**: `barHeight(for:)` が毎フレーム（30fps）× 40バー = 毎秒1,200回呼ばれる。`lastAudioLevel`（L16）は導入済みだが、`ForEach`内（L36）は依然として`barHeight(for:)`を直接呼び出しており、`wavePhase`変化（毎フレーム）のたびに全バーが再計算される。

**変更内容**:
1. `@State private var cachedHeights: [CGFloat]` を追加（初期値: `Array(repeating: VMDesignTokens.Spacing.xs, count: 40)`）
2. 既存の `onChange(of: timeline.date)` ブロック内で、audioLevel変化時のみ `recalculateHeights()` を呼び出し cachedHeights を更新（`wavePhase` 変化のみの場合はスキップ）
3. `ForEach` 内で `barHeight(for: index)` → `cachedHeights[index]` に置換
4. `recalculateHeights()` は既存の `barHeight(for:)` ロジックを使用し、全40バー分を一括計算

**受入基準**:
- audioLevel未変化時にbarHeight計算が走らないこと
- 波形アニメーションの見た目が変わらないこと
- ビルド成功、既存テストパス

### C-2 + E-2. RecordingCompletionView Reducer接続 + reduceMotion（🔴 Architecture + 🟡 Accessibility）

**ファイル**: `Sources/FeatureRecording/Views/RecordingCompletionView.swift`

**現状**:
- Reducer側（RecordingFeature.swift）に `CompletionStage` enum + 段階的遷移ロジックは実装済み
- View側は `@State private var showContent = false` で独自アニメーション制御のまま → Reducer状態と乖離
- reduceMotion未対応（※ RecordingView.swift は reduceMotion 対応済み。本件は RecordingCompletionView.swift のみが対象）

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

---

## Team 2: Architecture

### D-2. MemoListReducer.State 分割（🟡 Architecture）

**ファイル**:
- `Sources/FeatureMemo/MemoList/MemoListReducer.swift`（主変更）
- `Sources/FeatureMemo/MemoList/MemoListView.swift`（参照更新）
- `Tests/FeatureMemoTests/MemoListReducerTests.swift`（State生成更新）

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
6. MemoListView.swift の参照を更新（特に `$store.searchQuery.sending(\.searchQueryChanged)` → `$store.search.query.sending(\.searchQueryChanged)`、`store.isSearchActive` → `store.search.isActive` 等）
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
├── Team 1: C-1 → C-2+E-2
└── Team 2: D-2 → F-3

Phase 2（Team 1,2完了後）:
└── Team 3: F-1（D-2のState変更がMemoListReducerTests.swiftに波及するため）
```

## 検証方法

1. **ビルド**: Xcode MCPでビルド成功
2. **テスト**: `swift test` で全テストパス
3. **UI確認**: 録音→完了画面のアニメーション段階表示、波形の滑らかさ
4. **アクセシビリティ**: VoiceOverで Divider 非読み上げ、reduceMotion有効時の即時表示
5. **コードレビュー**: spec-gate + code-reviewer（新規spawn）
