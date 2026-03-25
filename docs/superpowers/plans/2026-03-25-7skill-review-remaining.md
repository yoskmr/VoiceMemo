# 7スキルレビュー残件対応 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 7スキル統合レビュー残件5件を完了し、Phase 2をクローズする

**Architecture:** TCA (The Composable Architecture) + SwiftUI。変更はView層のReducer接続改善、State分割による凝集度向上、テストのexhaustivity強化の3軸。

**Tech Stack:** Swift 6.2 / SwiftUI / TCA 1.17+ / Swift Testing / SwiftData

**Spec:** `docs/superpowers/specs/2026-03-25-7skill-review-remaining-design.md`

**Module base path:** `repository/ios/MurMurNoteModules/`

---

## Task 1: WaveformView cachedHeightsメモ化（C-1）

**Team 1 — UI/Performance**

**Files:**
- Modify: `Sources/SharedUI/Components/WaveformView.swift`

- [ ] **Step 1: cachedHeights State を追加**

`WaveformView.swift` の `@State private var lastAudioLevel` の下に追加:

```swift
/// 計算済みバー高さキャッシュ（audioLevel変化時のみ再計算）
@State private var cachedHeights: [CGFloat] = Array(repeating: VMDesignTokens.Spacing.xs, count: 40)
```

- [ ] **Step 2: recalculateHeights() メソッドを追加**

`barHeight(for:)` の下に追加:

```swift
/// audioLevel変化時に全バーの高さを一括再計算
private func recalculateHeights() {
    var heights = [CGFloat]()
    heights.reserveCapacity(barCount)
    for index in 0..<barCount {
        heights.append(barHeight(for: index))
    }
    cachedHeights = heights
}
```

- [ ] **Step 3: onChange ブロックを修正**

`onChange(of: timeline.date)` 内を以下に変更:

```swift
.onChange(of: timeline.date) { _, _ in
    if isRecording {
        wavePhase += 0.1
        if audioLevel != lastAudioLevel {
            lastAudioLevel = audioLevel
            recalculateHeights()
        }
    }
}
```

- [ ] **Step 4: ForEach 内の barHeight 呼び出しを cachedHeights に置換**

```swift
// Before:
height: barHeight(for: index)

// After:
height: cachedHeights[index]
```

- [ ] **Step 5: ビルド確認**

Run: Xcode MCP でビルド（`xcode-mcp-workflow` スキル使用）
Expected: ビルド成功、警告なし

- [ ] **Step 6: コミット**

```bash
git add repository/ios/MurMurNoteModules/Sources/SharedUI/Components/WaveformView.swift
git commit -m "perf(ui): WaveformViewのbarHeight計算をcachedHeightsでメモ化

audioLevel未変化時の無駄な再計算（毎秒1,200回）を排除。
wavePhase変化のみのフレームではキャッシュを再利用する。"
```

---

## Task 2: RecordingCompletionView Reducer接続 + reduceMotion（C-2 + E-2）

**Team 1 — UI/Performance + Accessibility**

**Files:**
- Modify: `Sources/FeatureRecording/RecordingFeature.swift`（CompletionStage に Comparable 追加）
- Modify: `Sources/FeatureRecording/Views/RecordingCompletionView.swift`（View書き換え）

**前提:** `RecordingFeature.State.CompletionStage` enum と `.recordingSaved` での段階遷移ロジックは `RecordingFeature.swift` に実装済み（L77-86, L263-274）。RecordingView.swift の reduceMotion は対応済み。

- [ ] **Step 1: CompletionStage に Comparable 準拠を追加（RecordingFeature.swift）**

`RecordingFeature.swift` L77 の enum 定義を修正（View書き換えで `>=` 比較を使うための前提変更）:

```swift
public enum CompletionStage: Comparable, Equatable, Sendable {
    case initial
    case checkmark
    case preview
    case cta
}
```

Swift の enum は宣言順で Comparable が自動合成されるため、追加実装は不要。

- [ ] **Step 2: @State showContent を削除し、reduceMotion Environment を追加**

RecordingCompletionView.swift の先頭部分を修正:

```swift
struct RecordingCompletionView: View {
    let store: StoreOf<RecordingFeature>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // showContent は削除（store.completionStage で制御）
```

- [ ] **Step 3: body を CompletionStage ベースに書き換え（RecordingCompletionView.swift）**

```swift
var body: some View {
    let stage = store.completionStage
    let animation: Animation? = reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8)

    VStack(spacing: VMDesignTokens.Spacing.xl) {
        Spacer()

        // 温かいアイコン（吹き出し + チェック）
        Image(systemName: "bubble.left.fill")
            .font(.system(size: 44))
            .foregroundColor(.vmPrimary.opacity(0.8))
            .scaleEffect(stage >= .checkmark ? 1 : 0.6)
            .opacity(stage >= .checkmark ? 1 : 0)
            .animation(animation, value: stage)

        // 温かいメッセージ
        Text("書きとめました")
            .font(.vmTitle3)
            .foregroundColor(.vmTextPrimary)
            .opacity(stage >= .preview ? 1 : 0)
            .animation(animation, value: stage)

        // 自動停止メッセージ
        if store.wasAutoStopped {
            Text("5分に達したので終了しました")
                .font(.vmCaption1)
                .foregroundColor(.vmTextTertiary)
                .opacity(stage >= .preview ? 1 : 0)
                .animation(animation, value: stage)
        }

        Spacer()

        // ボタン
        VStack(spacing: VMDesignTokens.Spacing.md) {
            Button { store.send(.viewMemoTapped) } label: {
                Text("メモを見る")
                    .font(.vmHeadline)
                    .foregroundColor(.vmPrimary)
            }

            Button { store.send(.dismissCompletion) } label: {
                Text("あとで")
                    .font(.vmCallout)
                    .foregroundColor(.vmTextTertiary)
            }
        }
        .opacity(stage >= .cta ? 1 : 0)
        .animation(animation, value: stage)
        .padding(.bottom, VMDesignTokens.Spacing.xxxl)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.vmBackground.ignoresSafeArea())
}
```

- [ ] **Step 4: ビルド確認**

Run: Xcode MCP でビルド
Expected: ビルド成功

- [ ] **Step 5: Comparable 順序のテストを追加**

`Tests/FeatureRecordingTests/RecordingFeatureTests.swift` に追加:

```swift
@Test("CompletionStage の順序が initial < checkmark < preview < cta であること")
func test_completionStage_ordering() {
    let stages: [RecordingFeature.State.CompletionStage] = [.initial, .checkmark, .preview, .cta]
    for i in 0..<stages.count - 1 {
        #expect(stages[i] < stages[i + 1])
    }
}
```

- [ ] **Step 6: テスト実行**

Run: Xcode MCP でテスト（FeatureRecordingTests ターゲット）
Expected: 全テストパス（新規テスト + 既存 completionStage テスト）

- [ ] **Step 7: コミット**

```bash
git add repository/ios/MurMurNoteModules/Sources/FeatureRecording/Views/RecordingCompletionView.swift
git add repository/ios/MurMurNoteModules/Sources/FeatureRecording/RecordingFeature.swift
git commit -m "fix(ui): RecordingCompletionViewをReducer駆動に移行しreduceMotion対応

@State showContent を削除し store.completionStage で段階的表示を制御。
reduceMotion有効時はアニメーションをスキップして即時表示する。
RecordingView.swift は対応済みのため本件はCompletionViewのみが対象。"
```

---

## Task 3: MemoListReducer.State 分割（D-2）

**Team 2 — Architecture**

**Files:**
- Modify: `Sources/FeatureMemo/MemoList/MemoListReducer.swift`（主変更）
- Modify: `Sources/FeatureMemo/MemoList/MemoListView.swift`（参照更新）
- Modify: `Tests/FeatureMemoTests/MemoListReducerTests.swift`（State生成更新）

- [ ] **Step 1: SearchState 子State を定義**

`MemoListReducer.swift` の `State` 内（L18の `@ObservableState` の下、プロパティ定義の前）に追加:

```swift
/// 検索関連の子State（凝集度向上のため分離）
@ObservableState
public struct SearchState: Equatable, Sendable {
    public var query: String = ""
    public var results: [SearchResultItem] = []
    public var isSearching: Bool = false
    public var isActive: Bool { !query.isEmpty }

    public init(
        query: String = "",
        results: [SearchResultItem] = [],
        isSearching: Bool = false
    ) {
        self.query = query
        self.results = results
        self.isSearching = isSearching
    }
}
```

- [ ] **Step 2: DeletionState 子State を定義**

SearchState の下に追加:

```swift
/// 削除確認の子State（凝集度向上のため分離）
@ObservableState
public struct DeletionState: Equatable, Sendable {
    public var pendingID: UUID? = nil
    public var showConfirmation: Bool = false

    public init(
        pendingID: UUID? = nil,
        showConfirmation: Bool = false
    ) {
        self.pendingID = pendingID
        self.showConfirmation = showConfirmation
    }
}
```

- [ ] **Step 3: State 本体のプロパティを子State に置換**

State 本体から以下を削除:
- `public var searchQuery: String = ""`
- `public var searchResults: [SearchResultItem] = []`
- `public var isSearching: Bool = false`
- `public var isSearchActive: Bool { !searchQuery.isEmpty }` (computed)
- `public var pendingDeleteID: UUID?`
- `public var showDeleteConfirmation: Bool = false`

代わりに追加:
```swift
/// 検索関連
public var search: SearchState = SearchState()
/// 削除確認関連
public var deletion: DeletionState = DeletionState()
```

- [ ] **Step 4: State.init を更新**

initパラメータから個別プロパティを削除し、子Stateパラメータに置換:

```swift
public init(
    memos: IdentifiedArrayOf<MemoItem> = [],
    sections: [MemoSection] = [],
    isLoading: Bool = false,
    hasMorePages: Bool = true,
    currentPage: Int = 0,
    errorMessage: String? = nil,
    search: SearchState = SearchState(),
    selectedMemo: MemoDetailReducer.State? = nil,
    emotionTrendState: EmotionTrendReducer.State? = nil,
    pendingMemoID: UUID? = nil,
    deletion: DeletionState = DeletionState(),
    aiQuotaUsed: Int = 0,
    aiQuotaLimit: Int = 15,
    nextResetDate: Date? = nil,
    showQuotaExceededAlert: Bool = false
) {
    self.memos = memos
    self.sections = sections
    self.isLoading = isLoading
    self.hasMorePages = hasMorePages
    self.currentPage = currentPage
    self.errorMessage = errorMessage
    self.search = search
    self.selectedMemo = selectedMemo
    self.emotionTrendState = emotionTrendState
    self.pendingMemoID = pendingMemoID
    self.deletion = deletion
    self.aiQuotaUsed = aiQuotaUsed
    self.aiQuotaLimit = aiQuotaLimit
    self.nextResetDate = nextResetDate
    self.showQuotaExceededAlert = showQuotaExceededAlert
}
```

- [ ] **Step 5: Reducer body 内の参照を更新**

置換ルール（Reducer body 全体に適用）:

| Before | After |
|--------|-------|
| `state.searchQuery` | `state.search.query` |
| `state.searchResults` | `state.search.results` |
| `state.isSearching` | `state.search.isSearching` |
| `state.pendingDeleteID` | `state.deletion.pendingID` |
| `state.showDeleteConfirmation` | `state.deletion.showConfirmation` |

- [ ] **Step 6: TODO コメントを削除**

L14-16 の TODO コメント3行を削除:
```
// TODO: [#10] State分割 - 検索関連を SearchState 子Stateに分離（searchQuery, searchResults, isSearching）
// TODO: [#10] State分割 - 削除関連を DeletionState に分離（pendingDeleteID, showDeleteConfirmation）
// 現在のStateプロパティ数が多く凝集度が低いため、Phase後半でサブState化を検討する
```

- [ ] **Step 7: MemoListView.swift の参照を更新**

置換ルール:

| Before | After |
|--------|-------|
| `store.isSearchActive` (L19) | `store.search.isActive` |
| `$store.searchQuery.sending(\.searchQueryChanged)` (L28) | `$store.search.query.sending(\.searchQueryChanged)` |
| `$store.showDeleteConfirmation.sending(\.deleteConfirmationPresented)` (L58) | `$store.deletion.showConfirmation.sending(\.deleteConfirmationPresented)` |
| `store.isSearching` (L168) | `store.search.isSearching` |
| `store.searchResults.isEmpty` (L171) | `store.search.results.isEmpty` |
| `store.searchResults` (L177, ForEach) | `store.search.results` |

- [ ] **Step 8: ビルド確認**

Run: Xcode MCP でビルド
Expected: ビルド成功（コンパイルエラー0件）

- [ ] **Step 9: MemoListReducerTests.swift の State 生成を更新**

テストファイル内で `MemoListReducer.State(...)` を生成している箇所を更新:
- `searchQuery:` → `search: .init(query:)` 形式に変更
- `pendingDeleteID:` → `deletion: .init(pendingID:)` 形式に変更
- `showDeleteConfirmation:` → `deletion: .init(showConfirmation:)` 形式に変更

テスト内のアサーションも同様に更新:
- `store.state.searchQuery` → `store.state.search.query`
- `store.state.searchResults` → `store.state.search.results`
- etc.

- [ ] **Step 10: テスト実行**

Run: Xcode MCP でテスト（FeatureMemoTests ターゲット）
Expected: 全テストパス

- [ ] **Step 11: コミット**

```bash
git add repository/ios/MurMurNoteModules/Sources/FeatureMemo/MemoList/MemoListReducer.swift
git add repository/ios/MurMurNoteModules/Sources/FeatureMemo/MemoList/MemoListView.swift
git add repository/ios/MurMurNoteModules/Tests/FeatureMemoTests/MemoListReducerTests.swift
git commit -m "refactor(memo): MemoListReducer.StateをSearchState/DeletionStateに分割

Stateの凝集度向上のため検索関連と削除確認関連を子Stateに分離。
- searchQuery/searchResults/isSearching → search: SearchState
- pendingDeleteID/showDeleteConfirmation → deletion: DeletionState
- MemoListView/Testsの参照も更新"
```

---

## Task 4: Divider accessibilityHidden（F-3）

**Team 2 — Accessibility**

**Files:**
- Modify: `Sources/FeatureMemo/MemoDetail/MemoDetailView.swift`

- [ ] **Step 1: Divider に accessibilityHidden を追加**

`MemoDetailView.swift` の MemoDetailAIOnboardingSheet 内、Divider（L594付近）を修正:

```swift
// Before:
Divider()
    .padding(.horizontal, VMDesignTokens.Spacing.xxl)

// After:
Divider()
    .padding(.horizontal, VMDesignTokens.Spacing.xxl)
    .accessibilityHidden(true)
```

- [ ] **Step 2: ビルド確認**

Run: Xcode MCP でビルド
Expected: ビルド成功

- [ ] **Step 3: コミット**

```bash
git add repository/ios/MurMurNoteModules/Sources/FeatureMemo/MemoDetail/MemoDetailView.swift
git commit -m "fix(a11y): MemoDetailAIOnboardingSheetのDividerをVoiceOver非読み上げに

デコレーション用のDividerに.accessibilityHidden(true)を追加。
VoiceOverユーザーに不要な区切り線の読み上げを防ぐ。"
```

---

## Task 5: exhaustivity = .off 解消（F-1）

**Team 3 — Testing（Task 1-4 完了後に着手）**

**Files:**
- Modify: `Tests/FeatureRecordingTests/RecordingFeatureTests.swift`
- Modify: `Tests/FeatureAITests/AIProcessingReducerTests.swift`
- Modify: `Tests/FeatureMemoTests/MemoDetailAIIntegrationTests.swift`
- Modify: `Tests/FeatureMemoTests/MemoDetailReducerTests.swift`
- Modify: `Tests/FeatureMemoTests/MemoListReducerTests.swift`

Note: `.off` の正確な件数は各ファイルを `grep -c "exhaustivity = .off"` で確認すること（事前調査では5ファイル合計38箇所程度）。

**方針:**
- `.off` の主原因は `.onAppear` 等で並行エフェクト（データロード + クォータロード）が発生し、テストが片方しか検証していないパターン
- 修正方法: 欠落している `store.receive()` を追加するか、本質的に非決定的な順序の場合は `store.skipReceivedActions()` を使用
- 完全解消が困難な箇所（RecordingFeatureTests のタイマー/STTストリーム等、長時間running effect）は `.off` を残し理由コメントを明記

- [ ] **Step 1: 各テストファイルの .off を全数カウントし、修正方針を決定**

各ファイルで `grep -n "exhaustivity = .off"` を実行し、全箇所を列挙。
それぞれについて以下を判断:
- A) `store.receive()` 追加で解消可能 → 追加
- B) 非決定的順序で `store.skipReceivedActions()` が適切 → 置換
- C) 長時間running effectで解消困難 → `.off` 残存 + 理由コメント強化

判断結果をコメントとしてテストファイル先頭に記録してから修正に着手する。

- [ ] **Step 2: MemoListReducerTests.swift の .off を解消**

Note: Task 3（D-2）で State 参照が `search.query` / `deletion.pendingID` 等に変更済み。テストの State 生成は Task 3 Step 9 で更新済みのため、本 Step では `.off` 解消のみに集中する。
主パターン: `.onAppear` で `.memosLoaded` + `.aiQuotaLoaded` が並行発生 → `.aiQuotaLoaded` の `store.receive()` を追加。

- [ ] **Step 3: MemoDetailReducerTests.swift の .off を解消**

主パターン: `.onAppear` で `.memoLoaded` + `._quotaInfoLoaded` が並行発生。
`._quotaInfoLoaded` の `store.receive()` を追加。

- [ ] **Step 4: MemoDetailAIIntegrationTests.swift の .off を解消**

主パターン: `.onAppear` の並行エフェクト + AI処理ステータスストリーム。
`._quotaInfoLoaded` と `.aiProcessingStatusUpdated` の `store.receive()` を追加。

- [ ] **Step 5: AIProcessingReducerTests.swift の .off を解消**

主パターン: StatusStream の並行エフェクト。
可能な箇所で `store.receive()` 追加、非決定的順序は `store.skipReceivedActions()` 使用。

- [ ] **Step 6: RecordingFeatureTests.swift の .off を解消（可能な範囲）**

タイマー・STTストリームの長時間running effectは解消困難。
- 解消可能: `.test_permissionResponse_true` / `.test_recordButtonTapped_録音開始失敗` 等
- 残存: `.test_recordButtonTapped_権限許可済み` / `.test_stopButtonTapped` 等（タイマー/STTの全アクション列挙が非現実的）
- 残存箇所には理由コメントを明記:
```swift
// exhaustivity = .off: 録音中のタイマーtick/STTストリーム/audioLevelUpdateが
// 非決定的タイミングで発生し、全アクションの明示的検証が非現実的なため維持
store.exhaustivity = .off
```

- [ ] **Step 7: 全テスト実行**

Run: Xcode MCP でテスト（全ターゲット）
Expected: 全テストパス

- [ ] **Step 8: .off 残存箇所の理由コメント最終確認**

残存する全 `.off` に以下の形式のコメントがあることを確認:
```swift
// exhaustivity = .off: [具体的理由]
```

- [ ] **Step 9: コミット**

```bash
git add repository/ios/MurMurNoteModules/Tests/
git commit -m "test: exhaustivity = .off を可能な限り解消し理由コメントを追加

5テストファイルの全 .off 箇所を精査。
- 欠落していた store.receive() を追加して解消
- 非決定的エフェクト順序は skipReceivedActions() で対応
- タイマー/STTストリーム等の長時間running effectは .off 残存（理由コメント付き）"
```

---

## 実行順序と依存関係

```
Task 1 (C-1)  ─┐
                ├─ 並列実行可能（Team 1）
Task 2 (C-2)  ─┘

Task 3 (D-2)  ─┐
                ├─ 並列実行可能（Team 2）
Task 4 (F-3)  ─┘

Task 5 (F-1)  ← Task 3 完了後（State 変更の波及があるため）
```

## 完了後の検証

- [ ] Xcode MCP でフルビルド成功
- [ ] 全テストパス
- [ ] spec-gate 再レビュー（新規spawn）
- [ ] code-reviewer 実行（新規spawn）
