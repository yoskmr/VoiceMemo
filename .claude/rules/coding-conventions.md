---
paths: ["**/*.swift"]
---

# コーディング規約（汎用）

- TCA の Reducer は `@Reducer` マクロ + `@ObservableState` を使用
- Dependency 注入は `@Dependency(\.xxx)` + `DependencyKey` 準拠
- テストは `TestStore` を使い、exhaustivity を適切に設定
- エンティティ変更は Domain 層の `VoiceMemoEntity` で行い、SwiftData モデルは InfraStorage 層のみ
- 設計書（`docs/spec/`）に準拠して実装する。乖離を見つけたら報告すること
