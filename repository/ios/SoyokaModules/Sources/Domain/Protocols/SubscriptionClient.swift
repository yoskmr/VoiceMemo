import Dependencies
import Foundation

// MARK: - Types

public struct SubscriptionProduct: Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let displayPrice: String
    public let period: SubscriptionPeriod

    public init(id: String, displayName: String, displayPrice: String, period: SubscriptionPeriod) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.period = period
    }
}

public enum SubscriptionPeriod: String, Equatable, Sendable {
    case monthly
    case yearly
}

public enum PurchaseResult: Equatable, Sendable {
    case success
    case pending
    case cancelled
    case failed(String)
}

public enum SubscriptionState: Equatable, Sendable {
    case free
    case pro(expiresAt: Date)
    case expired
}

// MARK: - Client

public struct SubscriptionClient: Sendable {
    public var fetchProducts: @Sendable () async throws -> [SubscriptionProduct]
    public var purchase: @Sendable (_ productID: String) async throws -> PurchaseResult
    public var currentSubscription: @Sendable () async -> SubscriptionState
    public var observeTransactionUpdates: @Sendable () -> AsyncStream<SubscriptionState>
    public var restorePurchases: @Sendable () async throws -> Void

    public init(
        fetchProducts: @escaping @Sendable () async throws -> [SubscriptionProduct],
        purchase: @escaping @Sendable (_ productID: String) async throws -> PurchaseResult,
        currentSubscription: @escaping @Sendable () async -> SubscriptionState,
        observeTransactionUpdates: @escaping @Sendable () -> AsyncStream<SubscriptionState>,
        restorePurchases: @escaping @Sendable () async throws -> Void
    ) {
        self.fetchProducts = fetchProducts
        self.purchase = purchase
        self.currentSubscription = currentSubscription
        self.observeTransactionUpdates = observeTransactionUpdates
        self.restorePurchases = restorePurchases
    }
}

// MARK: - DependencyKey

extension SubscriptionClient: TestDependencyKey {
    public static let testValue = SubscriptionClient(
        fetchProducts: unimplemented("SubscriptionClient.fetchProducts"),
        purchase: unimplemented("SubscriptionClient.purchase"),
        currentSubscription: unimplemented("SubscriptionClient.currentSubscription"),
        observeTransactionUpdates: unimplemented("SubscriptionClient.observeTransactionUpdates"),
        restorePurchases: unimplemented("SubscriptionClient.restorePurchases")
    )
}

extension DependencyValues {
    public var subscriptionClient: SubscriptionClient {
        get { self[SubscriptionClient.self] }
        set { self[SubscriptionClient.self] = newValue }
    }
}
