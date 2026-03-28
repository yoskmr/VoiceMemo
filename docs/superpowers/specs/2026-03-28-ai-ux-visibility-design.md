# AI機能の可視化 UX改善 設計書

## 概要

録音完了後にAI処理の進行状況がユーザーに伝わらない問題と、アプリ全体でAI機能の存在が認識されない問題を解決する。Soyokaの「温かく寄り添う友人」というトーンに合わせた文言・UI設計。

## スコープ

| 改善箇所 | 内容 |
|:--------|:-----|
| 録音完了画面 | AI処理中の進行表示 + 完了表示 |
| ウェルカム画面 | AI機能の一言説明追加 |
| メモ一覧カード | AI処理状態アイコン表示 |

## コンセプト準拠

- **トーン**: 温かく、親密で、寄り添う
- **用語**: 「AI処理」→「整える」、「録音」→「つぶやき」、「メモ」→「きおく」
- **キャッチコピーの延長**: 「声のままでいい。ちゃんと残るから。」→ 声を受け止めた上で、丁寧に整える

---

## 1. 録音完了画面の改善

### 変更ファイル
- `Sources/FeatureRecording/Views/RecordingCompletionView.swift`
- `Sources/FeatureRecording/RecordingFeature.swift`（State に aiStatus 追加）
- `SoyokaApp/SoyokaApp.swift`（AppReducer から AI処理状態を中継）

### 現状
```
[吹き出しアイコン]
「書きとめました」
「メモを見る」/「あとで」
```
AI処理がバックグラウンドで走っていることが一切伝わらない。

### 改善後

CompletionStage に連動した段階表示:

**Stage 1 (checkmark)**:
```
[吹き出しアイコン ✓]
「書きとめました」
```

**Stage 2 (preview) — AI処理開始を伝える**:
```
[吹き出しアイコン ✓]
「書きとめました」
「ことばを整えています…」
[パルスドット（vmPrimary、ゆっくり明滅）]
```

**Stage 3 (cta) — ボタン表示（AI処理中でも操作可能）**:
```
「書きとめました」
「ことばを整えています…」
[パルスドット]

[メモを見る]
[あとで]
```

**AI処理完了時（completionStage が cta の状態で AI 完了通知を受信）**:
```
「書きとめました」
「整えました」[小さなチェックマーク]

[メモを見る]
[あとで]
```

### 実装方針

RecordingFeature.State に `aiProcessingCompleted: Bool = false` を追加。
AppReducer で AI処理完了時に `recording.aiProcessingCompleted = true` を設定。

RecordingCompletionView は:
- `store.completionStage >= .preview` かつ `!store.aiProcessingCompleted` → 「ことばを整えています…」+ パルスドット
- `store.aiProcessingCompleted` → 「整えました」+ チェックマーク
- アニメーション: `.spring` で切り替え（reduceMotion 対応済み）

### 文言選定の根拠

| 候補 | 採否 | 理由 |
|:-----|:---:|:-----|
| 「AI処理中です」 | ✗ | 機械的。Soyokaのトーンに合わない |
| 「分析しています…」 | ✗ | 分析的・数値的な印象。設計原則で避ける |
| 「ことばを整えています…」 | ✓ | ユーザーの言葉を丁寧に扱う印象。「整える」はAI整理の世界観と一致 |
| 「整えました」 | ✓ | 「処理完了」ではなく、やさしい完了表現 |

---

## 2. ウェルカム画面の改善

### 変更ファイル
- `SoyokaApp/WelcomeView.swift`

### 現状
```
そよか
Soyoka

声のままでいい。
ちゃんと残るから。

[準備しています...]
```
AI機能の説明が一切ない。

### 改善後
```
そよか
Soyoka

声のままでいい。
ちゃんと残るから。

あなたの声を、整えて残します。  ← NEW（vmTextSecondary、vmCaption1）

[準備しています...]
```

### 文言選定の根拠

| 候補 | 採否 | 理由 |
|:-----|:---:|:-----|
| 「AIが自動で要約・タグ付けします」 | ✗ | 機能説明的。ウェルカム画面のポエティックなトーンに合わない |
| 「あなたの声を、整えて残します。」 | ✓ | キャッチコピーの延長。「声のままでいい」→「整えて残す」の自然な流れ |
| 「声を、きおくに。」 | △ | 短すぎてAI機能が伝わらない |

---

## 3. メモ一覧カードのAI状態表示

### 変更ファイル
- `Sources/SharedUI/Components/MemoCard.swift`（UI追加）
- `Sources/SharedUI/Models/MemoCardData.swift`（aiStatus フィールド追加）
- `Sources/FeatureMemo/MemoList/MemoListReducer.swift`（MemoItem に aiStatus 追加）
- `Sources/FeatureMemo/MemoList/MemoListView.swift`（MemoCard に aiStatus を渡す）

### 現状
メモカードにAI処理状態の表示がない。処理済み/未処理の区別がつかない。

### 改善後

メモカードのメタ情報行（日付・録音時間の横）に小さなステータスアイコンを追加:

| AI状態 | 表示 | 色 |
|:------|:-----|:---|
| 整理中 | パルスドット（ゆっくり明滅） | vmPrimary (0.6 opacity) |
| 整理済み | `checkmark.circle.fill`（SF Symbols, 12pt） | vmPrimary (0.5 opacity) |
| 未処理 | 表示なし | — |
| 失敗 | `arrow.clockwise.circle`（SF Symbols, 12pt） | vmWarning |

### AI状態の判定ロジック

`MemoItem` に `aiStatus: AIDisplayStatus` を追加:

```swift
public enum AIDisplayStatus: Equatable, Sendable {
    case none        // AI未処理（テキストなし or AI無効）
    case processing  // AI処理中
    case completed   // AI処理済み
    case failed      // AI処理失敗
}
```

MemoListReducer の `fetchMemoItems()` で判定:
- `entity.aiSummary != nil` → `.completed`
- `entity.aiSummary == nil` かつ AI処理キュー内 → `.processing`
- `entity.aiSummary == nil` かつ キュー外 → `.none`
- AI処理エラー記録あり → `.failed`

### アクセシビリティ

| 状態 | accessibilityLabel |
|:-----|:-------------------|
| 整理中 | 「AI整理中」 |
| 整理済み | 「AI整理済み」 |
| 失敗 | 「AI整理に失敗しました」 |

---

## 受入基準

1. 録音完了画面で「ことばを整えています…」が表示されること
2. AI処理完了時に「整えました」に切り替わること
3. ウェルカム画面に「あなたの声を、整えて残します。」が表示されること
4. メモ一覧カードにAI処理状態アイコンが表示されること
5. VoiceOver でAI状態が読み上げられること
6. reduceMotion 有効時にパルスアニメーションが無効化されること
7. 全既存テストがパスすること
