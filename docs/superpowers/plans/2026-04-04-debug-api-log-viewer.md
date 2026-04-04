# デバッグ用 API リクエストログビューア 実装プラン

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** デバッグメニューに API リクエスト/レスポンスを確認できるログビューア画面を追加する

**Architecture:** 新規 `InfraLogging` モジュール（actor ログストア + TCA Dependency）を基盤として、InfraNetwork/InfraLLM からログを投入し、FeatureSettings のデバッグメニューに一覧/詳細画面を提供する

**Tech Stack:** Swift 6.2 / TCA (ComposableArchitecture) / swift-dependencies / SwiftUI

**Design Spec:** `docs/superpowers/specs/2026-04-04-debug-api-log-viewer-design.md`

---

## Task 1: InfraLogging モジュールスキャフォールディング

**Files:**
- Modify: `repository/ios/SoyokaModules/Package.swift`
- Create: `repository/ios/SoyokaModules/Sources/InfraLogging/InfraLogging.swift`

- [ ] **Step 1: Package.swift に InfraLogging ターゲットを追加**

`Package.swift` の `// MARK: - Shared Modules` セクション末尾（`SharedUI` ターゲットの後）に追加:

```swift
        .target(
            name: "InfraLogging",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ],
            plugins: []
        ),
```

`// MARK: - Test Targets` セクションに追加:

```swift
        .testTarget(name: "InfraLoggingTests", dependencies: ["InfraLogging"]),
```

products に追加:

```swift
        .library(name: "InfraLogging", targets: ["InfraLogging"]),
```

InfraNetwork の dependencies に `"InfraLogging"` を追加:

```swift
        .target(
            name: "InfraNetwork",
            dependencies: [
                "Domain",
                "SharedUtil",
                "InfraLogging",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            plugins: []
        ),
```

InfraLLM の dependencies に `"InfraLogging"` を追加:

```swift
        .target(
            name: "InfraLLM",
            dependencies: [
                "Domain",
                "InfraNetwork",
                "InfraLogging",
            ],
            plugins: []
        ),
```

FeatureSettings の dependencies に `"InfraLogging"` を追加:

```swift
        .target(
            name: "FeatureSettings",
            dependencies: [
                "Domain",
                "SharedUI",
                "SharedUtil",
                "InfraLogging",
                "FeatureSubscription",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            plugins: []
        ),
```

FeatureSettingsTests にも `"InfraLogging"` を追加:

```swift
        .testTarget(name: "FeatureSettingsTests", dependencies: ["FeatureSettings", "FeatureSubscription", "InfraLogging", "Domain"]),
```

- [ ] **Step 2: モジュールエントリポイントを作成**

`Sources/InfraLogging/InfraLogging.swift`:

```swift
/// InfraLogging モジュール
/// デバッグ用 API リクエスト/レスポンスのログ記録・表示基盤
public enum InfraLoggingModule {
    public static let version = "0.1.0"
}
```

- [ ] **Step 3: SPM 依存解決を確認**

Run:
```bash
xcodebuild -resolvePackageDependencies \
  -project repository/ios/Soyoka.xcodeproj -scheme Soyoka
```

Expected: `Resolve Package Graph` が成功する

- [ ] **Step 4: コミット**

```bash
git add repository/ios/SoyokaModules/Package.swift \
        repository/ios/SoyokaModules/Sources/InfraLogging/InfraLogging.swift
git commit -m "feat(infra): InfraLogging モジュールのスキャフォールディング

デバッグ用APIログビューア機能の基盤モジュールを新設。
- Package.swift にターゲット追加
- InfraNetwork, InfraLLM, FeatureSettings から依存可能に"
```

---

## Task 2: データモデル + LogSanitizer（TDD）

**Files:**
- Create: `repository/ios/SoyokaModules/Sources/InfraLogging/Model/APIRequestLog.swift`
- Create: `repository/ios/SoyokaModules/Sources/InfraLogging/Model/LogSanitizer.swift`
- Create: `repository/ios/SoyokaModules/Tests/InfraLoggingTests/LogSanitizerTests.swift`

- [ ] **Step 1: LogSanitizer のテストを書く**

`Tests/InfraLoggingTests/LogSanitizerTests.swift`:

```swift
@testable import InfraLogging
import XCTest

final class LogSanitizerTests: XCTestCase {

    // MARK: - ヘッダーマスキング

    func test_sanitizeHeaders_Authorizationヘッダーがマスクされる() {
        let headers = [
            "Content-Type": "application/json",
            "Authorization": "Bearer eyJhbGci...",
        ]
        let result = LogSanitizer.sanitizeHeaders(headers)
        XCTAssertEqual(result?["Authorization"], "***")
        XCTAssertEqual(result?["Content-Type"], "application/json")
    }

    func test_sanitizeHeaders_複数の機密ヘッダーがマスクされる() {
        let headers = [
            "Cookie": "session=abc123",
            "Set-Cookie": "token=xyz",
            "X-API-Key": "sk-12345",
            "Accept": "application/json",
        ]
        let result = LogSanitizer.sanitizeHeaders(headers)
        XCTAssertEqual(result?["Cookie"], "***")
        XCTAssertEqual(result?["Set-Cookie"], "***")
        XCTAssertEqual(result?["X-API-Key"], "***")
        XCTAssertEqual(result?["Accept"], "application/json")
    }

    func test_sanitizeHeaders_nilの場合nilを返す() {
        XCTAssertNil(LogSanitizer.sanitizeHeaders(nil))
    }

    func test_sanitizeHeaders_大文字小文字を区別せずマスクする() {
        let headers = ["authorization": "Bearer token"]
        let result = LogSanitizer.sanitizeHeaders(headers)
        XCTAssertEqual(result?["authorization"], "***")
    }

    // MARK: - ボディマスキング

    func test_sanitizeBody_JSONのtokenフィールドがマスクされる() {
        let body = """
        {"access_token":"eyJhbG...","user":"test"}
        """
        let result = LogSanitizer.sanitizeBody(body)!
        XCTAssertFalse(result.contains("eyJhbG"))
        XCTAssertTrue(result.contains("test"))
    }

    func test_sanitizeBody_passwordフィールドがマスクされる() {
        let body = """
        {"password":"secret123","name":"test"}
        """
        let result = LogSanitizer.sanitizeBody(body)!
        XCTAssertFalse(result.contains("secret123"))
        XCTAssertTrue(result.contains("test"))
    }

    func test_sanitizeBody_16KB超はトリミングされる() {
        let largeBody = String(repeating: "a", count: 20_000)
        let result = LogSanitizer.sanitizeBody(largeBody)!
        XCTAssertLessThanOrEqual(result.utf8.count, 16_384 + 100) // マージン
        XCTAssertTrue(result.hasSuffix("...(truncated)"))
    }

    func test_sanitizeBody_nilの場合nilを返す() {
        XCTAssertNil(LogSanitizer.sanitizeBody(nil))
    }

    func test_sanitizeBody_JSON以外のテキストはそのまま返す() {
        let body = "plain text body"
        XCTAssertEqual(LogSanitizer.sanitizeBody(body), "plain text body")
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run:
```bash
xcodebuild test \
  -project repository/ios/Soyoka.xcodeproj -scheme InfraLogging \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:'InfraLoggingTests/LogSanitizerTests' 2>&1 | tail -20
```

Expected: コンパイルエラー（`LogSanitizer` が存在しない）

- [ ] **Step 3: APIRequestLog データモデルを作成**

`Sources/InfraLogging/Model/APIRequestLog.swift`:

```swift
import Foundation

/// API リクエストログのソース種別
public enum LogSource: String, Sendable, Equatable, Codable {
    /// InfraNetwork（BackendProxyClient 等）
    case network
    /// InfraLLM（HybridLLMRouter 等）
    case llm
}

/// API リクエストのステータス
public enum LogStatus: Sendable, Equatable, Codable {
    /// 成功（HTTP ステータスコード。LLM の場合は nil）
    case success(statusCode: Int?)
    /// 失敗（エラーメッセージ）
    case failure(message: String)

    /// 成功かどうか
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    /// 表示用テキスト
    public var displayText: String {
        switch self {
        case .success(let code):
            if let code { return "\(code) OK" }
            return "成功"
        case .failure(let message):
            return message
        }
    }
}

/// リクエスト詳細
public struct RequestDetail: Sendable, Equatable, Codable {
    /// HTTP ヘッダー（network のみ）
    public let headers: [String: String]?
    /// リクエストボディ（JSON 文字列）
    public let body: String?

    public init(headers: [String: String]? = nil, body: String? = nil) {
        self.headers = headers
        self.body = body
    }
}

/// レスポンス詳細
public struct ResponseDetail: Sendable, Equatable, Codable {
    /// HTTP ヘッダー（network のみ）
    public let headers: [String: String]?
    /// レスポンスボディ（JSON 文字列 or LLM 応答テキスト）
    public let body: String?

    public init(headers: [String: String]? = nil, body: String? = nil) {
        self.headers = headers
        self.body = body
    }
}

/// API リクエストログエントリ
public struct APIRequestLog: Identifiable, Sendable, Equatable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let source: LogSource
    public let endpoint: String
    public let method: String?
    public let status: LogStatus
    public let duration: TimeInterval
    public let request: RequestDetail
    public let response: ResponseDetail?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: LogSource,
        endpoint: String,
        method: String? = nil,
        status: LogStatus,
        duration: TimeInterval,
        request: RequestDetail,
        response: ResponseDetail? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.endpoint = endpoint
        self.method = method
        self.status = status
        self.duration = duration
        self.request = request
        self.response = response
    }

    /// ボディの推定バイトサイズ
    var estimatedBytes: Int {
        var total = 0
        total += request.body?.utf8.count ?? 0
        total += request.headers?.description.utf8.count ?? 0
        total += response?.body?.utf8.count ?? 0
        total += response?.headers?.description.utf8.count ?? 0
        total += endpoint.utf8.count + 100 // メタデータ概算
        return total
    }
}
```

- [ ] **Step 4: LogSanitizer を実装**

`Sources/InfraLogging/Model/LogSanitizer.swift`:

```swift
import Foundation

/// ログ保存前のマスキング処理
/// 機密情報（認証トークン、パスワード等）をマスクし、サイズを制限する
public enum LogSanitizer {

    /// マスク対象のヘッダー名（小文字で比較）
    private static let sensitiveHeaders: Set<String> = [
        "authorization",
        "cookie",
        "set-cookie",
        "x-api-key",
        "x-app-attest-assertion",
    ]

    /// マスク対象の JSON フィールド名
    private static let sensitiveFields: Set<String> = [
        "token",
        "access_token",
        "refresh_token",
        "password",
        "secret",
        "api_key",
    ]

    /// ボディの最大バイト数（16KB）
    private static let maxBodyBytes = 16_384

    /// ヘッダーの機密情報をマスクする
    public static func sanitizeHeaders(_ headers: [String: String]?) -> [String: String]? {
        guard let headers else { return nil }
        var result = headers
        for (key, _) in result {
            if sensitiveHeaders.contains(key.lowercased()) {
                result[key] = "***"
            }
        }
        return result
    }

    /// ボディの機密フィールドをマスクし、サイズを制限する
    public static func sanitizeBody(_ body: String?) -> String? {
        guard var body else { return nil }

        // JSON フィールドのマスキング
        if body.trimmingCharacters(in: .whitespaces).hasPrefix("{") ||
           body.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
            body = maskSensitiveJSONFields(body)
        }

        // サイズ制限
        if body.utf8.count > maxBodyBytes {
            let index = body.utf8.index(body.utf8.startIndex, offsetBy: maxBodyBytes)
            body = String(body[..<index]) + "...(truncated)"
        }

        return body
    }

    /// JSON 文字列内の機密フィールドの値をマスクする
    private static func maskSensitiveJSONFields(_ json: String) -> String {
        var result = json
        for field in sensitiveFields {
            // "field":"value" or "field": "value" パターンにマッチ
            let pattern = "(\"\(field)\"\\s*:\\s*)\"[^\"]*\""
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: "$1\"***\""
                )
            }
        }
        return result
    }
}
```

- [ ] **Step 5: テストが全て通ることを確認**

Run:
```bash
xcodebuild test \
  -project repository/ios/Soyoka.xcodeproj -scheme InfraLogging \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:'InfraLoggingTests/LogSanitizerTests' 2>&1 | tail -20
```

Expected: 全テスト PASS

- [ ] **Step 6: コミット**

```bash
git add repository/ios/SoyokaModules/Sources/InfraLogging/Model/ \
        repository/ios/SoyokaModules/Tests/InfraLoggingTests/
git commit -m "feat(infra): APIRequestLog データモデルと LogSanitizer を追加

認証情報漏洩防止のためのマスキング層を実装。
- ヘッダー: Authorization, Cookie, X-API-Key 等を自動マスク
- ボディ: token, password 等の JSON フィールドをマスク + 16KB サイズ制限"
```

---

## Task 3: APIRequestLogStore + APIRequestLogClient（TDD）

**Files:**
- Create: `repository/ios/SoyokaModules/Sources/InfraLogging/Store/APIRequestLogStore.swift`
- Create: `repository/ios/SoyokaModules/Sources/InfraLogging/Client/APIRequestLogClient.swift`
- Create: `repository/ios/SoyokaModules/Tests/InfraLoggingTests/APIRequestLogStoreTests.swift`

- [ ] **Step 1: APIRequestLogStore のテストを書く**

`Tests/InfraLoggingTests/APIRequestLogStoreTests.swift`:

```swift
@testable import InfraLogging
import XCTest

final class APIRequestLogStoreTests: XCTestCase {

    // MARK: - テストヘルパー

    private func makeLog(
        source: LogSource = .network,
        endpoint: String = "/api/v1/test",
        method: String? = "GET",
        status: LogStatus = .success(statusCode: 200),
        duration: TimeInterval = 0.5,
        bodySize: Int = 100
    ) -> APIRequestLog {
        APIRequestLog(
            source: source,
            endpoint: endpoint,
            method: method,
            status: status,
            duration: duration,
            request: RequestDetail(body: String(repeating: "x", count: bodySize)),
            response: ResponseDetail(body: String(repeating: "y", count: bodySize))
        )
    }

    // MARK: - append / getAll

    func test_append_ログが追加される() async {
        let store = APIRequestLogStore()
        let log = makeLog()

        await store.append(log)
        let logs = await store.getAll()

        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.endpoint, "/api/v1/test")
    }

    func test_append_複数ログが新しい順に返される() async {
        let store = APIRequestLogStore()
        let log1 = makeLog(endpoint: "/first")
        let log2 = makeLog(endpoint: "/second")

        await store.append(log1)
        await store.append(log2)
        let logs = await store.getAll()

        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(logs.first?.endpoint, "/second")
    }

    // MARK: - 件数制限

    func test_append_100件を超えると古いログが削除される() async {
        let store = APIRequestLogStore()

        for i in 0..<110 {
            await store.append(makeLog(endpoint: "/api/\(i)", bodySize: 10))
        }
        let logs = await store.getAll()

        XCTAssertEqual(logs.count, 100)
        // 最新（109）が先頭、最古（10）が末尾
        XCTAssertEqual(logs.first?.endpoint, "/api/109")
        XCTAssertEqual(logs.last?.endpoint, "/api/10")
    }

    // MARK: - サイズ制限

    func test_append_総容量1MBを超えると古いログが削除される() async {
        let store = APIRequestLogStore()
        // 1エントリ約 100KB → 11件で 1MB 超
        for i in 0..<15 {
            await store.append(makeLog(endpoint: "/api/\(i)", bodySize: 50_000))
        }
        let logs = await store.getAll()

        // 総容量 1MB 以内に収まるまで古いログが削除される
        let totalBytes = logs.reduce(0) { $0 + $1.estimatedBytes }
        XCTAssertLessThanOrEqual(totalBytes, 1_048_576)
    }

    // MARK: - clear

    func test_clear_全ログが削除される() async {
        let store = APIRequestLogStore()
        await store.append(makeLog())
        await store.append(makeLog())

        await store.clear()
        let logs = await store.getAll()

        XCTAssertTrue(logs.isEmpty)
    }

    // MARK: - export

    func test_export_JSON形式で出力される() async {
        let store = APIRequestLogStore()
        await store.append(makeLog(endpoint: "/api/v1/test"))

        let json = await store.export()

        XCTAssertTrue(json.contains("/api/v1/test"))
        XCTAssertTrue(json.contains("exportedAt"))
        // 有効な JSON であることを確認
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(json.utf8)))
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run:
```bash
xcodebuild test \
  -project repository/ios/Soyoka.xcodeproj -scheme InfraLogging \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:'InfraLoggingTests/APIRequestLogStoreTests' 2>&1 | tail -20
```

Expected: コンパイルエラー（`APIRequestLogStore` が存在しない）

- [ ] **Step 3: APIRequestLogStore を実装**

`Sources/InfraLogging/Store/APIRequestLogStore.swift`:

```swift
import Foundation

/// API リクエストログのインメモリストア（actor で排他制御）
///
/// - 最大 100 件のログを保持（リングバッファ方式）
/// - 1 エントリ最大 16KB、全体最大 1MB の二重サイズ制限
/// - `#if DEBUG` 時のみ使用される想定
public actor APIRequestLogStore {

    /// シングルトン（Infra モジュールからの直接アクセス用）
    public static let shared = APIRequestLogStore()

    private var logs: [APIRequestLog] = []
    private var totalBytes: Int = 0

    private let maxEntries = 100
    private let maxTotalBytes = 1_048_576 // 1MB

    public init() {}

    /// ログを追加する（サイズ制限適用後）
    public func append(_ log: APIRequestLog) {
        let entryBytes = log.estimatedBytes

        // 先頭（最新）に挿入
        logs.insert(log, at: 0)
        totalBytes += entryBytes

        // 件数制限
        while logs.count > maxEntries {
            let removed = logs.removeLast()
            totalBytes -= removed.estimatedBytes
        }

        // 総容量制限
        while totalBytes > maxTotalBytes, logs.count > 1 {
            let removed = logs.removeLast()
            totalBytes -= removed.estimatedBytes
        }
    }

    /// 全ログを取得する（新しい順）
    public func getAll() -> [APIRequestLog] {
        logs
    }

    /// 全ログをクリアする
    public func clear() {
        logs.removeAll()
        totalBytes = 0
    }

    /// ログを JSON 形式でエクスポートする
    public func export() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        struct ExportData: Codable {
            let exportedAt: Date
            let count: Int
            let logs: [APIRequestLog]
        }

        let data = ExportData(
            exportedAt: Date(),
            count: logs.count,
            logs: logs
        )

        guard let jsonData = try? encoder.encode(data),
              let json = String(data: jsonData, encoding: .utf8) else {
            return "{\"error\": \"export failed\"}"
        }
        return json
    }
}
```

- [ ] **Step 4: テストが全て通ることを確認**

Run:
```bash
xcodebuild test \
  -project repository/ios/Soyoka.xcodeproj -scheme InfraLogging \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:'InfraLoggingTests/APIRequestLogStoreTests' 2>&1 | tail -20
```

Expected: 全テスト PASS

- [ ] **Step 5: APIRequestLogClient を作成**

`Sources/InfraLogging/Client/APIRequestLogClient.swift`:

```swift
import Dependencies
import DependenciesMacros
import Foundation

/// TCA Dependency 用 API リクエストログクライアント
///
/// Reducer からのログアクセスに使用。テスト時はモック差し替え可能。
/// Infra モジュールからは `APIRequestLogStore.shared` を直接使用する。
@DependencyClient
public struct APIRequestLogClient: Sendable {
    /// ログを追加する
    public var append: @Sendable (APIRequestLog) async -> Void
    /// 全ログを取得する（新しい順）
    public var getAll: @Sendable () async -> [APIRequestLog] = { [] }
    /// 全ログをクリアする
    public var clear: @Sendable () async -> Void
    /// ログを JSON 形式でエクスポートする
    public var export: @Sendable () async -> String = { "" }
}

// MARK: - TCA DependencyKey

extension APIRequestLogClient: DependencyKey {
    public static let liveValue = APIRequestLogClient(
        append: { log in await APIRequestLogStore.shared.append(log) },
        getAll: { await APIRequestLogStore.shared.getAll() },
        clear: { await APIRequestLogStore.shared.clear() },
        export: { await APIRequestLogStore.shared.export() }
    )
}

extension DependencyValues {
    public var apiRequestLog: APIRequestLogClient {
        get { self[APIRequestLogClient.self] }
        set { self[APIRequestLogClient.self] = newValue }
    }
}
```

- [ ] **Step 6: InfraLogging の全テストが通ることを確認**

Run:
```bash
xcodebuild test \
  -project repository/ios/Soyoka.xcodeproj -scheme InfraLogging \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20
```

Expected: 全テスト PASS

- [ ] **Step 7: コミット**

```bash
git add repository/ios/SoyokaModules/Sources/InfraLogging/Store/ \
        repository/ios/SoyokaModules/Sources/InfraLogging/Client/ \
        repository/ios/SoyokaModules/Tests/InfraLoggingTests/
git commit -m "feat(infra): APIRequestLogStore と APIRequestLogClient を追加

actor ベースのインメモリログストアと TCA Dependency クライアント。
- 100件 + 1MB の二重サイズ制限でメモリ安全性を確保
- DependencyKey 準拠でテスト時のモック差し替えに対応"
```

---

## Task 4: APILogViewerReducer（TDD）

**Files:**
- Create: `repository/ios/SoyokaModules/Sources/FeatureSettings/Debug/APILogViewerReducer.swift`
- Create: `repository/ios/SoyokaModules/Tests/FeatureSettingsTests/APILogViewerReducerTests.swift`

- [ ] **Step 1: Reducer のテストを書く**

`Tests/FeatureSettingsTests/APILogViewerReducerTests.swift`:

```swift
#if DEBUG
import ComposableArchitecture
@testable import FeatureSettings
import InfraLogging
import XCTest

@MainActor
final class APILogViewerReducerTests: XCTestCase {

    // MARK: - ヘルパー

    private func makeLog(
        source: LogSource = .network,
        endpoint: String = "/api/v1/test",
        status: LogStatus = .success(statusCode: 200)
    ) -> APIRequestLog {
        APIRequestLog(
            source: source,
            endpoint: endpoint,
            method: "POST",
            status: status,
            duration: 1.0,
            request: RequestDetail(body: "{}"),
            response: ResponseDetail(body: "{}")
        )
    }

    // MARK: - onAppear

    func test_onAppear_ログが読み込まれる() async {
        let logs = [makeLog(endpoint: "/api/1"), makeLog(endpoint: "/api/2")]

        let store = TestStore(initialState: APILogViewer.State()) {
            APILogViewer()
        } withDependencies: {
            $0.apiRequestLog.getAll = { logs }
        }

        await store.send(.onAppear)
        await store.receive(\.logsLoaded) {
            $0.logs = logs
        }
    }

    // MARK: - フィルタ

    func test_filterChanged_Networkのみ表示される() async {
        let store = TestStore(initialState: APILogViewer.State()) {
            APILogViewer()
        }

        await store.send(.filterChanged(.network)) {
            $0.filter = .network
        }
    }

    func test_filterChanged_nilで全件表示に戻る() async {
        var state = APILogViewer.State()
        state.filter = .network

        let store = TestStore(initialState: state) {
            APILogViewer()
        }

        await store.send(.filterChanged(nil)) {
            $0.filter = nil
        }
    }

    // MARK: - filteredLogs computed property

    func test_filteredLogs_フィルタなし_全件返す() {
        var state = APILogViewer.State()
        state.logs = [
            makeLog(source: .network),
            makeLog(source: .llm),
        ]
        state.filter = nil

        XCTAssertEqual(state.filteredLogs.count, 2)
    }

    func test_filteredLogs_Networkフィルタ_networkのみ返す() {
        var state = APILogViewer.State()
        state.logs = [
            makeLog(source: .network, endpoint: "/net"),
            makeLog(source: .llm, endpoint: "/llm"),
        ]
        state.filter = .network

        XCTAssertEqual(state.filteredLogs.count, 1)
        XCTAssertEqual(state.filteredLogs.first?.endpoint, "/net")
    }

    // MARK: - clear

    func test_clearTapped_確認アラートが表示される() async {
        let store = TestStore(initialState: APILogViewer.State()) {
            APILogViewer()
        }

        await store.send(.clearTapped) {
            $0.showClearConfirmation = true
        }
    }

    func test_clearConfirmed_ログがクリアされる() async {
        var initialState = APILogViewer.State()
        initialState.logs = [makeLog()]
        initialState.showClearConfirmation = true

        let store = TestStore(initialState: initialState) {
            APILogViewer()
        } withDependencies: {
            $0.apiRequestLog.clear = {}
        }

        await store.send(.clearConfirmed) {
            $0.logs = []
            $0.showClearConfirmation = false
        }
    }

    func test_clearDismissed_アラートが閉じる() async {
        var initialState = APILogViewer.State()
        initialState.showClearConfirmation = true

        let store = TestStore(initialState: initialState) {
            APILogViewer()
        }

        await store.send(.clearDismissed) {
            $0.showClearConfirmation = false
        }
    }

    // MARK: - export

    func test_exportTapped_JSONがクリップボードにコピーされる() async {
        let store = TestStore(initialState: APILogViewer.State()) {
            APILogViewer()
        } withDependencies: {
            $0.apiRequestLog.export = { "{\"logs\":[]}" }
        }
        store.exhaustivity = .off

        await store.send(.exportTapped)
    }

    // MARK: - refresh

    func test_refreshRequested_ログが再読み込みされる() async {
        let logs = [makeLog(endpoint: "/refreshed")]

        let store = TestStore(initialState: APILogViewer.State()) {
            APILogViewer()
        } withDependencies: {
            $0.apiRequestLog.getAll = { logs }
        }

        await store.send(.refreshRequested)
        await store.receive(\.logsLoaded) {
            $0.logs = logs
        }
    }
}
#endif
```

- [ ] **Step 2: テストが失敗することを確認**

Run:
```bash
xcodebuild test \
  -project repository/ios/Soyoka.xcodeproj -scheme FeatureSettings \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:'FeatureSettingsTests/APILogViewerReducerTests' 2>&1 | tail -20
```

Expected: コンパイルエラー（`APILogViewer` が存在しない）

- [ ] **Step 3: APILogViewerReducer を実装**

`Sources/FeatureSettings/Debug/APILogViewerReducer.swift`:

```swift
#if DEBUG
import ComposableArchitecture
import InfraLogging

/// デバッグ用 API リクエストログビューアの Reducer
@Reducer
public struct APILogViewer {

    @ObservableState
    public struct State: Equatable {
        public var logs: [APIRequestLog] = []
        public var filter: LogSource? = nil
        public var showClearConfirmation = false

        /// フィルタ適用後のログ
        public var filteredLogs: [APIRequestLog] {
            guard let filter else { return logs }
            return logs.filter { $0.source == filter }
        }

        public init() {}
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case logsLoaded([APIRequestLog])
        case filterChanged(LogSource?)
        case clearTapped
        case clearConfirmed
        case clearDismissed
        case exportTapped
        case copyTapped(APIRequestLog)
        case refreshRequested
    }

    @Dependency(\.apiRequestLog) var apiRequestLog

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear, .refreshRequested:
                return .run { send in
                    let logs = await apiRequestLog.getAll()
                    await send(.logsLoaded(logs))
                }

            case let .logsLoaded(logs):
                state.logs = logs
                return .none

            case let .filterChanged(source):
                state.filter = source
                return .none

            case .clearTapped:
                state.showClearConfirmation = true
                return .none

            case .clearConfirmed:
                state.logs = []
                state.showClearConfirmation = false
                return .run { _ in
                    await apiRequestLog.clear()
                }

            case .clearDismissed:
                state.showClearConfirmation = false
                return .none

            case .exportTapped:
                return .run { _ in
                    let json = await apiRequestLog.export()
                    await MainActor.run {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = json
                        #endif
                    }
                }

            case let .copyTapped(log):
                return .run { _ in
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    encoder.dateEncodingStrategy = .iso8601
                    if let data = try? encoder.encode(log),
                       let json = String(data: data, encoding: .utf8) {
                        await MainActor.run {
                            #if canImport(UIKit)
                            UIPasteboard.general.string = json
                            #endif
                        }
                    }
                }
            }
        }
    }
}
#endif
```

- [ ] **Step 4: テストが全て通ることを確認**

Run:
```bash
xcodebuild test \
  -project repository/ios/Soyoka.xcodeproj -scheme FeatureSettings \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:'FeatureSettingsTests/APILogViewerReducerTests' 2>&1 | tail -20
```

Expected: 全テスト PASS

- [ ] **Step 5: コミット**

```bash
git add repository/ios/SoyokaModules/Sources/FeatureSettings/Debug/APILogViewerReducer.swift \
        repository/ios/SoyokaModules/Tests/FeatureSettingsTests/APILogViewerReducerTests.swift
git commit -m "feat(settings): APILogViewerReducer を追加

デバッグ用ログビューアの状態管理 Reducer。
- ログ取得、フィルタリング、クリア、エクスポート、コピーに対応
- TestStore による網羅的なテストを追加"
```

---

## Task 5: UI（APILogListView + APILogDetailView）

**Files:**
- Create: `repository/ios/SoyokaModules/Sources/FeatureSettings/Debug/APILogListView.swift`
- Create: `repository/ios/SoyokaModules/Sources/FeatureSettings/Debug/APILogDetailView.swift`

- [ ] **Step 1: APILogDetailView を作成**

`Sources/FeatureSettings/Debug/APILogDetailView.swift`:

```swift
#if DEBUG
import InfraLogging
import SharedUI
import SwiftUI

/// API リクエストログの詳細画面
struct APILogDetailView: View {
    let log: APIRequestLog
    let onCopy: () -> Void

    var body: some View {
        List {
            overviewSection
            requestHeadersSection
            requestBodySection
            responseHeadersSection
            responseBodySection
            copySection
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle(navigationTitleText)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - 概要セクション

    private var overviewSection: some View {
        Section {
            row(label: "ステータス", value: log.status.displayText, isError: !log.status.isSuccess)
            row(label: "所要時間", value: String(format: "%.2fs", log.duration))
            row(label: "時刻", value: formattedTimestamp)
            row(label: "ソース", value: log.source.rawValue.capitalized)
            if let method = log.method {
                row(label: "メソッド", value: method)
            }
        } header: {
            Text("概要")
        }
    }

    // MARK: - リクエストヘッダー

    @ViewBuilder
    private var requestHeadersSection: some View {
        if let headers = log.request.headers, !headers.isEmpty {
            Section {
                DisclosureGroup("リクエストヘッダー") {
                    ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        row(label: key, value: value)
                    }
                }
            }
        }
    }

    // MARK: - リクエストボディ

    @ViewBuilder
    private var requestBodySection: some View {
        if let body = log.request.body, !body.isEmpty {
            Section {
                DisclosureGroup("リクエストボディ") {
                    Text(prettyPrintJSON(body))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.vmTextSecondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - レスポンスヘッダー

    @ViewBuilder
    private var responseHeadersSection: some View {
        if let headers = log.response?.headers, !headers.isEmpty {
            Section {
                DisclosureGroup("レスポンスヘッダー") {
                    ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        row(label: key, value: value)
                    }
                }
            }
        }
    }

    // MARK: - レスポンスボディ

    @ViewBuilder
    private var responseBodySection: some View {
        if let body = log.response?.body, !body.isEmpty {
            Section {
                DisclosureGroup("レスポンスボディ") {
                    Text(prettyPrintJSON(body))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.vmTextSecondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - コピー

    private var copySection: some View {
        Section {
            Button {
                onCopy()
            } label: {
                HStack {
                    Spacer()
                    Label("この項目をコピー", systemImage: "doc.on.doc")
                    Spacer()
                }
            }
        }
    }

    // MARK: - ヘルパー

    private func row(label: String, value: String, isError: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.vmCaption1)
                .foregroundColor(isError ? .red : .vmTextTertiary)
        }
    }

    private var navigationTitleText: String {
        if let method = log.method {
            return "\(method) \(log.endpoint)"
        }
        return log.endpoint
    }

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: log.timestamp)
    }

    private func prettyPrintJSON(_ string: String) -> String {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let prettyString = String(data: prettyData, encoding: .utf8)
        else {
            return string
        }
        return prettyString
    }
}
#endif
```

- [ ] **Step 2: APILogListView を作成**

`Sources/FeatureSettings/Debug/APILogListView.swift`:

```swift
#if DEBUG
import ComposableArchitecture
import InfraLogging
import SharedUI
import SwiftUI

/// API リクエストログの一覧画面
public struct APILogListView: View {
    @Bindable var store: StoreOf<APILogViewer>

    public init(store: StoreOf<APILogViewer>) {
        self.store = store
    }

    public var body: some View {
        List {
            filterSection
            logsSection
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("API ログ")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    store.send(.exportTapped)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    store.send(.clearTapped)
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .overlay {
            if store.filteredLogs.isEmpty {
                ContentUnavailableView(
                    "ログなし",
                    systemImage: "network.slash",
                    description: Text("API リクエストのログがまだありません")
                )
            }
        }
        .alert("ログをクリア", isPresented: $store.showClearConfirmation.sending(\.clearDismissed)) {
            Button("クリア", role: .destructive) {
                store.send(.clearConfirmed)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("全ての API ログを削除しますか？")
        }
        .onAppear {
            store.send(.onAppear)
        }
        .refreshable {
            store.send(.refreshRequested)
            // 少し待ってからリフレッシュインジケータを消す
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    // MARK: - フィルタセクション

    private var filterSection: some View {
        Section {
            Picker("フィルタ", selection: $store.filter.sending(\.filterChanged)) {
                Text("ALL").tag(LogSource?.none)
                Text("Network").tag(LogSource?.some(.network))
                Text("LLM").tag(LogSource?.some(.llm))
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - ログ一覧セクション

    private var logsSection: some View {
        Section {
            ForEach(store.filteredLogs) { log in
                NavigationLink {
                    APILogDetailView(log: log) {
                        store.send(.copyTapped(log))
                    }
                } label: {
                    APILogRowView(log: log)
                }
            }
        } header: {
            if !store.filteredLogs.isEmpty {
                Text("\(store.filteredLogs.count) 件")
            }
        }
    }
}

// MARK: - ログ行ビュー

private struct APILogRowView: View {
    let log: APIRequestLog

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            VStack(alignment: .leading, spacing: 4) {
                endpointText
                detailText
            }
        }
        .padding(.vertical, 2)
    }

    private var statusIcon: some View {
        Group {
            if log.status.isSuccess {
                Image(systemName: "circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .font(.system(size: 10))
    }

    private var endpointText: some View {
        HStack(spacing: 4) {
            if let method = log.method {
                Text(method)
                    .font(.vmCaption1)
                    .fontWeight(.semibold)
                    .foregroundColor(.vmTextSecondary)
            }
            Text(log.endpoint)
                .font(.vmCaption1)
                .foregroundColor(.vmTextPrimary)
                .lineLimit(1)
        }
    }

    private var detailText: some View {
        HStack(spacing: 8) {
            Text(log.status.displayText)
                .foregroundColor(log.status.isSuccess ? .vmTextTertiary : .red)
            Text("·")
                .foregroundColor(.vmTextTertiary)
            Text(String(format: "%.2fs", log.duration))
                .foregroundColor(.vmTextTertiary)
            Text("·")
                .foregroundColor(.vmTextTertiary)
            Text(formattedTime)
                .foregroundColor(.vmTextTertiary)
        }
        .font(.system(.caption2))
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: log.timestamp)
    }
}
#endif
```

- [ ] **Step 3: ビルドが通ることを確認**

Run:
```bash
xcodebuild build \
  -project repository/ios/Soyoka.xcodeproj -scheme FeatureSettings \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: コミット**

```bash
git add repository/ios/SoyokaModules/Sources/FeatureSettings/Debug/APILogListView.swift \
        repository/ios/SoyokaModules/Sources/FeatureSettings/Debug/APILogDetailView.swift
git commit -m "feat(settings): APIログビューアのUI画面を追加

一覧画面（フィルタ、ステータスアイコン、Pull to Refresh）と
詳細画面（DisclosureGroup、JSON整形表示、コピー機能）を実装"
```

---

## Task 6: DebugMenuView へのナビゲーション統合

**Files:**
- Modify: `repository/ios/SoyokaModules/Sources/FeatureSettings/Debug/DebugMenuView.swift`

- [ ] **Step 1: DebugMenuView に API ログセクションを追加**

`DebugMenuView.swift` の `import` に追加:

```swift
import ComposableArchitecture
import InfraLogging
```

`body` の `List` 内、`networkSection` の直後に `apiLogSection` を追加:

```swift
        List {
            subscriptionSection
            aiProcessingSection
            sttEngineSection
            networkSection
            apiLogSection       // ← 追加
            dataSection
            uiInfoSection
            dangerZoneSection
        }
```

セクション定義を追加（`networkSection` の下あたり）:

```swift
    // MARK: - セクション: API ログ

    private var apiLogSection: some View {
        Section {
            NavigationLink {
                APILogListView(
                    store: Store(initialState: APILogViewer.State()) {
                        APILogViewer()
                    }
                )
            } label: {
                HStack {
                    Image(systemName: "network")
                    Text("API リクエストログ")
                }
            }
        } header: {
            Text("ログ")
        }
    }
```

- [ ] **Step 2: ビルドが通ることを確認**

Run:
```bash
xcodebuild build \
  -project repository/ios/Soyoka.xcodeproj -scheme Soyoka \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: 既存テストが全て通ることを確認**

Run:
```bash
xcodebuild test \
  -project repository/ios/Soyoka.xcodeproj -scheme FeatureSettings \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20
```

Expected: 全テスト PASS

- [ ] **Step 4: コミット**

```bash
git add repository/ios/SoyokaModules/Sources/FeatureSettings/Debug/DebugMenuView.swift
git commit -m "feat(settings): デバッグメニューに API ログビューアへのリンクを追加

ネットワークセクションの下にログセクションを配置。
NavigationLink で APILogListView に遷移する"
```

---

## Task 7: ログ投入 — InfraNetwork（BackendProxyClient）

**Files:**
- Modify: `repository/ios/SoyokaModules/Sources/InfraNetwork/BackendProxyClient.swift`

- [ ] **Step 1: import を追加**

`BackendProxyClient.swift` の先頭に追加:

```swift
import InfraLogging
```

- [ ] **Step 2: ログ投入ヘルパーを追加**

`BackendProxyClient` の `live()` メソッド内、`return BackendProxyClient(` の前に追加:

```swift
        /// デバッグ用ログ投入ヘルパー
        @Sendable func logRequest(
            endpoint: String,
            method: String,
            requestHeaders: [String: String]?,
            requestBody: String?,
            responseHeaders: [String: String]?,
            responseBody: String?,
            statusCode: Int?,
            error: Error?,
            duration: TimeInterval
        ) async {
            #if DEBUG
            let status: LogStatus = if let error {
                .failure(message: error.localizedDescription)
            } else {
                .success(statusCode: statusCode)
            }

            await APIRequestLogStore.shared.append(APIRequestLog(
                source: .network,
                endpoint: endpoint,
                method: method,
                status: status,
                duration: duration,
                request: RequestDetail(
                    headers: LogSanitizer.sanitizeHeaders(requestHeaders),
                    body: LogSanitizer.sanitizeBody(requestBody)
                ),
                response: ResponseDetail(
                    headers: LogSanitizer.sanitizeHeaders(responseHeaders),
                    body: LogSanitizer.sanitizeBody(responseBody)
                )
            ))
            #endif
        }
```

- [ ] **Step 3: authenticate にログ投入を追加**

`authenticate` クロージャ内の `let (data, response) = try await session.data(for: request)` の前に計測開始を追加し、return 前とエラー時にログ投入:

```swift
            authenticate: { deviceID, appVersion, osVersion in
                let url = baseURL.appendingPathComponent("api/v1/auth/device")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let body: [String: String] = [
                    "device_id": deviceID,
                    "app_version": appVersion,
                    "os_version": osVersion,
                ]
                request.httpBody = try JSONEncoder().encode(body)

                let requestBodyString = String(data: request.httpBody ?? Data(), encoding: .utf8)
                let startTime = CFAbsoluteTimeGetCurrent()

                do {
                    let (data, response) = try await session.data(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw BackendProxyError.networkError("Invalid response type")
                    }

                    let duration = CFAbsoluteTimeGetCurrent() - startTime
                    let responseBody = String(data: data, encoding: .utf8)

                    guard httpResponse.statusCode == 200 else {
                        let error = BackendProxyError.authenticationFailed("HTTP \(httpResponse.statusCode)")
                        await logRequest(
                            endpoint: "api/v1/auth/device", method: "POST",
                            requestHeaders: request.allHTTPHeaderFields, requestBody: requestBodyString,
                            responseHeaders: nil, responseBody: responseBody,
                            statusCode: httpResponse.statusCode, error: error, duration: duration
                        )
                        throw error
                    }

                    let authResponse = try decoder.decode(AuthResponse.self, from: data)
                    try keychainManager.save(key: .accessToken, string: authResponse.accessToken)

                    await logRequest(
                        endpoint: "api/v1/auth/device", method: "POST",
                        requestHeaders: request.allHTTPHeaderFields, requestBody: requestBodyString,
                        responseHeaders: nil, responseBody: responseBody,
                        statusCode: httpResponse.statusCode, error: nil, duration: duration
                    )

                    logger.info("デバイス認証成功: device_id=\(authResponse.deviceID)")
                    return authResponse
                } catch let error as BackendProxyError {
                    throw error
                } catch {
                    let duration = CFAbsoluteTimeGetCurrent() - startTime
                    await logRequest(
                        endpoint: "api/v1/auth/device", method: "POST",
                        requestHeaders: request.allHTTPHeaderFields, requestBody: requestBodyString,
                        responseHeaders: nil, responseBody: nil,
                        statusCode: nil, error: error, duration: duration
                    )
                    throw error
                }
            },
```

- [ ] **Step 4: processAI にログ投入を追加**

同様のパターンで `processAI` クロージャを更新。`let (data, response) = try await session.data(for: request)` の前に `startTime` と `requestBodyString` を取得し、成功/失敗の各パスで `logRequest()` を呼び出す。

エンドポイント: `"api/v1/ai/process"`, メソッド: `"POST"`

- [ ] **Step 5: getUsage にログ投入を追加**

同様のパターンで `getUsage` クロージャを更新。

エンドポイント: `"api/v1/usage"`, メソッド: `"GET"`, リクエストボディなし

- [ ] **Step 6: verifySubscription にログ投入を追加**

同様のパターンで `verifySubscription` クロージャを更新。

エンドポイント: `"api/v1/subscription/verify"`, メソッド: `"POST"`

- [ ] **Step 7: ビルドが通ることを確認**

Run:
```bash
xcodebuild build \
  -project repository/ios/Soyoka.xcodeproj -scheme InfraNetwork \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED

- [ ] **Step 8: 既存テストが通ることを確認**

Run:
```bash
xcodebuild test \
  -project repository/ios/Soyoka.xcodeproj -scheme InfraNetwork \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20
```

Expected: 全テスト PASS

- [ ] **Step 9: コミット**

```bash
git add repository/ios/SoyokaModules/Sources/InfraNetwork/BackendProxyClient.swift
git commit -m "feat(network): BackendProxyClient にデバッグログ投入を追加

4エンドポイント全てでリクエスト/レスポンスをログに記録。
- 認証ヘッダーは LogSanitizer で自動マスク
- #if DEBUG ガードでリリースビルドには影響なし"
```

---

## Task 8: ログ投入 — InfraNetwork（RemotePromptClient + ForceUpdateClient）

**Files:**
- Modify: `repository/ios/SoyokaModules/Sources/InfraNetwork/RemotePromptClient.swift`
- Modify: `repository/ios/SoyokaModules/Sources/InfraNetwork/ForceUpdateClient.swift`

- [ ] **Step 1: RemotePromptClient にログ投入を追加**

`RemotePromptClient.swift` に `import InfraLogging` を追加。

`live()` の `fetchLatest` クロージャ内に計測開始・ログ投入を追加:

```swift
    public static func live() -> RemotePromptClient {
        let session = URLSession.shared

        return RemotePromptClient(
            fetchLatest: { baseURL in
                guard let url = URL(string: "\(baseURL)/api/v1/prompts/latest") else {
                    throw RemotePromptError.invalidURL
                }

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 10

                let startTime = CFAbsoluteTimeGetCurrent()

                do {
                    let (data, response) = try await session.data(for: request)
                    let duration = CFAbsoluteTimeGetCurrent() - startTime

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw RemotePromptError.networkError("Invalid response type")
                    }

                    let responseBody = String(data: data, encoding: .utf8)

                    guard (200...299).contains(httpResponse.statusCode) else {
                        let error = RemotePromptError.serverError(httpResponse.statusCode)
                        #if DEBUG
                        await APIRequestLogStore.shared.append(APIRequestLog(
                            source: .network, endpoint: "api/v1/prompts/latest", method: "GET",
                            status: .failure(message: error.localizedDescription), duration: duration,
                            request: RequestDetail(),
                            response: ResponseDetail(body: LogSanitizer.sanitizeBody(responseBody))
                        ))
                        #endif
                        throw error
                    }

                    let promptResponse = try JSONDecoder().decode(RemotePromptResponse.self, from: data)
                    RemotePromptClient.saveCache(promptResponse)

                    #if DEBUG
                    await APIRequestLogStore.shared.append(APIRequestLog(
                        source: .network, endpoint: "api/v1/prompts/latest", method: "GET",
                        status: .success(statusCode: httpResponse.statusCode), duration: duration,
                        request: RequestDetail(),
                        response: ResponseDetail(body: LogSanitizer.sanitizeBody(responseBody))
                    ))
                    #endif

                    logger.info("プロンプトテンプレート取得成功: version=\(promptResponse.version)")
                    return promptResponse
                } catch let error as RemotePromptError {
                    throw error
                } catch {
                    let duration = CFAbsoluteTimeGetCurrent() - startTime
                    #if DEBUG
                    await APIRequestLogStore.shared.append(APIRequestLog(
                        source: .network, endpoint: "api/v1/prompts/latest", method: "GET",
                        status: .failure(message: error.localizedDescription), duration: duration,
                        request: RequestDetail(), response: nil
                    ))
                    #endif
                    throw error
                }
            }
        )
    }
```

- [ ] **Step 2: ForceUpdateClient にログ投入を追加**

`ForceUpdateClient.swift` に `import InfraLogging` を追加。

`live(baseURL:)` の `check` クロージャ内に同様のパターンでログ投入を追加。

エンドポイント: `"api/v1/version/check"`, メソッド: `"GET"`

```swift
                let startTime = CFAbsoluteTimeGetCurrent()
                // ... 既存の session.data(for: request) ...
                let duration = CFAbsoluteTimeGetCurrent() - startTime

                #if DEBUG
                await APIRequestLogStore.shared.append(APIRequestLog(
                    source: .network, endpoint: "api/v1/version/check", method: "GET",
                    status: .success(statusCode: httpResponse.statusCode), duration: duration,
                    request: RequestDetail(),
                    response: ResponseDetail(body: LogSanitizer.sanitizeBody(String(data: data, encoding: .utf8)))
                ))
                #endif
```

catch ブロックにも失敗ログを追加。

- [ ] **Step 3: ビルドが通ることを確認**

Run:
```bash
xcodebuild build \
  -project repository/ios/Soyoka.xcodeproj -scheme InfraNetwork \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: コミット**

```bash
git add repository/ios/SoyokaModules/Sources/InfraNetwork/RemotePromptClient.swift \
        repository/ios/SoyokaModules/Sources/InfraNetwork/ForceUpdateClient.swift
git commit -m "feat(network): RemotePromptClient/ForceUpdateClient にデバッグログ投入を追加

プロンプト取得とバージョンチェックのリクエスト/レスポンスをログに記録"
```

---

## Task 9: ログ投入 — InfraLLM（HybridLLMRouter）

**Files:**
- Modify: `repository/ios/SoyokaModules/Sources/InfraLLM/HybridLLMRouter.swift`

- [ ] **Step 1: import を追加**

```swift
import InfraLogging
```

- [ ] **Step 2: process メソッドをログ投入ラッパーで囲む**

`process(_ request:)` メソッドの先頭で計測開始し、各 return/throw の前にログ投入。既存の process ロジックを `processInternal` に移動し、公開メソッドでラップ:

```swift
    public func process(_ request: LLMRequest) async throws -> LLMResponse {
        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            let result = try await processInternal(request)
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            #if DEBUG
            await APIRequestLogStore.shared.append(APIRequestLog(
                source: .llm,
                endpoint: result.provider.rawValue,
                status: .success(statusCode: nil),
                duration: duration,
                request: RequestDetail(
                    body: LogSanitizer.sanitizeBody(request.text)
                ),
                response: ResponseDetail(
                    body: LogSanitizer.sanitizeBody(formatLLMResponse(result))
                )
            ))
            #endif
            return result
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            #if DEBUG
            await APIRequestLogStore.shared.append(APIRequestLog(
                source: .llm,
                endpoint: "HybridLLMRouter",
                status: .failure(message: error.localizedDescription),
                duration: duration,
                request: RequestDetail(
                    body: LogSanitizer.sanitizeBody(request.text)
                ),
                response: nil
            ))
            #endif
            throw error
        }
    }
```

既存の `process` メソッドの中身を `private func processInternal(_ request: LLMRequest) async throws -> LLMResponse` にリネーム。

- [ ] **Step 3: LLMResponse フォーマットヘルパーを追加**

```swift
    #if DEBUG
    private func formatLLMResponse(_ response: LLMResponse) -> String {
        var parts: [String] = []
        if let summary = response.summary {
            parts.append("summary: \(summary.title)")
        }
        if let tags = response.tags {
            parts.append("tags: \(tags.map(\.label).joined(separator: ", "))")
        }
        if let sentiment = response.sentiment {
            parts.append("sentiment: \(sentiment.primary.rawValue)")
        }
        parts.append("provider: \(response.provider.rawValue)")
        return parts.joined(separator: "\n")
    }
    #endif
```

- [ ] **Step 4: ビルドが通ることを確認**

Run:
```bash
xcodebuild build \
  -project repository/ios/Soyoka.xcodeproj -scheme InfraLLM \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: 既存テストが通ることを確認**

Run:
```bash
xcodebuild test \
  -project repository/ios/Soyoka.xcodeproj -scheme InfraLLM \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20
```

Expected: 全テスト PASS

- [ ] **Step 6: コミット**

```bash
git add repository/ios/SoyokaModules/Sources/InfraLLM/HybridLLMRouter.swift
git commit -m "feat(llm): HybridLLMRouter にデバッグログ投入を追加

LLM ルーティング結果（プロバイダ名、プロンプト、応答要約）をログに記録。
- process メソッドをラッパー/内部実装に分割して計測・記録"
```

---

## Task 10: 全体ビルド + 全テスト通過確認

**Files:** なし（確認のみ）

- [ ] **Step 1: アプリ全体ビルド**

Run:
```bash
xcodebuild build \
  -project repository/ios/Soyoka.xcodeproj -scheme Soyoka \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED

- [ ] **Step 2: 全テスト実行**

Run:
```bash
xcodebuild test \
  -project repository/ios/Soyoka.xcodeproj -scheme Soyoka \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30
```

Expected: 全テスト PASS（既存 369 + 新規テスト）

- [ ] **Step 3: ビルド/テスト失敗があれば修正してコミット**

問題があれば修正し、各モジュールのテストを個別に再実行して原因を特定する。
