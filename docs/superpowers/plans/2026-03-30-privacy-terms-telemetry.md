# プライバシーポリシー・利用規約・TelemetryDeck 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** プライバシーポリシー・利用規約のWebサイト公開、TelemetryDeck分析SDK導入、SubscriptionViewへのリンク追加を行う

**Architecture:** Cloudflare Pages で静的HTMLサイトを公開。TelemetryDeckは SharedUtil に AnalyticsClient プロトコルを定義し、SoyokaApp ターゲットで LiveValue を実装する TCA Dependency パターン。SubscriptionView に法的リンクを追加してApp Store審査要件を満たす。

**Tech Stack:** HTML/CSS（静的サイト）、TelemetryDeck SwiftSDK 2.x、swift-dependencies、TCA @Dependency

**Spec:** `docs/superpowers/specs/2026-03-29-privacy-terms-telemetry-design.md`

---

## File Map

```
新規作成:
  repository/terms_privacy/privacy.md          # 法的文書ソース（プライバシーポリシー）
  repository/terms_privacy/terms.md            # 法的文書ソース（利用規約）
  repository/soyoka_website/index.html         # トップページ
  repository/soyoka_website/privacy/index.html # プライバシーポリシーHTML
  repository/soyoka_website/terms/index.html   # 利用規約HTML
  repository/soyoka_website/style.css          # 共通スタイル
  repository/ios/SoyokaModules/Sources/SharedUtil/AnalyticsClient.swift  # プロトコル + DependencyKey
  repository/ios/SoyokaApp/LiveAnalyticsClient.swift                     # TelemetryDeck live実装

変更:
  repository/ios/SoyokaModules/Package.swift                             # SharedUtil に swift-dependencies 追加、Feature に SharedUtil 追加
  repository/ios/SoyokaApp/SoyokaApp.swift                               # TelemetryDeck 初期化
  repository/ios/SoyokaModules/Sources/FeatureSubscription/SubscriptionView.swift  # 法的リンク追加
  repository/ios/SoyokaModules/Sources/FeatureRecording/RecordingFeature.swift     # analytics イベント
  repository/ios/SoyokaModules/Sources/FeatureMemo/MemoList/MemoListReducer.swift  # analytics イベント
  repository/ios/SoyokaModules/Sources/FeatureMemo/MemoDetail/MemoDetailReducer.swift # analytics イベント
  repository/ios/SoyokaModules/Sources/FeatureMemo/MemoEdit/MemoEditReducer.swift  # analytics イベント
  repository/ios/SoyokaModules/Sources/FeatureSearch/SearchReducer.swift           # analytics イベント
  repository/ios/SoyokaModules/Sources/FeatureSettings/Settings/SettingsReducer.swift # analytics イベント
  repository/ios/SoyokaModules/Sources/FeatureSubscription/SubscriptionReducer.swift  # analytics イベント
```

---

## Task 1: 法的文書をリポジトリに配置

**Files:**
- Create: `repository/terms_privacy/privacy.md`
- Create: `repository/terms_privacy/terms.md`

- [ ] **Step 1: ディレクトリ作成と文書コピー**

```bash
mkdir -p /Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/terms_privacy
```

作成済みの法的文書をコピーする:

```bash
cp "/Users/y.itomura501/dev/mydev/test/VoiceMemo/works/20260329_05_プライバシーポリシー利用規約作成/result/privacy-policy.md" \
   /Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/terms_privacy/privacy.md

cp "/Users/y.itomura501/dev/mydev/test/VoiceMemo/works/20260329_05_プライバシーポリシー利用規約作成/result/terms-of-service.md" \
   /Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/terms_privacy/terms.md
```

- [ ] **Step 2: コピーされた内容を確認**

```bash
head -5 /Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/terms_privacy/privacy.md
head -5 /Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/terms_privacy/terms.md
```

Expected: 各ファイルの先頭5行が表示される（`# Soyoka プライバシーポリシー` / `# Soyoka 利用規約`）

- [ ] **Step 3: Commit**

```bash
cd /Users/y.itomura501/dev/mydev/test/VoiceMemo
git add repository/terms_privacy/privacy.md repository/terms_privacy/terms.md
git commit -m "docs(legal): プライバシーポリシー・利用規約のソースMarkdownを配置

- 競合5アプリの調査に基づき作成（Spokenly/Otter.ai/Aiko/Whisper Transcription/VOMO AI）
- APPI準拠、App Store Guideline 5.1.2(i) 対応
- TelemetryDeck利用分析の記載を含む"
```

---

## Task 2: Webサイト（静的HTML）を作成

**Files:**
- Create: `repository/soyoka_website/style.css`
- Create: `repository/soyoka_website/index.html`
- Create: `repository/soyoka_website/privacy/index.html`
- Create: `repository/soyoka_website/terms/index.html`

- [ ] **Step 1: ディレクトリ構造を作成**

```bash
mkdir -p /Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/soyoka_website/privacy
mkdir -p /Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/soyoka_website/terms
```

- [ ] **Step 2: 共通スタイルシートを作成**

`repository/soyoka_website/style.css` を作成する。モバイルファースト、シンプル、読みやすいデザイン:

```css
:root {
  --color-bg: #fafafa;
  --color-surface: #ffffff;
  --color-text: #1a1a1a;
  --color-text-secondary: #6b6b6b;
  --color-border: #e5e5e5;
  --color-primary: #5b7f6e;
  --max-width: 720px;
}

* { margin: 0; padding: 0; box-sizing: border-box; }

body {
  font-family: -apple-system, BlinkMacSystemFont, "Hiragino Sans", "Hiragino Kaku Gothic ProN", "Noto Sans JP", sans-serif;
  background: var(--color-bg);
  color: var(--color-text);
  line-height: 1.8;
  -webkit-text-size-adjust: 100%;
}

.container {
  max-width: var(--max-width);
  margin: 0 auto;
  padding: 2rem 1.5rem 4rem;
}

h1 { font-size: 1.5rem; margin-bottom: 0.5rem; }
h2 { font-size: 1.25rem; margin-top: 2.5rem; margin-bottom: 0.75rem; border-bottom: 1px solid var(--color-border); padding-bottom: 0.5rem; }
h3 { font-size: 1.1rem; margin-top: 1.5rem; margin-bottom: 0.5rem; }

p { margin-bottom: 1rem; }
ul, ol { margin-bottom: 1rem; padding-left: 1.5rem; }
li { margin-bottom: 0.25rem; }

table { width: 100%; border-collapse: collapse; margin-bottom: 1.5rem; font-size: 0.9rem; overflow-x: auto; display: block; }
th, td { border: 1px solid var(--color-border); padding: 0.5rem 0.75rem; text-align: left; }
th { background: var(--color-bg); font-weight: 600; white-space: nowrap; }

blockquote { border-left: 3px solid var(--color-primary); padding: 0.75rem 1rem; margin: 1rem 0; background: #f5f5f5; font-size: 0.95rem; }

a { color: var(--color-primary); }

.meta { color: var(--color-text-secondary); font-size: 0.85rem; margin-bottom: 2rem; }
.footer { margin-top: 3rem; padding-top: 1.5rem; border-top: 1px solid var(--color-border); color: var(--color-text-secondary); font-size: 0.8rem; text-align: center; }

hr { border: none; border-top: 1px solid var(--color-border); margin: 2rem 0; }

strong { font-weight: 600; }

@media (max-width: 600px) {
  .container { padding: 1.5rem 1rem 3rem; }
  h1 { font-size: 1.3rem; }
  h2 { font-size: 1.15rem; }
  table { font-size: 0.8rem; }
  th, td { padding: 0.4rem 0.5rem; }
}
```

- [ ] **Step 3: トップページを作成**

`repository/soyoka_website/index.html` を作成する:

```html
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Soyoka</title>
  <link rel="stylesheet" href="/style.css">
</head>
<body>
  <div class="container">
    <h1>Soyoka</h1>
    <p>AI音声メモアプリ</p>
    <hr>
    <ul>
      <li><a href="/privacy/">プライバシーポリシー</a></li>
      <li><a href="/terms/">利用規約</a></li>
    </ul>
    <div class="footer">
      <p>&copy; 2026 そよか運営チーム</p>
    </div>
  </div>
</body>
</html>
```

- [ ] **Step 4: プライバシーポリシーHTMLを作成**

`repository/terms_privacy/privacy.md` の内容をHTMLに変換し、`repository/soyoka_website/privacy/index.html` として保存する。

変換方法: pandoc を使用（インストール済みの場合）、または手動でHTML化する。

```bash
# pandoc がある場合
cd /Users/y.itomura501/dev/mydev/test/VoiceMemo
pandoc repository/terms_privacy/privacy.md \
  --standalone \
  --metadata title="プライバシーポリシー | Soyoka" \
  --css="/style.css" \
  --template=<(cat <<'TMPL'
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$title$</title>
<link rel="stylesheet" href="/style.css">
</head>
<body>
<div class="container">
$body$
<div class="footer">
<p><a href="/">Soyoka トップ</a></p>
<p>&copy; 2026 そよか運営チーム</p>
</div>
</div>
</body>
</html>
TMPL
) \
  -o repository/soyoka_website/privacy/index.html
```

pandoc がない場合は `brew install pandoc` でインストールするか、手動でMarkdownからHTMLを生成する。

- [ ] **Step 5: 利用規約HTMLを作成**

同様に `repository/terms_privacy/terms.md` をHTMLに変換:

```bash
cd /Users/y.itomura501/dev/mydev/test/VoiceMemo
pandoc repository/terms_privacy/terms.md \
  --standalone \
  --metadata title="利用規約 | Soyoka" \
  --css="/style.css" \
  --template=<(cat <<'TMPL'
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$title$</title>
<link rel="stylesheet" href="/style.css">
</head>
<body>
<div class="container">
$body$
<div class="footer">
<p><a href="/">Soyoka トップ</a></p>
<p>&copy; 2026 そよか運営チーム</p>
</div>
</div>
</body>
</html>
TMPL
) \
  -o repository/soyoka_website/terms/index.html
```

- [ ] **Step 6: ブラウザで表示確認**

```bash
open /Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/soyoka_website/index.html
open /Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/soyoka_website/privacy/index.html
open /Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/soyoka_website/terms/index.html
```

確認ポイント:
- テキストが読みやすいか
- テーブルが正しく表示されるか
- モバイル幅（Chrome DevTools で iPhone 15 等）で崩れないか
- リンクが正しく動作するか

- [ ] **Step 7: Commit**

```bash
cd /Users/y.itomura501/dev/mydev/test/VoiceMemo
git add repository/soyoka_website/
git commit -m "feat(web): soyoka.app 静的サイトを作成

- プライバシーポリシー・利用規約をHTML化
- モバイルファーストのレスポンシブデザイン
- Cloudflare Pages デプロイ用"
```

---

## Task 3: AnalyticsClient プロトコル定義（SharedUtil）

**Files:**
- Create: `repository/ios/SoyokaModules/Sources/SharedUtil/AnalyticsClient.swift`
- Modify: `repository/ios/SoyokaModules/Package.swift`

- [ ] **Step 1: Package.swift に swift-dependencies を SharedUtil に追加**

`repository/ios/SoyokaModules/Package.swift` の SharedUtil ターゲットを変更:

```swift
// 変更前:
.target(
    name: "SharedUtil",
    dependencies: [],
    plugins: []
),

// 変更後:
.target(
    name: "SharedUtil",
    dependencies: [
        .product(name: "Dependencies", package: "swift-dependencies"),
    ],
    plugins: []
),
```

- [ ] **Step 2: Package.swift に Feature モジュールへの SharedUtil 依存を追加**

analytics イベントを送信する Feature モジュールに SharedUtil を追加:

```swift
// FeatureRecording に SharedUtil 追加:
.target(
    name: "FeatureRecording",
    dependencies: [
        "Domain",
        "SharedUI",
        "SharedUtil",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
    ],
    plugins: []
),

// FeatureMemo に SharedUtil 追加:
.target(
    name: "FeatureMemo",
    dependencies: [
        "Domain",
        "SharedUI",
        "SharedUtil",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
    ],
    plugins: []
),

// FeatureSearch に SharedUtil 追加:
.target(
    name: "FeatureSearch",
    dependencies: [
        "Domain",
        "SharedUI",
        "SharedUtil",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
    ],
    plugins: []
),

// FeatureSubscription に SharedUtil 追加:
.target(
    name: "FeatureSubscription",
    dependencies: [
        "Domain",
        "SharedUI",
        "SharedUtil",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
    ],
    plugins: []
),
```

FeatureSettings は既に SharedUtil に依存しているので変更不要。

- [ ] **Step 3: AnalyticsClient.swift を作成**

`repository/ios/SoyokaModules/Sources/SharedUtil/AnalyticsClient.swift`:

```swift
import Dependencies

/// 匿名アプリ利用分析クライアント
/// TelemetryDeck への依存は SoyokaApp ターゲットの LiveValue に隔離する
public struct AnalyticsClient: Sendable {
    /// イベント名のみ送信
    public var send: @Sendable (_ event: String) -> Void
    /// イベント名 + パラメータ送信
    public var sendWithParameters: @Sendable (_ event: String, _ parameters: [String: String]) -> Void

    public init(
        send: @escaping @Sendable (_ event: String) -> Void,
        sendWithParameters: @escaping @Sendable (_ event: String, _ parameters: [String: String]) -> Void
    ) {
        self.send = send
        self.sendWithParameters = sendWithParameters
    }
}

// MARK: - DependencyKey

extension AnalyticsClient: DependencyKey {
    /// テスト時はイベントを無視する
    public static let liveValue = AnalyticsClient(
        send: { _ in },
        sendWithParameters: { _, _ in }
    )

    public static let testValue = AnalyticsClient(
        send: { _ in },
        sendWithParameters: { _, _ in }
    )
}

extension DependencyValues {
    public var analyticsClient: AnalyticsClient {
        get { self[AnalyticsClient.self] }
        set { self[AnalyticsClient.self] = newValue }
    }
}
```

- [ ] **Step 4: パッケージが解決されることを確認**

```bash
cd /Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/ios/SoyokaModules
swift package resolve
```

Expected: 正常に解決される（エラーなし）

- [ ] **Step 5: ビルド確認**

Xcode MCP または xcodebuild でビルドを確認:

```bash
cd /Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/ios
xcodebuild -project Soyoka.xcodeproj -scheme Soyoka -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
cd /Users/y.itomura501/dev/mydev/test/VoiceMemo
git add repository/ios/SoyokaModules/Package.swift
git add repository/ios/SoyokaModules/Sources/SharedUtil/AnalyticsClient.swift
git commit -m "feat(analytics): AnalyticsClient プロトコルを SharedUtil に定義

- TCA @Dependency パターンで DI 可能な分析クライアント
- テスト時はイベントを無視する testValue を提供
- Feature モジュールに SharedUtil 依存を追加"
```

---

## Task 4: LiveAnalyticsClient + TelemetryDeck 初期化（SoyokaApp）

**Files:**
- Create: `repository/ios/SoyokaApp/LiveAnalyticsClient.swift`
- Modify: `repository/ios/SoyokaApp/SoyokaApp.swift`

**前提:** TelemetryDeck SwiftSDK を Xcode プロジェクトに SPM パッケージとして追加する必要がある。

- [ ] **Step 1: Xcode で TelemetryDeck SwiftSDK を追加**

Xcode で `Soyoka.xcodeproj` を開き:
1. File > Add Package Dependencies...
2. URL: `https://github.com/TelemetryDeck/SwiftSDK`
3. Dependency Rule: Up to Next Major Version, 2.0.0
4. Add to Target: SoyokaApp

または `xcode-mcp-workflow` スキルを使用してビルド確認する。

- [ ] **Step 2: TelemetryDeck ダッシュボードでアプリを登録**

https://dashboard.telemetrydeck.com にアクセスし:
1. 新しいアプリを作成（名前: Soyoka）
2. APP ID をコピー

- [ ] **Step 3: LiveAnalyticsClient.swift を作成**

`repository/ios/SoyokaApp/LiveAnalyticsClient.swift`:

```swift
import Dependencies
import SharedUtil
import TelemetryDeck

extension AnalyticsClient {
    /// TelemetryDeck を使った本番用 AnalyticsClient
    static func live() -> Self {
        AnalyticsClient(
            send: { event in
                TelemetryDeck.signal(event)
            },
            sendWithParameters: { event, parameters in
                TelemetryDeck.signal(event, parameters: parameters)
            }
        )
    }
}
```

- [ ] **Step 4: SoyokaApp.swift に TelemetryDeck 初期化を追加**

`repository/ios/SoyokaApp/SoyokaApp.swift` の `SoyokaApp` 構造体の `init()` に追加（既存の init がない場合は作成）:

```swift
import TelemetryDeck

// @main struct の init() に以下を追加:
init() {
    let config = TelemetryDeck.Config(appID: "YOUR-APP-ID-FROM-DASHBOARD")
    TelemetryDeck.initialize(config: config)
}
```

`YOUR-APP-ID-FROM-DASHBOARD` は Step 2 で取得した APP ID に置き換える。

- [ ] **Step 5: AnalyticsClient の liveValue を上書き**

`repository/ios/SoyokaApp/SoyokaApp.swift` または適切な DI 設定ファイル（`LiveDependencies.swift` 等）で、AnalyticsClient の liveValue を上書き:

```swift
import SharedUtil

// LiveDependencies.swift または SoyokaApp.swift 内:
extension AnalyticsClient: @retroactive DependencyKey {
    public static let liveValue = AnalyticsClient.live()
}
```

**注意:** `@retroactive` は既に SharedUtil で `DependencyKey` 準拠を定義しているため必要。もし Swift 6.2 で `@retroactive` に問題がある場合は、SharedUtil 側の `liveValue` をデフォルト（noop）のままにし、SoyokaApp の DI 設定で `withDependencies` を使って上書きする方法もある。

- [ ] **Step 6: ビルド確認**

```bash
cd /Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/ios
xcodebuild -project Soyoka.xcodeproj -scheme Soyoka -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
cd /Users/y.itomura501/dev/mydev/test/VoiceMemo
git add repository/ios/SoyokaApp/LiveAnalyticsClient.swift
git add repository/ios/SoyokaApp/SoyokaApp.swift
git commit -m "feat(analytics): TelemetryDeck SDK を初期化し LiveAnalyticsClient を実装

- アプリ起動時に TelemetryDeck.initialize を実行
- AnalyticsClient.live() で TelemetryDeck.signal に橋渡し
- プライバシー重視の匿名分析（GDPR同意不要）"
```

---

## Task 5: 各 Reducer に analytics イベントを追加

**Files:**
- Modify: `repository/ios/SoyokaModules/Sources/FeatureRecording/RecordingFeature.swift`
- Modify: `repository/ios/SoyokaModules/Sources/FeatureMemo/MemoList/MemoListReducer.swift`
- Modify: `repository/ios/SoyokaModules/Sources/FeatureMemo/MemoDetail/MemoDetailReducer.swift`
- Modify: `repository/ios/SoyokaModules/Sources/FeatureMemo/MemoEdit/MemoEditReducer.swift`
- Modify: `repository/ios/SoyokaModules/Sources/FeatureSearch/SearchReducer.swift`
- Modify: `repository/ios/SoyokaModules/Sources/FeatureSettings/Settings/SettingsReducer.swift`
- Modify: `repository/ios/SoyokaModules/Sources/FeatureSubscription/SubscriptionReducer.swift`

各 Reducer に `@Dependency(\.analyticsClient) var analyticsClient` を追加し、対応するアクション内で `analyticsClient.send("event.name")` を呼び出す。

- [ ] **Step 1: RecordingFeature.swift にイベント追加**

`import SharedUtil` を追加し、Reducer body 内に `@Dependency(\.analyticsClient) var analyticsClient` を追加。以下のアクションにイベント送信を追加:

```swift
// recordButtonTapped で録音開始時:
analyticsClient.send("recording.started")

// recordingCompleted で録音完了時:
analyticsClient.send("recording.completed")

// transcriptionUpdated（最終テキスト確定時）:
// engine パラメータ付きで送信
analyticsClient.sendWithParameters("transcription.engineUsed", ["engine": "whisperkit"]) // or "apple"
```

- [ ] **Step 2: MemoListReducer.swift にイベント追加**

```swift
// memoTapped:
analyticsClient.send("memo.viewed")

// deleteConfirmed:
analyticsClient.send("memo.deleted")
```

- [ ] **Step 3: MemoDetailReducer.swift にイベント追加**

```swift
// onAppear:
analyticsClient.send("memo.viewed")
```

- [ ] **Step 4: MemoEditReducer.swift にイベント追加**

```swift
// saveTapped（編集保存時）:
analyticsClient.send("memo.edited")
```

- [ ] **Step 5: SearchReducer.swift にイベント追加**

```swift
// performSearch:
analyticsClient.send("search.performed")
```

- [ ] **Step 6: SettingsReducer.swift にイベント追加**

```swift
// onAppear:
analyticsClient.send("settings.opened")
```

- [ ] **Step 7: SubscriptionReducer.swift にイベント追加**

```swift
// onAppear:
analyticsClient.send("subscription.viewOpened")

// 購入成功時:
analyticsClient.sendWithParameters("subscription.purchased", ["plan": "monthly"]) // or "yearly"
```

- [ ] **Step 8: ビルド確認**

```bash
cd /Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/ios
xcodebuild -project Soyoka.xcodeproj -scheme Soyoka -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 9: 既存テストがパスすることを確認**

```bash
cd /Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/ios
xcodebuild -project Soyoka.xcodeproj -scheme SoyokaModules -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -10
```

Expected: 全テストパス。AnalyticsClient の testValue は noop なので既存テストに影響なし。

- [ ] **Step 10: Commit**

```bash
cd /Users/y.itomura501/dev/mydev/test/VoiceMemo
git add repository/ios/SoyokaModules/Sources/
git commit -m "feat(analytics): 各 Reducer に TelemetryDeck イベント送信を追加

- recording.started/completed: コア機能利用率
- transcription.engineUsed: STTエンジン選択傾向
- memo.viewed/edited/deleted: きおく操作
- search.performed: 検索利用率
- subscription.viewOpened/purchased: 課金ファネル
- settings.opened: 設定利用率"
```

---

## Task 6: SubscriptionView に法的リンクを追加

**Files:**
- Modify: `repository/ios/SoyokaModules/Sources/FeatureSubscription/SubscriptionView.swift`

- [ ] **Step 1: restoreSection の下に法的リンクを追加**

`SubscriptionView.swift` の `body` 内、`restoreSection` の下に `legalLinksSection` を追加:

```swift
// body の VStack 内、restoreSection の後に追加:
public var body: some View {
    ScrollView {
        VStack(spacing: VMDesignTokens.Spacing.xl) {
            headerSection
            featureComparisonSection
            planSelectionSection
            restoreSection
            legalLinksSection  // ← 追加
        }
        // ... 以下既存コード
    }
}
```

新しい computed property を追加:

```swift
// MARK: - Legal Links

private var legalLinksSection: some View {
    HStack(spacing: VMDesignTokens.Spacing.xs) {
        Link("プライバシーポリシー", destination: URL(string: "https://soyoka.app/privacy")!)
        Text("｜")
            .foregroundColor(.vmTextTertiary)
        Link("利用規約", destination: URL(string: "https://soyoka.app/terms")!)
    }
    .font(.vmCaption2)
    .foregroundColor(.vmTextTertiary)
}
```

- [ ] **Step 2: ビルド確認**

```bash
cd /Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/ios
xcodebuild -project Soyoka.xcodeproj -scheme Soyoka -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
cd /Users/y.itomura501/dev/mydev/test/VoiceMemo
git add repository/ios/SoyokaModules/Sources/FeatureSubscription/SubscriptionView.swift
git commit -m "feat(subscription): 課金画面にプライバシーポリシー・利用規約リンクを追加

- App Store 審査要件（課金画面での法的リンク表示）に対応
- 購入ボタン下部に小さなテキストリンクとして配置"
```

---

## Task 7: Cloudflare Pages へデプロイ（手動）

この Task はコード変更ではなく、Cloudflare ダッシュボードでの設定作業。

- [ ] **Step 1: Cloudflare Pages プロジェクトを作成**

1. https://dash.cloudflare.com にログイン
2. Workers & Pages > Create > Pages
3. 「Direct Upload」を選択（GitHub連携 or Direct Upload）
4. プロジェクト名: `soyoka-website`

- [ ] **Step 2: サイトをアップロード**

`repository/soyoka_website/` ディレクトリの内容をアップロード:
- Direct Upload の場合: ダッシュボードからフォルダをドラッグ&ドロップ
- Wrangler CLI の場合:

```bash
cd /Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/soyoka_website
npx wrangler pages deploy . --project-name=soyoka-website
```

- [ ] **Step 3: カスタムドメインを設定**

1. Cloudflare Pages プロジェクト > Custom domains
2. `soyoka.app` を追加
3. DNS 設定が自動で構成される（ドメインが既にCloudflare管理下のため）

- [ ] **Step 4: 動作確認**

ブラウザで以下のURLにアクセスし、正しく表示されることを確認:
- https://soyoka.app/
- https://soyoka.app/privacy/
- https://soyoka.app/terms/

モバイル表示（iPhone Safari）でも確認する。

---

## Task 8: App Store Connect プライバシーラベル更新（手動）

この Task はコード変更ではなく、App Store Connect での設定作業。

- [ ] **Step 1: App Store Connect にログイン**

https://appstoreconnect.apple.com > Soyoka > App Privacy

- [ ] **Step 2: データ収集の申告を更新**

以下のデータタイプを追加:

| カテゴリ | データタイプ | 用途 | ユーザーに紐付け | トラッキングに使用 |
|:--------|:----------|:-----|:-------------|:---------------|
| 識別子 | Device ID | アプリ機能 | いいえ | いいえ |
| 使用状況データ | Product Interaction | 分析 | いいえ | いいえ |

- [ ] **Step 3: プライバシーポリシーURLを確認**

App Store Connect > App Information > Privacy Policy URL が `https://soyoka.app/privacy` に設定されていることを確認。未設定の場合は設定する。

---

## 完了チェックリスト

- [ ] `https://soyoka.app/privacy` がブラウザで表示される
- [ ] `https://soyoka.app/terms` がブラウザで表示される
- [ ] TelemetryDeck ダッシュボードでシグナルが受信される（シミュレータで確認）
- [ ] SubscriptionView に法的リンクが表示される
- [ ] 設定画面の既存リンクが正しく動作する
- [ ] 全テストがパスする
- [ ] App Store Connect のプライバシーラベルが更新されている
