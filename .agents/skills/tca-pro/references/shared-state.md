# Shared State

## @Shared
- Value-type mechanism for sharing state across multiple Features.
- Changes in one Feature are instantly reflected in all others that share the same reference.
- Fully testable: exhaustive tests can assert @Shared mutations.

## Persistence strategies
- `@Shared(.appStorage("key"))` — backed by UserDefaults.
- `@Shared(.fileStorage(.url))` — backed by file system (JSON-encoded).
- Custom strategies — for remote config, feature flags, or external data sources.

## Rules
- Use @Shared only when state truly needs synchronization across multiple Features.
- Avoid excessive sharing — keep Feature state self-contained when possible.
- The parent initializes and passes @Shared references to children.
- When combining @Shared with DelegateAction, be aware that state mutation timing in tests may differ from expectations.
