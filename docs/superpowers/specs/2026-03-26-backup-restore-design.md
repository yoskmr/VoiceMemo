# Soyoka バックアップ/リストア機能 設計書

## Context

バンドルID変更（`io.murmurnote.app` → `app.soyoka`）により、旧アプリのSwiftDataコンテナが新アプリから参照不可になった。データ移行手段として、かつ永続的なバックアップ/リストア機能として実装する。

## 要件

- 全メモデータ（文字起こし、AI要約、感情分析、タグ）+ 音声ファイルをエクスポート可能
- ShareSheet 経由で共有（AirDrop、ファイルアプリ等）
- `.soyokabackup` カスタムファイルタイプで新アプリに関連付け
- 設定画面からのインポート + 外部ファイルタップによるインポートの2入口
- UUID ベースの重複チェック（既存データの上書き防止）
- TCA + Clean Architecture に準拠

## アーキテクチャ

### モジュール配置

```
FeatureSettings（UI層）
  └─ BackupReducer + BackupView
       ↓ uses
Domain（プロトコル層）
  ├─ BackupExportClient（protocol）
  └─ BackupImportClient（protocol）
       ↓ implemented by
InfraStorage（実装層）
  ├─ BackupExporter（JSON + ZIP生成）
  └─ BackupImporter（ZIP展開 + SwiftData書き込み）
```

### 依存方向

- FeatureSettings → Domain（プロトコル参照のみ）
- InfraStorage → Domain（プロトコル準拠）
- SoyokaApp → LiveDependencies で接続

### ZIP ライブラリ選択

**ZIPFoundation を採用する。**
- ライセンス: MIT（App Store 問題なし）
- バイナリサイズ: 約200KB（許容範囲）
- SPM 対応済み
- フォールバック案: Apple `libcompression` + `Foundation` での自前実装（ZIPFoundation に問題が見つかった場合のみ）

## エクスポートフロー

```
User: 設定 → きおくのバックアップ → バックアップを作成
  ↓
BackupReducer: .exportTapped
  ↓
BackupExportClient.export()
  ↓
1. SwiftData から全 VoiceMemoModel + 子モデル + TagModel を取得
2. Domain Entity に変換
3. BackupPayload struct にマッピング
4. Codable で JSON シリアライズ → metadata.json
5. Documents/Audio/ から音声ファイルを一時ディレクトリにコピー
6. 一時ディレクトリを ZIP 化 → {timestamp}.soyokabackup
7. URL を返却
  ↓
BackupReducer: ShareSheet を表示（fileURL）
  ↓
User: AirDrop / ファイルアプリに保存
  ↓
BackupReducer: ShareSheet の onDismiss で一時ファイルをクリーンアップ
```

### 一時ファイル管理

- 一時ファイルは `FileManager.default.temporaryDirectory` に配置
- エクスポート: ShareSheet の `onDismiss` コールバックで削除
- 実装では `defer { try? FileManager.default.removeItem(at: tempDir) }` を必ず使用
- エラー発生時も defer により確実にクリーンアップされる

## インポートフロー

### 入口1: 設定画面

```
User: 設定 → きおくのバックアップ → バックアップから復元
  ↓
BackupReducer: .importTapped → ファイルピッカー表示（UTType: .soyokaBackup）
  ↓
User: .soyokabackup ファイルを選択
  ↓
BackupReducer: .importFileSelected(url) → BackupImportClient.import(fileURL)
```

### 入口2: 外部ファイル（TCA スコープ委譲）

```
User: ファイルアプリ等で .soyokabackup をタップ
  ↓
iOS: Soyoka アプリを起動（onOpenURL）
  ↓
AppReducer: .openURL(url)
  ↓
AppReducer: .send(.settings(.backup(.importFromURL(url))))
  ↓
BackupReducer がインポート処理を実行（UI状態は BackupReducer が管理）
```

**注意**: AppReducer は直接 BackupImportClient を呼ばない。TCA のスコープを通じて BackupReducer に委譲する。インポートのUI状態（プログレス、完了アラート）は BackupReducer が保持する。

### インポート処理

```
BackupImportClient.import(fileURL):
  let tempDir = FileManager.default.temporaryDirectory.appending("backup-import")
  defer { try? FileManager.default.removeItem(at: tempDir) }

  1. ZIP を tempDir に展開
  2. metadata.json を読み取り・デコード → BackupPayload
  3. バージョンチェック（後述のポリシー参照）
  4. タグのインポート:
     a. バックアップのタグ名で既存タグを検索
     b. 名前一致 → 既存タグの UUID を採用（バックアップ UUID は破棄）
     c. 名前不一致 → 新規タグとして作成
     d. 名前→TagModel のルックアップテーブルを構築
  5. 各メモについて:
     a. UUID で既存データを検索
     b. 存在する場合 → スキップ（重複）
     c. 存在しない場合:
        - SwiftData に VoiceMemoModel + 子モデルを書き込み
        - tagNames をルックアップテーブルで TagModel に変換し、リレーション設定
        - 音声ファイルを Documents/Audio/ にコピー
        - audioFilePath は相対パス形式で保存（後述）
  6. FTS5 インデックスにインポートしたメモを登録
  7. インポート結果を返却（成功件数、スキップ件数）
```

## データフォーマット

### ファイル構造

```
{timestamp}.soyokabackup (ZIP)
├── metadata.json
└── audio/
    ├── {memo-uuid-1}.m4a
    ├── {memo-uuid-2}.m4a
    └── ...
```

### audioFilePath の仕様

**`audioFilePath` は常に相対パス形式 `Audio/{uuid}.m4a` で保存する。**

- エクスポート時: 絶対パスから `Audio/{uuid}.m4a` を抽出して JSON に書き込み
- インポート時: `Documents/Audio/` にコピー後、`Audio/{uuid}.m4a` を SwiftData に保存
- 再生時: `Documents` ディレクトリをベースに結合してフルパスを生成
- これにより異なるデバイスやアプリ再インストール後もパスが有効

### バージョン互換性ポリシー

```swift
let currentSupportedVersion = 1
```

- バックアップの `version` が `currentSupportedVersion` より **大きい場合のみ** エラー（「新しいバージョンのアプリが必要です」）
- `version` が `currentSupportedVersion` **以下** の場合は互換扱い
- 将来のスキーマ変更（version 2 等）でフィールド追加する場合、新フィールドは Optional とし、旧バージョンのバックアップでも読めるようにする
- `BackupPayload` の Codable デコードは未知フィールドを無視する（Swift の `Codable` デフォルト動作）

### metadata.json スキーマ

```json
{
  "version": 1,
  "exportedAt": "2026-03-26T12:00:00+09:00",
  "sourceApp": "Soyoka",
  "sourceBundleId": "io.murmurnote.app",
  "memos": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "title": "散歩中のアイデア",
      "createdAt": "2026-03-20T10:30:00+09:00",
      "updatedAt": "2026-03-20T10:35:00+09:00",
      "durationSeconds": 45.2,
      "audioFileName": "550e8400-e29b-41d4-a716-446655440000.m4a",
      "audioFormat": "m4a",
      "status": "completed",
      "isFavorite": false,
      "transcription": {
        "id": "...",
        "fullText": "今日は天気が良くて...",
        "language": "ja-JP",
        "engineType": "speech_analyzer",
        "confidence": 0.85,
        "processedAt": "2026-03-20T10:35:00+09:00"
      },
      "aiSummary": {
        "id": "...",
        "title": "散歩中の気づき",
        "summaryText": "天気の良い日に...",
        "keyPoints": ["ポイント1", "ポイント2"],
        "providerType": "on_device_apple_intelligence",
        "isOnDevice": true,
        "generatedAt": "2026-03-20T10:36:00+09:00"
      },
      "emotionAnalysis": {
        "id": "...",
        "primaryEmotion": "joy",
        "confidence": 0.72,
        "emotionScores": { "joy": 0.72, "calm": 0.20, "surprise": 0.08 },
        "evidence": [{ "text": "天気が良くて", "emotion": "joy" }],
        "analyzedAt": "2026-03-20T10:36:00+09:00"
      },
      "tagNames": ["アイデア", "散歩"]
    }
  ],
  "tags": [
    {
      "id": "...",
      "name": "アイデア",
      "colorHex": "#FF9500",
      "source": "ai",
      "createdAt": "2026-03-20T10:36:00+09:00"
    }
  ]
}
```

### Codable 実装の注意事項

**enum rawValue の整合性:**
- `engineType`: `STTEngineType` の rawValue をそのまま使用（`"speech_analyzer"`, `"whisper_kit"`, `"cloud_stt"`）
- `providerType`: `LLMProviderType` の rawValue をそのまま使用（`"on_device_apple_intelligence"`, `"on_device_llama_cpp"` 等）
- `primaryEmotion`: `EmotionCategory` の rawValue をそのまま使用
- `status`: `MemoStatus` の rawValue をそのまま使用
- `source`: `TagSource` の rawValue をそのまま使用
- `audioFormat`: `AudioFormat` の rawValue をそのまま使用

**emotionScores の Dictionary エンコード:**
- `BackupPayload` 内では `emotionScores` を `[String: Double]` 型で定義する
- エクスポート時: `EmotionAnalysisEntity.emotionScores: [EmotionCategory: Double]` → キーを `.rawValue` で String に変換
- インポート時: `[String: Double]` → `EmotionCategory(rawValue:)` でマッピング
- これにより JSON は `{ "joy": 0.72, ... }` の自然なオブジェクト形式になる

**keyPoints の Data 変換:**
- `AISummaryModel.keyPointsData: Data?` は内部で `[String]` を JSON エンコードしたもの
- `BackupPayload` 内では `keyPoints: [String]?` としてデコード済みの配列を直接保持

## タグの重複マージ戦略

メモは `tagNames: [String]` で参照し、タグマスタは `tags[]` で管理する。

**インポート時のルール:**
1. バックアップのタグを名前で既存 DB のタグと照合
2. **名前一致**: 既存タグの UUID を採用し、バックアップのタグ UUID は破棄する
3. **名前不一致**: バックアップのタグを新規作成（UUID もバックアップのものを使用）
4. メモの `tagNames` は名前ベースでタグを引き、SwiftData のリレーション（多対多）を設定

```
バックアップ: タグ「アイデア」(uuid: AAA)
既存DB:      タグ「アイデア」(uuid: BBB)
→ 既存の BBB を採用。メモには BBB のタグを関連付け。
```

## UI設計

### 設定画面への追加

```
設定
├── ...（既存項目）
├── きおくのバックアップ           ← 新規セクション
│   ├── バックアップを作成         → エクスポート処理 → ShareSheet
│   └── バックアップから復元       → ファイルピッカー → インポート処理
└── ...
```

### エクスポート中のUI

- プログレス表示（メモ数/音声ファイルコピー進捗）
- 完了時: ShareSheet 自動表示

### インポート中のUI

- プログレス表示（処理中メモ数）
- 完了時: アラート「N件のきおくを復元しました（M件はスキップ）」

**用語規約（terminology.md 準拠）:**
- 「メモ」→「きおく」
- 「録音」→「つぶやき」
- UIテキストでは上記の用語を使用すること

## エラーハンドリング

| エラー | 対応 |
|--------|------|
| ZIP 展開失敗 | アラート「ファイルが破損しています」 |
| JSON デコード失敗 | アラート「対応していないバックアップ形式です」 |
| バージョン不一致（version > currentSupportedVersion） | アラート「新しいバージョンのアプリが必要です」 |
| ディスク容量不足 | アラート「ストレージの空き容量が不足しています」 |
| 音声ファイル欠損 | 該当きおくは音声なしで復元、警告表示 |
| 一時ファイルクリーンアップ失敗 | ログ出力のみ（OS が tmp/ を自動クリーンアップ） |

## 新規ファイル一覧

| パス | 説明 |
|------|------|
| `Domain/Protocols/BackupExportClient.swift` | エクスポートプロトコル + DependencyKey |
| `Domain/Protocols/BackupImportClient.swift` | インポートプロトコル + DependencyKey |
| `Domain/ValueObjects/BackupPayload.swift` | Codable なバックアップデータ構造体 |
| `Domain/ValueObjects/BackupResult.swift` | インポート結果（成功/スキップ件数） |
| `InfraStorage/Backup/BackupExporter.swift` | エクスポート実装 |
| `InfraStorage/Backup/BackupImporter.swift` | インポート実装 |
| `FeatureSettings/Backup/BackupReducer.swift` | TCA Reducer |
| `FeatureSettings/Backup/BackupView.swift` | SwiftUI View |
| `Tests/FeatureSettingsTests/BackupReducerTests.swift` | Reducer テスト |
| `Tests/InfraStorageTests/BackupExporterTests.swift` | エクスポートテスト |
| `Tests/InfraStorageTests/BackupImporterTests.swift` | インポートテスト |

## 既存ファイル変更

| パス | 変更内容 |
|------|---------|
| `FeatureSettings/Settings/SettingsReducer.swift` | backup サブステート追加 |
| `FeatureSettings/Settings/SettingsView.swift` | バックアップセクション追加 |
| `SoyokaApp/SoyokaApp.swift` | onOpenURL → settings.backup に委譲 |
| `SoyokaApp/Info.plist` | UTType .soyokabackup 登録 |
| `SoyokaModules/Package.swift` | InfraStorage に ZIPFoundation 依存追加 |

## テスト計画

- BackupExporter: モックデータでエクスポート → ZIP 構造検証 + JSON の enum rawValue 正確性検証
- BackupImporter: テスト用 ZIP でインポート → SwiftData 検証
- BackupPayload Codable: emotionScores の [String: Double] ↔ [EmotionCategory: Double] 変換テスト
- BackupReducer: TCA TestStore で UI 状態遷移テスト
- 重複チェック: 同じデータを2回インポートしてスキップ確認
- タグマージ: 同名タグが既存にある場合の UUID 採用テスト
- 音声欠損時: metadata.json のみの ZIP でインポートして部分復元確認
- FTS5 再構築: インポート後に検索で該当メモがヒットすることを確認
- バージョン互換: version:2 の未来バックアップでエラー、version:1 で成功を確認

## 移行手順（一時的なバンドルID戻し）

1. `project.yml` の `PRODUCT_BUNDLE_IDENTIFIER` を `io.murmurnote.app` に一時変更
2. エクスポート機能付きでビルド → 実機インストール
3. エクスポート実行 → `.soyokabackup` ファイルをファイルアプリに保存
4. `project.yml` の `PRODUCT_BUNDLE_IDENTIFIER` を `app.soyoka` に戻す
5. インポート機能付きでビルド → 実機インストール
6. `.soyokabackup` ファイルをタップ or 設定からインポート
7. データ復元完了
