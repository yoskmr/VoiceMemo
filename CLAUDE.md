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
