# TCA 最新ベストプラクティス調査

## 依頼内容

TCA (The Composable Architecture) 1.17+ の最新ベストプラクティスを12トピックにわたって調査する。

## 調査トピック

1. @Reducer マクロの正しい使い方（TCA 1.17+）
2. @ObservableState vs ViewState の移行パターン
3. Effect のベストプラクティス（.run, .publisher, キャンセル）
4. DependencyKey / DependencyValues の設計パターン
5. Navigation（StackState/StackAction, tree-based vs stack-based）
6. テスト: TestStore の使い方、exhaustivity、non-exhaustive テスト
7. パフォーマンス: ViewStore の不要な再計算を避けるパターン
8. 共通のアンチパターン（やってはいけないこと）
9. Swift 6 Concurrency との互換性（Sendable 準拠、@MainActor）
10. 子Reducer合成: Scope, ifLet, forEach の正しい使い分け
11. SharedState / @Shared の使い方
12. DelegateAction パターン

## 実施内容

- pointfreeco 公式 GitHub リポジトリ（リリースノート、ディスカッション）を調査
- Point-Free 公式ブログ記事を参照
- コミュニティのベストプラクティス記事を収集
- Swift 6 移行ガイドを調査

## 成果物

- `result/tca-best-practices-2025.md` - 12トピックの包括的調査レポート

## 知見

- TCA 1.24/1.25 で v2.0 に向けた大規模 deprecation が進行中
- `ViewStore`, `WithViewStore`, `@BindingState`, `ForEachStore`, `IfLetStore` はすべて deprecated
- `@ObservableState` + Store 直接アクセスが唯一の推奨パターン
- `Effect.concatenate`, `Effect.map` も deprecated、`.run` + async/await に統一
- CancelID の型ベース指定は Swift のバグで release ビルドが壊れるため enum case に変更済み
