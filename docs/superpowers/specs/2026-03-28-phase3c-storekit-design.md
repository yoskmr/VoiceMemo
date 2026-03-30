# Phase 3c: StoreKit 2 サブスクリプション 設計書

## 概要

StoreKit 2 を使って Pro プラン（月額¥500 / 年額¥4,800）のサブスクリプションを実装し、iOS 側の使用量制限 UI と連携する。Sign In with Apple は含まない（デバイストークン認証のまま）。

## スコープ

### 含む

| 機能 | 関連要件 |
|:-----|:---------|
| StoreKit 2 Product 取得・購入フロー | REQ-024 |
| 購読状態管理（Transaction 監視） | REQ-024 |
| Pro プラン UI（プラン一覧・購入画面） | REQ-024 |
| 設定画面からプラン管理画面への遷移 | REQ-024 |
| iOS 側の使用量制限 UI 改善 | REQ-011 |
| 購読状態に応じた機能制限/解放 | REQ-012 |

### 含まない

| 機能 | 理由 |
|:-----|:-----|
| Sign In with Apple | 別フェーズ。デバイストークン認証で動作 |
| Backend Proxy 課金検証 | Phase 3a で Secrets のみ。サーバー側 Transaction 検証は後回し |
| appAccountToken 紐付け | Sign In with Apple 導入後に対応 |

## アーキテクチャ

```
FeatureSubscription（TCA Reducer + View）
  ↓ Domain層プロトコル経由
Domain/Protocols/SubscriptionClient（StoreKit 2 抽象化）
  ↓
InfraLLM層 or App層（Live 実装）
  └── StoreKit 2 API（Product, Transaction, Product.SubscriptionInfo）
```

---

## 1. SubscriptionClient プロトコル（Domain）

### 新規ファイル
- `Sources/Domain/Protocols/SubscriptionClient.swift`

```swift
public struct SubscriptionClient: Sendable {
    /// 利用可能な Product を取得
    public var fetchProducts: @Sendable () async throws -> [SubscriptionProduct]
    /// 購入実行
    public var purchase: @Sendable (String) async throws -> PurchaseResult
    /// 現在の購読状態を取得
    public var currentSubscription: @Sendable () async -> SubscriptionState
    /// Transaction 更新を監視
    public var observeTransactionUpdates: @Sendable () -> AsyncStream<SubscriptionState>
    /// 購入復元
    public var restorePurchases: @Sendable () async throws -> Void
}

public struct SubscriptionProduct: Equatable, Sendable, Identifiable {
    public let id: String           // Product ID
    public let displayName: String
    public let displayPrice: String
    public let period: SubscriptionPeriod
}

public enum SubscriptionPeriod: String, Equatable, Sendable {
    case monthly
    case yearly
}

public enum PurchaseResult: Equatable, Sendable {
    case success
    case pending       // 承認待ち（ファミリー承認等）
    case cancelled
    case failed(String)
}

public enum SubscriptionState: Equatable, Sendable {
    case free
    case pro(expiresAt: Date)
    case expired
}
```

TCA `DependencyKey` 準拠: `\.subscriptionClient`

---

## 2. SubscriptionReducer（FeatureSubscription）

### 新規ファイル
- `Sources/FeatureSubscription/SubscriptionReducer.swift`

### State
```swift
@ObservableState
public struct State: Equatable {
    public var products: [SubscriptionProduct] = []
    public var subscriptionState: SubscriptionState = .free
    public var isLoading: Bool = false
    public var isPurchasing: Bool = false
    public var errorMessage: String?
    public var showSuccessMessage: Bool = false
}
```

### Action
```swift
public enum Action: Equatable, Sendable {
    case onAppear
    case productsLoaded([SubscriptionProduct])
    case purchaseTapped(productID: String)
    case purchaseCompleted(PurchaseResult)
    case restoreTapped
    case restoreCompleted
    case subscriptionStateChanged(SubscriptionState)
    case dismissError
}
```

### 処理フロー
1. `onAppear` → `fetchProducts()` + `currentSubscription()` + `observeTransactionUpdates()`
2. `purchaseTapped` → `isPurchasing = true` → `purchase(productID)` → `purchaseCompleted`
3. `subscriptionStateChanged` → State 更新

---

## 3. SubscriptionView（FeatureSubscription）

### 新規ファイル
- `Sources/FeatureSubscription/SubscriptionView.swift`

### UI 構成

```
NavigationStack
├── ヘッダー: 「Soyoka Pro」タイトル
├── 機能比較セクション
│   ├── AI整理: 無料 月15回 / Pro 無制限
│   ├── 感情分析: 無料 ✗ / Pro ✓
│   └── テーマ: 無料 ✗ / Pro ✓
├── プラン選択セクション
│   ├── 月額 ¥500 ボタン
│   └── 年額 ¥4,800 ボタン（「2ヶ月お得」バッジ）
├── 購入復元リンク
└── 利用規約・プライバシーポリシーリンク
```

### 文言（Soyoka トーン準拠）
- ヘッダー: 「もっと自由に、整えよう。」
- 月額: 「月額プラン」
- 年額: 「年額プラン（2ヶ月分お得）」
- 復元: 「以前の購入を復元」

---

## 4. StoreKit 2 Live 実装

### 新規ファイル
- `Sources/FeatureSubscription/LiveSubscriptionClient.swift`

### Product ID

| ID | プラン |
|:---|:------|
| `app.soyoka.pro.monthly` | Pro 月額 |
| `app.soyoka.pro.yearly` | Pro 年額 |

### 実装内容

```swift
extension SubscriptionClient {
    public static func live() -> Self {
        SubscriptionClient(
            fetchProducts: {
                let products = try await Product.products(for: [
                    "app.soyoka.pro.monthly",
                    "app.soyoka.pro.yearly"
                ])
                return products.map { SubscriptionProduct(from: $0) }
            },
            purchase: { productID in
                guard let product = try await Product.products(for: [productID]).first else {
                    return .failed("Product not found")
                }
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    let transaction = try checkVerified(verification)
                    await transaction.finish()
                    return .success
                case .pending:
                    return .pending
                case .userCancelled:
                    return .cancelled
                @unknown default:
                    return .failed("Unknown")
                }
            },
            currentSubscription: {
                await getCurrentSubscriptionState()
            },
            observeTransactionUpdates: {
                AsyncStream { continuation in
                    let task = Task {
                        for await result in Transaction.updates {
                            if let transaction = try? checkVerified(result) {
                                await transaction.finish()
                                let state = await getCurrentSubscriptionState()
                                continuation.yield(state)
                            }
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            restorePurchases: {
                try await AppStore.sync()
            }
        )
    }
}
```

### 購読状態判定

```swift
func getCurrentSubscriptionState() async -> SubscriptionState {
    for await result in Transaction.currentEntitlements {
        if let transaction = try? checkVerified(result),
           transaction.productType == .autoRenewable {
            return .pro(expiresAt: transaction.expirationDate ?? .distantFuture)
        }
    }
    return .free
}
```

---

## 5. 設定画面連携

### 変更ファイル
- `Sources/FeatureSettings/Settings/SettingsReducer.swift`
- `Sources/FeatureSettings/Settings/SettingsView.swift`

### 変更内容
- `planManagement` の `.comingSoonTapped` → SubscriptionView への NavigationDestination に変更
- SettingsReducer.State に `@Presents var subscription: SubscriptionReducer.State?` 追加

---

## 6. 使用量制限の購読状態連携

### 変更内容

AIProcessingQueue（Phase 3b で実装済み）の使用量チェックに購読状態を反映:
- `SubscriptionState.pro` → 使用量制限なし（`quotaClient.canProcess()` を常に true にするか、チェックをスキップ）
- `SubscriptionState.free` → 既存の月15回制限

AIQuotaClient の live 実装に SubscriptionClient を注入し、Pro プラン時はカウントスキップ。

---

## 受入基準

1. プラン一覧画面で月額・年額の商品情報が表示されること
2. 購入フローが動作すること（Sandbox 環境でテスト）
3. 購入後にプランが Pro に切り替わること
4. Pro プラン時に AI 処理の月次制限が解除されること
5. 設定画面の「プラン管理」から SubscriptionView に遷移すること
6. 購入復元が動作すること
7. Transaction 更新が自動反映されること
8. 全既存テストがパスすること
