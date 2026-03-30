# Phase 4 リリース MVP 設計書

## 概要

App Store リリースに最低限必要な4タスクを MVP スコープで実装する。

## 実装タスク

### 1. オンボーディング改善（TASK-0035 MVP）

**現状**: WelcomeView（STT 準備画面）+ AIOnboardingView（初回 AI 処理時）が別々に存在。

**MVP 変更内容**:
- WelcomeView に**権限リクエスト**を追加（マイク + 音声認識）
- STT 準備完了後、権限未許可なら権限リクエスト画面を表示
- 権限許可済みならそのままメイン画面へ
- 3ステップ TabView は不要（現状の1画面フローで十分）

**変更ファイル**:
- `SoyokaApp/WelcomeView.swift`

### 2. アクセシビリティ補完（TASK-0037 MVP）

**現状**: 主要コンポーネント（RecordButton, WaveformView 等）は対応済み。残り9コンポーネント。

**MVP 変更内容**:
未対応コンポーネントに accessibilityLabel/hint を追加:
- `MemoCard`: 既に `accessibilityElement(children: .combine)` あり。追加不要
- `TagChip`: `accessibilityLabel("タグ: \(text)")` 追加
- `AISummarySection`: セクション全体に `accessibilityElement(children: .combine)` 追加
- `SearchResultCard`: 既に対応済み
- 最小タップターゲット 44pt: 主要ボタンを確認し不足分を `.frame(minWidth: 44, minHeight: 44)` で修正

**変更ファイル**:
- `Sources/SharedUI/Components/TagChip.swift`
- `Sources/FeatureMemo/MemoDetail/MemoDetailView.swift`（AISummarySection）
- 主要ボタンの minHeight 確認

### 3. E2E 統合テスト（TASK-0039 MVP）

**MVP 変更内容**:
主要フローの統合テスト3本:
1. 録音 → 保存 → メモ一覧表示 → メモ詳細表示
2. 検索 → 結果表示 → メモ詳細遷移
3. AI 処理キュー → 結果保存 → メモ詳細表示

パフォーマンステスト・メモリリーク検出は v1.1 で対応。

**新規ファイル**:
- `Tests/E2ETests/` 配下に統合テスト

### 4. App Store リリース準備（TASK-0040 MVP）

**MVP 変更内容**:
- Info.plist 権限文言の詳細化（「デバイスにのみ保存」等）
- プライバシーポリシー作成（`docs/privacy-policy.md`）
- App Store 説明文作成（`docs/appstore/`）
- App Store Connect 設定手順書

**新規ファイル**:
- `docs/privacy-policy.md`
- `docs/appstore/description-ja.md`
- `docs/appstore/keywords-ja.md`

## 受入基準

1. 初回起動時にマイク・音声認識の権限リクエストが表示されること
2. 全主要コンポーネントに VoiceOver ラベルがあること
3. E2E 統合テストが3本パスすること
4. プライバシーポリシーが作成されていること
5. App Store 説明文が作成されていること
