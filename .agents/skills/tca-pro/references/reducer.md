# @Reducer Structure

## @Reducer Macro

- Always use `@Reducer` macro on the top-level struct. It automatically synthesizes `Reducer` protocol conformance and applies `@CasePathable` to `Action` (and nested enums).
- Name Reducer structs as `XxxFeature` (e.g., `RecordingFeature`). Do not use the `XxxReducer` suffix — it is redundant with the macro.
- Do not manually add `: Reducer` conformance when using `@Reducer`; the macro provides it.


## State

- Always annotate State with `@ObservableState`. This is required for v2.0 readiness and enables direct observation without `ViewStore`.
- Define State as `struct State: Equatable`. TCA relies on equality checks for state diffing.
- Provide an explicit `init` with all properties as parameters so tests can construct arbitrary states easily.
- Nested enums representing modes or status belong inside `State` (e.g., `State.Mode`).
- Never use `@BindingState` — it is deprecated. Use `@Presents` for child state and direct property access with `@ObservableState`.


## Action

- Define as `enum Action` without any protocol conformance. Do not add `Equatable` or `Sendable` — TCA handles equality internally. Add `Sendable` only when `AlertState` or `ConfirmationDialogState` requires it.
- Name actions by "what happened", not "what to do": `saveButtonTapped` (correct), `saveItem` (incorrect).
- For async response actions, use a dedicated result enum instead of `Result<Void, Error>` when the error type is not `Equatable`.
- Optionally categorize actions with nested enums: `Action.view`, `Action.internal`, `Action.delegate`. Use this pattern when the Reducer is composed and needs to communicate with a parent.


## body

- Declare as `var body: some ReducerOf<Self>`.
- If the compiler cannot infer the type, write `Reduce<State, Action> { state, action in ... }` explicitly.
- Place child Reducers (`Scope`) **before** the parent `Reduce` block so child state is updated first.
- Chain `ifLet` and `forEach` **after** the `Reduce` block — they decorate the parent Reducer.


## Example: Correct @Reducer structure

```swift
// Before — deprecated patterns
struct CounterReducer: Reducer {
    struct State: Equatable {
        @BindingState var count = 0
    }
    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case incrementButtonTapped
    }
    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            // ...
        }
    }
}

// After — modern @Reducer with @ObservableState
@Reducer
struct CounterFeature {
    @ObservableState
    struct State: Equatable {
        var count = 0
        init(count: Int = 0) { self.count = count }
    }
    enum Action {
        case incrementButtonTapped
        case decrementButtonTapped
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .incrementButtonTapped:
                state.count += 1
                return .none
            case .decrementButtonTapped:
                state.count -= 1
                return .none
            }
        }
    }
}
```

## Example: Composition ordering

```swift
// Before — wrong order: parent Reduce runs before child
@Reducer
struct ParentFeature {
    // ...
    var body: some ReducerOf<Self> {
        Reduce { state, action in /* parent logic */ }
        Scope(state: \.child, action: \.child) { ChildFeature() }
    }
}

// After — correct order: Scope first, then Reduce, then ifLet
@Reducer
struct ParentFeature {
    @ObservableState
    struct State: Equatable {
        var child = ChildFeature.State()
        @Presents var detail: DetailFeature.State?
    }
    enum Action {
        case child(ChildFeature.Action)
        case detail(PresentationAction<DetailFeature.Action>)
    }
    var body: some ReducerOf<Self> {
        Scope(state: \.child, action: \.child) { ChildFeature() }
        Reduce { state, action in
            // parent logic here
            .none
        }
        .ifLet(\.$detail, action: \.detail) { DetailFeature() }
    }
}
```
