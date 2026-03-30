# SpeechAnalyzer (iOS 26+) STTエンジン移行計画

## Context

WhisperKit base モデルでの日本語音声認識が実用レベルに達していない（hallucination多発、固有名詞認識不能）。iOS 26+ のみ対象とし、Apple SpeechAnalyzer を主STTエンジンに切り替える。既存の `STTEngineProtocol` に準拠した新エンジンを追加し、WhisperKit依存を削除する。

SpeechAnalyzer にはカスタム辞書機能がないため、既存のApple Foundation Models後処理パイプラインで固有名詞補正を強化する。

---

## Phase 1: 基盤実装（並行可能）

### TASK-SA-001: SpeechAnalyzerEngine 新規実装
**新規**: `Sources/InfraSTT/Engines/SpeechAnalyzerEngine.swift` (~250行)

`STTEngineProtocol` 準拠の新エンジン:
- `SpeechTranscriber(locale: ja_JP, preset: .progressiveLiveTranscription)` でストリーミング認識
- `SpeechAnalyzer.bestAvailableAudioFormat` で最適フォーマット取得 → 内部で `AVAudioConverter` 変換
- audioStream の PCMBuffer → フォーマット変換 → SpeechAnalyzer にフィード
- volatile結果 → `TranscriptionResult(isFinal: false)`、final結果 → `isFinal: true`
- `AssetInventory` で言語パックDL管理
- `setCustomDictionary` は no-op（後処理で対応）
- `@available(iOS 26.0, *)` + `@unchecked Sendable` + NSLock

**Sendable/Lock設計（Codexレビュー#6対応）**:
- lock保護対象: `analyzer`, `transcriber`, `lastResult`, `inputBuilder`
- `AsyncStream.onTermination` で analyzer セッション解放を保証
- start中のstop / stop中のstart は状態遷移テーブルで管理

**音声フォーマット変換（Codexレビュー#5対応）**:
- `AVAudioConverter` はセッション開始時に1回生成、セッション中再利用
- バッファ遅延時はドロップ（リアルタイム優先、欠落許容）
- 変換先フォーマット: `bestAvailableAudioFormat` の戻り値

参考: `AppleSpeechEngine.swift` のパターン踏襲（セッション再起動は不要）

### TASK-SA-002: AVAudioEngineRecorder のデシメーション削除
**変更**: `Sources/InfraSTT/Recording/AVAudioEngineRecorder.swift` (~40行)

- デシメーション処理（48kHz→16kHz変換）を削除
- ネイティブフォーマット（48kHz）のPCMバッファをそのまま yield
- サンプルレート変換はSTTエンジン側の責務に移行
- AAC録音は従来通り

### TASK-SA-009: Package.swift / ビルド設定の更新
**変更**: `Package.swift` (~15行)

- `.package(url: "https://github.com/argmaxinc/WhisperKit", ...)` 削除
- `InfraSTT` ターゲットの WhisperKit 依存削除
- **platforms を `.iOS(.v26)` に更新**（Codexレビュー#2対応: iOS 26+専用化を明示）
- WhisperKitEngine.swift, MockWhisperKitEngine.swift 削除

---

## Phase 2: 接続（Phase 1 完了後）

### TASK-SA-004: STTEngineFactory の更新（Codexレビュー#3対応）
**変更**: `Sources/InfraSTT/STTEngineFactory.swift` (~20行)

**Factory経由に統一**（直接具象を使わない）:
```swift
case .speechAnalyzer:
    return SpeechAnalyzerEngine()
case .whisperKit:
    return SpeechAnalyzerEngine()  // WhisperKit削除後はSpeechAnalyzerにフォールバック
case .cloudSTT:
    return SpeechAnalyzerEngine()
```

フォールバックチェーン簡素化: `[.speechAnalyzer]`
STTEngineSelector の WhisperKit 分岐を削除

### TASK-SA-005: RecordingDependencies + WelcomeView + SettingsView の更新
**変更ファイル（Codexレビュー#1,#3対応）**:
- `MurMurNoteApp/RecordingDependencies.swift` (~30行): **Factory経由**でエンジン解決に統一
- `MurMurNoteApp/WelcomeView.swift` (~40行): WhisperKitEngine直接参照を削除、SpeechAnalyzer言語パックDLに置換
- `Sources/FeatureSettings/Settings/SettingsView.swift` (~10行): デバッグメニューのSTTエンジン表示を「SpeechAnalyzer」に更新、UserDefaultsフラグ削除

RecordingDependencies は Factory 経由:
```swift
let factory = STTEngineFactory()
let (engine, _) = await factory.resolveEngine(context: context)
```

---

## Phase 3: AI後処理強化（独立、並行可能）

### TASK-SA-006: 固有名詞補正の強化（Codexレビュー#4対応）

**変更ファイル**:
- `Domain/Protocols/CustomDictionaryClient.swift` (~15行): `getDictionaryPairs() -> [(reading: String, display: String)]` 追加
- `Domain/Services/PromptTemplate.swift` (~20行): `buildUserPrompt` に reading ペア対応オーバーロード追加
- `Domain/Protocols/LLMProviderClient.swift` (~5行): `LLMRequest.customDictionaryPairs: [(String, String)]` フィールド追加（既存 `customDictionary: [String]` との互換維持）
- `Data/AIProcessingQueueLive.swift` (~10行): `getDictionaryPairs()` 呼び出し、LLMRequest に注入
- `InfraLLM/OnDeviceLLMProvider.swift` (~10行): 新フィールド利用

プロンプトへの注入形式:
```
正しい固有名詞（読み → 表記）: いとむら → 糸村、すずか → 鈴香、しろま → 城間
```

**互換性**: 既存の `customDictionary: [String]` は残し、新フィールドが空なら従来動作。

---

## Phase 4: テストと整理（Phase 2 完了後）

### TASK-SA-008: テスト実装（Codexレビュー#7対応）
**新規**: `Tests/InfraSTTTests/SpeechAnalyzerEngineTests.swift` (~200行)

正常系:
- プロトコル適合、engineType、supportedLanguages
- startTranscription → AsyncStream取得
- setCustomDictionary (no-op確認)

**異常系・並行系（Codexレビュー#7追加分）**:
- start→stop連打、二重start、stop中cancel の競合テスト
- stream termination時のリソース解放（analyzer/transcriber が nil化）
- AssetInventory未DL時の isAvailable → false
- finishTranscription未開始時 → STTError.engineNotInitialized

**変更**: `Tests/InfraSTTTests/STTEngineFactoryTests.swift` (~15行)
- `.speechAnalyzer` → `SpeechAnalyzerEngine` を返すことを確認

### TASK-SA-007: 旧コード削除（全テスト通過後）

**削除**:
- `Sources/InfraSTT/Engines/WhisperKitEngine.swift` (-493行)
- `Sources/InfraSTT/Engines/MockWhisperKitEngine.swift` (-157行)
- `Sources/InfraSTT/Engines/AppleSpeechEngine.swift` (-約280行)
- `Tests/InfraSTTTests/WhisperKitEngineTests.swift`
- `Tests/InfraSTTTests/AppleSpeechEngineTests.swift`
- `Info.plist` の `NSSpeechRecognitionUsageDescription`（SpeechAnalyzerはマイク権限のみ）

---

## 主要ファイル一覧

| ファイル | 操作 |
|:--------|:-----|
| `Sources/InfraSTT/Engines/SpeechAnalyzerEngine.swift` | **新規** |
| `Sources/InfraSTT/Recording/AVAudioEngineRecorder.swift` | 変更（デシメーション削除） |
| `Sources/InfraSTT/STTEngineFactory.swift` | 変更（Factory統一） |
| `MurMurNoteApp/RecordingDependencies.swift` | 変更（Factory経由） |
| `MurMurNoteApp/WelcomeView.swift` | 変更（WhisperKit参照削除） |
| `Sources/FeatureSettings/Settings/SettingsView.swift` | 変更（表示更新） |
| `Domain/Services/PromptTemplate.swift` | 変更（読みペア対応） |
| `Domain/Protocols/CustomDictionaryClient.swift` | 変更（ペア取得追加） |
| `Domain/Protocols/LLMProviderClient.swift` | 変更（ペアフィールド追加） |
| `Package.swift` | 変更（WhisperKit削除、iOS 26+） |
| `Tests/InfraSTTTests/SpeechAnalyzerEngineTests.swift` | **新規** |
| `Sources/InfraSTT/Engines/WhisperKitEngine.swift` | **削除** |
| `Sources/InfraSTT/Engines/MockWhisperKitEngine.swift` | **削除** |
| `Sources/InfraSTT/Engines/AppleSpeechEngine.swift` | **削除** |

## 再利用する既存コード

- `STTEngineProtocol` (`Domain/Protocols/STTEngineProtocol.swift`): インターフェース変更なし
- `TranscriptionResult` / `TranscriptionSegment`: 型変更なし
- `STTEngineSelector`: WhisperKit分岐削除のみ
- `PromptTemplate.onDeviceSimple`: `{custom_dictionary}` プレースホルダー活用
- `CustomDictionaryClient`: 既存の `getContextualStrings()` に加えペア取得メソッド追加
- `STTEngineFactory`: Factory経由のエンジン解決を維持

## 見積もり

- **新規コード**: ~450行
- **削除コード**: ~930行
- **ネット**: 約-480行（コードベース削減）

## 検証方法

1. `swift test --filter SpeechAnalyzerEngineTests` で新エンジンの単体テスト
2. `swift test` で全テストがパスすることを確認
3. Xcode MCP で `BuildProject` → ビルド成功確認
4. 実機テスト: 録音 → 日本語文字起こし → AI整理 のE2Eフロー確認
5. デバッグメニューでSTTエンジン表示が「SpeechAnalyzer」になることを確認
6. start/stop連打テスト（リソースリーク検証）
