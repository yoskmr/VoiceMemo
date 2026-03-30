# Phase 3b: LLM ハイブリッド統合 設計書

## 概要

iOS アプリから Backend Proxy（Phase 3a）経由でクラウド LLM を呼び出し、オンデバイス LLM とのハイブリッドルーティングを実現する。録音完了後に自動で AI 処理（要約+タグ+感情分析）を実行し、結果をメモに保存する。

## スコープ

### 含む

| 機能 | 説明 |
|:-----|:-----|
| Backend Proxy HTTP クライアント | `api-dev.soyoka.app` への認証付きリクエスト（InfraNetwork） |
| クラウド LLM 統合 | Backend Proxy 経由で GPT-4o mini を呼び出し |
| Apple Intelligence 統合 | iOS 26+ / A17 Pro+ で Foundation Models API を使用（既存コード拡張） |
| llama.cpp 統合 | 非対応デバイス向けのオンデバイス LLM（Phi-3-mini Q4_K_M） |
| ハイブリッドルーティング | Apple Intelligence → llama.cpp → Cloud の優先順位で自動選択 |
| AI 処理キュー実装 | AIProcessingQueueClient の具体実装（メモ保存後の自動 AI 処理） |
| 感情分析対応 | 8カテゴリ感情分析をクラウド LLM で実行 |

### 含まない（Phase 3c / Phase 4）

| 機能 | 理由 |
|:-----|:-----|
| StoreKit 課金 | Phase 3c |
| Sign In with Apple | Phase 3c |
| クラウド高精度 STT | Pro 限定、Phase 3c |
| llama.cpp モデルの自動ダウンロード UI | Phase 4（MVP ではバンドル or 手動） |

## アーキテクチャ

### LLM プロバイダ選択フロー

```
録音完了 → AI処理キュー → プロバイダ選択
                              │
                              ├─ iOS 26+ && A17 Pro+ && 8GB+
                              │   → Apple Intelligence Foundation Models
                              │   （要約+タグのみ。感情分析はクラウドへ）
                              │
                              ├─ A16+ && 6GB+ && モデルDL済み
                              │   → llama.cpp (Phi-3-mini)
                              │   （要約+タグのみ。感情分析はクラウドへ）
                              │
                              └─ 上記以外 or オンライン時
                                  → Backend Proxy (GPT-4o mini)
                                  （要約+タグ+感情分析の統合処理）

※ オンデバイス処理後、オンライン時に感情分析のみクラウドで追加実行
※ クラウド障害時はオンデバイスにフォールバック（EC-010）
```

### モジュール構成

```
FeatureAI（AI処理キュー管理）
  ↓ Domain層プロトコル経由
InfraLLM（LLMプロバイダ選択 + オンデバイス処理）
  ├── OnDeviceLLMProvider（Apple Intelligence + llama.cpp）
  ├── CloudLLMProvider（Backend Proxy HTTP クライアント経由）NEW
  └── HybridLLMRouter（ルーティングロジック）NEW
InfraNetwork（Backend Proxy HTTP クライアント）
  ├── BackendProxyClient NEW
  └── KeychainManager（トークン保管、既存）
```

---

## 1. Backend Proxy HTTP クライアント（InfraNetwork）

### 新規ファイル
- `Sources/InfraNetwork/BackendProxyClient.swift`

### 実装内容

```swift
public struct BackendProxyClient: Sendable {
    /// デバイス認証（JWT 取得）
    /// - Parameters: deviceID, appVersion, osVersion
    public var authenticate: @Sendable (_ deviceID: String, _ appVersion: String, _ osVersion: String) async throws -> AuthResponse
    /// AI 処理リクエスト
    public var processAI: @Sendable (AIProcessRequest) async throws -> AIProcessResponse
    /// 使用量確認
    public var getUsage: @Sendable () async throws -> UsageResponse
}
```

**ベース URL**: `https://api-dev.soyoka.app`（環境切替可能）

**認証フロー**:
1. 初回: `POST /api/v1/auth/device` → JWT 取得 → Keychain 保存
2. 以降: Keychain から JWT 取得 → `Authorization: Bearer <JWT>` ヘッダー付与
3. 401 受信: 再認証（JWT 再取得）

**リクエスト/レスポンス**: Phase 3a 設計書の API 仕様に準拠。

---

## 2. クラウド LLM プロバイダ（InfraLLM）

### 新規ファイル
- `Sources/InfraLLM/CloudLLMProvider.swift`

### 実装内容

`LLMProviderClient` プロトコルに準拠し、BackendProxyClient を使ってクラウド LLM を呼び出す。

```swift
public final class CloudLLMProvider: @unchecked Sendable {
    private let proxyClient: BackendProxyClient

    public func process(_ request: LLMRequest) async throws -> LLMResponse
    public func processSentimentOnly(_ request: LLMRequest) async throws -> LLMSentimentResult
    public func isAvailable() async -> Bool  // ネットワーク到達性チェック
    public func providerType() -> LLMProviderType  // .cloudGPT4oMini
}
```

Note: `@unchecked Sendable` は既存の `OnDeviceLLMProvider` と同じパターン。

**感情分析**: クラウド LLM のみが対応。レスポンスの `sentiment` フィールドを `EmotionAnalysisEntity` に変換。

---

## 3. ハイブリッド LLM ルーター（InfraLLM）

### 新規ファイル
- `Sources/InfraLLM/HybridLLMRouter.swift`

### ルーティングロジック

```swift
public final class HybridLLMRouter: @unchecked Sendable {
    private let deviceChecker: DeviceCapabilityChecker
    private let onDeviceProvider: OnDeviceLLMProvider
    private let cloudProvider: CloudLLMProvider

    public func process(_ request: LLMRequest) async throws -> LLMResponse {
        // 1. オンデバイス処理を試行（要約+タグ）
        // Note: Phase 3b MVP では Apple Intelligence のみ。
        // llama.cpp は Phase 4 で追加（OnDeviceLLMProvider.isAvailable() が
        // Apple Intelligence 非対応デバイスでは false を返す）
        if await onDeviceProvider.isAvailable() {
            do {
                let onDeviceResult = try await onDeviceProvider.process(request)

                // 2. 感情分析はクラウドで追加実行（オンライン時 + ユーザー設定ON）
                if request.tasks.contains(.sentimentAnalysis),
                   await cloudProvider.isAvailable() {
                    let sentimentResult = try await cloudProvider.processSentimentOnly(request)
                    return onDeviceResult.merging(sentiment: sentimentResult)
                }
                return onDeviceResult
            } catch {
                // オンデバイス処理失敗 → クラウドにフォールバック（EC-010）
                if await cloudProvider.isAvailable() {
                    return try await cloudProvider.process(request)
                }
                throw error
            }
        }

        // 3. オンデバイス不可 → クラウドで全処理
        if await cloudProvider.isAvailable() {
            return try await cloudProvider.process(request)
        }

        // 4. 全て不可 → ネットワークエラー（deviceNotSupported ではない）
        throw LLMError.processingFailed("オンデバイスLLM非対応かつネットワーク不達")
    }
}
```

Note: `@unchecked Sendable` は既存の `OnDeviceLLMProvider` と同じパターン。

### フォールバック戦略

| 条件 | 処理 |
|:-----|:-----|
| Apple Intelligence 対応 + オンライン | オンデバイス（要約+タグ）+ クラウド（感情分析） |
| Apple Intelligence 対応 + オフライン | オンデバイス（要約+タグのみ）。感情分析は後でリトライ |
| llama.cpp 対応 + オンライン | オンデバイス（要約+タグ）+ クラウド（感情分析） |
| llama.cpp 対応 + オフライン | オンデバイス（要約+タグのみ） |
| 非対応デバイス + オンライン | クラウド（全処理） |
| 非対応デバイス + オフライン | エラー（後でリトライ） |
| クラウド障害 | オンデバイスにフォールバック（EC-010） |

---

## 4. AI 処理キュー具体実装

### 新規ファイル
- `Sources/InfraLLM/AIProcessingQueue.swift`

Note: `Data` レイヤーは既存の SPM モジュール構成に存在しない。`AIProcessingQueue` は LLM プロバイダと密接に連携するため `InfraLLM` モジュール内に配置する。

### 実装内容

`AIProcessingQueueClient` プロトコルの具体実装。

**処理フロー**:
1. `enqueueProcessing(memoID)`: メモ ID を受け取り、バックグラウンドで処理開始
2. VoiceMemoRepository からメモのテキストを取得
3. **ユーザー設定を参照**: 感情分析が有効（デフォルト無効, REQ-005 オプトイン）の場合のみ `.sentimentAnalysis` を `LLMRequest.tasks` に含める
4. HybridLLMRouter に LLMRequest を送信
5. 結果を VoiceMemoRepository に保存（AISummaryEntity, Tags, EmotionAnalysis）
6. `observeStatus(memoID)` でステータスを AsyncStream で配信

**感情分析オプトイン制御**:
```swift
// UserDefaults から感情分析設定を取得（デフォルト: false）
let sentimentEnabled = UserDefaults.standard.bool(forKey: "sentimentAnalysisEnabled")
var tasks: Set<LLMTask> = [.summarize, .tagging]
if sentimentEnabled {
    tasks.insert(.sentimentAnalysis)
}
```

**使用量カウント**:
- クラウド LLM を使用した場合のみ `quotaClient.recordUsage()` を呼び出す
- オンデバイス処理はカウント対象外（product-owner 判断 2026-03-28、REQ-003 注記参照）

**キュー管理**:
- Actor ベースで排他制御
- 同時実行数: 1（シリアル処理）
- リトライ: 自動リトライなし（手動リトライのみ）

---

## 5. 感情分析対応

### 変更ファイル
- `Sources/Domain/Protocols/LLMProviderClient.swift`（LLMTask に .sentimentAnalysis 追加 — 既に定義済みか確認）
- `Sources/Domain/Entities/EmotionAnalysisEntity.swift`（既存）

### LLMResponse 拡張

`LLMResponse` に感情分析結果フィールドを追加:
```swift
public struct LLMResponse: Equatable, Sendable {
    // 既存（let で統一 — 既存コード準拠）
    public let summary: LLMSummaryResult?
    public let tags: [LLMTagResult]
    public let processingTimeMs: Int
    public let provider: LLMProviderType
    // NEW
    public let sentiment: LLMSentimentResult?
}

public struct LLMSentimentResult: Equatable, Sendable {
    public let primary: EmotionCategory
    public let scores: [EmotionCategory: Double]
    public let evidence: [SentimentEvidence]
}
```

Note: `LLMTask` は既に `CaseIterable` に準拠。`.sentimentAnalysis` 追加時に `allCases` が変わるため、`allCases` を参照するテストコードの更新が必要。

---

## 6. llama.cpp 統合

### 方針

MVP では llama.cpp のフル統合は複雑なため、以下の段階的アプローチを取る:

**Phase 3b MVP**: Apple Intelligence + Cloud の2択ルーティング。llama.cpp は `LLMModelManager` のスタブを維持し、Phase 4 で実装。

**理由**:
- llama.cpp の Swift バインディング（SPM パッケージ）の選定・統合に時間がかかる
- モデルファイル（2.5GB）のダウンロード・キャッシュ管理が複雑
- Apple Intelligence + Cloud で MVP のユーザー体験は十分

### llama.cpp を Phase 4 に回す影響

| デバイス | Phase 3b での動作 |
|:---------|:----------------|
| iPhone 15 Pro+ (A17, iOS 26+) | Apple Intelligence（オンデバイス） |
| iPhone 14 Pro (A16, 6GB) | Cloud のみ（オンデバイス不可） |
| iPhone 14 以前 | Cloud のみ |

A16 デバイスのオフライン時は AI 処理不可。Phase 4 で llama.cpp を追加すれば解決。

---

## 7. LiveDependencies 統合

### 変更ファイル
- `SoyokaApp/LiveDependencies.swift`（既存の依存注入ファイル群）

### 接続

```swift
// InfraNetwork
let proxyClient = BackendProxyClient.live(
    baseURL: "https://api-dev.soyoka.app",
    keychainManager: keychainManager
)

// InfraLLM
let cloudProvider = CloudLLMProvider(proxyClient: proxyClient)
let onDeviceProvider = OnDeviceLLMProvider()
let router = HybridLLMRouter(
    deviceChecker: DeviceCapabilityChecker(),
    onDeviceProvider: onDeviceProvider,
    cloudProvider: cloudProvider
)

// Data
let aiQueue = AIProcessingQueue(
    router: router,
    repository: voiceMemoRepository,
    quotaClient: aiQuotaClient
)
```

---

## 受入基準

1. 録音完了後に AI 処理が自動実行されること
2. AI 処理結果（要約+タグ）がメモ詳細画面に表示されること
3. オンライン時に感情分析結果が表示されること
4. Apple Intelligence 対応デバイスでオンデバイス処理が実行されること
5. 非対応デバイスでクラウド処理にフォールバックすること
6. クラウド障害時にオンデバイスにフォールバックすること（EC-010）
7. 月次使用量制限が機能すること（クラウド処理のみカウント。オンデバイス処理は無料。REQ-003 注記参照）
8. オフライン時にオンデバイス処理（要約+タグのみ）が動作すること
9. 感情分析がデフォルト無効で、ユーザー設定で有効化した場合のみ実行されること（REQ-005 オプトイン）
10. 全既存テストがパスすること
