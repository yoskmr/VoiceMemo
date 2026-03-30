# 強制アップデート機能 設計書

## 概要

Soyoka iOS アプリに強制アップデート機能を導入する。既存の Cloudflare Workers バックエンドに軽量なバージョンチェックエンドポイントを追加し、iOS 側でフルスクリーンブロックUIを表示する。

### 目的

- クリティカルなバグ修正時に旧バージョンの使用を防止する
- バックエンドの破壊的 API 変更時に旧クライアントを遮断する

### スコープ外

- 推奨アップデート（スキップ可能な通知）は対象外。強制のみ
- マスコットキャラクター等のイラスト。テキストベースのUIのみ

---

## アーキテクチャ

```
┌─────────────────────────────────────┐
│  Cloudflare KV                      │
│  key: "minimum_app_version"         │
│  value: "1.1.0"                     │
└────────────┬────────────────────────┘
             │
   GET /api/v1/version/check
             │
┌────────────▼────────────────────────┐
│  iOS App                            │
│                                     │
│  AppReducer                         │
│    ├─ onAppear → バージョンチェック  │
│    └─ scenePhase(.active) → 同上    │
│                                     │
│  ForceUpdateClient (InfraNetwork)   │
│    └─ check() → ForceUpdateStatus   │
│                                     │
│  ForceUpdateOverlay (SharedUI)      │
│    └─ フルスクリーン・閉じ不可      │
└─────────────────────────────────────┘
```

---

## 1. バックエンド（Cloudflare Workers）

### 1.1 新規エンドポイント

```
GET /api/v1/version/check
```

- **認証**: 不要（公開エンドポイント）
- **レート制限**: 120 req/min per IP（既存のレート制限基盤を流用）

### 1.2 レスポンス

```json
{
  "minimum_version": "1.0.0",
  "store_url": "https://apps.apple.com/app/idXXXXXXXX"
}
```

| フィールド | 型 | 説明 |
|:----------|:---|:----|
| `minimum_version` | `string` | semver 形式の最低必須バージョン |
| `store_url` | `string` | App Store の直リンク |

### 1.3 データソース

- **Cloudflare KV** namespace: `APP_CONFIG`
  - key: `minimum_app_version` → value: `"1.0.0"`
  - key: `app_store_url` → value: `"https://apps.apple.com/app/idXXXXXXXX"`
- KV の値を更新するだけでデプロイ不要で即時反映（TTL: なし、即時伝播）

### 1.4 バリデーション

- レスポンスの `minimum_version` が semver として不正な場合、`500` を返す
- KV に値が存在しない場合、デフォルト `"1.0.0"` を返す（アップデート不要扱い）

### 1.5 ルーティング

```typescript
// src/routes/version.ts
app.get("/api/v1/version/check", async (c) => {
  const minimumVersion = await c.env.APP_CONFIG.get("minimum_app_version") ?? "1.0.0"
  const storeUrl = await c.env.APP_CONFIG.get("app_store_url") ?? ""
  return c.json({ minimum_version: minimumVersion, store_url: storeUrl })
})
```

---

## 2. iOS クライアント

### 2.1 ForceUpdateClient（InfraNetwork モジュール）

TCA の `DependencyKey` として定義。

```swift
// InfraNetwork/ForceUpdateClient.swift

struct ForceUpdateClient {
    var check: @Sendable () async throws -> ForceUpdateStatus
}

enum ForceUpdateStatus: Equatable {
    case upToDate
    case updateRequired(storeURL: URL)
}
```

**内部ロジック:**
1. `GET /api/v1/version/check` を呼び出す
2. レスポンスの `minimum_version` と `Bundle.main` の `CFBundleShortVersionString` を semver 比較
3. 現在のバージョン < `minimum_version` なら `.updateRequired(storeURL:)` を返す
4. それ以外は `.upToDate` を返す

**semver 比較:** Foundation の `Bundle.main.infoDictionary` から取得し、ドット区切りで数値比較（major → minor → patch）。

### 2.2 スロットル

- フォアグラウンド復帰時のチェックは**最短5分間隔**に制限
- `UserDefaults` に最終チェック時刻を保存
- アプリ起動時（`onAppear`）は常にチェックする（スロットル対象外）

### 2.3 AppReducer への統合

```swift
// AppReducer 内の関連部分

case .onAppear:
    return .run { send in
        await send(.forceUpdateCheckResponse(
            Result { try await forceUpdateClient.check() }
        ))
    }

case .scenePhaseChanged(.active):
    // スロットル判定後にチェック
    guard shouldCheckForceUpdate() else { return .none }
    return .run { send in
        await send(.forceUpdateCheckResponse(
            Result { try await forceUpdateClient.check() }
        ))
    }

case .forceUpdateCheckResponse(.success(.updateRequired(let storeURL))):
    state.forceUpdate = ForceUpdateState(storeURL: storeURL)
    return .none

case .forceUpdateCheckResponse(.success(.upToDate)):
    state.forceUpdate = nil
    return .none

case .forceUpdateCheckResponse(.failure):
    // ネットワークエラー時はブロックしない
    return .none
```

**State の追加:**

```swift
@ObservableState
struct AppState {
    // ... 既存の状態 ...
    var forceUpdate: ForceUpdateState?
}

struct ForceUpdateState: Equatable {
    let storeURL: URL
}
```

### 2.4 ネットワークエラー時の挙動

- オフライン / タイムアウト / サーバーエラー → **ブロックしない**（`forceUpdate = nil` のまま）
- 理由: ネットワーク障害でアプリが使えなくなるのは UX 方針「ユーザーの操作を必要以上に止めない」に反する

---

## 3. UI（ForceUpdateOverlay）

### 3.1 レイアウト

```
┌─────────────────────────────────┐
│            StatusBar            │
│                                 │
│                                 │
│                                 │
│                                 │
│     アップデートが必要です        │  ← .title, .bold
│                                 │
│     最新バージョンに              │  ← .subheadline, .secondary
│     アップデートしてください。    │
│                                 │
│     ┌───────────────────┐       │
│     │   ストアを開く     │       │  ← プライマリボタン（アクセントカラー）
│     └───────────────────┘       │
│                                 │
│                                 │
│                                 │
└─────────────────────────────────┘
```

### 3.2 配置

- `AppView` の `ZStack` 最前面に `forceUpdate != nil` 時のみ表示
- `NavigationStack` や `TabView` よりも上のレイヤー
- `.interactiveDismissDisabled(true)` で閉じ不可
- 背景色: `Color(.systemBackground)`（ライト/ダークモード対応）

### 3.3 ボタンアクション

```swift
UIApplication.shared.open(storeURL)
```

- App Store アプリが開き、Soyoka のページに直接遷移
- ボタンタップ後もオーバーレイは表示されたまま（アプリに戻っても再表示）

### 3.4 アクセシビリティ

- VoiceOver: タイトル・説明テキスト・ボタンすべてにラベル付与
- Dynamic Type 対応

### 3.5 SharedUI モジュールへの配置

```
SharedUI/
  └─ ForceUpdate/
       └─ ForceUpdateOverlay.swift
```

---

## 4. テスト戦略

### 4.1 バックエンド

- KV に値がある場合のレスポンス検証
- KV に値がない場合のデフォルト値検証
- レート制限の動作検証

### 4.2 iOS

| テスト対象 | テスト内容 |
|:----------|:----------|
| ForceUpdateClient | semver 比較ロジック（1.0.0 < 1.1.0, 1.0.0 == 1.0.0, 2.0.0 > 1.9.9） |
| AppReducer | `.updateRequired` → `state.forceUpdate` が設定される |
| AppReducer | `.upToDate` → `state.forceUpdate` が nil |
| AppReducer | ネットワークエラー → `state.forceUpdate` が nil のまま |
| AppReducer | スロットル — 5分以内の再チェックがスキップされる |
| ForceUpdateOverlay | スナップショットテスト（ライト/ダーク） |

---

## 5. 運用

### 5.1 強制アップデートの発動手順

1. Cloudflare KV の `minimum_app_version` を新しいバージョンに更新
2. 即時反映（デプロイ不要）
3. ユーザーが次にアプリを開く or フォアグラウンド復帰した時点でブロック

### 5.2 強制アップデートの解除手順

1. KV の `minimum_app_version` を現行の最新バージョン以下に戻す
2. ユーザーが次にチェックした時点で自動解除

### 5.3 モニタリング

- Cloudflare Workers のダッシュボードでリクエスト数・エラー率を監視
- 異常なリクエスト増加時はレート制限で自動防御

---

## 6. 変更対象ファイル

### バックエンド（新規・変更）

| ファイル | 種別 | 内容 |
|:--------|:-----|:----|
| `repository/backend/src/routes/version.ts` | 新規 | バージョンチェックルート |
| `repository/backend/src/index.ts` | 変更 | ルート登録追加 |
| `repository/backend/wrangler.toml` | 変更 | KV namespace バインディング追加 |

### iOS（新規・変更）

| ファイル | 種別 | 内容 |
|:--------|:-----|:----|
| `SoyokaModules/Sources/InfraNetwork/ForceUpdateClient.swift` | 新規 | API クライアント |
| `SoyokaModules/Sources/SharedUI/ForceUpdate/ForceUpdateOverlay.swift` | 新規 | フルスクリーンUI |
| `SoyokaModules/Sources/Domain/Entities/ForceUpdateStatus.swift` | 新規 | ステータス enum |
| `SoyokaApp/SoyokaApp.swift` | 変更 | AppReducer にチェックロジック追加 |
| `SoyokaApp/LiveDependencies.swift` | 変更 | ForceUpdateClient の live 実装登録 |
| `SoyokaModules/Package.swift` | 変更 | モジュール依存調整（必要に応じて） |

### テスト（新規）

| ファイル | 種別 | 内容 |
|:--------|:-----|:----|
| `SoyokaModules/Tests/InfraNetworkTests/ForceUpdateClientTests.swift` | 新規 | semver 比較テスト |
| `SoyokaModules/Tests/AppReducerTests/ForceUpdateTests.swift` | 新規 | Reducer 統合テスト |
