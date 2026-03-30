# Soyoka 日本語最適化提案

**作成日**: 2026-03-30
**前提**: 現在の実装分析 + 技術調査 + 競合分析に基づく

---

## 0. 現在の実装ギャップ（即座に修正すべきバグ）

### BUG-1: 日本語テキストへのスペース強制挿入

**ファイル**: `FeatureRecording/RecordingFeature.swift:247`

```swift
// 現在（バグ）
state.confirmedTranscription += text + " "

// 修正案
let separator = state.language.hasPrefix("ja") ? "" : " "
state.confirmedTranscription += text + separator
```

日本語は単語間にスペースを入れないため、現状「こんにちは 今日は いい天気 ですね」のような不自然な出力になっている。

---

## 1. STTエンジン層の日本語最適化（P0: 必須）

### 1.1 Apple Speech: SFCustomLanguageModelData の活用（iOS 17+）

**現状**: `contextualStrings` のみ使用
**提案**: iOS 17+の `SFCustomLanguageModelData` でカスタム言語モデルを構築

```swift
// カスタム言語モデル: 日本語の思考整理・感情表現に特化した語彙
let modelData = SFCustomLanguageModelData(
    locale: Locale(identifier: "ja-JP"),
    identifier: "com.soyoka.thought-journal",
    version: "1.0"
)

// 思考整理の語彙を追加
modelData.insert(["振り返り", "気づき", "モヤモヤ", "スッキリ"])
modelData.insert(["やりたいこと", "目標", "課題", "アイデア"])

// 感情表現の語彙を追加（日本語特有の微細な感情）
modelData.insert(["切ない", "懐かしい", "もどかしい", "ほっとする"])
modelData.insert(["しんどい", "ワクワク", "ドキドキ", "ソワソワ"])

// 人名・固有名詞のカスタム発音
modelData.insert(
    "Soyoka",
    pronunciation: "そよか",
    displayRepresentation: "Soyoka"
)
```

**効果**: 思考整理・感情表現の認識精度が大幅向上。競合との差別化。

### 1.2 WhisperKit: kotoba-whisper モデルの検討

**現状**: 標準Whisperモデル使用
**提案**: [kotoba-whisper](https://huggingface.co/kotoba-tech/kotoba-whisper-v2.2) を評価

| モデル | サイズ | 日本語CER | 速度 | 備考 |
|:-------|:------|:---------|:-----|:-----|
| whisper-large-v3 | 1.5GB | ベースライン | 1x | 汎用 |
| kotoba-whisper-v2.2 | ~500MB | large-v3同等 | **6.3x速い** | 日本語特化。句読点パイプライン内蔵 |

- kotoba-whisper-v2.2 は large-v3 の蒸留モデルで、**日本語精度を維持しつつ6.3倍高速**
- 句読点自動挿入 (`punctuators`) と話者分離 (`diarizers`) をパイプラインに内蔵
- **課題**: WhisperKit (CoreML) への変換が必要。要検証

### 1.3 Whisper: initial_prompt による日本語精度向上

**提案**: 文字起こし開始時に日本語スタイルを誘導する initial_prompt を設定

```swift
// 思考整理文脈での initial_prompt
let prompt = "今日の振り返りです。仕事で気づいたことを話します。"
```

- initial_prompt に句読点付きの日本語文を入れると、出力も句読点付きになりやすい
- 「思考整理」文脈のプロンプトにより、独り言・メモ調のテキストが自然になる
- **注意**: 効果は冒頭部分に限定される（長時間録音では減衰）

---

## 2. テキスト後処理の日本語最適化（P0: 必須）

### 2.1 句読点自動挿入

**現状**: 未実装（設計書に記載あり、LLM層に委譲予定）
**提案**: LLM呼び出し前にルールベースの軽量処理を追加

```swift
public struct JapanesePunctuationInserter {
    // 文末パターン: 述語の終止形 + 接続助詞で文区切りを推定
    static let sentenceEndPatterns = [
        "です", "ます", "ました", "でした",
        "だ", "った", "ない", "ません",
        "ている", "ていた", "ていない",
        "と思う", "と思います", "かな", "けど",
        "んだよね", "じゃないかな", "なんですよ",
    ]

    // 息継ぎ（無音区間 > 0.5秒）の位置に読点を挿入
    func insertPunctuation(
        text: String,
        silenceTimestamps: [TimeInterval]
    ) -> String { ... }
}
```

**段階的アプローチ**:
1. **Phase 1**: 無音区間ベースの読点挿入（STT層で実装可能）
2. **Phase 2**: ルールベースの句点挿入（文末パターンマッチ）
3. **Phase 3**: LLMによる高品質な句読点・改行の最適化

### 2.2 フィラー除去の拡充

**現状**: 20語のフィラー辞書（TextPreprocessor.swift）
**提案**: カテゴリ別に拡充 + 文脈依存の除去ロジック

```swift
// 追加すべきフィラー（カテゴリ別）
let additionalFillers: [String: [String]] = [
    // つなぎ系（ほぼ常に除去可能）
    "connector": ["えーと", "あのー", "なんか", "そのー", "ええと"],

    // 思考系（思考整理では残す選択肢も）
    "thinking": ["うーん", "なんだろう", "なんていうか"],

    // 相槌系（独り言では除去、対話では残す）
    "backchannel": ["うん", "ああ", "はい", "そうそう"],

    // 口癖系（個人差が大きい）
    "habit": ["やっぱ", "やっぱり", "まあ", "ほら", "こう",
              "なんか", "てか", "ていうか", "みたいな"],

    // 言い直し系（前の発話を取り消す）
    "correction": ["じゃなくて", "っていうか", "いや"],
]
```

**差別化ポイント**: ユーザー設定でフィラー除去レベルを選択可能に
- **レベル1（軽量）**: つなぎ系のみ除去
- **レベル2（標準）**: つなぎ + 口癖系を除去
- **レベル3（クリーン）**: 全カテゴリ除去
- **OFF**: 原文保持（日記としてリアルな記録を残したい場合）

### 2.3 口語→書き言葉変換（LLMプロンプト）

**提案**: AI要約時のプロンプトに日本語スタイル変換を組み込む

```
# 指示
以下の音声メモを、自然な書き言葉に整形してください。

## ルール
- 話し言葉の冗長な表現を簡潔にする
- 「〜な感じ」「〜的な」→ 具体的な表現に
- 主語が省略されている場合は文脈から補完する
- 敬語/タメ口の混在を統一する（ユーザー設定: {style}）
- 句読点を適切に挿入する
- 段落分けする（話題の転換点で改行）

## スタイル選択
- ですます調: 丁寧な記録
- だ/である調: 簡潔なメモ
- 箇条書き: アイデア整理向け
```

---

## 3. 日本語特化のプロダクト機能（P1: 差別化）

### 3.1 日本語感情分析（競合ゼロの領域）

**技術選択肢**:

| 手法 | 精度 | レイテンシ | プライバシー |
|:-----|:-----|:---------|:-----------|
| Apple NaturalLanguage (NLTagger) | 中（-1.0〜1.0のスコアのみ） | < 10ms | ◎ オンデバイス |
| LLMプロンプト | 高（7+感情分類可能） | 1-3秒 | △ API依存 |
| CoreML カスタムモデル | 高 | < 100ms | ◎ オンデバイス |

**推奨**: Phase 1は NLTagger（即座に実装可能）、Phase 2でLLMプロンプト、Phase 3でCoreMLカスタムモデル

**日本語特有の感情語彙**（競合にない粒度）:

```swift
enum JapaneseEmotion: String, CaseIterable {
    // 基本6感情（Voxly+と同等）
    case joy = "うれしい"
    case sadness = "悲しい"
    case anger = "怒り"
    case fear = "不安"
    case surprise = "驚き"
    case disgust = "嫌悪"

    // 日本語特有の感情（差別化）
    case setsunai = "切ない"        // bittersweet nostalgia
    case natsukashii = "懐かしい"    // nostalgic warmth
    case modokashii = "もどかしい"   // frustrating patience
    case hottosuru = "ほっとする"    // relief
    case wakuwaku = "ワクワク"      // excited anticipation
    case moyamoya = "モヤモヤ"      // vague unease
    case sukkiri = "スッキリ"       // refreshed clarity
}
```

### 3.2 「振り返り」テンプレート（日本の手帳文化との接点）

**KPT法テンプレート**:
```
Keep（続けたいこと）: ___
Problem（問題だったこと）: ___
Try（次に試したいこと）: ___
```

**YWT法テンプレート**:
```
Y（やったこと）: ___
W（わかったこと）: ___
T（次にやること）: ___
```

**実装**: 音声メモの AI要約時にテンプレート形式を選択可能にする

### 3.3 日本語の主語補完

日本語は主語を省略する傾向が強い。AI要約時に主語を補完：

```
入力: 「今日ミーティングあって、ちょっとモヤモヤした。なんか伝わってない気がして。」
↓ AI処理
出力: 「今日のミーティングでモヤモヤを感じた。自分の意見がチームに伝わっていないと感じている。」
```

---

## 4. 優先度マトリクス

| 優先度 | 施策 | 工数 | 効果 | 競合差別化 |
|:------|:-----|:-----|:-----|:---------|
| **P0** | BUG-1: スペース挿入修正 | 0.5h | 高 | - |
| **P0** | 句読点自動挿入（ルールベース） | 2-3日 | 高 | 中（無限もじおこしが先行） |
| **P0** | フィラー除去レベル設定 | 1日 | 高 | 高（レベル選択は競合なし） |
| **P1** | SFCustomLanguageModelData 導入 | 3-5日 | 中 | 高 |
| **P1** | 口語→書き言葉LLMプロンプト | 1-2日 | 高 | 高 |
| **P1** | 日本語感情語彙（NLTagger） | 2-3日 | 中 | **極高**（競合ゼロ） |
| **P1** | 振り返りテンプレート（KPT/YWT） | 1日 | 中 | 高（日本文化特化） |
| **P2** | kotoba-whisper モデル評価 | 1-2週 | 高 | 高 |
| **P2** | 日本語主語補完 | 3-5日 | 中 | 高 |
| **P2** | CoreML感情分析モデル | 2-3週 | 高 | **極高** |
| **P3** | 方言対応（関西弁等） | 2-4週 | 低 | ニッチだが独自性 |
| **P3** | 敬語⇔カジュアル自動変換 | 1-2週 | 低 | ニッチ |

---

## 5. 競合がやっていないこと → Soyokaの独自価値

| 施策 | なぜ競合がやらないか | Soyokaができる理由 |
|:-----|:-------------------|:-----------------|
| 日本語感情分析（切ない、モヤモヤ等） | グローバルアプリは英語ベースの6感情で十分 | 日本語特化だからこそ微細な感情を扱える |
| KPT/YWTテンプレート | 欧米では馴染みがない手法 | 日本のビジネス・自己啓発文化に根付いている |
| フィラー除去レベル選択 | 英語のフィラーは種類が少なく一律除去で十分 | 日本語のフィラーは多様で文脈依存 |
| 主語補完AI | 英語は主語必須なので不要 | 日本語の主語省略は文字起こしの読みにくさの主因 |
| SFCustomLanguageModelData | 汎用アプリでは特定領域の語彙強化は不要 | 「思考整理」特化だからこそ効果的 |

---

## Sources

- [SFCustomLanguageModelData - Apple Developer](https://developer.apple.com/documentation/speech/sfcustomlanguagemodeldata)
- [Customize on-device speech recognition - WWDC23](https://developer.apple.com/videos/play/wwdc2023/10101/)
- [SpeechModelBuilder (GitHub)](https://github.com/Compiler-Inc/SpeechModelBuilder)
- [kotoba-whisper-v2.2 (Hugging Face)](https://huggingface.co/kotoba-tech/kotoba-whisper-v2.2)
- [Best prompt to transcribe Japanese? (Whisper Discussion)](https://github.com/openai/whisper/discussions/2151)
- [NaturalLanguage Framework - Apple Developer](https://developer.apple.com/documentation/naturallanguage)
- [Explore Natural Language multilingual models - WWDC23](https://developer.apple.com/videos/play/wwdc2023/10042/)
- [iOS 26: SpeechAnalyzer Guide](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide)
- [contextualStrings - Apple Developer](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/contextualstrings)
- [Whisper punctuation improvement (OpenAI Cookbook)](https://cookbook.openai.com/examples/whisper_correct_misspelling)
