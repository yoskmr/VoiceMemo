# CLAUDE.md

MurMurNote（AI音声メモアプリ）の開発ガイド。

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

## コーディング規約

- TCA の Reducer は `@Reducer` マクロ + `@ObservableState` を使用
- Dependency 注入は `@Dependency(\.xxx)` + `DependencyKey` 準拠
- テストは `TestStore` を使い、exhaustivity を適切に設定
- エンティティ変更は Domain 層の `VoiceMemoEntity` で行い、SwiftData モデルは InfraStorage 層のみ
- 設計書（`docs/spec/`）に準拠して実装する。乖離を見つけたら報告すること

### TCA Reducer 規約（tca-pro スキル使用時の追加制約）

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

### テスト規約（swift-testing-pro スキル使用時の追加制約）

- テスト命名: `test_アクション名_条件_期待結果()` 日本語（例: `test_recordButtonTapped_権限許可済み_recordingに遷移する`）
- `@MainActor` 必須
- TestStore セットアップ: `withDependencies` クロージャで依存を明示スタブ
- DependencyClient の `testValue` は `unimplemented()` — テストで使う依存は全て明示的にスタブする
- `store.exhaustivity = .off` は TODO コメント付きで限定使用
- `ImmediateClock()` でクロック差し替え
- ヘルパーメソッド: `makeMemoItem(...)`, `makeEntity(...)` デフォルトパラメータ付き
- テストファイル配置: `Tests/FeatureXxxTests/` でソース構造をミラー

### SharedUI 規約（swiftui-pro スキル使用時の追加制約）

- カラートークン: `vmPrimary`, `vmSecondary`, `vmAccent`（暖色 HSB色相20-40）等を使用 — 生の `Color` 値使用禁止
- フォント: `VMFonts.swift` のトークンを使用
- スペーシング: `VMSpacing.swift` のトークンを使用
- 感情カラー: `EmotionCategoryColor.swift` を使用
- 再利用コンポーネント: `MemoCard`, `TagChip`, `WaveformView`, `EmotionBadge`, `RecordButton`
- ダーク/ライトモード: `vmAdaptive(light:dark:)` パターン
- View バインディング: `@Bindable var store: StoreOf<XxxReducer>` パターン
- NFR-012: 暖色系パレット要件に準拠

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

## チームオーケストレーションルール

### チーム組成の判断基準

関心事が複数モジュールに渡る場合、CLAUDE.md のオーケストレーター（メインエージェント）はチームを組成する:

- **単一モジュール変更**: サブエージェント1体で対応（チーム不要）
- **2-3モジュール変更**: tech-lead に委譲し、tech-lead がスキルを選択
- **4モジュール以上 or クロスレイヤー変更**: AgentTeams でチーム組成

### フェーズ別エージェント体制

| フェーズ | 主要エージェント | 補助 |
|:--------|:--------------|:-----|
| 要件定義・設計 | product-owner | tech-lead（技術的実現性確認） |
| プロトタイプ（サイドクエスト） | tech-lead | audio-ai-engineer（音声AI関連時） |
| 実装 | tech-lead → 既存スキル群 | — |
| レビュー・検証 | spec-gate（新規spawn） | code-reviewer |
| リリース準備 | product-owner（ASO/GTM） | tech-lead（ビルド） |

### コンテキストフレッシュ戦略

レビュー・評価を行うエージェントは、毎回新規 spawn する。前回のレビュー文脈を引き継がない:

- `spec-gate`: 整合チェックのたびに新規 Agent として起動
- `code-reviewer`: コードレビューのたびに新規 Agent として起動
- **理由**: 同一レビュアーの繰り返し使用はバイアス蓄積を招く（スコアが緩やかに合格ラインに到達する現象）

### ワークツリー活用ガイドライン

複数の独立した機能を並行開発する場合、git worktree を活用:

```
development
├── feature/ai-summary     ... 音声AIチーム（audio-ai-engineer + tech-lead）
├── feature/storekit       ... 課金チーム（tech-lead + 既存スキル）
└── e2e-test               ... E2Eテストチーム
```

- 各ワークツリーで独立した Claude Code セッションを起動
- ブランチごとにチーム構成を変えることが可能
- PR 作成前に spec-gate（新規spawn）でブランチ検証

## 3レイヤーシミュレーション設計

エージェント開発を「シミュレーション」として捉え、3つのレイヤーで設計する:

### レイヤー1: タスクレベル（手順型スキル）

個々の作業手順をスキルとして定義。コンテキストフォーク（新規サブエージェント生成）で実行:

| タスク | 対応スキル/手段 |
|:-------|:-------------|
| TCA Reducer 実装 | `tca-pro` スキル + CLAUDE.md の Reducer 規約 |
| SwiftUI View 実装 | `swiftui-pro` スキル + SharedUI 規約 |
| テスト生成 | `swift-testing-pro` スキル + テスト規約 |
| コードレビュー | `code-reviewer` エージェント（毎回新規spawn） |
| 設計書整合チェック | `spec-gate` エージェント（毎回新規spawn） |
| ASO最適化 | `app-store-aso` スキル |
| ビルド・テスト実行 | `xcode-mcp-workflow` スキル |

### レイヤー2: サブエージェントレベル（辞書型スキル + メモリー）

各エージェントの「人格」として機能する専門知識と判断基準:

| エージェント | 辞書型知識 | アイデンティティ（判断基準） |
|:-----------|:---------|:------------------------|
| product-owner | ビジネスモデル、ペルソナ、競合、フェーズ構成 | 非交渉的要件3つ、MoSCoW判定基準 |
| tech-lead | モジュール境界、Reducer/テスト/UI規約 | 複雑性予算、ワークアラウンド隔離原則 |
| audio-ai-engineer | パイプライン構成、メモリ制約、PromptTemplate | プロンプト簡素化原則、精度優先方針 |
| spec-gate | 設計書体系、REQ/TASK体系、トレーサビリティ規約 | Severity判定基準、コンテキストフレッシュ |

### レイヤー3: チームレベル（CLAUDE.md）

本ファイル（CLAUDE.md）でチームの組成ルール・運用方針を定義:
- チーム組成の判断基準（上記「チームオーケストレーションルール」）
- フェーズ別体制変更
- コンテキストフレッシュ戦略
- ワークツリー活用ガイドライン
