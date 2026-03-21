# Performance Optimization

## @ObservableState automatic optimization
- Views only track state properties that are actually accessed during rendering.
- Manual scoping with `ViewStore` + `observe:` is no longer needed.
- For iOS 16 and earlier, wrap views with `WithPerceptionTracking`.

## Rules
- Always apply `@ObservableState` to every State type.
- Never perform O(n) computation inside the Reducer body — scope functions run on every action dispatch.
- Debounce high-frequency Actions (timers, scroll events).
- Use Optional State + `.ifLet` to skip reducer processing for hidden screens.
- Avoid computed properties on State — they execute on every hot path evaluation. Pre-compute values instead.
- Place UI-only ephemeral state (hover, focus) in the View layer with `@State`, not in the Store.
- Never access external sources (UserDefaults, singletons) inside scope functions.
- Do not use `.send()` as a substitute for method calls — each send triggers rescoping and equality checks.
