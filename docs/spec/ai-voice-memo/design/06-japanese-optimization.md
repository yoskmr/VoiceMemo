# 日本語音声認識・テキスト最適化設計書

> **文書ID**: DES-006
> **バージョン**: 1.0
> **作成日**: 2026-03-30
> **ステータス**: ドラフト
> **準拠仕様書**: INT-SPEC-001 v1.0（統合インターフェース仕様書）
> **関連要件**: REQ-002, REQ-019, REQ-025, NFR-002

---

## 1. 全体構成と施策間依存関係

### 1.1 実装順序テーブル

| 順序 | ID | 施策名 | Phase | 工数見積 | 依存先 | リスク |
|:-----|:---|:-------|:------|:---------|:-------|:-------|
| 1 | **P0-0** | taskHint/addsPunctuation 追加 | Phase 2 | 0.5h | なし | 極小 |
| 2 | **P0-1** | スペース強制挿入修正 | Phase 2 | 2h | P0-0 | 小 |
| 3 | **P0-2** | 句読点自動挿入 | Phase 2 | 4h | P0-0, P0-1 | 中 |
| 4 | **P0-3** | フィラー除去レベル設定 | Phase 2 | 6h | P0-2 | 中 |
| 5 | **P1-4** | 日本語感情語彙（13感情） | Phase 3 | 8h | なし | 中 |
| 6 | **P1-5** | 口語→書き言葉LLMプロンプト | Phase 3 | 6h | P0-3 | 小 |
| 7 | **P1-7** | 日本語の主語補完AI | Phase 3 | 8h | P1-5 | 中 |
| 8 | **P2-8** | kotoba-whisper 評価 | Phase 4 | 16h | なし | 大 |
| 9 | **P2-9** | CoreML感情分析カスタムモデル | Phase 4 | 20h | P1-4 | 大 |
| 10 | **P3-6** | SFCustomLanguageModelData | 未定 | 12h | なし | 大（ROI不明） |

---

## 2. P0-0: AppleSpeechEngine taskHint/addsPunctuation 追加

### 概要

`AppleSpeechEngine.swift` の `SFSpeechAudioBufferRecognitionRequest` に2行追加で句読点自動挿入と認識精度を改善。全施策で最もROIが高い。

### 変更対象

**ファイル**: `Sources/InfraSTT/Engines/AppleSpeechEngine.swift` L145付近

```swift
let request = SFSpeechAudioBufferRecognitionRequest()
request.shouldReportPartialResults = true
request.taskHint = .dictation           // P0-0: 音声メモに最適な認識モード
request.addsPunctuation = true          // P0-0: 句読点自動挿入（iOS 16+）
```

### 技術的根拠

| 設定 | 効果 | iOS |
|:-----|:-----|:----|
| `taskHint = .dictation` | 認識モデルを長文口述向けに最適化 | 10+ |
| `addsPunctuation = true` | 句点（。）・読点（、）を自動挿入 | 16+ |

### 制約事項

- オンデバイスモード（`requiresOnDeviceRecognition = true`）では効果が限定的
- 読点の精度がやや低い → P0-2のルールベース挿入で補完

---

## 3. P0-1: スペース強制挿入修正

### 概要

Apple Speech Framework の日本語認識結果で、漢字-ひらがな境界に不要な半角スペースが挿入される問題を修正。

### 変更対象

**ファイル**: `Sources/Domain/UseCases/TextPreprocessor.swift`

```swift
/// 日本語テキスト中の不要なスペースを除去する
public static func removeUnnecessarySpaces(_ text: String) -> String {
    var result = text
    // 日本語文字間の半角スペースを除去
    let japanesePattern = "([\\p{Han}\\p{Hiragana}\\p{Katakana}]) ([\\p{Han}\\p{Hiragana}\\p{Katakana}])"
    result = result.replacingOccurrences(
        of: japanesePattern, with: "$1$2", options: .regularExpression
    )
    return result
}
```

### テスト

```swift
func test_removeUnnecessarySpaces_日本語文字間のスペース_除去される() {
    let input = "今日 は いい 天気 です"
    XCTAssertEqual(TextPreprocessor.removeUnnecessarySpaces(input), "今日はいい天気です")
}

func test_removeUnnecessarySpaces_英数字間のスペース_保持される() {
    let input = "iOS 17 のアプリ"
    XCTAssertEqual(TextPreprocessor.removeUnnecessarySpaces(input), "iOS 17 のアプリ")
}
```

---

## 4. P0-2: 句読点自動挿入

### 概要

STTエンジン出力に句読点が不足する場合に、ルールベースで補完。P0-0の`addsPunctuation`と補完的に機能。

### 設計方針

1. **ポーズベース挿入**: 0.8秒以上のギャップ→句点、0.3-0.8秒→読点
2. **文末パターンマッチ**: 日本語の文末表現（「です」「ます」「ました」等）+ スペースで句点挿入
3. **LLM後処理との役割分担**: 高確信度パターンのみ処理、曖昧なケースはLLM委託

### 変更対象

**ファイル**: `Sources/Domain/UseCases/TextPreprocessor.swift`（新メソッド追加）

```swift
public static func insertPunctuation(
    _ text: String,
    segments: [TranscriptionSegment] = []
) -> String
```

---

## 5. P0-3: フィラー除去レベル設定

### フィラー除去レベル

| レベル | 名前 | 挙動 |
|:------|:-----|:-----|
| `.none` | 除去なし | フィラーを一切除去しない |
| `.light` | 軽度除去（デフォルト） | 思考中フィラーのみ除去（えーと、あのー、うーん） |
| `.aggressive` | 完全除去 | 口癖系・相槌系も含めて除去 |

### 変更対象

**新規ファイル**: `Sources/Domain/ValueObjects/FillerRemovalLevel.swift`

```swift
public enum FillerRemovalLevel: String, Codable, CaseIterable, Sendable {
    case none, light, aggressive
}
```

**既存変更**: `Sources/InfraLLM/TextPreprocessor.swift`

```swift
public static func removeFillers(_ text: String, level: FillerRemovalLevel = .light) -> String
```

### フィラー分類

| 優先度 | 種類 | 例 | `.light` | `.aggressive` |
|:------|:-----|:---|:--------:|:------------:|
| 高 | 思考中 | えーと、あのー、うーん | 除去 | 除去 |
| 中 | 口癖系 | なんか、まあ、こう | 保持 | 除去 |
| 低 | 相槌 | はい、そうですね | 保持 | 除去 |

---

## 6. P1-4: 日本語感情語彙（13感情）

### 13感情カテゴリ

| カテゴリ | 英語キー | 既存/新規 |
|:---------|:---------|:---------|
| 喜び | `joy` | 既存 |
| 安心 | `calm` | 既存 |
| 期待 | `anticipation` | 既存 |
| 悲しみ | `sadness` | 既存 |
| 不安 | `anxiety` | 既存 |
| 怒り | `anger` | 既存 |
| 驚き | `surprise` | 既存 |
| 中立 | `neutral` | 既存 |
| 感謝 | `gratitude` | **新規** |
| 達成感 | `achievement` | **新規** |
| 懐かしさ | `nostalgia` | **新規** |
| もやもや | `ambivalence` | **新規** |
| 決意 | `determination` | **新規** |

### 変更対象

**既存変更**: `Sources/Domain/ValueObjects/EmotionCategory.swift`

```swift
public enum EmotionCategory: String, Codable, CaseIterable, Sendable {
    case joy, calm, anticipation, sadness, anxiety, anger, surprise, neutral
    case gratitude, achievement, nostalgia, ambivalence, determination

    public static var legacyCategories: [EmotionCategory] {
        [.joy, .calm, .anticipation, .sadness, .anxiety, .anger, .surprise, .neutral]
    }
}
```

### 設計書整合性

- 02-ai-pipeline.md セクション4.1 の EmotionCategory を8→13に更新が必要
- 00-integration-spec.md セクション3.2 の EmotionCategory も同期更新が必要

---

## 7. P1-5: 口語→書き言葉LLMプロンプト

### WritingStyle 定義

| WritingStyle | 変換方向 |
|:------------|:--------|
| `.soft` | 話し言葉のニュアンスを残す |
| `.formal` | 「です・ます」調に統一 |
| `.casual` | 体言止め・SNS風 |
| `.reflection` | 手紙風・共感トーン　※品質改善まで実装保留 |
| `.essay` | 随筆風　※品質改善まで実装保留 |

> ※v1.4対応: `.reflection`（手紙）と `.essay`（随筆）はオンデバイスLLM（Phi-3-mini）での日本語文体変換品質が不十分なため、品質改善まで実装を保留する。UIでは「Coming Soon」として表示し、選択不可とする。`.soft`/`.formal`/`.casual` の3スタイルは無料ユーザーにも開放する。

### 変更対象

**新規ファイル**: `Sources/Domain/ValueObjects/WritingStyle.swift`
**既存変更**: `Sources/InfraLLM/PromptTemplate.swift`

---

## 8. P1-7: 日本語の主語補完AI

### 適用条件

| 場面 | 主語補完 | 理由 |
|:-----|:---------|:-----|
| 個人メモ閲覧 | しない | 省略が自然 |
| AI要約生成 | する | 要約は第三者が読む可能性 |
| エクスポート・共有 | オプション | 共有先での可読性向上 |

### 変更対象

**既存変更**: `Sources/InfraLLM/PromptTemplate.swift`
- `cloudIntegrated` プロンプトに主語補完指示を追加
- `writingStyle` が `.formal` または `.essay` の場合のみ有効化

---

## 9. P2-8: kotoba-whisper 評価

### CoreML版情報

| 項目 | 値 |
|:-----|:---|
| モデル名 | `yslinear/kotoba-whisper-v2.2-coreml` |
| 公開場所 | HuggingFace（CoreML変換済み） |
| ベースモデル | large-v3 蒸留（6.3倍高速） |
| 特徴 | 句読点サポート、話者分離 |

### initial_prompt の制約

| 制約 | 詳細 |
|:-----|:-----|
| **最初の30秒のみ有効** | 2番目以降のセグメントでは前セグメントのデコード結果で上書きされる |
| **トークン上限224** | Whisperのコンテキストウィンドウの半分 |
| **長時間録音への影響** | 30秒以降のセグメントでは効果が減衰 |

### 評価計画

| 評価項目 | 合格基準 |
|:---------|:---------|
| メモリ使用量 | iPhone 15（6GB）で安定動作 |
| 日本語CER | 既存WhisperKit small以下 |
| RTF | 0.3以下 |

---

## 10. P2-9: CoreML感情分析カスタムモデル

### モデル設計

| 項目 | 仕様 |
|:-----|:-----|
| 入力 | 日本語テキスト（最大500文字） |
| 出力 | 13カテゴリの確率分布 |
| ベースモデル | BERT-base-japanese ファインチューニング |
| モデルサイズ | 約100MB（FP16） |
| 推論時間 | < 200ms（A16以上） |

---

## 11. P3-6: SFCustomLanguageModelData（降格）

> **P1 → P3に降格**: STT技術調査（2026-03-30）に基づく判断

### 降格理由

| 理由 | 詳細 |
|:-----|:-----|
| 日本語での効果が限定的 | 漢字・ひらがな・カタカナ混在により英語ほどの効果がない |
| SpeechAnalyzer（iOS 26+）と非互換 | `SFSpeechRecognizer` 専用APIで iOS 26+ では利用不可 |
| 投資対効果が低い | 工数12hに対し明確な改善が見込めない |

### SpeechAnalyzer の contextualStrings 非対応

`SpeechAnalyzerEngine.swift` L282-285 の `setCustomDictionary` は no-op。LLM後処理による固有名詞補正が正しいアプローチ。

### 再評価条件

- Apple が SpeechAnalyzer 向けカスタム言語モデルAPIを公開した場合
- 日本語向け X-SAMPA 発音定義の公式ガイダンスが提供された場合

---

## 12. 共通設定モデル

**新規ファイル**: `Sources/Domain/ValueObjects/JapaneseOptimizationSettings.swift`

```swift
public struct JapaneseOptimizationSettings: Codable, Equatable, Sendable {
    public var fillerRemovalLevel: FillerRemovalLevel = .light
    public var writingStyle: WritingStyle = .soft
    public var subjectCompletionEnabled: Bool = false
    public var punctuationInsertionEnabled: Bool = true
}
```

---

## 13. データフロー全体図

```
マイク入力
  ↓
AVAudioEngine (PCM 16kHz Mono)
  ↓
STTEngine選択
  ├── iOS 26+: SpeechAnalyzer
  └── iOS 17-25: AppleSpeechEngine + taskHint=.dictation + addsPunctuation=true (P0-0)
  ↓
生テキスト
  ↓ テキスト後処理パイプライン
  ├── [P0-1] スペース除去
  ├── [P0-2] 句読点挿入
  ├── [P0-3] フィラー除去（レベル設定）
  ├── 句読点正規化（既存）
  ├── カスタム辞書置換（既存）
  ↓
整形テキスト → SwiftData 保存
  ↓ LLM後処理
  ├── [P1-5] WritingStyle に応じた清書プロンプト
  ├── [P1-7] 主語補完（.formal/.essay のみ）
  ├── [P1-4] 感情分析（13カテゴリ）
  ↓
AI処理結果 → SwiftData 更新
```

---

## 14. 設計書整合性

### 他設計書への要求変更

| 対象 | 変更内容 | トリガー |
|:-----|:---------|:---------|
| 02-ai-pipeline.md セクション4.1 | EmotionCategory 8→13段階 | P1-4 |
| 02-ai-pipeline.md セクション2.5 | TextPostProcessingPipeline にスペース除去・句読点挿入追加 | P0-1, P0-2 |
| 02-ai-pipeline.md セクション6 | PromptTemplate に WritingStyle・主語補完追加 | P1-5, P1-7 |
| 00-integration-spec.md セクション3.2 | EmotionCategory enum 更新 | P1-4 |
| 04-ui-design-system.md | EmotionBadge 新規5カテゴリ追加 | P1-4 |

---

## 15. モジュール別変更サマリ

| モジュール | 変更ファイル | 施策 | 種別 |
|:----------|:-----------|:-----|:-----|
| InfraSTT | `AppleSpeechEngine.swift` | P0-0 | 修正（2行） |
| Domain | `TextPreprocessor.swift` | P0-1,P0-2,P0-3 | 拡張 |
| Domain | `FillerRemovalLevel.swift` | P0-3 | 新規 |
| Domain | `WritingStyle.swift` | P1-5 | 新規 |
| Domain | `JapaneseOptimizationSettings.swift` | 共通 | 新規 |
| Domain | `EmotionCategory.swift` | P1-4 | 修正 |
| InfraLLM | `PromptTemplate.swift` | P1-5,P1-7 | 拡張 |
| FeatureSettings | `SettingsReducer.swift` | P0-3,P1-5 | 拡張 |
| SharedUI | `EmotionBadge.swift` | P1-4 | 修正 |

---

## 16. テスト影響分析

### 新規テスト見積

| テストファイル | 施策 | テスト数 |
|:-------------|:-----|:--------|
| TextPreprocessorTests | P0-1,P0-2,P0-3 | 15件 |
| FillerRemovalLevelTests | P0-3 | 5件 |
| WritingStyleTests | P1-5 | 5件 |
| EmotionCategoryTests | P1-4 | 8件 |
| JapaneseOptimizationSettingsTests | 共通 | 3件 |

### 既存テストへの影響

| テストファイル | 影響 | 対応 |
|:-------------|:-----|:-----|
| TextPreprocessorTests | `removeFillers` にlevelパラメータ追加 | デフォルト値あり、既存テスト動作 |
| EmotionCategory参照テスト | CaseIterable件数 8→13 | 件数アサーション更新 |
