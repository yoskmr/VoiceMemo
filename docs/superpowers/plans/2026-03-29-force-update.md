# 強制アップデート機能 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cloudflare Workers KV に設定した最低バージョンを下回るアプリに対し、フルスクリーンブロックで App Store 遷移を強制する。

**Architecture:** バックエンド側は既存の Cloudflare Workers + KV に認証不要の `GET /api/v1/version/check` エンドポイントを追加。iOS 側は `ForceUpdateClient`（InfraNetwork）で API を叩き、`AppReducer` でアプリ起動時 + フォアグラウンド復帰時にチェック。ブロック対象なら `ForceUpdateOverlay`（SharedUI）をフルスクリーン表示。

**Tech Stack:** Cloudflare Workers (Hono + KV), Swift 6.2, TCA 1.17+, SwiftUI, swift-dependencies

**Spec:** `docs/superpowers/specs/2026-03-29-force-update-design.md`

---

## ファイル構成

### バックエンド（新規・変更）

| ファイル | 種別 | 責務 |
|:--------|:-----|:----|
| `repository/backend/src/routes/version.ts` | 新規 | バージョンチェックルート（KV 読み取り） |
| `repository/backend/src/index.ts` | 変更 | ルート登録 + レート制限ミドルウェア追加 |

### iOS（新規・変更）

| ファイル | 種別 | 責務 |
|:--------|:-----|:----|
| `repository/ios/SoyokaModules/Sources/InfraNetwork/ForceUpdateClient.swift` | 新規 | API クライアント + semver 比較 + TCA Dependency |
| `repository/ios/SoyokaModules/Sources/SharedUI/ForceUpdate/ForceUpdateOverlay.swift` | 新規 | フルスクリーンブロック UI |
| `repository/ios/SoyokaApp/SoyokaApp.swift` | 変更 | AppReducer に State/Action/Reduce 追加、AppView に overlay + scenePhase |
| `repository/ios/SoyokaModules/Tests/InfraNetworkTests/ForceUpdateClientTests.swift` | 新規 | semver 比較のユニットテスト |
| `repository/ios/SoyokaModules/Tests/E2ETests/ForceUpdateE2ETests.swift` | 新規 | AppReducer 統合テスト |

---

## Task 1: バックエンド — バージョンチェックルート

**Files:**
- Create: `repository/backend/src/routes/version.ts`
- Modify: `repository/backend/src/index.ts`

- [ ] **Step 1: バージョンチェックルートを作成**

```typescript
// repository/backend/src/routes/version.ts
import { Hono } from "hono";
import type { Env } from "../types.js";

const versionRoutes = new Hono<{ Bindings: Env }>();

versionRoutes.get("/check", async (c) => {
  const minimumVersion =
    (await c.env.KV.get("minimum_app_version")) ?? "1.0.0";
  const storeUrl = (await c.env.KV.get("app_store_url")) ?? "";

  return c.json({
    minimum_version: minimumVersion,
    store_url: storeUrl,
  });
});

export { versionRoutes };
```

- [ ] **Step 2: index.ts にルート登録を追加**

`repository/backend/src/index.ts` の Prompt Routes の前に以下を追加:

```typescript
import { versionRoutes } from "./routes/version.js";

// --- Version Check Routes (認証不要、レート制限あり: 120/min) ---

app.use("/api/v1/version/*", createRateLimitMiddleware({ maxRequests: 120 }));
app.route("/api/v1/version", versionRoutes);
```

import 文は既存の import ブロックの末尾（`import { promptRoutes }` の後）に追加。
ルート登録は `// --- Prompt Routes ---` コメントの**直前**に挿入。

- [ ] **Step 3: ローカルでビルド確認**

Run: `cd repository/backend && npx wrangler dev --env dev`

curl でエンドポイント確認:

```bash
curl -s http://localhost:8787/api/v1/version/check | jq .
```

Expected:
```json
{
  "minimum_version": "1.0.0",
  "store_url": ""
}
```

KV にまだ値を入れていないのでデフォルト値が返る。

- [ ] **Step 4: コミット**

```bash
git add repository/backend/src/routes/version.ts repository/backend/src/index.ts
git commit -m "feat(backend): バージョンチェックエンドポイント追加

- GET /api/v1/version/check: Cloudflare KV から最低バージョンを返す
- 認証不要、レート制限 120req/min
- KV 未設定時はデフォルト 1.0.0 を返す（強制アップデート非発動）"
```

---

## Task 2: iOS — ForceUpdateClient の型定義とテスト（RED）

**Files:**
- Create: `repository/ios/SoyokaModules/Sources/InfraNetwork/ForceUpdateClient.swift`
- Create: `repository/ios/SoyokaModules/Tests/InfraNetworkTests/ForceUpdateClientTests.swift`

- [ ] **Step 1: ForceUpdateClient の型定義を作成**

```swift
// repository/ios/SoyokaModules/Sources/InfraNetwork/ForceUpdateClient.swift

import Dependencies
import Foundation
import os.log

private let logger = Logger(subsystem: "app.soyoka", category: "ForceUpdate")

// MARK: - Response Type

struct VersionCheckResponse: Sendable, Equatable, Codable {
    let minimumVersion: String
    let storeUrl: String

    private enum CodingKeys: String, CodingKey {
        case minimumVersion = "minimum_version"
        case storeUrl = "store_url"
    }
}

// MARK: - Status

public enum ForceUpdateStatus: Sendable, Equatable {
    case upToDate
    case updateRequired(storeURL: URL)
}

// MARK: - Errors

public enum ForceUpdateError: Error, Sendable, Equatable {
    case invalidURL
    case networkError(String)
    case serverError(Int)
    case decodingFailed
}

// MARK: - ForceUpdateClient

public struct ForceUpdateClient: Sendable {
    public var check: @Sendable (_ baseURL: String) async throws -> ForceUpdateStatus

    public init(
        check: @escaping @Sendable (_ baseURL: String) async throws -> ForceUpdateStatus
    ) {
        self.check = check
    }
}

// MARK: - Semver Comparison

extension ForceUpdateClient {
    /// current < minimum なら true を返す
    public static func isVersionLessThan(_ current: String, minimum: String) -> Bool {
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let minimumParts = minimum.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(currentParts.count, minimumParts.count)
        for i in 0..<maxCount {
            let c = i < currentParts.count ? currentParts[i] : 0
            let m = i < minimumParts.count ? minimumParts[i] : 0
            if c < m { return true }
            if c > m { return false }
        }
        return false // equal
    }
}

// MARK: - TCA DependencyKey

extension ForceUpdateClient: TestDependencyKey {
    public static let testValue = ForceUpdateClient(
        check: unimplemented("ForceUpdateClient.check")
    )
}

extension DependencyValues {
    public var forceUpdateClient: ForceUpdateClient {
        get { self[ForceUpdateClient.self] }
        set { self[ForceUpdateClient.self] = newValue }
    }
}
```

- [ ] **Step 2: semver 比較のテストを作成**

```swift
// repository/ios/SoyokaModules/Tests/InfraNetworkTests/ForceUpdateClientTests.swift

@testable import InfraNetwork
import XCTest

final class ForceUpdateClientTests: XCTestCase {

    // MARK: - Semver Comparison

    func test_isVersionLessThan_マイナーバージョンが低い場合_trueを返す() {
        XCTAssertTrue(ForceUpdateClient.isVersionLessThan("1.0.0", minimum: "1.1.0"))
    }

    func test_isVersionLessThan_メジャーバージョンが低い場合_trueを返す() {
        XCTAssertTrue(ForceUpdateClient.isVersionLessThan("1.9.9", minimum: "2.0.0"))
    }

    func test_isVersionLessThan_パッチバージョンが低い場合_trueを返す() {
        XCTAssertTrue(ForceUpdateClient.isVersionLessThan("1.0.0", minimum: "1.0.1"))
    }

    func test_isVersionLessThan_同一バージョンの場合_falseを返す() {
        XCTAssertFalse(ForceUpdateClient.isVersionLessThan("1.0.0", minimum: "1.0.0"))
    }

    func test_isVersionLessThan_現在が高い場合_falseを返す() {
        XCTAssertFalse(ForceUpdateClient.isVersionLessThan("2.0.0", minimum: "1.9.9"))
    }

    func test_isVersionLessThan_パーツ数が異なる場合_正しく比較する() {
        XCTAssertTrue(ForceUpdateClient.isVersionLessThan("1.0", minimum: "1.0.1"))
        XCTAssertFalse(ForceUpdateClient.isVersionLessThan("1.0.1", minimum: "1.0"))
    }

    func test_isVersionLessThan_大きな数字の比較() {
        XCTAssertTrue(ForceUpdateClient.isVersionLessThan("1.0.99", minimum: "1.1.0"))
        XCTAssertFalse(ForceUpdateClient.isVersionLessThan("10.0.0", minimum: "9.99.99"))
    }
}
```

- [ ] **Step 3: テストを実行して PASS を確認**

Xcode MCP または以下で実行:

```
swift test --package-path repository/ios/SoyokaModules --filter ForceUpdateClientTests
```

Expected: 全テスト PASS

- [ ] **Step 4: コミット**

```bash
git add repository/ios/SoyokaModules/Sources/InfraNetwork/ForceUpdateClient.swift \
       repository/ios/SoyokaModules/Tests/InfraNetworkTests/ForceUpdateClientTests.swift
git commit -m "feat(ios): ForceUpdateClient の型定義と semver 比較テスト

- ForceUpdateClient: check 関数 + ForceUpdateStatus/ForceUpdateError 型
- isVersionLessThan: major.minor.patch の数値比較
- TestDependencyKey/DependencyValues 登録（TCA DI パターン準拠）
- 7つの semver 比較テストケース（全 PASS）"
```

---

## Task 3: iOS — ForceUpdateClient の live 実装

**Files:**
- Modify: `repository/ios/SoyokaModules/Sources/InfraNetwork/ForceUpdateClient.swift`

- [ ] **Step 1: live 実装を追加**

`ForceUpdateClient.swift` の `// MARK: - TCA DependencyKey` の **前** に以下を追加:

```swift
// MARK: - Live Implementation

extension ForceUpdateClient {
    /// 本番用クライアント
    public static func live() -> ForceUpdateClient {
        let session = URLSession.shared

        return ForceUpdateClient(
            check: { baseURL in
                guard let url = URL(string: "\(baseURL)/api/v1/version/check") else {
                    throw ForceUpdateError.invalidURL
                }

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 10

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ForceUpdateError.networkError("Invalid response type")
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw ForceUpdateError.serverError(httpResponse.statusCode)
                }

                let decoder = JSONDecoder()
                guard let versionCheck = try? decoder.decode(VersionCheckResponse.self, from: data) else {
                    throw ForceUpdateError.decodingFailed
                }

                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

                if isVersionLessThan(currentVersion, minimum: versionCheck.minimumVersion),
                   let storeURL = URL(string: versionCheck.storeUrl) {
                    logger.info("強制アップデート: current=\(currentVersion) < minimum=\(versionCheck.minimumVersion)")
                    return .updateRequired(storeURL: storeURL)
                }

                logger.debug("バージョンOK: current=\(currentVersion) >= minimum=\(versionCheck.minimumVersion)")
                return .upToDate
            }
        )
    }
}
```

- [ ] **Step 2: ビルド確認**

Xcode MCP でビルド、またはコマンドラインで:

```
swift build --package-path repository/ios/SoyokaModules
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: コミット**

```bash
git add repository/ios/SoyokaModules/Sources/InfraNetwork/ForceUpdateClient.swift
git commit -m "feat(ios): ForceUpdateClient の live 実装を追加

- URLSession で GET /api/v1/version/check を呼び出し
- Bundle.main から CFBundleShortVersionString を取得して semver 比較
- タイムアウト 10秒、ステータスコード検証付き"
```

---

## Task 4: iOS — ForceUpdateOverlay（SharedUI）

**Files:**
- Create: `repository/ios/SoyokaModules/Sources/SharedUI/ForceUpdate/ForceUpdateOverlay.swift`

- [ ] **Step 1: フルスクリーンオーバーレイを作成**

```swift
// repository/ios/SoyokaModules/Sources/SharedUI/ForceUpdate/ForceUpdateOverlay.swift

import SwiftUI

/// 強制アップデート時にアプリ全体をブロックするフルスクリーンオーバーレイ
public struct ForceUpdateOverlay: View {
    private let storeURL: URL
    @Environment(\.openURL) private var openURL

    public init(storeURL: URL) {
        self.storeURL = storeURL
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("アップデートが必要です")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("最新バージョンにアップデートしてください。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                openURL(storeURL)
            } label: {
                Text("ストアを開く")
                    .font(.headline)
                    .frame(maxWidth: 240)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()
    }
}
```

- [ ] **Step 2: ビルド確認**

Xcode MCP でビルド、またはコマンドラインで:

```
swift build --package-path repository/ios/SoyokaModules
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: コミット**

```bash
git add repository/ios/SoyokaModules/Sources/SharedUI/ForceUpdate/ForceUpdateOverlay.swift
git commit -m "feat(ui): ForceUpdateOverlay — 強制アップデートのフルスクリーンUI

- テキストベースのシンプルなデザイン（キャラなし）
- 閉じるボタンなし、interactiveDismissDisabled で閉じ不可
- ライト/ダークモード対応（systemBackground）
- Dynamic Type 対応"
```

---

## Task 5: iOS — AppReducer に強制アップデートロジックを統合 + テスト（RED → GREEN）

**Files:**
- Create: `repository/ios/SoyokaModules/Tests/E2ETests/ForceUpdateE2ETests.swift`
- Modify: `repository/ios/SoyokaApp/SoyokaApp.swift`

- [ ] **Step 1: AppReducer の強制アップデートテストを作成（RED）**

```swift
// repository/ios/SoyokaModules/Tests/E2ETests/ForceUpdateE2ETests.swift

@testable import InfraNetwork
import ComposableArchitecture
import XCTest

// AppReducer は SoyokaApp ターゲットにあるため、
// E2E テストでは ForceUpdateClient の振る舞いのみを検証する。
// AppReducer 統合テストは Xcode の SoyokaApp テストターゲットで実施。

// ここでは ForceUpdateClient のスタブ動作を検証する。
@MainActor
final class ForceUpdateE2ETests: XCTestCase {

    func test_check_updateRequired_正しいステータスを返す() async throws {
        let testURL = URL(string: "https://apps.apple.com/app/id123456")!
        let client = ForceUpdateClient(
            check: { _ in .updateRequired(storeURL: testURL) }
        )

        let status = try await client.check("https://api.example.com")
        XCTAssertEqual(status, .updateRequired(storeURL: testURL))
    }

    func test_check_upToDate_正しいステータスを返す() async throws {
        let client = ForceUpdateClient(
            check: { _ in .upToDate }
        )

        let status = try await client.check("https://api.example.com")
        XCTAssertEqual(status, .upToDate)
    }

    func test_check_networkError_エラーをスローする() async {
        let client = ForceUpdateClient(
            check: { _ in throw ForceUpdateError.networkError("timeout") }
        )

        do {
            _ = try await client.check("https://api.example.com")
            XCTFail("エラーがスローされるべき")
        } catch let error as ForceUpdateError {
            XCTAssertEqual(error, .networkError("timeout"))
        }
    }
}
```

- [ ] **Step 2: テストを実行して PASS を確認**

```
swift test --package-path repository/ios/SoyokaModules --filter ForceUpdateE2ETests
```

Expected: 全テスト PASS

- [ ] **Step 3: AppReducer に State/Action を追加**

`repository/ios/SoyokaApp/SoyokaApp.swift` を以下のように変更:

**import 追加:**

```swift
import InfraNetwork  // 既存 import の末尾に追加
```

**State に追加** (`settings` の後):

```swift
        var forceUpdateStoreURL: URL?
        var lastForceUpdateCheck: Date?
```

**Action に追加** (`aiProcessingCompleted` の後):

```swift
        case scenePhaseChanged(ScenePhase)
        case forceUpdateCheckResponse(Result<ForceUpdateStatus, Error>)
```

**Dependency 追加** (`aiProcessingQueue` の後):

```swift
    @Dependency(\.forceUpdateClient) var forceUpdateClient
    @Dependency(\.date.now) var now
```

**Reduce 内に追加** (`case let .tabSelected(tab):` の前に):

```swift
            // MARK: - 強制アップデートチェック

            case .scenePhaseChanged(.active):
                // スロットル: 前回チェックから5分未満ならスキップ
                if let lastCheck = state.lastForceUpdateCheck,
                   now.timeIntervalSince(lastCheck) < 300 {
                    return .none
                }
                state.lastForceUpdateCheck = now
                return .run { [forceUpdateClient] send in
                    await send(.forceUpdateCheckResponse(
                        Result { try await forceUpdateClient.check("https://api.soyoka.app") }
                    ))
                }

            case .scenePhaseChanged:
                return .none

            case let .forceUpdateCheckResponse(.success(status)):
                switch status {
                case .upToDate:
                    state.forceUpdateStoreURL = nil
                case let .updateRequired(storeURL):
                    state.forceUpdateStoreURL = storeURL
                }
                return .none

            case .forceUpdateCheckResponse(.failure):
                // ネットワークエラー時はブロックしない
                return .none
```

**既存の `.recording(.recordingSaved)` case の先頭にバージョンチェックを merge:**

録音完了時ではなく、`case .recording:` の直前（既存コードは変更不要）。

代わりに、AppView の `onAppear` から `.scenePhaseChanged(.active)` を送信してアプリ起動時チェックを実現する（Step 4 で実装）。

- [ ] **Step 4: AppView にオーバーレイと scenePhase を追加**

`repository/ios/SoyokaApp/SoyokaApp.swift` の `AppView` を以下のように変更:

```swift
struct AppView: View {
    @Bindable var store: StoreOf<AppReducer>
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            TabView(selection: $store.selectedTab.sending(\.tabSelected)) {
                // ホームタブ: 録音画面
                NavigationStack {
                    RecordingView(
                        store: store.scope(state: \.recording, action: \.recording)
                    )
                    .navigationTitle("つぶやき")
                    .navigationBarTitleDisplayMode(.large)
                }
                .tabItem { Label("つぶやき", systemImage: "bubble.left.fill") }
                .tag(AppReducer.State.Tab.home)

                // メモ一覧タブ
                MemoListView(
                    store: store.scope(state: \.memoList, action: \.memoList)
                )
                .tabItem { Label("きおく", systemImage: "book.fill") }
                .tag(AppReducer.State.Tab.memoList)

                // 設定タブ
                SettingsView(
                    store: store.scope(state: \.settings, action: \.settings)
                )
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(AppReducer.State.Tab.settings)
            }
            .tint(Color.vmPrimary)

            // 強制アップデートオーバーレイ
            if let storeURL = store.forceUpdateStoreURL {
                ForceUpdateOverlay(storeURL: storeURL)
                    .transition(.opacity)
                    .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.forceUpdateStoreURL != nil)
        .preferredColorScheme(store.settings.themeType.colorScheme)
        .onOpenURL { url in
            store.send(.openURL(url))
        }
        .onChange(of: scenePhase) { _, newPhase in
            store.send(.scenePhaseChanged(newPhase))
        }
        .onAppear {
            // アプリ起動時のチェック（スロットル対象外にするため直接 .active を送る）
            store.send(.scenePhaseChanged(.active))
        }
    }
}
```

- [ ] **Step 5: ビルド確認**

Xcode MCP でビルド。

Expected: BUILD SUCCEEDED

- [ ] **Step 6: テストを実行**

```
swift test --package-path repository/ios/SoyokaModules --filter ForceUpdateE2ETests
swift test --package-path repository/ios/SoyokaModules --filter ForceUpdateClientTests
```

Expected: 全テスト PASS

- [ ] **Step 7: コミット**

```bash
git add repository/ios/SoyokaApp/SoyokaApp.swift \
       repository/ios/SoyokaModules/Tests/E2ETests/ForceUpdateE2ETests.swift
git commit -m "feat(ios): AppReducer に強制アップデートチェックを統合

- scenePhase(.active) でバージョンチェック発火（起動時 + フォアグラウンド復帰）
- 5分間スロットルで過剰なAPI呼び出しを防止
- ネットワークエラー時はブロックしない（UX方針準拠）
- ForceUpdateOverlay を ZStack 最前面に配置（閉じ不可）"
```

---

## Task 6: iOS — ForceUpdateClient の live 値を DI 登録

**Files:**
- Modify: `repository/ios/SoyokaApp/SoyokaApp.swift` または既存の Dependencies ファイル

- [ ] **Step 1: 既存の Dependencies ファイル構成を確認**

`repository/ios/SoyokaApp/` に `RecordingDependencies.swift`, `StorageDependencies.swift` がある。
ネットワーク系の DI 登録がどこにあるか確認する。

`RemotePromptClient` の live 登録場所を `grep` で探す:

```bash
grep -r "RemotePromptClient" repository/ios/SoyokaApp/ --include="*.swift" -l
```

同じファイルに `ForceUpdateClient` の live 登録を追加する。

- [ ] **Step 2: ForceUpdateClient の DependencyKey 登録を追加**

登録先ファイル（おそらく `NetworkDependencies.swift` or 該当ファイル）に以下を追加:

```swift
import InfraNetwork

extension ForceUpdateClient: DependencyKey {
    public static let liveValue = ForceUpdateClient.live()
}
```

もし `RemotePromptClient` の live 登録が見つからない場合、`SoyokaApp/` 直下に新規ファイルを作成:

```swift
// repository/ios/SoyokaApp/NetworkDependencies.swift

import InfraNetwork

extension ForceUpdateClient: DependencyKey {
    public static let liveValue = ForceUpdateClient.live()
}
```

- [ ] **Step 3: ビルド確認**

Xcode MCP でビルド。

Expected: BUILD SUCCEEDED

- [ ] **Step 4: コミット**

```bash
git add repository/ios/SoyokaApp/
git commit -m "feat(ios): ForceUpdateClient の live DI 登録

- DependencyKey.liveValue として ForceUpdateClient.live() を登録
- 本番環境で URLSession 経由のバージョンチェックが有効化"
```

---

## Task 7: 最終検証

- [ ] **Step 1: 全テスト実行**

```
swift test --package-path repository/ios/SoyokaModules
```

Expected: 全テスト PASS（既存 369 テスト + 新規テスト）

- [ ] **Step 2: Xcode ビルド + シミュレータ起動**

Xcode MCP で Soyoka アプリをビルド・実行。

確認事項:
- アプリが正常に起動する（KV 未設定のため強制アップデートは発動しない）
- コンソールログに `バージョンOK` または `networkError` が出力される（dev サーバーが起動していない場合はエラーだが、アプリはブロックされない）

- [ ] **Step 3: 最終コミット（必要な場合）**

変更がある場合のみ:

```bash
git add -A
git commit -m "chore: 強制アップデート機能の最終調整"
```
