---
name: tca-pro
description: Reviews, writes, and improves TCA (The Composable Architecture) code for correctness, modern API usage, and best practices. Use when reading, writing, or reviewing Swift projects that use TCA.
license: MIT
metadata:
  author: MurMurNote Team
  version: "1.0"
---

Review TCA (The Composable Architecture) code for correctness, modern API usage, and adherence to project conventions. Report only genuine problems - do not nitpick or invent issues.

Review process:

1. Validate Reducer structure using `references/reducer.md`.
1. Verify Effect patterns and async handling using `references/effects.md`.
1. Check dependency injection design using `references/dependencies.md`.
1. Validate child Reducer composition using `references/composition.md`.
1. Ensure navigation patterns are correct using `references/navigation.md`.
1. Verify shared state usage using `references/shared-state.md`.
1. Check testing patterns using `references/testing.md`.
1. Audit performance pitfalls using `references/performance.md`.
1. Validate Swift 6 concurrency compliance using `references/concurrency.md`.
1. Final check against common anti-patterns using `references/antipatterns.md`.

If doing a partial review, load only the relevant reference files.


## Core Instructions

- Target TCA 1.17+ with `@Reducer` macro and `@ObservableState`.
- All deprecated APIs (`ViewStore`, `WithViewStore`, `IfLetStore`, `ForEachStore`, `SwitchStore`, `NavigationStackStore`, `@BindingState`, `Effect.concatenate`, `Effect.map`, `TaskResult`) must not appear in new code.
- Reducer naming: prefer `XxxFeature` over `XxxReducer` suffix.
- Action naming: describe "what happened" (e.g., `saveButtonTapped`), not "what to do" (e.g., `saveItem`).
- Dependencies use struct-based clients with `@DependencyClient`, not protocols.
- State must always have `@ObservableState` for v2.0 readiness.


## Output Format

Organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated (e.g., "Use `@ObservableState` on all State types").
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes to make first.

Example output:

### CounterFeature.swift

**Line 15: Action should not be `Equatable` — TCA handles equality internally.**

```swift
// Before
enum Action: Equatable {
    case incrementButtonTapped
}

// After
enum Action {
    case incrementButtonTapped
}
```

**Line 42: Use `Effect.run` instead of deprecated `Effect.concatenate`.**

```swift
// Before
return .concatenate(
    .run { send in await send(.fetchUser) },
    .run { send in await send(.fetchPosts) }
)

// After
return .run { send in
    let user = await fetchUser()
    await send(.userLoaded(user))
    let posts = await fetchPosts(userId: user.id)
    await send(.postsLoaded(posts))
}
```

### Summary

1. **Correctness (high):** Deprecated API usage on line 42 will break in TCA v2.0.
2. **Convention (medium):** Action Equatable conformance is unnecessary overhead.

End of example.


## References

- `references/reducer.md` - @Reducer macro, State, Action, and body structure patterns.
- `references/effects.md` - Effect patterns: .run, .merge, cancellation, and debounce.
- `references/dependencies.md` - DependencyKey, @DependencyClient, and Client struct design.
- `references/composition.md` - Child Reducer composition: Scope, ifLet, forEach, ordering rules.
- `references/navigation.md` - Tree-based and Stack-based navigation patterns.
- `references/shared-state.md` - @Shared, AppStorage, FileStorage, and cross-feature state.
- `references/testing.md` - TestStore, exhaustivity modes, TestClock, and testing best practices.
- `references/performance.md` - Observation optimization, avoiding unnecessary recomputation.
- `references/concurrency.md` - Swift 6 compatibility, Sendable, @MainActor rules.
- `references/antipatterns.md` - Common TCA mistakes and their fixes.
