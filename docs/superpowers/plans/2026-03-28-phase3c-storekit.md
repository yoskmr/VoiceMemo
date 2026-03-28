# Phase 3c: StoreKit 2 サブスクリプション 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** StoreKit 2 で Pro プラン（月額/年額）の購入・管理を実装し、Pro 時の AI 処理無制限化を実現する

**Architecture:** SubscriptionClient（Domain プロトコル）→ StoreKit 2 Live 実装。SubscriptionReducer + SubscriptionView で購入フロー。設定画面から遷移。

**Tech Stack:** Swift 6.2 / SwiftUI / TCA 1.17+ / StoreKit 2 / Swift Testing

**Spec:** `docs/superpowers/specs/2026-03-28-phase3c-storekit-design.md`

**Module base path:** `repository/ios/SoyokaModules/`

---

## Task 1: SubscriptionClient プロトコル定義（Domain）

**Files:**
- Create: `Sources/Domain/Protocols/SubscriptionClient.swift`

**変更内容:**
- SubscriptionClient struct（TCA DependencyKey 準拠）
- SubscriptionProduct, SubscriptionPeriod, PurchaseResult, SubscriptionState 型定義
- `\.subscriptionClient` で DependencyValues アクセス

**コミット:** `feat(domain): SubscriptionClientプロトコルと関連型を定義`

---

## Task 2: SubscriptionReducer 実装（FeatureSubscription）

**Files:**
- Create: `Sources/FeatureSubscription/SubscriptionReducer.swift`
- Create: `Tests/FeatureSubscriptionTests/SubscriptionReducerTests.swift`

**変更内容:**
- State: products, subscriptionState, isLoading, isPurchasing, errorMessage
- Action: onAppear, productsLoaded, purchaseTapped, purchaseCompleted, restoreTapped, subscriptionStateChanged
- 処理フロー: onAppear → fetchProducts + observeTransactionUpdates
- テスト: 商品読み込み、購入フロー（成功/キャンセル）、状態変更

**コミット:** `feat(subscription): SubscriptionReducer実装（購入・状態管理）`

---

## Task 3: SubscriptionView 実装（FeatureSubscription）

**Files:**
- Create: `Sources/FeatureSubscription/SubscriptionView.swift`

**変更内容:**
- ヘッダー: 「もっと自由に、整えよう。」
- 機能比較テーブル（Free vs Pro）
- 月額/年額プラン選択ボタン
- 購入復元リンク
- ローディング・エラー表示
- Soyoka のトーン・デザイントークン準拠

**コミット:** `feat(subscription): SubscriptionView実装（プラン一覧・購入UI）`

---

## Task 4: StoreKit 2 Live 実装（FeatureSubscription）

**Files:**
- Create: `Sources/FeatureSubscription/LiveSubscriptionClient.swift`

**変更内容:**
- Product.products(for:) で商品取得
- product.purchase() で購入実行
- Transaction.currentEntitlements で購読状態判定
- Transaction.updates で更新監視
- AppStore.sync() で購入復元
- Product ID: `app.soyoka.pro.monthly`, `app.soyoka.pro.yearly`

**コミット:** `feat(subscription): StoreKit 2 Live実装（Product取得・購入・復元）`

---

## Task 5: 設定画面からプラン管理画面への遷移

**Files:**
- Modify: `Sources/FeatureSettings/Settings/SettingsReducer.swift`
- Modify: `Sources/FeatureSettings/Settings/SettingsView.swift`
- Modify: `Package.swift`（FeatureSettings に FeatureSubscription 依存追加）

**変更内容:**
- SettingsReducer.State に `@Presents var subscription: SubscriptionReducer.State?`
- SettingsReducer.Action に `.subscription(PresentationAction<SubscriptionReducer.Action>)`
- `.comingSoonTapped(.planManagement)` → `state.subscription = SubscriptionReducer.State()` に変更
- SettingsView に `.navigationDestination` で SubscriptionView を表示

**コミット:** `feat(settings): プラン管理から SubscriptionView への遷移を実装`

---

## Task 6: Pro プラン時の AI 処理無制限化

**Files:**
- Modify: `Sources/InfraLLM/AIProcessingQueue.swift`
- Modify: LiveDependencies（SubscriptionClient.live を注入）

**変更内容:**
- AIProcessingQueue に SubscriptionClient を注入
- `enqueueProcessing` 内で `subscriptionClient.currentSubscription()` を確認
- `.pro` の場合は quotaClient.recordUsage() をスキップ
- `.pro` の場合は quotaClient.canProcess() チェックもスキップ
- LiveDependencies に SubscriptionClient.live() を追加

**コミット:** `feat(subscription): Proプラン時のAI処理無制限化を実装`

---

## 実行順序

```
Task 1 (Domain プロトコル) ← 全タスクの前提
  ↓
Task 2 (Reducer) + Task 3 (View) ← 並列可
  ↓
Task 4 (StoreKit Live) ← Task 1 に依存
  ↓
Task 5 (設定画面連携) ← Task 2, 3 に依存
  ↓
Task 6 (AI 無制限化) ← Task 4 に依存
```

## 完了後の検証

- [ ] `swift build` 成功
- [ ] `swift test` 全テストパス
- [ ] Sandbox 環境で購入フロー動作確認
- [ ] Pro プラン時に AI 処理制限が解除されること
