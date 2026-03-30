# Phase 3b: LLM ハイブリッド統合 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iOS アプリから Backend Proxy 経由でクラウド LLM を呼び出し、Apple Intelligence とのハイブリッドルーティングで AI 処理（要約+タグ+感情分析）を自動実行する

**Architecture:** HybridLLMRouter が Apple Intelligence → Cloud の優先順位で自動選択。BackendProxyClient が api-dev.soyoka.app と通信。AIProcessingQueue が録音完了後のバックグラウンド処理を管理。

**Tech Stack:** Swift 6.2 / SwiftUI / TCA 1.17+ / Swift Testing

**Spec:** `docs/superpowers/specs/2026-03-28-phase3b-llm-hybrid-design.md`

**Module base path:** `repository/ios/SoyokaModules/`
**App base path:** `repository/ios/SoyokaApp/`

---

## Task 1: LLMResponse に感情分析フィールドを追加 + LLMTask 拡張

**Files:**
- Modify: `Sources/Domain/Protocols/LLMProviderClient.swift`

**変更内容:**
- `LLMResponse` に `sentiment: LLMSentimentResult?` フィールド追加（`let`）
- `LLMSentimentResult` 構造体を新規定義（primary, scores, evidence）
- `SentimentEvidence` 構造体を新規定義（text, emotion）
- `LLMTask` に `.sentimentAnalysis` を追加（既に CaseIterable 準拠）
- `LLMResponse` の既存 init を更新（sentiment パラメータ追加、デフォルト nil）

**テスト:** 既存の LLMProviderClient テストが通ること

**コミット:** `feat(domain): LLMResponseに感情分析フィールドを追加しLLMTask拡張`

---

## Task 2: BackendProxyClient 実装（InfraNetwork）

**Files:**
- Create: `Sources/InfraNetwork/BackendProxyClient.swift`
- Create: `Sources/InfraNetwork/Models/ProxyModels.swift`
- Create: `Tests/InfraNetworkTests/BackendProxyClientTests.swift`
- Modify: `Package.swift`（InfraNetwork に Domain 依存追加）

**変更内容:**
- `BackendProxyClient` struct（TCA DependencyKey 準拠）
  - `authenticate(deviceID:appVersion:osVersion:)` → JWT 取得 → Keychain 保存
  - `processAI(AIProcessRequest)` → Backend Proxy の `/api/v1/ai/process` を呼び出し
  - `getUsage()` → `/api/v1/usage` を呼び出し
- JWT トークンの自動管理（Keychain 保存/取得、401 時の再認証）
- `ProxyModels.swift`: AuthResponse, AIProcessRequest, AIProcessResponse, UsageResponse の型定義
- ベース URL は環境変数で切替可能（dev/staging/production）
- テスト: fetch をモックしたユニットテスト

**コミット:** `feat(network): BackendProxyClient実装（認証+AI処理+使用量）`

---

## Task 3: CloudLLMProvider 実装（InfraLLM）

**Files:**
- Create: `Sources/InfraLLM/CloudLLMProvider.swift`
- Create: `Tests/InfraLLMTests/CloudLLMProviderTests.swift`
- Modify: `Package.swift`（InfraLLM に InfraNetwork 依存追加）

**変更内容:**
- `CloudLLMProvider: @unchecked Sendable`
  - `process(_: LLMRequest)` → BackendProxyClient.processAI を呼び出し、レスポンスを LLMResponse に変換
  - `processSentimentOnly(_: LLMRequest)` → 感情分析のみリクエスト
  - `isAvailable()` → ネットワーク到達性チェック（URLSession で HEAD リクエスト）
  - `providerType()` → `.cloudGPT4oMini`
  - `asClient()` → `LLMProviderClient` に変換
- BackendProxyClient のレスポンス（AIProcessResponse）を Domain 層の LLMResponse に変換するマッピング
- テスト: BackendProxyClient をモックしたユニットテスト

**コミット:** `feat(llm): CloudLLMProvider実装（BackendProxy経由GPT-4o mini）`

---

## Task 4: HybridLLMRouter 実装（InfraLLM）

**Files:**
- Create: `Sources/InfraLLM/HybridLLMRouter.swift`
- Create: `Tests/InfraLLMTests/HybridLLMRouterTests.swift`

**変更内容:**
- `HybridLLMRouter: @unchecked Sendable`
- ルーティングロジック:
  1. `onDeviceProvider.isAvailable()` → オンデバイス処理（要約+タグ）
  2. 感情分析有効 + `cloudProvider.isAvailable()` → クラウドで感情分析追加
  3. オンデバイス失敗 → クラウドフォールバック（EC-010）
  4. オンデバイス不可 → クラウドで全処理
  5. 全不可 → `LLMError.processingFailed`
- `asClient()` → `LLMProviderClient` に変換
- テスト: OnDeviceProvider/CloudProvider をモックし、6パターンのルーティングを検証

**コミット:** `feat(llm): HybridLLMRouter実装（Apple Intelligence→Cloud自動選択）`

---

## Task 5: AIProcessingQueue 具体実装（InfraLLM）

**Files:**
- Create: `Sources/InfraLLM/AIProcessingQueue.swift`
- Create: `Tests/InfraLLMTests/AIProcessingQueueTests.swift`

**変更内容:**
- `AIProcessingQueue: Actor`（排他制御）
- `AIProcessingQueueClient` プロトコルの具体実装
- 処理フロー:
  1. `enqueueProcessing(memoID)` → VoiceMemoRepository からテキスト取得
  2. 感情分析設定チェック（UserDefaults `sentimentAnalysisEnabled`、デフォルト false）
  3. `LLMRequest` 構築（tasks: [.summarize, .tagging] + オプション .sentimentAnalysis）
  4. `HybridLLMRouter.process()` 呼び出し
  5. 結果を VoiceMemoRepository に保存
  6. クラウド利用時のみ `quotaClient.recordUsage()`
  7. `observeStatus(memoID)` で AsyncStream 配信
- `asClient()` → `AIProcessingQueueClient` に変換
- テスト: Router/Repository/Quota をモックしたユニットテスト

**コミット:** `feat(llm): AIProcessingQueue具体実装（感情分析オプトイン+クラウドのみカウント）`

---

## Task 6: LiveDependencies 統合 + E2E 接続

**Files:**
- Modify: `SoyokaApp/LiveDependencies.swift`（または対応する Dependencies ファイル群）
- Modify: `Package.swift`（必要に応じて依存追加）

**変更内容:**
- BackendProxyClient.live の生成・注入
- CloudLLMProvider の生成・注入
- HybridLLMRouter の生成・注入（`\.llmProvider` に設定）
- AIProcessingQueue の生成・注入（`\.aiProcessingQueue` に設定）
- 既存の MockLLMProvider → HybridLLMRouter への切替

**コミット:** `feat(app): LiveDependenciesにLLMハイブリッド統合を接続`

---

## Task 7: ビルド修正 + 全テスト通過

**Files:**
- 各テストファイル（LLMResponse の init 変更に伴う修正）
- 既存コードのコンパイルエラー修正

**変更内容:**
- LLMResponse に `sentiment` パラメータが追加されたことによる既存テスト・既存コードの修正
- LLMTask に `.sentimentAnalysis` 追加による `allCases` 参照コードの確認
- `swift build` + `swift test` で全テストパス

**コミット:** `fix(test): LLMResponse感情分析フィールド追加に伴うテスト修正`

---

## 実行順序と依存関係

```
Task 1 (Domain 型拡張) ← 全タスクの前提
  ↓
Task 2 (BackendProxyClient)
  ↓
Task 3 (CloudLLMProvider) ← Task 2 に依存
  ↓
Task 4 (HybridLLMRouter) ← Task 3 に依存
  ↓
Task 5 (AIProcessingQueue) ← Task 4 に依存
  ↓
Task 6 (LiveDependencies) ← Task 2-5 全て依存
  ↓
Task 7 (ビルド修正 + テスト)
```

## 完了後の検証

- [ ] `swift build` 成功
- [ ] `swift test` 全テストパス
- [ ] 実機で録音 → AI 処理自動実行 → メモ詳細にAI結果表示
