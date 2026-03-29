import Dependencies
import Domain
import StoreKit

// MARK: - DependencyKey (liveValue)

extension SubscriptionClient: DependencyKey {
    public static let liveValue = SubscriptionClient.live()
}

// MARK: - StoreKit 2 Live Implementation

extension SubscriptionClient {
    public static func live() -> Self {
        SubscriptionClient(
            fetchProducts: {
                let productIDs = ["app.soyoka.pro.monthly", "app.soyoka.pro.yearly"]
                let products = try await Product.products(for: productIDs)
                return products.compactMap { product -> SubscriptionProduct? in
                    guard let subscription = product.subscription else { return nil }
                    let period: Domain.SubscriptionPeriod =
                        subscription.subscriptionPeriod.unit == .month ? .monthly : .yearly
                    return SubscriptionProduct(
                        id: product.id,
                        displayName: product.displayName,
                        displayPrice: product.displayPrice,
                        period: period
                    )
                }
            },
            purchase: { productID in
                guard let product = try await Product.products(for: [productID]).first else {
                    return .failed("商品が見つかりません")
                }
                let result = try await product.purchase()
                switch result {
                case let .success(verification):
                    switch verification {
                    case let .verified(transaction):
                        await transaction.finish()
                        return .success
                    case .unverified:
                        return .failed("購入の検証に失敗しました")
                    }
                case .pending:
                    return .pending
                case .userCancelled:
                    return .cancelled
                @unknown default:
                    return .failed("不明なエラー")
                }
            },
            currentSubscription: {
                #if DEBUG
                // デバッグメニュー: Pro プラン強制ON
                if UserDefaults.standard.bool(forKey: "debug_forceProPlan") {
                    return .pro(expiresAt: Date.distantFuture)
                }
                #endif
                for await result in Transaction.currentEntitlements {
                    switch result {
                    case let .verified(transaction):
                        if transaction.productType == .autoRenewable,
                           let expirationDate = transaction.expirationDate,
                           expirationDate > Date() {
                            return .pro(expiresAt: expirationDate)
                        }
                    case .unverified:
                        continue
                    }
                }
                return .free
            },
            observeTransactionUpdates: {
                AsyncStream { continuation in
                    let task = Task {
                        for await result in Transaction.updates {
                            if case let .verified(transaction) = result {
                                await transaction.finish()
                                // 状態を再判定
                                var currentState: SubscriptionState = .free
                                for await entitlement in Transaction.currentEntitlements {
                                    if case let .verified(t) = entitlement,
                                       t.productType == .autoRenewable,
                                       let exp = t.expirationDate, exp > Date() {
                                        currentState = .pro(expiresAt: exp)
                                        break
                                    }
                                }
                                continuation.yield(currentState)
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
