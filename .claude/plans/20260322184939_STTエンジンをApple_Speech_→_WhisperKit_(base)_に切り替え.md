# STTエンジンをApple Speech → WhisperKit (base) に切り替え

## Context

現在のApple SFSpeechRecognizerは固有名詞・カジュアル発話の認識精度が低く、「鈴鹿恵那付き」「城島」「余命家族」のような誤変換が頻発。WhisperKit（OpenAI Whisperのオンデバイス版）のbaseモデルに切り替えることで大幅な精度向上を見込む。

WhisperKitEngine.swift は**既に完全実装済み**（STTEngineProtocol準拠、チャンク処理、モデル管理、カスタム辞書対応）。切り替えは最小限の変更で可能。

## 変更内容

### 1. RecordingDependencies.swift（メイン変更）
`ios/MurMurNoteApp/RecordingDependencies.swift`

- `AppleSpeechEngine()` → `WhisperKitEngine(modelName: "openai_whisper-base")` に差し替え
- `setCustomDictionary` の接続も WhisperKitEngine に変更

```swift
// 変更前
let engine = AppleSpeechEngine()

// 変更後
let engine = WhisperKitEngine(modelName: "openai_whisper-base")
```

### 2. WhisperKitEngine.swift（モデル名デフォルト変更）
`ios/MurMurNoteModules/Sources/InfraSTT/Engines/WhisperKitEngine.swift`

- デフォルトモデル名: `"openai_whisper-small"` → `"openai_whisper-base"`
- 初回起動時にモデルが自動ダウンロードされる（WhisperKitConfig の `download: true` で対応済み）

### 3. AVAudioEngineRecorder のサンプルレート確認
`ios/MurMurNoteModules/Sources/InfraSTT/Recording/AVAudioEngineRecorder.swift`

- WhisperKitは16kHzを要求。AVAudioEngineRecorderが出力するPCMバッファのサンプルレートが16kHzか確認
- 異なる場合はリサンプリングが必要（WhisperKitEngine内で`extractFloatData`時に対応するか、レコーダー側で設定）

### 4. RecordingFeature のテキスト蓄積ロジック確認
`ios/MurMurNoteModules/Sources/FeatureRecording/RecordingFeature.swift`

- Apple Speechはセッション切れ（無音タイムアウト）で `isFinal` を送信 → RecordingFeature で蓄積管理
- WhisperKitは3秒チャンクで結果を返す → `isFinal` は最後のチャンクのみ
- RecordingFeature の `confirmedTranscription` 蓄積ロジックは `isFinal` に依存しているため、WhisperKitの挙動と整合するか確認が必要
- WhisperKitは毎チャンクが独立した認識結果のため、Apple Speechのような「リセット検出」は不要になる可能性

### 5. 初回モデルダウンロードのUX
- WhisperKit baseモデル: 約140MB
- 初回つぶやき時にダウンロードが自動実行される（WhisperKitConfig `download: true`）
- ダウンロード中はSTTが動かない → ユーザーに「初回はモデルをダウンロード中」と表示すべき
- **Phase 1**: ダウンロード中はApple Speechにフォールバック（または待機メッセージ表示）
- **将来**: 設定画面にモデルダウンロード状態を表示

## 変更ファイル一覧

| ファイル | 変更内容 |
|:---------|:---------|
| `ios/MurMurNoteApp/RecordingDependencies.swift` | AppleSpeech → WhisperKit差し替え |
| `ios/MurMurNoteModules/Sources/InfraSTT/Engines/WhisperKitEngine.swift` | デフォルトモデル名をbaseに変更 |
| `ios/MurMurNoteModules/Sources/InfraSTT/Recording/AVAudioEngineRecorder.swift` | サンプルレート確認・調整 |
| `ios/MurMurNoteModules/Sources/FeatureRecording/RecordingFeature.swift` | テキスト蓄積ロジックの調整（必要に応じて） |

## 検証方法

1. ビルド: `xcodebuild` でエラー0件
2. 実機テスト:
   - 初回起動 → モデルダウンロード完了を確認
   - つぶやき → 文字起こし精度がApple Speechより改善されているか
   - 「城間」「鈴香」「CBcloud」等の固有名詞が正しく認識されるか
   - 5分録音 → テキスト蓄積が正しく動作するか
3. テスト: `swift test` で既存テスト全パス（STTはモック経由のため影響なし）
