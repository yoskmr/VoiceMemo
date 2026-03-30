# AI機能の可視化 UX改善 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 録音完了画面でAI処理の進行状況を表示し、ウェルカム画面とメモ一覧カードでAI機能の存在を可視化する

**Architecture:** RecordingFeature.State に `aiProcessingCompleted` を追加し、AppReducer の AI処理キュー監視から完了通知を中継。MemoCardData に `AIDisplayStatus` を追加しメモ一覧にAI状態アイコンを表示。

**Tech Stack:** Swift 6.2 / SwiftUI / TCA 1.17+ / Swift Testing

**Spec:** `docs/superpowers/specs/2026-03-28-ai-ux-visibility-design.md`

**Module base path:** `repository/ios/SoyokaModules/`
**App base path:** `repository/ios/SoyokaApp/`

---

## Task 1: ウェルカム画面にAI機能の一言説明を追加

**Files:**
- Modify: `repository/ios/SoyokaApp/WelcomeView.swift`

- [ ] **Step 1: キャッチコピーの下にサブテキストを追加**

`WelcomeView.swift` の `Text("声のままでいい。\nちゃんと残るから。")` ブロックの直後（L35の後）に追加:

```swift
Text("あなたの声を、整えて残します。")
    .font(.vmCaption1)
    .foregroundColor(.vmTextTertiary)
    .padding(.top, VMDesignTokens.Spacing.xs)
```

- [ ] **Step 2: ビルド確認**

Run: `xcode-mcp-workflow` スキルでビルド
Expected: ビルド成功

- [ ] **Step 3: コミット**

```bash
git add repository/ios/SoyokaApp/WelcomeView.swift
git commit -m "feat(ui): ウェルカム画面にAI機能の一言説明を追加

「あなたの声を、整えて残します。」をキャッチコピーの下に追加。
AI機能の存在をアプリ初回起動時に自然に伝える。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: RecordingFeature.State に aiProcessingCompleted を追加

**Files:**
- Modify: `Sources/FeatureRecording/RecordingFeature.swift`
- Modify: `Tests/FeatureRecordingTests/RecordingFeatureTests.swift`

- [ ] **Step 1: テストを先に書く**

`RecordingFeatureTests.swift` に追加:

```swift
@Test("aiProcessingCompleted の初期値が false であること")
func test_aiProcessingCompleted_initialValue() {
    let state = RecordingFeature.State()
    #expect(state.aiProcessingCompleted == false)
}

@Test("aiProcessingCompleted が設定可能であること")
func test_aiProcessingCompleted_canBeSet() {
    var state = RecordingFeature.State()
    state.aiProcessingCompleted = true
    #expect(state.aiProcessingCompleted == true)
}
```

- [ ] **Step 2: RecordingFeature.State に aiProcessingCompleted を追加**

`RecordingFeature.swift` の State 内、`completionStage` の下に追加:

```swift
/// AI処理が完了したかどうか（完了画面の表示制御用）
public var aiProcessingCompleted: Bool = false
```

init パラメータにも追加:

```swift
public init(
    // ... 既存パラメータ ...,
    completionStage: CompletionStage = .initial,
    aiProcessingCompleted: Bool = false
) {
    // ... 既存代入 ...
    self.completionStage = completionStage
    self.aiProcessingCompleted = aiProcessingCompleted
}
```

- [ ] **Step 3: viewMemoTapped / dismissCompletion で aiProcessingCompleted をリセット**

`RecordingFeature.swift` の `.viewMemoTapped` と `.dismissCompletion` ハンドラ内の状態リセット箇所に追加:

```swift
state.aiProcessingCompleted = false
```

- [ ] **Step 4: テスト実行**

Run: `swift test --filter FeatureRecordingTests`
Expected: 全テストパス

- [ ] **Step 5: コミット**

```bash
git add repository/ios/SoyokaModules/Sources/FeatureRecording/RecordingFeature.swift
git add repository/ios/SoyokaModules/Tests/FeatureRecordingTests/RecordingFeatureTests.swift
git commit -m "feat(recording): RecordingFeature.StateにaiProcessingCompletedを追加

完了画面でAI処理の完了を表示するためのフラグ。
viewMemoTapped/dismissCompletionでリセット。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: AppReducer にAI処理完了通知の中継を実装

**Files:**
- Modify: `repository/ios/SoyokaApp/SoyokaApp.swift`

- [ ] **Step 1: AppReducer.Action に aiProcessingCompleted を追加**

```swift
enum Action {
    case tabSelected(State.Tab)
    case recording(RecordingFeature.Action)
    case memoList(MemoListReducer.Action)
    case settings(SettingsReducer.Action)
    case openURL(URL)
    case aiProcessingCompleted(UUID)  // NEW
}
```

- [ ] **Step 2: .recording(.recordingSaved) のエフェクトにAI完了監視を追加**

既存の `.recording(.recordingSaved(let memo))` ハンドラの `.run` エフェクト内（FTS5インデックス更新 + AI処理キュー追加の後）に、AI処理完了を監視するエフェクトを `.merge` に追加:

```swift
// 既存の .merge に追加
.run { [aiProcessingQueue] send in
    for await status in aiProcessingQueue.observeStatus(memo.id) {
        if case .completed = status {
            await send(.aiProcessingCompleted(memo.id))
            break
        }
    }
}
```

Note: `aiProcessingQueue.observeStatus` が AsyncStream を返す前提。存在しない場合は `aiProcessingQueue` の既存 API（`statusStream` 等）を使用すること。実装時に `AIProcessingQueueClient` プロトコルを確認。

- [ ] **Step 3: .aiProcessingCompleted ハンドラを追加**

```swift
case let .aiProcessingCompleted(memoID):
    state.recording.aiProcessingCompleted = true
    return .none
```

- [ ] **Step 4: ビルド確認**

Run: `xcode-mcp-workflow` スキルでビルド
Expected: ビルド成功

- [ ] **Step 5: コミット**

```bash
git add repository/ios/SoyokaApp/SoyokaApp.swift
git commit -m "feat(app): AppReducerにAI処理完了通知の中継を実装

recordingSaved時にAI処理キューのステータスを監視し、
完了時にrecording.aiProcessingCompleted = trueを設定。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: 録音完了画面にAI処理状態表示を追加

**Files:**
- Modify: `Sources/FeatureRecording/Views/RecordingCompletionView.swift`

- [ ] **Step 1: AI処理状態セクションを追加**

`RecordingCompletionView.swift` の「温かいメッセージ」セクション（`Text("書きとめました")` ブロック）と自動停止メッセージの間に、AI処理状態表示を挿入:

```swift
// 温かいメッセージ
Text("書きとめました")
    .font(.vmTitle3)
    .foregroundColor(.vmTextPrimary)
    .opacity(stage >= .preview ? 1 : 0)
    .animation(animation, value: stage)

// AI処理状態表示
if stage >= .preview {
    if store.aiProcessingCompleted {
        HStack(spacing: VMDesignTokens.Spacing.xs) {
            Image(systemName: "checkmark")
                .font(.vmCaption1)
                .foregroundColor(.vmPrimary)
            Text("整えました")
                .font(.vmCaption1)
                .foregroundColor(.vmTextSecondary)
        }
        .transition(.opacity)
        .animation(animation, value: store.aiProcessingCompleted)
    } else {
        HStack(spacing: VMDesignTokens.Spacing.xs) {
            if reduceMotion {
                Circle()
                    .fill(Color.vmPrimary.opacity(0.6))
                    .frame(width: 8, height: 8)
            } else {
                PulsingDotView()
            }
            Text("ことばを整えています…")
                .font(.vmCaption1)
                .foregroundColor(.vmTextTertiary)
        }
        .transition(.opacity)
        .animation(animation, value: store.aiProcessingCompleted)
    }
}
```

- [ ] **Step 2: import SharedUI が既にあることを確認**

`PulsingDotView` は SharedUI モジュール。ファイル先頭に `import SharedUI` があること（既存）。

- [ ] **Step 3: ビルド確認**

Run: `xcode-mcp-workflow` スキルでビルド
Expected: ビルド成功

- [ ] **Step 4: コミット**

```bash
git add repository/ios/SoyokaModules/Sources/FeatureRecording/Views/RecordingCompletionView.swift
git commit -m "feat(ui): 録音完了画面にAI処理状態表示を追加

「ことばを整えています…」（処理中）→「整えました」（完了）の段階表示。
PulsingDotViewで処理中を表現、reduceMotion対応済み。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: MemoCardData に AIDisplayStatus を追加

**Files:**
- Modify: `Sources/SharedUI/Components/MemoCard.swift`

- [ ] **Step 1: AIDisplayStatus enum を定義**

`MemoCard.swift` の先頭（`MemoCardData` 定義の前）に追加:

```swift
/// メモカードに表示するAI処理状態
public enum AIDisplayStatus: Equatable, Sendable {
    case none        // AI未処理
    case processing  // AI処理中
    case completed   // AI処理済み
}
```

- [ ] **Step 2: MemoCardData に aiStatus フィールドを追加**

```swift
public struct MemoCardData: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let createdAt: Date
    public let durationSeconds: Double
    public let transcriptPreview: String
    public let emotion: EmotionCategory?
    public let tags: [String]
    public let aiStatus: AIDisplayStatus  // NEW

    public init(
        id: UUID,
        title: String,
        createdAt: Date,
        durationSeconds: Double,
        transcriptPreview: String,
        emotion: EmotionCategory?,
        tags: [String],
        aiStatus: AIDisplayStatus = .none  // デフォルト値で後方互換
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.transcriptPreview = transcriptPreview
        self.emotion = emotion
        self.tags = tags
        self.aiStatus = aiStatus
    }
}
```

- [ ] **Step 3: MemoCard のフッター行にAI状態アイコンを追加**

`MemoCard.body` のフッター `HStack`（日付とデュレーションの行）を修正:

```swift
// フッター: 日付、AI状態、デュレーション
HStack {
    Text(formattedDate)
        .font(.vmCaption1)
        .foregroundColor(.vmTextTertiary)

    // AI処理状態アイコン
    switch data.aiStatus {
    case .processing:
        Circle()
            .fill(Color.vmPrimary.opacity(0.6))
            .frame(width: 6, height: 6)
            .accessibilityLabel("AI整理中")
    case .completed:
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 10))
            .foregroundColor(.vmPrimary.opacity(0.5))
            .accessibilityLabel("AI整理済み")
    case .none:
        EmptyView()
    }

    Spacer()

    Text(formattedDuration)
        .font(.vmCaption1)
        .foregroundColor(.vmTextTertiary)
}
```

- [ ] **Step 4: accessibilityLabel を更新**

既存の `accessibilityLabel` にAI状態を追加:

```swift
.accessibilityLabel("\(data.title), \(formattedDate), \(formattedDuration)\(aiStatusAccessibilityLabel)")
```

computed property を追加:

```swift
private var aiStatusAccessibilityLabel: String {
    switch data.aiStatus {
    case .processing: return ", AI整理中"
    case .completed: return ", AI整理済み"
    case .none: return ""
    }
}
```

- [ ] **Step 5: ビルド確認**

Run: `xcode-mcp-workflow` スキルでビルド
Expected: ビルド成功（MemoCardData の init にデフォルト値があるため既存呼び出し元はそのまま動作）

- [ ] **Step 6: コミット**

```bash
git add repository/ios/SoyokaModules/Sources/SharedUI/Components/MemoCard.swift
git commit -m "feat(ui): MemoCardDataにAIDisplayStatusを追加しカードにアイコン表示

メモカードのフッター行にAI処理状態アイコンを表示。
- processing: パルスドット（vmPrimary 0.6）
- completed: チェックマーク（vmPrimary 0.5）
- none: 非表示
VoiceOver対応済み。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: MemoListReducer で AI状態を MemoCardData に反映

**Files:**
- Modify: `Sources/FeatureMemo/MemoList/MemoListReducer.swift`

- [ ] **Step 1: MemoItem に aiStatus を追加**

`MemoListReducer.MemoItem` に `aiStatus` フィールドを追加:

```swift
public struct MemoItem: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var durationSeconds: Double
    public var transcriptPreview: String
    public var emotion: EmotionCategory?
    public var tags: [String]
    public var audioFilePath: String
    public var aiStatus: AIDisplayStatus  // NEW

    public init(
        id: UUID,
        title: String,
        createdAt: Date,
        durationSeconds: Double,
        transcriptPreview: String,
        emotion: EmotionCategory?,
        tags: [String],
        audioFilePath: String,
        aiStatus: AIDisplayStatus = .none  // デフォルト値
    ) {
        // ... 既存代入 ...
        self.aiStatus = aiStatus
    }
}
```

`import SharedUI` がファイル先頭にあること（`AIDisplayStatus` は SharedUI で定義）。

- [ ] **Step 2: fetchMemoItems() で aiStatus を判定**

`MemoListReducer.fetchMemoItems()` 内の `.map` を更新:

```swift
return entities.map { entity in
    let aiStatus: AIDisplayStatus = entity.aiSummary != nil ? .completed : .none
    return MemoItem(
        id: entity.id,
        title: entity.title,
        createdAt: entity.createdAt,
        durationSeconds: entity.durationSeconds,
        transcriptPreview: String((entity.aiSummary?.summaryText ?? entity.transcription?.fullText ?? "").prefix(60)),
        emotion: entity.emotionAnalysis?.primaryEmotion,
        tags: entity.tags.map(\.name),
        audioFilePath: entity.audioFilePath,
        aiStatus: aiStatus
    )
}
```

Note: `.processing` 判定は AI処理キューの状態が必要。MVP では `.none` と `.completed` のみ判定し、`.processing` は将来のAI処理キュー連携で追加する。

- [ ] **Step 3: cardData 変換プロパティを更新**

ファイル末尾の `extension MemoListReducer.MemoItem` を更新:

```swift
extension MemoListReducer.MemoItem {
    public var cardData: MemoCardData {
        MemoCardData(
            id: id,
            title: title,
            createdAt: createdAt,
            durationSeconds: durationSeconds,
            transcriptPreview: transcriptPreview,
            emotion: emotion,
            tags: tags,
            aiStatus: aiStatus
        )
    }
}
```

- [ ] **Step 4: ビルド確認**

Run: `xcode-mcp-workflow` スキルでビルド
Expected: ビルド成功

- [ ] **Step 5: テスト実行**

Run: `swift test --filter FeatureMemoTests`
Expected: 全テストパス

- [ ] **Step 6: コミット**

```bash
git add repository/ios/SoyokaModules/Sources/FeatureMemo/MemoList/MemoListReducer.swift
git commit -m "feat(memo): MemoListReducerでAI状態をMemoCardDataに反映

fetchMemoItems()でaiSummaryの有無からAIDisplayStatusを判定。
cardData変換にaiStatusを追加。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## 実行順序と依存関係

```
Task 1 (ウェルカム画面) ← 独立

Task 2 (RecordingFeature.State)
  ↓
Task 3 (AppReducer AI通知中継) ← Task 2 に依存
  ↓
Task 4 (完了画面 UI) ← Task 2, 3 に依存

Task 5 (MemoCardData + MemoCard UI) ← 独立
  ↓
Task 6 (MemoListReducer 連携) ← Task 5 に依存
```

Task 1, Task 2, Task 5 は並列実行可能。

---

## 完了後の検証

- [ ] Xcode MCP でフルビルド成功
- [ ] 全テストパス
- [ ] 録音完了画面で「ことばを整えています…」が表示されること（UI確認）
- [ ] ウェルカム画面に「あなたの声を、整えて残します。」が表示されること（UI確認）
- [ ] メモ一覧カードにAI状態アイコンが表示されること（UI確認）
