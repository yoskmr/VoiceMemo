# CLAUDE.md

MurMurNote（AI音声メモアプリ）の開発ガイド。

## 重要

- あなたはマネージャーで agent オーケストレーターです
- あなたは絶対に実装せず、全て subagent や task agent に委託すること
- タスクは超細分化し、PDCA サイクルを構築すること。
- 適当なスキルを利用すること

## 開発について

- TDD 及びテスト駆動開発で実践する際は、全て t-wada の推奨する進め方に従ってください
- リファクタリングは Martin Fowler が推奨する進め方に従ってください

## エージェント起動ルール

- 大きなコード変更（3 ファイル以上、または 100 行以上）を完了した後は、
  必ず code-reviewer エージェントを起動すること。
- 複数ファイルに変更がある場合は、並列で code-reviewer を起動すること。
- セキュリティ関連のファイル（auth*, security*, credential\*）を変更した場合は、
  必ず security-auditor エージェントを起動すること。
- コードを書いた後（Edit/Write でコード変更を行った後）は、
  必ず `/simplify` を実行してコードの簡潔化・リファクタリングを行うこと。
- コードの実装が完了した後は、`codex-code-reviewer` スキルを実行して
  OpenAI Codex CLI によるコードレビューを行うこと。

## コミットメッセージルール（全エージェント共通）

サブエージェント含む全てのエージェントが `git commit` を行う際は、以下のフォーマットに従うこと：

```
<type>(<scope>): <日本語で変更の目的を簡潔に>（50文字以内）

<なぜこの変更をしたのかを日本語で説明（2〜4行）>
- 変更の動機・背景
- どのような問題を解決するか、またはどのような価値を追加するか
```

## プロジェクト概要

- **アプリ名**: MurMurNote
- **プラットフォーム**: iOS 17+
- **言語**: Swift 6.2 / SwiftUI
- **アーキテクチャ**: TCA (The Composable Architecture) + Clean Architecture
- **Xcodeプロジェクト**: `repository/ios/MurMurNote.xcodeproj`
- **SPMパッケージ**: `repository/ios/MurMurNoteModules/`（マルチモジュール構成）

## 開発環境

- Xcode 26.3 / macOS 26.3.1 / Swift 6.2.4
- Xcode MCP ブリッジ対応（`xcrun mcpbridge`）

## ディレクトリ構成

```
VoiceMemo/
├── CLAUDE.md                    # ← このファイル
├── repository/                  # ソースコード（git管理）
│   ├── ios/                     # iOSアプリ
│   │   ├── MurMurNote.xcodeproj # Xcode プロジェクト
│   │   ├── MurMurNoteApp/       # アプリターゲット（エントリポイント + DI）
│   │   │   ├── MurMurNoteApp.swift  # @main, AppReducer, AppView
│   │   │   └── LiveDependencies.swift  # 本番 Dependency 接続
│   │   └── MurMurNoteModules/   # Swift Package（全モジュール）
│   │       ├── Package.swift
│   │       ├── Sources/         # 99ファイル / 8,400行
│   │       └── Tests/           # 44ファイル / 369テスト全パス
│   ├── backend/                 # バックエンドAPI（Phase 3で作成予定）
│   └── .gitignore
├── docs/
│   ├── spec/ai-voice-memo/      # 要件定義・設計書
│   │   ├── requirements.md      # 要件定義
│   │   ├── user-stories.md      # ユーザーストーリー
│   │   ├── acceptance-criteria.md
│   │   └── design/              # 設計書（6ファイル）
│   │       ├── 00-integration-spec.md  # 統合仕様書
│   │       ├── 01-system-architecture.md
│   │       ├── 02-ai-pipeline.md
│   │       ├── 03-backend-proxy.md
│   │       ├── 04-ui-design-system.md
│   │       └── 05-security.md
│   └── tasks/ai-voice-memo/     # タスク定義
├── works/                       # 作業ディレクトリ（調査・分析）
└── reports/                     # 最終レポート
```

## モジュール構成（依存方向: 上→下）

```
Feature層      FeatureRecording / FeatureMemo / FeatureSearch / FeatureSettings / FeatureAI / FeatureSubscription
                    ↓
Domain層       Domain（エンティティ、プロトコル、ValueObject、UseCases）
                    ↓
Infra層        InfraSTT / InfraStorage / InfraLLM / InfraNetwork
                    ↓
共通層         SharedUI / SharedUtil
```

### 主要な依存ライブラリ

- **TCA** (swift-composable-architecture 1.17+): 状態管理
- **swift-dependencies**: DI コンテナ
- **WhisperKit** (0.9+): オンデバイス STT エンジン（Apple Speech と切替可能）

## ビルド・テスト

### Xcode MCP 経由（推奨）

Xcode が起動している場合、MCP ツール経由で操作する。

```
XcodeListWindows → tabIdentifier を取得（全ツールの前提）
BuildProject     → ビルド実行
GetBuildLog      → ビルドログ・エラー取得
RunSomeTests     → 指定テスト実行
RunAllTests      → 全テスト実行
GetTestList      → テスト一覧
XcodeListNavigatorIssues → Issue Navigator のエラー・警告
RenderPreview    → SwiftUI Preview のスクリーンショット取得
DocumentationSearch → Apple ドキュメント・WWDC 検索（tabIdentifier 不要）
ExecuteSnippet   → Swift REPL でコード検証
```

### CLI フォールバック（Xcode MCP 未接続時）

```bash
# ビルド
cd repository/ios && xcodebuild -project MurMurNote.xcodeproj -scheme MurMurNote -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build -skipMacroValidation

# テスト（SPM）
cd repository/ios/MurMurNoteModules && swift test
```

## Xcode MCP 連携ルール

本プロジェクトでは Xcode 26.3 の MCP（Model Context Protocol）ブリッジを使用し、Claude Code から Xcode を直接操作する。
`xcodebuild` CLI よりも Xcode MCP ツールを優先して使うこと。

**前提条件**: Xcode が起動し、プロジェクトが開かれている状態であること。

### 利用可能なツール一覧（全20ツール）

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

### 開発ワークフローでの活用ルール

1. **ビルド確認**: コード変更後は `BuildProject` → `GetBuildLog` で確認する。`xcodebuild` CLI は使わない
2. **エラー確認**: `XcodeListNavigatorIssues` で Issue Navigator のエラーを取得する
3. **テスト実行**: `RunSomeTests` で変更に関連するテストを実行する。全テストは `RunAllTests`
4. **UI確認**: SwiftUI のレイアウト確認には `RenderPreview` でスクリーンショットを取得する
5. **API調査**: Apple フレームワークの使い方は `DocumentationSearch` で検索する
6. **tabIdentifier の取得**: ファイル操作・ビルド・テスト・診断系ツールは `tabIdentifier` が必須。操作前に `XcodeListWindows` で取得すること
7. **コードスニペットの検証**: `ExecuteSnippet` で Swift コードの動作を即座に検証できる

## コーディング規約

- TCA の Reducer は `@Reducer` マクロ + `@ObservableState` を使用
- Dependency 注入は `@Dependency(\.xxx)` + `DependencyKey` 準拠
- テストは `TestStore` を使い、exhaustivity を適切に設定
- エンティティ変更は Domain 層の `VoiceMemoEntity` で行い、SwiftData モデルは InfraStorage 層のみ
- 設計書（`docs/spec/`）に準拠して実装する。乖離を見つけたら報告すること

## 現在の実装状況

### 動作確認済み
- 録音（開始/停止/一時停止）
- リアルタイム文字起こし（Apple Speech + テキスト蓄積）
- メモ保存（SwiftData 永続化）

### コード接続済み・実機未確認
- メモ一覧 / 詳細表示 / テキスト編集 / 削除
- FTS5 全文検索

### 未実装（stub / Phase 3-4）
- 音声再生エンジン（UI のみ）
- AI 要約・タグ付け・感情分析
- Backend Proxy / StoreKit 課金
- 設定画面の実体

## プロジェクト配置ルール

- ソースコードは `repository/` 配下にアプリ種別ごとのディレクトリで管理する
  - `repository/ios/` — iOSアプリ（Swift/SwiftUI）
  - `repository/backend/` — バックエンドAPI（Phase 3で作成予定）
- `works/`、`reports/` は調査・分析用であり、ソースコードとは分離する

## 作業ディレクトリ運用ルール

作業依頼を受けた際は `works/` 配下で作業する：

1. **命名規則**: `YYYYMMDD_{作業No.}_{作業内容}`
   - 同じ日付が既存の場合は No. をインクリメント
   - 作業開始前に `ls works/ | grep YYYYMMDD` で確認

2. **標準フォルダ構成**:
   ```
   works/YYYYMMDD_XX_作業名/
   ├── README.md
   ├── scripts/     # SQL, Python, Ruby 等
   ├── data/        # CSV, JSON 等
   └── result/      # 成果物（YYYYMMDDHHMM サブディレクトリ）
   ```

3. **作業完了時**: README.md に依頼内容・実施内容・知見・TODO を記載

4. **最終レポート**: `reports/YYYYMMDD_{No.}_{タイトル}.md` に配置

## データの可視化

- 図は `mermaid` 記法を使用
- Python 画像生成時は `Hiragino Sans` フォントを指定
- 円グラフ禁止、棒グラフを使用
