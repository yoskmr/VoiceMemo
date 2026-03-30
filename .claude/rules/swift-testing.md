---
paths: ["**/Tests/**/*.swift"]
---

# テスト規約

- テスト命名: `test_アクション名_条件_期待結果()` 日本語（例: `test_recordButtonTapped_権限許可済み_recordingに遷移する`）
- `@MainActor` 必須
- TestStore セットアップ: `withDependencies` クロージャで依存を明示スタブ
- DependencyClient の `testValue` は `unimplemented()` — テストで使う依存は全て明示的にスタブする
- `store.exhaustivity = .off` は TODO コメント付きで限定使用
- `ImmediateClock()` でクロック差し替え
- ヘルパーメソッド: `makeMemoItem(...)`, `makeEntity(...)` デフォルトパラメータ付き
- テストファイル配置: `Tests/FeatureXxxTests/` でソース構造をミラー
