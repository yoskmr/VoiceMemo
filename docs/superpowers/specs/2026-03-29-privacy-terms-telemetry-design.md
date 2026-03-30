# プライバシーポリシー・利用規約・TelemetryDeck 実装設計書

## 概要

Soyoka（AI音声メモアプリ）にプライバシーポリシー・利用規約のWebページ公開、TelemetryDeck分析SDK導入、およびApp Store要件対応を行う。

## 背景・動機

- App Store審査にはプライバシーポリシーURLが必須
- サブスクリプション課金画面にはプライバシーポリシー・利用規約リンクが必要（App Store Guidelines）
- ユーザー行動分析のためにプライバシー重視のTelemetryDeckを導入
- 作成済みドキュメント:
  - `works/20260329_05_プライバシーポリシー利用規約作成/result/privacy-policy.md`
  - `works/20260329_05_プライバシーポリシー利用規約作成/result/terms-of-service.md`

## 参考にした競合

| アプリ                | 参考点                                                        |
| :-------------------- | :------------------------------------------------------------ |
| Spokenly              | オンデバイス/クラウド処理の分離記載、サードパーティ名指し列挙 |
| Otter.ai              | 体系的セクション構成、AI学習開示、GDPR/CCPA対応               |
| Aiko                  | 「データがデバイスを離れない」技術的保証の表現                |
| Whisper Transcription | 精度免責の記載方法                                            |
| VOMO AI               | 反面教師（音声データ未記載・規約リンク切れを避ける）          |

## 設計決定事項

| 項目            | 決定                                                     | 理由                                           |
| :-------------- | :------------------------------------------------------- | :--------------------------------------------- |
| Webホスティング | Cloudflare Pages                                         | ドメイン（soyoka.app）が既にCloudflare管理下   |
| URL             | `https://soyoka.app/privacy`, `https://soyoka.app/terms` | 既存コードのリンク先と一致                     |
| 表示方法        | 外部ブラウザ（SwiftUI `Link`）                           | 現状維持、追加実装不要                         |
| 初回同意フロー  | なし                                                     | App Store DL時にApple標準EULAに同意済み        |
| 分析SDK         | TelemetryDeck                                            | プライバシー重視、GDPR同意不要、Swift製SPM対応 |

## スコープ

### 1. Webサイト（Cloudflare Pages）

**目的:** プライバシーポリシーと利用規約をWebページとして公開する

**構成:**

```text
repository/soyoka_website/
├── index.html          # トップページ（最小限、各ページへのリンク）
├── privacy/
│   └── index.html      # プライバシーポリシー
├── terms/
│   └── index.html      # 利用規約
└── style.css           # 共通スタイル（シンプル、レスポンシブ）

repository/terms_privacy/
├── privacy.md          # この内容を soyoka_website/privacy/index.html に変換する
└── terms.md            # この内容を soyoka_website/terms/index.html に変換する
```

**要件:**

- 作成済みMarkdownをHTMLに変換して公開
- モバイルファーストのレスポンシブデザイン（iOSから開くため）
- シンプルで読みやすいデザイン（余計な装飾不要）
- Cloudflare Pagesにデプロイ（GitHubリポジトリ連携 or Direct Upload）
- `soyoka.app` カスタムドメイン設定

**現状との整合:**

- SettingsView の `Link(destination: URL(string: "https://soyoka.app/privacy")!)` がそのまま動作する
- SettingsView の `Link(destination: URL(string: "https://soyoka.app/terms")!)` がそのまま動作する

### 2. TelemetryDeck SDK導入

**目的:** ユーザーの利用パターン（機能利用率、利用時間帯、セッション情報）を匿名で分析する

#### 2.1 Package.swift 変更

```swift
// 追加する依存
.package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.0.0")
```

対象モジュール: `SoyokaApp`（アプリターゲット）で初期化するため、Featureモジュールには直接依存させない。

#### 2.2 初期化（SoyokaApp.swift）

アプリ起動時に `TelemetryDeck.initialize(config:)` を呼び出す。

```swift
import TelemetryDeck

// AppView の init() または SoyokaApp の init() で:
let config = TelemetryDeck.Config(appID: "YOUR-APP-ID")
TelemetryDeck.initialize(config: config)
```

**注意:** APP IDは TelemetryDeck ダッシュボード（https://dashboard.telemetrydeck.com）でアプリ登録後に取得する。ハードコードして問題ない（APIキーではなく、公開IDのため）。

#### 2.3 トラッキングイベント設計

| イベント名                 | 送信タイミング                                          | 目的                |
| :------------------------- | :------------------------------------------------------ | :------------------ |
| `recording.started`        | 録音開始時                                              | コア機能の利用率    |
| `recording.completed`      | 録音完了時                                              | 録音完了率          |
| `transcription.completed`  | 文字起こし完了時                                        | STT利用状況         |
| `transcription.engineUsed` | 文字起こし完了時（パラメータ: engine=whisperkit/apple） | エンジン選択傾向    |
| `memo.viewed`              | メモ詳細表示時                                          | 振り返り頻度        |
| `memo.edited`              | メモ編集時                                              | 編集機能利用率      |
| `memo.deleted`             | メモ削除時                                              | 削除頻度            |
| `search.performed`         | 検索実行時                                              | 検索機能利用率      |
| `ai.summaryRequested`      | AI要約リクエスト時                                      | AI機能利用率（Pro） |
| `ai.tagRequested`          | AIタグ付けリクエスト時                                  | AI機能利用率（Pro） |
| `ai.emotionRequested`      | AI感情分析リクエスト時                                  | AI機能利用率（Pro） |
| `subscription.viewOpened`  | 課金画面表示時                                          | 課金ファネル        |
| `subscription.purchased`   | 購入完了時（パラメータ: plan=monthly/yearly）           | 購入コンバージョン  |
| `settings.opened`          | 設定画面表示時                                          | 設定利用率          |

**実装方針:**

- 各FeatureモジュールのReducer内で `TelemetryDeck.signal()` を直接呼ぶのではなく、`SharedUtil` に薄いラッパー（`AnalyticsClient`）を定義し、TCA の `@Dependency` として注入する
- これにより、テスト時にモック差し替えが可能
- AnalyticsClient のプロトコルは SharedUtil に、LiveValue は SoyokaApp ターゲットに配置

```text
SharedUtil/
  AnalyticsClient.swift    # protocol + DependencyKey
SoyokaApp/
  LiveAnalyticsClient.swift # TelemetryDeck を使った live 実装
```

### 3. SubscriptionView 修正

**目的:** App Store審査要件を満たすため、課金画面にプライバシーポリシー・利用規約リンクを追加する

**変更箇所:** `FeatureSubscription/SubscriptionView.swift`

**追加位置:** 購入ボタンの下（購入前に確認できる位置）

**UI:** 小さなテキストリンク2つ（Spokenly参考）

```text
プライバシーポリシー | 利用規約
```

SwiftUI `Link` で `https://soyoka.app/privacy` と `https://soyoka.app/terms` にリンク。

### 4. App Store Connect プライバシーラベル更新

**目的:** TelemetryDeck導入に伴い、プライバシーラベルを正確に更新する

**追加申告項目:**

| カテゴリ       | データタイプ        | ユーザーに紐付け | トラッキングに使用 |
| :------------- | :------------------ | :--------------- | :----------------- |
| 識別子         | Device ID           | いいえ           | いいえ             |
| 使用状況データ | Product Interaction | いいえ           | いいえ             |

**既存の申告（変更なし）:**

- 音声データ（デバイスローカル、収集なし）
- クラッシュログ（Apple提供）

## 対象外（スコープ外）

- アプリ内WebView / SFSafariViewController の実装（現状の外部ブラウザ遷移で十分）
- 初回起動時の同意フロー（不要と決定）
- 多言語対応（まず日本語のみ）
- App Store Connect へのカスタムEULA登録（Webサイト公開後に別途対応）

## 依存関係

```text
1. Webサイト公開（Cloudflare Pages）
   └─ 前提: なし（独立して作業可能）

2. TelemetryDeck SDK導入
   ├─ 2.1 Package.swift に依存追加
   ├─ 2.2 AnalyticsClient 定義（SharedUtil）
   ├─ 2.3 LiveAnalyticsClient 実装（SoyokaApp）
   ├─ 2.4 SoyokaApp.swift で初期化
   └─ 2.5 各 Reducer にイベント送信追加
       └─ 前提: 2.1〜2.4 完了

3. SubscriptionView 修正
   └─ 前提: なし（独立して作業可能）

4. App Store Connect 更新
   └─ 前提: 1〜3 すべて完了後
```

## テスト方針

- **TelemetryDeck:** AnalyticsClient をモック化してReducerテストでイベント送信を検証
- **SubscriptionView:** リンクの存在確認（UIテスト or スナップショット）
- **Webサイト:** ブラウザで表示確認、モバイル表示確認
- **E2E:** 設定画面・課金画面からリンクタップ → 外部ブラウザで正しいページが開くことを確認

## リスク・注意事項

| リスク                              | 対策                                                          |
| :---------------------------------- | :------------------------------------------------------------ |
| TelemetryDeck APP ID のハードコード | 公開IDのため問題なし。ただし DEBUG/RELEASE で分けることを検討 |
| Cloudflare Pages のビルド失敗       | 静的HTMLのため失敗リスクは極めて低い                          |
| プライバシーポリシーの法的正確性    | 弁護士確認を推奨（ドキュメントに注記済み）                    |
| OpenAI API利用の記載                | 「提供開始予定」と明記済み。実装時にポリシー更新が必要        |
