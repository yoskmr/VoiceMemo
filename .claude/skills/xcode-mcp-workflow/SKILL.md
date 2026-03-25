---
name: xcode-mcp-workflow
description: SoyokaプロジェクトでのXcode MCP連携ルールとビルド(build)・テスト(test)手順。ビルド、テスト実行、デバッグ(debug)、エラー確認(error/warning)、SwiftUI Preview、Xcode操作など開発ワークフロー全般で必ず参照すること。コード変更後のビルド確認やテスト実行時、xcodebuild や swift test を使おうとした場面でも自動的に使うこと。
---

# Xcode MCP 連携ワークフロー

本プロジェクトでは Xcode 26.3 の MCP（Model Context Protocol）ブリッジを使用し、Claude Code から Xcode を直接操作する。
`xcodebuild` CLI よりも Xcode MCP ツールを優先して使うこと。

**前提条件**: Xcode が起動し、プロジェクトが開かれている状態であること。

## 利用可能なツール一覧（全20ツール）

| カテゴリ | ツール名 | 用途 |
|:---------|:---------|:-----|
| **ワークスペース** | `XcodeListWindows` | 開いているウィンドウ一覧と `tabIdentifier` を取得（**他ツールの前に必ず呼ぶ**） |
| **ファイル操作** | `XcodeRead` | ファイル読み込み |
| | `XcodeWrite` | ファイル書き込み |
| | `XcodeUpdate` | ファイルの部分更新 |
| | `XcodeGlob` | パターンでファイル検索 |
| | `XcodeGrep` | コード内テキスト検索 |
| | `XcodeLS` | ディレクトリ一覧 |
| | `XcodeMakeDir` | ディレクトリ作成 |
| | `XcodeRM` | ファイル/ディレクトリ削除 |
| | `XcodeMV` | ファイル移動/リネーム |
| **ビルド** | `BuildProject` | プロジェクトのビルド実行 |
| | `GetBuildLog` | ビルドログ取得（エラー・警告の確認） |
| **テスト** | `RunAllTests` | 全テスト実行 |
| | `RunSomeTests` | 指定テストのみ実行 |
| | `GetTestList` | テスト一覧取得 |
| **診断** | `XcodeListNavigatorIssues` | Issue Navigator のエラー・警告一覧取得 |
| | `XcodeRefreshCodeIssuesInFile` | 指定ファイルのコード診断更新 |
| **インテリジェンス** | `DocumentationSearch` | Apple ドキュメント・WWDC 動画の横断検索（`tabIdentifier`不要） |
| | `ExecuteSnippet` | Swift コードスニペットの REPL 実行 |
| | `RenderPreview` | SwiftUI Preview のスクリーンショット取得 |

## 開発ワークフロールール

1. **ビルド確認**: コード変更後は `BuildProject` → `GetBuildLog` で確認する。`xcodebuild` CLI は使わない
2. **エラー確認**: `XcodeListNavigatorIssues` で Issue Navigator のエラーを取得する
3. **テスト実行**: `RunSomeTests` で変更に関連するテストを実行する。全テストは `RunAllTests`
4. **UI確認**: SwiftUI のレイアウト確認には `RenderPreview` でスクリーンショットを取得する
5. **API調査**: Apple フレームワークの使い方は `DocumentationSearch` で検索する
6. **tabIdentifier の取得**: ファイル操作・ビルド・テスト・診断系ツールは `tabIdentifier` が必須。操作前に `XcodeListWindows` で取得すること
7. **コードスニペットの検証**: `ExecuteSnippet` で Swift コードの動作を即座に検証できる

## CLI フォールバック（Xcode MCP 未接続時）

Xcode MCP に接続できない場合のみ、以下の CLI コマンドを使う：

```bash
# ビルド
cd repository/ios && xcodebuild -project Soyoka.xcodeproj -scheme Soyoka -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build -skipMacroValidation

# テスト（SPM）
cd repository/ios/SoyokaModules && swift test
```
