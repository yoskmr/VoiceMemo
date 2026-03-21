# Swift 6 Concurrency Compatibility

## Sendable conformance
- State: Value types conform automatically in most cases.
- Action: Requires `Sendable` only when using `AlertState` or `ConfirmationDialogState`.
- Dependency Client: `DependencyKey` protocol requires `Sendable` conformance.
- Values captured in `Effect.run` must be Sendable — use explicit capture lists: `[id = state.itemId]`.

## @MainActor
- Never annotate the Reducer itself with `@MainActor` — TCA manages actor isolation internally.
- `Effect.run` automatically leaves the MainActor — work runs on a background executor.
- `await send()` returns to the MainActor to mutate state.

## Migration strategy
- Enable `StrictConcurrency` module by module, incrementally.
- Use `@preconcurrency import` for third-party frameworks not yet Swift 6 compatible (last resort).
- Swift 6.2 improves `@Sendable` inference — fewer explicit annotations needed.
