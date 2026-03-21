# Testing with TestStore

## Basic Structure

- Initialize with `TestStore(initialState:) { XxxFeature() } withDependencies: { ... }`.
- Override dependencies by assigning closure literals directly inside the `withDependencies` block — no mock class needed.
- Annotate test classes (or structs) with `@MainActor` to satisfy TCA's main-actor isolation.
- Prefer Swift Testing (`@Test`, `@Suite`) over XCTest when using TCA 1.17+.

## State Change Assertions

- Use `await store.send(.action) { $0.property = expectedValue }` to declaratively assert state mutations.
- In exhaustive mode (default), every changed property must be asserted inside the trailing closure — omitting any causes a test failure.
- Use `XCTAssertNoDifference` instead of `XCTAssertEqual` for clearer diff output on failure.

## Effect Response Assertions

- Use `await store.receive(\.actionKeyPath)` to expect a specific Action dispatched by an Effect.
- KeyPath syntax ignores associated values: `await store.receive(\.recordingFailed)`.
- Match deeply nested Result patterns: `await store.receive(\.memosLoaded.success)`.
- Assert state changes in the trailing closure of `receive`, just like `send`.

## Exhaustivity Modes

- `.on` (default): Unit-test mode. Every state change and every Effect must be explicitly asserted.
- `.off`: Integration-test mode. Assert only the state properties you care about; the rest are silently ignored.
- `.off(showSkippedAssertions: true)`: Debug mode. Prints skipped assertions to the console for visibility.
- Set via `store.exhaustivity = .off` after creating the TestStore.

## TestClock

- Use `TestClock` for deterministic testing of debounce, throttle, and timer logic.
- Create with `let clock = TestClock()` and inject via `$0.continuousClock = clock`.
- Advance time manually: `await clock.advance(by: .seconds(2))`.
- Never use `Task.sleep` in tests — always use `TestClock` to control time.

## Best Practices

- Call `await store.finish()` at the end of every test to verify no unconsumed Effects remain.
- Use `store.skipInFlightEffects()` to discard long-running Effects (timers, streams) that are irrelevant to the test scenario.
- Tell a story with Action names: `.refreshButtonTapped` -> `.apiResponse` -> `.deleteButtonTapped`.
- Use `prepareDependencies` only when `State.init` reads a dependency internally.
- Capture test expectations with `let` bindings for readability: `let expectedMemo = VoiceMemoEntity(...)`.

## XCTest vs Swift Testing

- Prefer Swift Testing (`@Test`, `@Suite`) — TCA 1.17+ provides full support.
- Use `XCTAssertNoDifference` (from CustomDump) for readable assertion failures.
- In Swift Testing, use `#expect` for simple checks and `withKnownIssue` for expected failures.


## Complete Example

```swift
import ComposableArchitecture
import Testing

@MainActor
@Suite("RecordingFeature Tests")
struct RecordingFeatureTests {
    @Test("Recording starts after permission is granted")
    func startRecording() async {
        let clock = TestClock()

        let store = TestStore(
            initialState: RecordingFeature.State()
        ) {
            RecordingFeature()
        } withDependencies: {
            $0.audioSession.requestPermission = { true }
            $0.audioSession.setActive = { _ in }
            $0.continuousClock = clock
        }

        await store.send(.recordButtonTapped) {
            $0.isRequestingPermission = true
        }

        await store.receive(\.permissionResponse) {
            $0.isRequestingPermission = false
            $0.isRecording = true
        }

        // Advance clock — if the timer fires every 1s, use exhaustivity = .off
        // or receive each tick individually. This example assumes non-exhaustive mode.
        store.exhaustivity = .off
        await clock.advance(by: .seconds(3))

        await store.receive(\.timerTicked) {
            $0.elapsedSeconds = 3
        }

        await store.send(.stopButtonTapped) {
            $0.isRecording = false
        }

        await store.receive(\.recordingSaved)

        await store.finish()
    }
}
```
