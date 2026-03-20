# Xcode 26.3 MCP (Model Context Protocol) ツール調査レポート

**調査日**: 2026-03-20
**対象**: Xcode 26.3 RC / `xcrun mcpbridge`

---

## 1. 概要

Xcode 26.3 は MCP（Model Context Protocol）サーバーを内蔵しており、`xcrun mcpbridge` バイナリが MCP プロトコルと Xcode の内部 XPC レイヤーの間を橋渡しする。

```
Agent <-> MCP Protocol <-> mcpbridge <-> XPC <-> Xcode
```

合計 **20 ツール** が公開されている。

---

## 2. 利用可能なツール一覧

### 2.1 ファイル操作（9 ツール）

| ツール名 | 説明 | 必須パラメータ | オプションパラメータ |
|----------|------|--------------|-------------------|
| **XcodeRead** | プロジェクト内ファイルの内容を読み取る（行番号付き、最大600行） | `tabIdentifier`, `filePath` | `limit` (integer), `offset` (integer) |
| **XcodeWrite** | プロジェクト内にファイルを作成または上書き | `tabIdentifier`, `filePath`, `content` | - |
| **XcodeUpdate** | ファイル内のテキストを置換して編集（str_replace方式） | `tabIdentifier`, `filePath`, `oldString`, `newString` | `replaceAll` (boolean) |
| **XcodeGlob** | ワイルドカードパターンでファイルを検索 | `tabIdentifier` | `pattern` (default: `**/*`), `path` |
| **XcodeGrep** | 正規表現でファイル内容を検索 | `tabIdentifier`, `pattern` | `glob`, `path`, `type`, `ignoreCase`, `multiline`, `linesContext`, `linesBefore`, `linesAfter`, `showLineNumbers`, `outputMode` (content\|filesWithMatches\|count), `headLimit` |
| **XcodeLS** | ディレクトリ内のファイル一覧を表示 | `tabIdentifier`, `path` | `recursive` (boolean, default: true), `ignore` (string[]) |
| **XcodeMakeDir** | ディレクトリ/グループを作成 | `tabIdentifier`, `directoryPath` | - |
| **XcodeRM** | ファイル/ディレクトリを削除 | `tabIdentifier`, `path` | `deleteFiles` (boolean, default: true), `recursive` |
| **XcodeMV** | ファイル/ディレクトリの移動・リネーム・コピー | `tabIdentifier`, `sourcePath`, `destinationPath` | `operation` (move\|copy), `overwriteExisting` |

### 2.2 ビルド & テスト（5 ツール）

| ツール名 | 説明 | 必須パラメータ | オプションパラメータ |
|----------|------|--------------|-------------------|
| **BuildProject** | Xcode プロジェクトをビルドし、完了まで待機 | `tabIdentifier` | - |
| **GetBuildLog** | 現在/最近のビルドログを取得（フィルタリング可能） | `tabIdentifier` | `severity` (error\|warning\|remark), `pattern` (regex), `glob` |
| **RunAllTests** | アクティブスキームのテストプランの全テストを実行 | `tabIdentifier` | - |
| **RunSomeTests** | 特定のテストを識別子で実行 | `tabIdentifier`, `tests` (array of {targetName, testIdentifier}) | - |
| **GetTestList** | テストプランで利用可能な全テストを一覧取得 | `tabIdentifier` | - |

### 2.3 診断・コード分析（2 ツール）

| ツール名 | 説明 | 必須パラメータ | オプションパラメータ |
|----------|------|--------------|-------------------|
| **XcodeListNavigatorIssues** | Issue Navigator に表示されるワークスペースの問題を一覧 | `tabIdentifier` | `severity` (error\|warning\|remark), `glob`, `pattern` |
| **XcodeRefreshCodeIssuesInFile** | 特定ファイルのコンパイラ診断情報（エラー/警告/注記）を取得 | `tabIdentifier`, `filePath` | - |

### 2.4 インテリジェンス（3 ツール）

| ツール名 | 説明 | 必須パラメータ | オプションパラメータ |
|----------|------|--------------|-------------------|
| **DocumentationSearch** | Apple Developer Documentation をセマンティック検索（Squirrel MLX使用、WWDC動画も対象） | `query` | `frameworks` (string[]) |
| **ExecuteSnippet** | ファイルコンテキスト内でSwiftコードスニペットをビルド・実行（REPL環境） | `tabIdentifier`, `codeSnippet`, `sourceFilePath` | `timeout` (seconds, default: 120) |
| **RenderPreview** | SwiftUI プレビューをビルド・レンダリングしてスナップショットを取得 | `tabIdentifier`, `sourceFilePath` | `previewDefinitionIndexInFile` (integer, default: 0), `timeout` (seconds, default: 120) |

### 2.5 ワークスペース（1 ツール）

| ツール名 | 説明 | 必須パラメータ | オプションパラメータ |
|----------|------|--------------|-------------------|
| **XcodeListWindows** | 開いている Xcode ウィンドウとワークスペース情報を一覧 | なし | - |

---

## 3. 重要パラメータ: tabIdentifier

ほぼ全てのツールで `tabIdentifier` が必須パラメータとなっている。

**取得方法**: エージェントはまず `XcodeListWindows()` を呼び出して、アクティブなプロジェクトの `tabIdentifier` を取得し、以降のツール呼び出しで使用する。

```
1. XcodeListWindows() -> tabIdentifier を取得
2. BuildProject(tabIdentifier: "xxx") -> ビルド実行
3. GetBuildLog(tabIdentifier: "xxx") -> ログ取得
```

---

## 4. Claude Code からの設定方法

### 4.1 前提条件

1. **Xcode 26.3** がインストール済みであること
2. Xcode が起動し、プロジェクトが開かれていること
3. Xcode の設定で MCP を有効化すること:
   - Xcode -> Settings (`Cmd + ,`) -> Intelligence -> "Xcode Tools" (Model Context Protocol) を ON

### 4.2 MCP サーバーの追加

```bash
claude mcp add --transport stdio xcode -- xcrun mcpbridge
```

### 4.3 設定の確認

```bash
claude mcp list
```

### 4.4 環境変数（オプション）

| 環境変数 | 説明 |
|---------|------|
| `MCP_XCODE_PID` | 接続先の Xcode プロセス ID を明示的に指定（複数インスタンス時） |
| `MCP_XCODE_SESSION_ID` | Xcode ツールセッションを識別する UUID |

通常、単一インスタンスの場合は mcpbridge が自動検出するため設定不要。

### 4.5 推奨される CLAUDE.md の追記事項

```markdown
## Xcode MCP

- ビルドスキーム名: <プロジェクトのスキーム名>
- テストターゲット: <テストターゲット名>
- ビルドの特記事項: <特殊な設定があれば>
- DocumentationSearch では frameworks パラメータで検索範囲を絞れる
```

---

## 5. 既知の問題

### 5.1 tools/list 応答の遅延

`tools/list` の応答が遅い場合がある。これは mcpbridge が Xcode の XPC 接続を確立するまでに時間がかかるためと考えられる。Xcode が完全に起動し、プロジェクトが読み込まれた状態であることを確認すること。

### 5.2 structuredContent の欠落（RC 1 の問題）

Xcode 26.3 RC 1 では、mcpbridge がツール結果を `structuredContent` ではなく `content` フィールドに JSON 文字列として返すバグがある。

- **Claude Code / Codex**: Apple との共同設計により問題なく動作
- **Cursor**: MCP 仕様を厳密に準拠するため、エラーが発生
  - エラー例: `"Tool XcodeListWindows has an output schema but did not return structured content"`
- **Gemini CLI**: v0.27 以降でワークアラウンドを含むパッチが適用済み
- **RC 2 で修正済み**

### 5.3 新規プロジェクト作成の制限

Xcode の MCP サーバーはプロジェクトの新規作成をサポートしていない。プロジェクトは手動で Xcode 内から作成する必要がある。

---

## 6. アーキテクチャ詳細

### DocumentationSearch の特徴

- **Squirrel MLX** を使用（Apple の MLX ベースのオンデバイス埋め込みモデル）
- iOS 15 から iOS 26 までのドキュメントをカバー
- WWDC 動画のトランスクリプトも検索対象

### RenderPreview の特徴

- 実際の SwiftUI プレビューのスクリーンショットを返す
- エージェントがUI変更を視覚的に確認可能

### ExecuteSnippet の特徴

- Swift REPL 環境として機能
- ロジックの迅速な検証・プロトタイピングに使用

---

## 7. 情報ソース

- [Exploring AI Driven Coding: Using Xcode 26.3 MCP Tools in Cursor, Claude Code and Codex - Rudrank Riyam](https://rudrank.com/exploring-xcode-using-mcp-tools-cursor-external-clients)
- [Xcode 26.3: Use AI Agents from Cursor, Claude Code & Beyond - DEV Community](https://dev.to/arshtechpro/xcode-263-use-ai-agents-from-cursor-claude-code-beyond-4dmi)
- [Xcode 26.3 Ships Agentic Coding - Awesome Agents](https://awesomeagents.ai/news/xcode-26-3-agentic-coding-teardown/)
- [Agentic Coding in Xcode 26.3 with Claude Code and Codex - Swiftjective-C](https://swiftjectivec.com/Agentic-Coding-Codex-Claude-Code-in-Xcode/)
- [How to Use Xcode's MCP Server - BleepingSwift](https://bleepingswift.com/blog/xcode-mcp-server-ai-workflow)
- [Agentic Coding in Xcode with Gemini CLI - Peter Friese](https://peterfriese.dev/blog/2026/agentic-coding-xcode-geminicli/)
- [Xcode 26.3.0 RC 1 MCP tools/list response (JSON) - GitHub Gist](https://gist.github.com/keith/d8aca9661002388650cf2fdc5eac9f3b)
- [Apple Newsroom: Xcode 26.3](https://www.apple.com/newsroom/2026/02/xcode-26-point-3-unlocks-the-power-of-agentic-coding/)
- [Gemini CLI mcpbridge fix PR](https://github.com/google-gemini/gemini-cli/pull/18376)
