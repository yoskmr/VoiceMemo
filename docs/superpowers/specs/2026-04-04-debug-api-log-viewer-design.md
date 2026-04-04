# デバッグ用 API リクエストログビューア設計書

**作成日**: 2026-04-04
**ステータス**: 承認済み
**対象**: Soyoka iOS アプリ

## 概要

デバッグメニューに API リクエストの内容と結果を確認できる画面を追加する。リクエストの成功/失敗が開発中に分かりづらい問題を解決する。

## スコープ

### 対象

- **InfraNetwork**: BackendProxyClient（4エンドポイント）、RemotePromptClient、ForceUpdateClient
- **InfraLLM**: HybridLLMRouter のルーティング結果 + 入出力（プロンプト/応答）

### 対象外

- リリースビルドでのログ機能（`#if DEBUG` のみ）
- ログの永続化（メモリ保持 + エクスポートで対応）

## アーキテクチャ: アプローチ2（InfraLogging モジュール新設）

今後の API エンドポイント増加（Phase 3-4）やデバッグ機能拡張を見据え、専用モジュールとして独立させる。

### 依存方向

```
FeatureSettings
    ↓
InfraNetwork  ──→  InfraLogging  ←──  InfraLLM
                        ↓
              swift-dependencies（外部）
```

InfraLogging は SharedUtil に依存せず、swift-dependencies のみに依存する軽量基盤モジュール。

## データモデル（InfraLogging）

### APIRequestLog

```swift
public struct APIRequestLog: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let source: LogSource        // .network / .llm
    public let endpoint: String          // "/api/v1/ai/process" or "CloudLLMProvider"
    public let method: String?           // "GET", "POST"（network のみ）
    public let status: LogStatus         // .success(statusCode) / .failure(error)
    public let duration: TimeInterval    // 所要時間
    public let request: RequestDetail    // リクエスト詳細
    public let response: ResponseDetail? // レスポンス詳細
}

public enum LogSource: String, Sendable {
    case network    // BackendProxyClient 系
    case llm        // LLM ルーティング結果
}

public enum LogStatus: Sendable {
    case success(statusCode: Int?)  // LLM は statusCode なし
    case failure(message: String)
}

public struct RequestDetail: Sendable {
    public let headers: [String: String]?  // network のみ
    public let body: String?               // JSON 文字列
}

public struct ResponseDetail: Sendable {
    public let headers: [String: String]?  // network のみ
    public let body: String?               // JSON 文字列 or LLM 応答テキスト
}
```

## ログストア（actor + TCA Dependency）

### APIRequestLogStore

```swift
public actor APIRequestLogStore {
    private var logs: [APIRequestLog] = []
    private var totalBytes: Int = 0

    private let maxEntries = 100
    private let maxBytesPerEntry = 16_384   // 16KB
    private let maxTotalBytes = 1_048_576   // 1MB

    public func append(_ log: APIRequestLog)   // サイズ制限適用後に追加
    public func getAll() -> [APIRequestLog]
    public func clear()
    public func export() -> String             // JSON 形式
}
```

- **件数制限**: 最大100件（古いものから削除）
- **サイズ制限**: 1エントリ最大16KB、全体最大1MB の二重制限
- **actor**: 複数クライアントからの同時 append に対するデータレース防止

### TCA Dependency

```swift
public struct APIRequestLogClient: Sendable {
    public var append: @Sendable (APIRequestLog) async -> Void
    public var getAll: @Sendable () async -> [APIRequestLog]
    public var clear: @Sendable () async -> Void
    public var export: @Sendable () async -> String
}

extension APIRequestLogClient: DependencyKey {
    public static let liveValue: Self = { ... }()   // actor 経由
    public static let testValue: Self = { ... }()   // メモリ内モック
}
```

## マスキング（LogSanitizer）

ログ保存前に必ず経由する。

```swift
enum LogSanitizer {
    /// ヘッダーマスク対象: Authorization, Cookie, Set-Cookie, X-API-Key
    static func sanitizeHeaders(_ headers: [String: String]?) -> [String: String]?

    /// ボディ: 16KB超は切り詰め + JSON フィールド "token", "password", "secret" を "***" に置換
    static func sanitizeBody(_ body: String?) -> String?
}
```

## ログ投入

### 投入パターン

```swift
@Dependency(\.apiRequestLog) var apiRequestLog

let startTime = CFAbsoluteTimeGetCurrent()
let (data, response) = try await URLSession.shared.data(for: request)
let duration = CFAbsoluteTimeGetCurrent() - startTime

#if DEBUG
await apiRequestLog.append(APIRequestLog(
    source: .network,
    endpoint: "/api/v1/ai/process",
    method: "POST",
    status: .success(statusCode: httpResponse.statusCode),
    duration: duration,
    request: RequestDetail(
        headers: LogSanitizer.sanitizeHeaders(requestHeaders),
        body: LogSanitizer.sanitizeBody(requestBodyString)
    ),
    response: ResponseDetail(
        headers: LogSanitizer.sanitizeHeaders(responseHeaders),
        body: LogSanitizer.sanitizeBody(responseBodyString)
    )
))
#endif
```

### 投入箇所（計7箇所）

| モジュール | ファイル | 箇所数 |
|:----------|:--------|:------:|
| InfraNetwork | BackendProxyClient | 4 |
| InfraNetwork | RemotePromptClient | 1 |
| InfraNetwork | ForceUpdateClient | 1 |
| InfraLLM | HybridLLMRouter | 1 |

### LLM ログの内容

- `endpoint`: プロバイダ名（"CloudLLMProvider", "OnDeviceLLMProvider", "MockLLMProvider"）
- `request.body`: 送信したプロンプト
- `response.body`: LLM の応答テキスト
- `method`: nil（HTTP ではないため）

## UI 設計（FeatureSettings）

### 画面遷移

```
DebugMenuView
  └→ NavigationLink "APIログ"
       └→ APILogListView（一覧）
            └→ NavigationLink
                 └→ APILogDetailView（詳細）
```

### APILogListView（一覧画面）

- 新しいログが上に表示（降順）
- ステータスアイコン: 緑●（成功）/ 赤✕（失敗）
- 各行: メソッド + エンドポイント、ステータスコード、所要時間、時刻
- フィルタ: セグメント Picker（ALL / Network / LLM）
- ナビバー右: クリアボタン（確認アラート付き）、共有ボタン（JSON エクスポート → ShareLink）

### APILogDetailView（詳細画面）

- **概要セクション**: ステータス、所要時間、時刻、ソース
- **リクエストヘッダー**: DisclosureGroup（初期閉じ）
- **リクエストボディ**: DisclosureGroup、JSON 整形表示
- **レスポンスヘッダー**: DisclosureGroup
- **レスポンスボディ**: DisclosureGroup、JSON 整形表示
- **コピーボタン**: 1件分の全情報を JSON でクリップボードにコピー

### Reducer

```swift
@Reducer
public struct APILogViewer {
    @ObservableState
    public struct State: Equatable {
        var logs: [APIRequestLog] = []
        var filter: LogSource? = nil         // nil = ALL
        var selectedLog: APIRequestLog?
    }

    public enum Action {
        case onAppear
        case filterChanged(LogSource?)
        case logSelected(APIRequestLog)
        case clearTapped
        case clearConfirmed
        case exportTapped
        case copyTapped(APIRequestLog)
    }

    @Dependency(\.apiRequestLog) var apiRequestLog
}
```

- `SettingsReducer` から独立した Reducer として管理
- `onAppear` でログ取得、フィルタ変更時に再フィルタリング

## モジュールファイル構成

### InfraLogging（新規）

```
Sources/InfraLogging/
├── InfraLogging.swift
├── Model/
│   ├── APIRequestLog.swift
│   └── LogSanitizer.swift
├── Store/
│   └── APIRequestLogStore.swift
└── Client/
    └── APIRequestLogClient.swift
```

### Package.swift 変更

```swift
.target(
    name: "InfraLogging",
    dependencies: [
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesMacros", package: "swift-dependencies"),
    ]
),
.testTarget(
    name: "InfraLoggingTests",
    dependencies: ["InfraLogging"]
),
```

既存モジュールへの依存追加: InfraNetwork, InfraLLM, FeatureSettings に `"InfraLogging"` を追加。

## 変更対象ファイル一覧

| 区分 | ファイル | 変更内容 |
|:----|:--------|:--------|
| **新規** | `Sources/InfraLogging/` (5ファイル) | モジュール全体 |
| **新規** | `Tests/InfraLoggingTests/` (2ファイル) | ストア + マスキングのテスト |
| **新規** | `Sources/FeatureSettings/Debug/APILogListView.swift` | 一覧画面 |
| **新規** | `Sources/FeatureSettings/Debug/APILogDetailView.swift` | 詳細画面 |
| **新規** | `Sources/FeatureSettings/Debug/APILogViewerReducer.swift` | Reducer |
| **変更** | `Package.swift` | InfraLogging ターゲット追加 + 依存追加 |
| **変更** | `Sources/FeatureSettings/Debug/DebugMenuView.swift` | NavigationLink 追加 |
| **変更** | `Sources/InfraNetwork/BackendProxyClient.swift` | ログ投入 (4箇所) |
| **変更** | `Sources/InfraNetwork/RemotePromptClient.swift` | ログ投入 (1箇所) |
| **変更** | `Sources/InfraNetwork/ForceUpdateClient.swift` | ログ投入 (1箇所) |
| **変更** | `Sources/InfraLLM/Provider/HybridLLMRouter.swift` | ログ投入 (1箇所) |

合計: **新規8ファイル、変更5ファイル**

## Codex レビュー反映事項

| 重要度 | 指摘 | 対応 |
|:---:|:-----|:-----|
| High | 認証ヘッダー漏洩リスク | LogSanitizer でマスキング |
| High | データレース | actor 化 |
| Medium | body 肥大によるメモリ圧迫 | 16KB/entry + 1MB 総量の二重制限 |
| Medium | static shared のテスト汚染 | TCA Dependency 化 |
