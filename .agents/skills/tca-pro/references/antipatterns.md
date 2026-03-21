# Anti-Patterns

## 1. Use Action as a method call substitute
- Bad: `return .send(.sharedLogic)` to invoke shared logic across actions.
- Good: Extract shared logic into a `mutating func` on State or a private helper on the Reducer.
- Why: Each `.send()` triggers rescoping + equality checks — far more expensive than a function call.

## 2. Name Actions by what they do instead of what happened
- Bad: `case incrementCount`, `case saveItem`
- Good: `case incrementButtonTapped`, `case saveButtonTapped`
- Why: Actions are events, not commands. "What happened" naming keeps the Reducer as the single source of logic.

## 3. Perform heavy computation in the Reducer body
- Bad: O(n) computation, file I/O, or network calls directly in the Reducer.
- Good: Offload to `Effect.run` to execute off the main thread.
- Why: The Reducer runs on the main thread — heavy work causes UI freezes.

## 4. Use property observers (didSet/willSet) on State
- Bad: Adding `didSet` side effects to State properties.
- Good: Handle state-change side effects in the Reducer via Effects.
- Why: Property observers bypass the Reducer, making behavior untestable.

## 5. Create excessive parent-child bidirectional communication
- Bad: Parent catches child's internal Actions and sends Actions back in a loop.
- Good: Use the DelegateAction pattern for loose coupling.
- Why: Bidirectional loops make code hard to understand and debug.

## 6. Add Equatable conformance to Action
- Bad: `enum Action: Equatable`
- Good: `enum Action` (or `enum Action: Sendable` only when needed).
- Why: TCA handles Action comparison internally — manual Equatable adds unnecessary overhead.

## 7. Continue using ViewStore / WithViewStore
- Bad: `WithViewStore(store, observe: { $0 })` wrapper.
- Good: Access Store properties directly — `@ObservableState` tracks accessed properties automatically.
- Why: Deprecated in TCA 1.24+, will be removed in v2.0.

## 8. Use type-based cancel IDs
- Bad: `.cancellable(id: SomeReducer.self)` — using a type itself as the cancel ID.
- Good: `private enum CancelID { case search }` inside the Reducer, then `.cancellable(id: CancelID.search)`.
- Why: Type-based cancel IDs (`SomeType.self`) hit a known Swift bug that breaks release builds.
