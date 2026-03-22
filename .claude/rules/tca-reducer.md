---
paths: ["**/*Feature*.swift", "**/*Reducer*.swift"]
---

# TCA Reducer 規約

Reducer のセクション順序（`RecordingFeature.swift` を正規パターンとする）:
1. `// MARK: - Constants` — 定数定義
2. `// MARK: - State` — `@ObservableState public struct State: Equatable`、`public init` は全パラメータにデフォルト値
3. `// MARK: - Action` — `public enum Action: Equatable, Sendable`、ユーザー操作は `xxxButtonTapped`、内部は `xxxLoaded/xxxFailed/xxxUpdated`
4. `// MARK: - Dependencies` — `@Dependency(\.xxx) var xxx`
5. `// MARK: - Cancellation IDs` — `private enum CancelID { case xxx }`
6. `// MARK: - Reducer Body` — `public init() {}` + `public var body: some ReducerOf<Self>`
7. `// MARK: - Effects` — `private func xxxEffect() -> Effect<Action>` + `.cancellable(id:)`

必須ルール:
- Doc comment に設計書参照を記載（例: `/// 設計書01-system-architecture.md セクション2.2 準拠`）
- Result ハンドリング: `.success` / `.failure(EquatableError)`
- ナビゲーション: `@Presents` + `.ifLet`
- Feature 層から Infra 層への直接依存禁止（Package.swift で制約済み）
