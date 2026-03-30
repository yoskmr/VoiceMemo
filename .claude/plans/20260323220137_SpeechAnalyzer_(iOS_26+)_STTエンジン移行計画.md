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
- `SpeechAnalyzer.bestAvailableAudioFormat` で最適フォーマット取得
- audioStream から受け取った PCMBuffer をフォーマット変換 → SpeechAnalyzer にフィード
- volatile結果 → `TranscriptionResult(isFinal: false)`、final結果 → `isFinal: true`
- `AssetInventory` で言語パックDL管理
- `setCustomDictionary` は no-op（後処理で対応）
- `@available(iOS 26.0, *)` + `@unchecked Sendable` + NSLock

参考: `AppleSpeechEngine.swift` のパターンを踏襲（セッション再起動は不要、SpeechAnalyzerは1分制限なし）

### TASK-SA-002: AVAudioEngineRecorder のデシメーション削除
**変更**: `Sources/InfraSTT/Recording/AVAudioEngineRecorder.swift` (~40行)

- デシメーション処理（48kHz→16kHz変換）を削除
- ネイティブフォーマット（48kHz）のPCMバッファをそのまま yield
- サンプルレート変換はSTTエンジン側の責務に移行
- AAC録音は従来通り

### TASK-SA-009: Package.swift からWhisperKit依存削除
**変更**: `Package.swift` (~10行)

- `.package(url: "https://github.com/argmaxinc/WhisperKit", ...)` 削除
- `InfraSTT` ターゲットの WhisperKit 依存削除
- WhisperKitEngine.swift, MockWhisperKitEngine.swift 削除
- WhisperKitEngineTests.swift 削除

---

## Phase 2: 接続（Phase 1 完了後）

### TASK-SA-004: STTEngineFactory の更新
**変更**: `Sources/InfraSTT/STTEngineFactory.swift` (~15行)

```swift
case .speechAnalyzer:
    return SpeechAnalyzerEngine()  // iOS 26+ 前提
```

フォールバックチェーン: `[.speechAnalyzer]`（WhisperKit削除）

### TASK-SA-005: RecordingDependencies の更新
**変更**: `MurMurNoteApp/RecordingDependencies.swift` (~30行)

- WhisperKit 関連のインスタンス生成・分岐を削除
- `SpeechAnalyzerEngine()` を直接使用
- `STTEngineClient.liveValue` を簡素化

---

## Phase 3: AI後処理強化（独立、並行可能）

### TASK-SA-006: 固有名詞補正の強化
**変更ファイル**:
- `Domain/Services/PromptTemplate.swift` (~15行): 読みがな付きカスタム辞書をプロンプトに注入
- `Domain/Protocols/CustomDictionaryClient.swift` (~10行): `getDictionaryPairs() -> [(reading, display)]` 追加
- `Data/AIProcessingQueueLive.swift` (~5行): 新メソッド呼び出し

現在の `{custom_dictionary}` プレースホルダーに「読み → 正しい表記」ペアを含める:
```
正しい固有名詞: 鈴香（すずか）、城間（しろま）、糸村（いとむら）
```

---

## Phase 4: テストと整理（Phase 2 完了後）

### TASK-SA-008: テスト実装
**新規**: `Tests/InfraSTTTests/SpeechAnalyzerEngineTests.swift` (~150行)
- プロトコル適合、engineType、supportedLanguages、startTranscription、stopTranscription 等
- 既存 `AppleSpeechEngineTests.swift` のパターン踏襲

**変更**: `Tests/InfraSTTTests/STTEngineFactoryTests.swift` (~10行)

### TASK-SA-007: 旧コード削除
- `InfraSTT/Engines/WhisperKitEngine.swift` 削除 (-493行)
- `InfraSTT/Engines/MockWhisperKitEngine.swift` 削除 (-157行)
- `InfraSTT/Engines/AppleSpeechEngine.swift` 削除
- `Tests/InfraSTTTests/WhisperKitEngineTests.swift` 削除
- `Tests/InfraSTTTests/AppleSpeechEngineTests.swift` 削除

---

## 主要ファイル一覧

| ファイル | 操作 |
|:--------|:-----|
| `Sources/InfraSTT/Engines/SpeechAnalyzerEngine.swift` | **新規** |
| `Sources/InfraSTT/Recording/AVAudioEngineRecorder.swift` | 変更（デシメーション削除） |
| `Sources/InfraSTT/STTEngineFactory.swift` | 変更 |
| `MurMurNoteApp/RecordingDependencies.swift` | 変更 |
| `Domain/Services/PromptTemplate.swift` | 変更 |
| `Domain/Protocols/CustomDictionaryClient.swift` | 変更 |
| `Package.swift` | 変更（WhisperKit削除） |
| `Tests/InfraSTTTests/SpeechAnalyzerEngineTests.swift` | **新規** |
| `Sources/InfraSTT/Engines/WhisperKitEngine.swift` | **削除** |
| `Sources/InfraSTT/Engines/MockWhisperKitEngine.swift` | **削除** |
| `Sources/InfraSTT/Engines/AppleSpeechEngine.swift` | **削除** |

## 再利用する既存コード

- `STTEngineProtocol` (`Domain/Protocols/STTEngineProtocol.swift`): インターフェース変更なし
- `TranscriptionResult` / `TranscriptionSegment`: 型変更なし
- `STTEngineSelector`: ロジック変更なし（iOS 26+ → .speechAnalyzer は実装済み）
- `PromptTemplate.onDeviceSimple`: `{custom_dictionary}` プレースホルダー活用
- `CustomDictionaryClient`: 既存の `getContextualStrings()` に加えペア取得メソッド追加

## 見積もり

- **新規コード**: ~400行
- **削除コード**: ~800行
- **ネット**: 約-400行（コードベース削減）

## 検証方法

1. `swift test --filter SpeechAnalyzerEngineTests` で新エンジンの単体テスト
2. `swift test` で全テスト（387件）がパスすることを確認
3. Xcode MCP で `BuildProject` → ビルド成功確認
4. 実機テスト: 録音 → 日本語文字起こし → AI整理 のE2Eフロー確認
5. デバッグメニューでSTTエンジン表示が「SpeechAnalyzer」になることを確認
