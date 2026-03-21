# Child Reducer Composition

## Scope (always-visible child Feature)

- Use `Scope` to embed a child Feature that is always present in the parent State.
- Write `Scope(state: \.child, action: \.child) { ChildFeature() }` in the parent `body`.
- Place `Scope` **before** the parent `Reduce` block so the child processes its actions first, then the parent can react.
- The parent State must hold a non-optional child State property: `var child = ChildFeature.State()`.
- The parent Action must have a case wrapping the child Action: `case child(ChildFeature.Action)`.


## ifLet (optional child Feature / presentation)

- Use `ifLet` for child Features that appear conditionally — sheets, alerts, navigation destinations.
- Annotate the optional child State with `@Presents`: `@Presents var detail: DetailFeature.State?`.
- Wrap the child Action in `PresentationAction`: `case detail(PresentationAction<DetailFeature.Action>)`.
- Chain `.ifLet(\.$detail, action: \.detail) { DetailFeature() }` **after** the parent `Reduce` block.
- To handle a specific child action in the parent, pattern-match on `.presented`: `case .detail(.presented(.saveButtonTapped))`.
- Setting the `@Presents` property to `nil` in the parent automatically dismisses the child and cancels its in-flight effects.


## forEach (collection of child Features)

- Use `forEach` when the parent holds a collection of identically-typed child Features.
- Store child states in `IdentifiedArrayOf<ItemFeature.State>`.
- Wrap the child Action with `IdentifiedActionOf`: `case items(IdentifiedActionOf<ItemFeature>)`.
- Chain `.forEach(\.items, action: \.items) { ItemFeature() }` **after** the parent `Reduce` block.
- To handle a specific child action, pattern-match on the id: `case .items(.element(id: let id, action: .delegate(.didDelete)))`.


## forEach with NavigationStack

- Use `StackState<Path.State>` and `StackActionOf<Path>` for stack-based navigation.
- Define the path as a `@Reducer enum Path` containing a case per destination: `case detail(DetailFeature)`.
- Chain `.forEach(\.path, action: \.path)` **after** the parent `Reduce` block — the `@Reducer enum` synthesizes the child Reducer automatically.
- Push destinations by appending to `StackState`: `state.path.append(.detail(DetailFeature.State()))`.
- Pop by removing from the stack; in-flight effects of removed screens are cancelled automatically.


## Composition ordering rules

- Place `Scope` (always-present children) **first** in `body`.
- Place the parent `Reduce` block **second**.
- Chain `ifLet` and `forEach` **after** the `Reduce` block.
- This ordering guarantees: child reduces first, parent reacts second, optional/collection decorators apply last.


## DelegateAction pattern

- Use a nested `DelegateAction` enum when a child needs to notify its parent of domain events.
- Define `case delegate(DelegateAction)` inside the child's `Action`.
- The child must never handle `.delegate` actions itself — always `return .none` for them.
- The parent catches delegate actions via pattern matching: `case .child(.delegate(.didFinishSaving(let item)))`.
- `DelegateAction` cases must not trigger Effects — they are pure notifications only.
- Prefer `DelegateAction` over relying on the parent to inspect child state changes; it makes intent explicit.


## Complete example

```swift
@Reducer
struct ParentFeature {
    @ObservableState
    struct State: Equatable {
        // Always-present child
        var counter = CounterFeature.State()
        // Optional child (sheet)
        @Presents var editor: EditorFeature.State?
        // Collection children
        var items = IdentifiedArrayOf<ItemFeature.State>()
    }

    enum Action {
        case counter(CounterFeature.Action)
        case editor(PresentationAction<EditorFeature.Action>)
        case items(IdentifiedActionOf<ItemFeature>)
        case addButtonTapped
        case editButtonTapped
    }

    var body: some ReducerOf<Self> {
        // 1. Scope — child processes first
        Scope(state: \.counter, action: \.counter) {
            CounterFeature()
        }

        // 2. Reduce — parent logic
        Reduce { state, action in
            switch action {
            case .addButtonTapped:
                state.items.append(ItemFeature.State(title: "New"))
                return .none

            case .editButtonTapped:
                state.editor = EditorFeature.State()
                return .none

            // Handle child delegate
            case .items(.element(id: let id, action: .delegate(.didMarkComplete))):
                state.items.remove(id: id)
                return .none

            // Handle presented child action
            case .editor(.presented(.delegate(.didSave(let text)))):
                state.items.append(ItemFeature.State(title: text))
                return .none

            case .counter, .editor, .items:
                return .none
            }
        }
        // 3. ifLet / forEach — decorators after Reduce
        .ifLet(\.$editor, action: \.editor) {
            EditorFeature()
        }
        .forEach(\.items, action: \.items) {
            ItemFeature()
        }
    }
}
```
