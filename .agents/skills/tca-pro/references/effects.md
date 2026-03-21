# Effect Patterns

## Effect.run (recommended)

- Use `Effect.run` for all new Effect code. It integrates naturally with Swift Concurrency via async/await.
- Handle errors with the trailing `catch:` closure: `} catch: { error, send in ... }`.
- Capture state values explicitly with `[captured = state.value]` to satisfy Sendable requirements. Never capture `state` itself.
- Call `await send(.actionName(result))` inside the closure to feed results back to the Reducer.

```swift
// Before (deprecated TaskResult)
return .task {
    await TaskResult {
        try await apiClient.fetchMemos()
    }
}

// After (Effect.run)
return .run { [query = state.searchQuery] send in
    let memos = try await apiClient.fetchMemos(query: query)
    await send(.memosLoaded(memos))
} catch: { error, send in
    await send(.memosLoadFailed(error.localizedDescription))
}
```


## Effect.merge

- Combine multiple independent Effects with `.merge()` when they should execute in parallel.
- Do not use `.merge()` for sequential operations; use a single `.run` with sequential awaits instead.

```swift
return .merge(
    .run { send in
        let stream = try await audioRecorder.startRecording()
        for await level in stream {
            await send(.audioLevelUpdated(level))
        }
    },
    .run { send in
        for await _ in clock.timer(interval: .seconds(1)) {
            await send(.timerTicked)
        }
    }
)
```


## Cancellation

- Define cancel IDs as `private enum CancelID { case xxx }`. Do not use type-based cancel IDs (`CancelID.self`) — this triggers a known Swift bug that breaks release builds.
- Attach `.cancellable(id: CancelID.xxx, cancelInFlight:)` to any long-running Effect.
- Set `cancelInFlight: true` to auto-cancel the previous in-flight Effect when a new one starts (ideal for search debounce).
- Use `.cancel(id: CancelID.xxx)` for explicit cancellation (e.g., on `viewDidDisappear`).

```swift
private enum CancelID { case search }

case .searchQueryChanged:
    return .run { [query = state.query] send in
        try await clock.sleep(for: .milliseconds(300))
        let results = try await searchClient.search(query)
        await send(.searchResultsLoaded(results))
    }
    .cancellable(id: CancelID.search, cancelInFlight: true)

case .viewDidDisappear:
    return .cancel(id: CancelID.search)
```


## Debounce

- Combine `clock.sleep(for:)` with `.cancellable(cancelInFlight: true)` for debounce.
- Inject the clock via `@Dependency(\.continuousClock)` so tests can use `TestClock` to advance time deterministically.

```swift
@Dependency(\.continuousClock) var clock

// Inside Reducer body
case .searchQueryChanged:
    return .run { [query = state.query] send in
        try await clock.sleep(for: .milliseconds(300))
        let results = try await searchClient.search(query)
        await send(.searchResultsLoaded(results))
    }
    .cancellable(id: CancelID.search, cancelInFlight: true)
```


## Sequential execution

- Do not use `Effect.concatenate` — it is deprecated since TCA 1.25.
- Perform sequential work inside a single `.run` closure with multiple awaits.

```swift
// Before (deprecated)
return .concatenate(
    .run { send in await send(.fetchUser) },
    .run { send in await send(.fetchPosts) }
)

// After
return .run { send in
    let user = try await userClient.fetch()
    await send(.userLoaded(user))
    let posts = try await postClient.fetch(userId: user.id)
    await send(.postsLoaded(posts))
}
```


## Deprecated APIs

- `Effect.concatenate` — replace with sequential awaits inside `.run`.
- `Effect.map` — replace with `await send()` inside `.run`.
- `Effect.publisher` — replace with `.run` + async/await.
- `TaskResult` — replace with Swift native `Result` or direct try/catch in `.run`.


## Rules

- Never perform heavy computation directly in the Reducer body — it runs on the main thread. Offload to `.run`.
- Do not use `await send()` as a way to call shared logic across actions. Extract shared logic into a private helper method instead.
- When passing errors through Actions, wrap with `Result { try await ... }.mapError { EquatableError($0) }` so the Action payload stays Equatable.
