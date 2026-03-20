# Phase 3a 計画策定

## 依頼内容

MurMurNote アプリの Phase 3 全体ロードマップと、Phase 3a（オンデバイス AI 処理）の詳細な要件定義・設計・タスク化・UI/UX 仕様を作成する。

## 実施内容

1. **Phase 3 全体ロードマップ**: 3a / 3b / 3c の概要、依存関係、期間目安
2. **Phase 3a 要件定義（EARS 記法）**: オンデバイス AI 処理の全要件をEARS記法で記述
3. **Phase 3a 詳細設計**: モジュール構成、データフロー、プロンプト設計、エラーハンドリング
4. **Phase 3a タスク化**: 1日単位のタスク分解（依存関係・推定作業量付き）
5. **Phase 3a UI/UX 仕様**: AI 要約カード、タグアニメーション、月15回制限 UI 等

## 成果物

| ファイル | 内容 |
|:---------|:-----|
| `result/phase3-roadmap.md` | Phase 3 全体ロードマップ |
| `result/phase3a-requirements.md` | Phase 3a 要件定義（EARS 記法） |
| `result/phase3a-design.md` | Phase 3a 詳細設計 |
| `result/phase3a-tasks.md` | Phase 3a タスク一覧 |
| `result/phase3a-ux-spec.md` | Phase 3a UI/UX 仕様 |

## 前提条件

- Phase 3a はオンデバイス AI 処理のみ（Backend 不要）
- Apple Intelligence Foundation Models API 優先、非対応時は llama.cpp フォールバック
- 感情分析はクラウド必須のため Phase 3b へスキップ
- 既存の FeatureAI / InfraLLM / Domain 層はスタブ状態（v0.1.0）

## 参照ドキュメント

- `docs/spec/ai-voice-memo/requirements.md` -- 統合機能要件書
- `docs/spec/ai-voice-memo/design/02-ai-pipeline.md` -- AI パイプライン設計書
- `docs/spec/ai-voice-memo/design/04-ui-design-system.md` -- UI デザインシステム設計書（セクション14含む）
- `docs/spec/ai-voice-memo/user-stories.md` -- ユーザーストーリー

## 知見・メモ

- 既存の `AIProcessingQueueClient` は TCA Dependency として定義済み（Domain 層）。testValue のみ実装
- `MemoDetailReducer` は既に `aiProcessingStatus` / `aiSummary` / `emotion` / `tags` の State を保持しており、AI 処理完了時のリロードロジックも実装済み
- `MemoDetailView` は `AISummarySection` / `AIProcessingStatusView` / `TagFlowLayout` / `EmotionDetailCard` の UI コンポーネントが実装済み（Phase 3 で実体化する前提の枠組み）
- `InfraLLM` モジュールはバージョン表示のみ（空モジュール）
- `FeatureAI` モジュールもバージョン表示のみ（空モジュール）
- Apple Intelligence Foundation Models は `@Generable` マクロ経由の構造化出力のみ対応。自由プロンプト実行は iOS 26 時点で未公開
- 設計書では llama.cpp (Phi-3-mini Q4_K_M) を一次候補としている

## TODO

- Phase 3a 実装着手前に、Apple Intelligence Foundation Models API の iOS 26 正式版 API を再調査する
- llama.cpp Swift バインディングのライブラリ選定（swift-llama.cpp or llama.cpp の C API ブリッジ）
