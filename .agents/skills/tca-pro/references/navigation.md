# Navigation Patterns

## Two Paradigms

- **Tree-based**: Use for Sheet, Popover, Alert, ConfirmationDialog. The parent holds the child's state as an `Optional`.
- **Stack-based**: Use for push/pop navigation with `NavigationStack`. Manage the screen stack via `StackState`.


## Tree-based (@Presents + .ifLet)

- Declare optional child state with `@Presents var child: ChildFeature.State?`.
- Wrap the child action in `PresentationAction`: `case child(PresentationAction<ChildFeature.Action>)`.
- Chain `.ifLet(\.$child, action: \.child) { ChildFeature() }` **after** the parent `Reduce` block.
- In the View, bind with `$store.scope(state: \.child, action: \.child)` and pass to `.sheet`, `.alert`, or `.confirmationDialog`.
- Set `@Presents` to `nil` to dismiss; TCA handles the teardown automatically.

```swift
@Reducer
struct ParentFeature {
    @ObservableState
    struct State: Equatable {
        @Presents var addItem: AddItemFeature.State?
    }
    enum Action {
        case addButtonTapped
        case addItem(PresentationAction<AddItemFeature.Action>)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .addButtonTapped:
                state.addItem = AddItemFeature.State()
                return .none
            case .addItem:
                return .none
            }
        }
        .ifLet(\.$addItem, action: \.addItem) { AddItemFeature() }
    }
}
```


## Stack-based (StackState + .forEach)

- Define a `@Reducer enum Path` with a case per destination: `case detail(DetailFeature)`.
- Declare `var path = StackState<Path.State>()` in the parent State.
- Declare `case path(StackActionOf<Path>)` in the parent Action.
- Chain `.forEach(\.path, action: \.path)` **after** the parent `Reduce` block.
- In the View, use `NavigationStack(path: $store.scope(state: \.path, action: \.path))`.
- Push by appending to `state.path`; pop by removing from it. This makes deep linking straightforward.

```swift
@Reducer
struct AppFeature {
    @Reducer
    enum Path {
        case detail(DetailFeature)
        case settings(SettingsFeature)
    }
    @ObservableState
    struct State: Equatable {
        var path = StackState<Path.State>()
    }
    enum Action {
        case path(StackActionOf<Path>)
        case goToDetailTapped(ItemID)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .goToDetailTapped(id):
                state.path.append(.detail(DetailFeature.State(itemID: id)))
                return .none
            case .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}
```


## Tab Navigation

- Use a simple enum property in State: `var selectedTab: Tab`.
- Bind in the View with `$store.selectedTab.sending(\.tabSelected)`.
- Do not use `@Presents` or `StackState` for tabs — they are always alive, not pushed or presented.


## Deprecated APIs — Do Not Use

- `NavigationStackStore` → Replace with `NavigationStack(path: $store.scope(state: \.path, action: \.path))`.
- `IfLetStore` → Replace with `if let store = store.scope(state: \.child, action: \.child)`.
- `ForEachStore` → Replace with `ForEach(store.scope(state: \.items, action: \.items))`.
- `SwitchStore` / `CaseLet` → Replace with Swift standard `switch store.state`.


## Decision Guide

| Scenario | Pattern |
|:---------|:--------|
| Sheet / Alert / ConfirmationDialog | Tree-based (`@Presents` + `.ifLet`) |
| Push/pop screen stack | Stack-based (`StackState` + `.forEach`) |
| Tab switching | Enum State property |
| Deep linking | Stack-based (paths are directly manipulable) |
| Mixed (tabs + push within a tab) | Enum for tabs, Stack-based inside each tab |
