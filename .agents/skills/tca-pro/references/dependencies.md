# Dependency Injection

## Client Struct Pattern (Recommended)

- Define dependencies as a struct holding `@Sendable` closures, not as a protocol.
- Apply `@DependencyClient` macro to auto-generate `unimplemented` stubs for every endpoint.
- Each closure property represents one endpoint the dependency exposes.
- Test code can override only the specific endpoints it cares about; unoverridden endpoints fail loudly via `unimplemented`.

## DependencyKey Conformance

- `liveValue` is required — this is the production implementation.
- Omit `testValue` to get an automatic failing stub; any test that accidentally calls the dependency will fail immediately, surfacing unintended usage.
- Provide `previewValue` for lightweight stubs used in SwiftUI Previews. Keep it minimal and deterministic.

## DependencyValues Registration

- Extend `DependencyValues` with a computed property (getter + setter) to register the client.
- Use a private `DependencyKey`-conforming type, or combine key conformance directly on the client struct.

## Reducer Injection

- Inject via `@Dependency(\.xxx)` as a stored property on the Reducer.
- Prefer TCA built-in dependencies for testability: `\.continuousClock`, `\.date.now`, `\.calendar`, `\.uuid`, `\.withRandomNumberGenerator`.
- Never call `Date()`, `UUID()`, or `Calendar.current` directly inside a Reducer body — always go through `@Dependency`.

## Test Dependency Overrides

- Override inside `TestStore` using the `withDependencies` trailing closure: `TestStore(initialState:reducer:) { } withDependencies: { $0.xxx = ... }`.
- Assign closure literals directly to client endpoints — no mock class needed.
- Use `prepareDependencies` only when `State.init` itself reads a dependency internally.
- Override `\.continuousClock` with `TestClock` for time-dependent logic; advance manually in tests.

## Rules

- Place client struct definitions in the Domain layer.
- Place `liveValue` implementations in the Infra layer.
- A UseCase client may compose other clients by accepting them via `@Dependency` — avoid deeply nested manual injection.
- Always use `@DependencyClient` + `unimplemented` rather than hand-writing empty stubs.
- Mark every closure property `@Sendable` — the macro does this automatically, but verify if adding endpoints manually.


## Complete Example

```swift
import Dependencies
import DependenciesMacros
import Foundation

// ── Domain Layer: Client Definition ──────────────────────────

@DependencyClient
struct AudioSessionClient: Sendable {
    /// Activate or deactivate the audio session.
    var setActive: @Sendable (_ isActive: Bool) throws -> Void
    /// Request recording permission. Returns true if granted.
    var requestPermission: @Sendable () async -> Bool
    /// Observe interruption events.
    var interruptions: @Sendable () -> AsyncStream<AudioInterruption> = {
        .finished
    }
}

enum AudioInterruption: Sendable, Equatable {
    case began
    case ended(shouldResume: Bool)
}

// ── DependencyKey + DependencyValues ─────────────────────────

extension AudioSessionClient: DependencyKey {
    static let liveValue: Self = {
        // Infra layer provides the real implementation.
        // Typically imported from InfraAudio module.
        LiveAudioSessionClient.make()
    }()

    // testValue is auto-generated as unimplemented by @DependencyClient.
    // previewValue returns safe no-op defaults:
    static let previewValue = Self(
        setActive: { _ in },
        requestPermission: { true }
    )
}

extension DependencyValues {
    var audioSession: AudioSessionClient {
        get { self[AudioSessionClient.self] }
        set { self[AudioSessionClient.self] = newValue }
    }
}

// ── Reducer Injection ────────────────────────────────────────

@Reducer
struct RecordingFeature {
    @ObservableState
    struct State: Equatable { /* ... */ }

    enum Action {
        case recordButtonTapped
        case permissionResponse(Bool)
    }

    @Dependency(\.audioSession) var audioSession

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .recordButtonTapped:
                return .run { send in
                    let granted = await audioSession.requestPermission()
                    await send(.permissionResponse(granted))
                }
            case .permissionResponse:
                return .none
            }
        }
    }
}
```
