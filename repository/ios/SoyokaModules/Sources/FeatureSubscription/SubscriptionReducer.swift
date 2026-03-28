import ComposableArchitecture
import Domain

@Reducer
public struct SubscriptionReducer {
    @ObservableState
    public struct State: Equatable {
        public var products: [SubscriptionProduct] = []
        public var subscriptionState: SubscriptionState = .free
        public var isLoading: Bool = false
        public var isPurchasing: Bool = false
        public var errorMessage: String?
        public var showSuccessMessage: Bool = false

        public init() {}
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case productsLoaded(Result<[SubscriptionProduct], EquatableError>)
        case subscriptionStateLoaded(SubscriptionState)
        case purchaseTapped(productID: String)
        case purchaseCompleted(PurchaseResult)
        case restoreTapped
        case restoreCompleted(RestoreResult)
        case subscriptionStateChanged(SubscriptionState)
        case dismissError
        case dismissSuccess
    }

    /// Result<Void, Error> のEquatable準拠ラッパー
    public enum RestoreResult: Equatable, Sendable {
        case success
        case failure(String)
    }

    @Dependency(\.subscriptionClient) var subscriptionClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = true
                return .merge(
                    .run { send in
                        let result = await Result { try await subscriptionClient.fetchProducts() }
                            .mapError { EquatableError($0) }
                        await send(.productsLoaded(result))
                    },
                    .run { send in
                        let state = await subscriptionClient.currentSubscription()
                        await send(.subscriptionStateLoaded(state))
                    },
                    .run { send in
                        for await state in subscriptionClient.observeTransactionUpdates() {
                            await send(.subscriptionStateChanged(state))
                        }
                    }
                )

            case let .productsLoaded(.success(products)):
                state.isLoading = false
                state.products = products
                return .none

            case let .productsLoaded(.failure(error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                return .none

            case let .subscriptionStateLoaded(subState):
                state.subscriptionState = subState
                return .none

            case let .purchaseTapped(productID):
                state.isPurchasing = true
                return .run { send in
                    let result = try await subscriptionClient.purchase(productID)
                    await send(.purchaseCompleted(result))
                }

            case let .purchaseCompleted(result):
                state.isPurchasing = false
                switch result {
                case .success:
                    state.showSuccessMessage = true
                case .pending:
                    state.errorMessage = "購入の承認を待っています"
                case .cancelled:
                    break
                case let .failed(message):
                    state.errorMessage = message
                }
                return .none

            case .restoreTapped:
                state.isLoading = true
                return .run { send in
                    do {
                        try await subscriptionClient.restorePurchases()
                        await send(.restoreCompleted(.success))
                    } catch {
                        await send(.restoreCompleted(.failure(error.localizedDescription)))
                    }
                }

            case .restoreCompleted(.success):
                state.isLoading = false
                return .none

            case let .restoreCompleted(.failure(message)):
                state.isLoading = false
                state.errorMessage = message
                return .none

            case let .subscriptionStateChanged(subState):
                state.subscriptionState = subState
                return .none

            case .dismissError:
                state.errorMessage = nil
                return .none

            case .dismissSuccess:
                state.showSuccessMessage = false
                return .none
            }
        }
    }
}
