# Soyoka 日本語音声認識・文字起こし最適化 調査レポート

**調査日**: 2026-03-30
**対象アプリ**: Soyoka（iOS 17+ / Swift 6.2 / TCA）
**前提**: 既存調査（20260323_01, 20260323_02）の結果を踏まえた実装レベルの最適化提案

---

## 目次

1. [Apple Speech Framework の日本語最適化](#1-apple-speech-framework-の日本語最適化)
2. [WhisperKit / Whisper の日本語最適化](#2-whisperkit--whisper-の日本語最適化)
3. [日本語テキスト後処理](#3-日本語テキスト後処理)
4. [日本語NLP活用](#4-日本語nlp活用)
5. [Soyoka への具体的実装提案](#5-soyoka-への具体的実装提案)

---

## 1. Apple Speech Framework の日本語最適化

### 1.1 SFSpeechRecognizer の日本語固有設定（iOS 17-25）

現在の Soyoka の `AppleSpeechEngine` は基本的な設定で動作しているが、以下の最適化が可能。

#### ロケール設定

```swift
// 現状（OK）
let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))

// 補足: ja-JP は BCP47 形式。SFSpeechRecognizer は ja_JP も受け付けるが、
// BCP47 形式（ja-JP）の方が Apple の推奨
```

#### taskHint の設定

`SFSpeechRecognitionRequest` に `taskHint` を設定することで、認識モデルの挙動を最適化できる。

| taskHint | 用途 | Soyoka での適用 |
|:---------|:-----|:-------------|
| `.dictation` | 長文の口述（デフォルト） | 音声メモの通常録音に適合 |
| `.search` | 短い検索クエリ | 不適合 |
| `.confirmation` | Yes/No回答 | 不適合 |
| `.unspecified` | 汎用 | フォールバック用 |

**現状の実装への追加提案**:

```swift
// AppleSpeechEngine.swift の startRecognitionSession() 内
let request = SFSpeechAudioBufferRecognitionRequest()
request.shouldReportPartialResults = true
request.taskHint = .dictation  // ← 追加: 音声メモに最適
```

#### addsPunctuation の活用

iOS 16+ で利用可能。日本語の句読点（「。」「、」）を自動挿入する。

```swift
request.addsPunctuation = true  // ← 追加: 句読点自動挿入
```

**日本語での効果**:
- 「。」（句点）の挿入精度は比較的高い（ポーズ検出ベース）
- 「、」（読点）の挿入は精度がやや低い（文法構造の解析が必要）
- オンデバイスモード（`requiresOnDeviceRecognition = true`）では効果が限定的

#### contextualStrings の日本語活用

**現状の実装（OK）**: `AppleSpeechEngine` は既に `contextualStrings` をサポートしている。

**日本語での最適化ポイント**:

```swift
// 効果的な contextualStrings の構成
let contextualStrings = [
    // 1. 固有名詞（漢字表記）
    "糸村", "田中太郎",
    // 2. 固有名詞（カタカナ表記）— 外来語・サービス名
    "ソヨカ", "スラック",
    // 3. 専門用語・複合語
    "音声認識", "文字起こし",
    // 4. 誤認識されやすいフレーズ
    "今日の会議", "明日の予定",
]
```

**重要な制約**:
- `contextualStrings` は認識候補のブースティングであり、強制ではない
- 日本語では漢字・ひらがな・カタカナの混在により、効果が英語ほど明確でない
- 登録数は 100 件以内が推奨（多すぎると逆効果の可能性）
- `requiresOnDeviceRecognition = true` 時は効果が限定的

#### SFCustomLanguageModelData（iOS 17+）

より高度なカスタマイズとして `SFCustomLanguageModelData` が利用可能だが、日本語での制約がある。

```swift
// 日本語でのカスタム言語モデル構築
let builder = SFCustomLanguageModelData(
    locale: Locale(identifier: "ja-JP"),
    identifier: "com.soyoka.customLM",
    version: 1
) {
    // フレーズブースティング
    PhraseCount(phrase: "ソヨカ", count: 100)
    PhraseCount(phrase: "音声メモ", count: 50)
}
```

**日本語での制約**:
- X-SAMPA による発音定義は日本語サブセットの公式ドキュメントが不明確
- テンプレート機能は日本語の文法構造に適用しにくい
- **iOS 26 の SpeechAnalyzer とは互換性なし**

### 1.2 SpeechAnalyzer（iOS 26+）の日本語対応状況

#### 日本語サポート: 確認済み

`SpeechTranscriber.supportedLocales` に `ja_JP` が含まれる（全42ロケール中）。

#### 現状の実装の評価

Soyoka の `SpeechAnalyzerEngine` の実装は概ね適切だが、以下の改善点がある。

**改善1: reportingOptions に `.volatileResults` を指定**（実装済み）

```swift
// 現状（OK）
let newTranscriber = SpeechTranscriber(
    locale: locale,
    transcriptionOptions: [],
    reportingOptions: [.volatileResults],
    attributeOptions: []
)
```

**改善2: attributeOptions に `.audioTimeRange` を追加**

```swift
// 改善案: 単語レベルのタイムスタンプ取得
let newTranscriber = SpeechTranscriber(
    locale: locale,
    transcriptionOptions: [],
    reportingOptions: [.volatileResults],
    attributeOptions: [.audioTimeRange]  // ← 追加
)
```

これにより、各単語の音声タイムスタンプが取得でき、以下に活用可能:
- 音声再生時のハイライト同期（Phase 3-4 で実装予定）
- 句読点挿入の精度向上（ポーズ長の計測）

**改善3: SpeechDetector との併用**

```swift
// VAD（音声活動検出）を併用してセグメンテーション精度を向上
let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveLiveTranscription)
let detector = SpeechDetector(detectionOptions: [], reportResults: true)
let analyzer = SpeechAnalyzer(modules: [transcriber, detector])
```

#### カスタム辞書: 非対応（重要）

SpeechAnalyzer には `contextualStrings` 相当の機能がない。これは Apple Developer Forums でも指摘されており、現時点で公式の代替手段はない。

**Soyoka での対応戦略**:
1. LLM 後処理でカスタム辞書の読み→表記ペアを活用（既に `PromptTemplate` で実装済み）
2. `DictionaryRecommendationEngine` による学習的補正（既に実装済み）
3. 将来的に Apple が API を追加する可能性に備え、`STTEngineProtocol` のインターフェースは維持

#### 句読点自動挿入

SpeechAnalyzer の新モデルは、SFSpeechRecognizer より句読点挿入の精度が向上している。ただし、日本語の読点（「、」）の挿入は依然として課題がある。

**対策**: LLM 後処理（`PromptTemplate.onDeviceSimple`）で「句読点を適切に入れ、読みやすくする」指示を含めている（既に実装済み）。

---

## 2. WhisperKit / Whisper の日本語最適化

### 2.1 モデルサイズ別の日本語精度

| モデル | パラメータ | サイズ(fp16) | 日本語CER | iPhone動作 | 推奨度 |
|:-------|:----------|:-----------|:---------|:----------|:------|
| tiny | 39M | ~30MB | ~33% | 全機種 | 非推奨 |
| base | 74M | ~140MB | ~20% | 全機種 | 低品質だが軽量 |
| small | 244M | ~460MB | ~10-12% | 6GB+ | **実用的な上限** |
| medium | 769M | ~1.5GB | ~7-8% | Mac専用 | iPhone不可 |
| large-v3 | 1.55B | ~3GB | ~5% | Mac専用 | iPhone不可 |
| large-v3-turbo | 809M | ~1.6GB | ~5% | Mac専用 | iPhone不可 |

**日本語固有の特性**:
- Whisper の訓練データにおける日本語比率は約17%（英語65%）
- tiny/base では日本語のハルシネーション（幻聴）が頻発
- small が iPhone で実用的な上限（6GB RAM 以上が必須）
- **結論: iPhone では small モデルが日本語の精度と実行可能性のバランス点**

### 2.2 日本語特化 fine-tuned モデル

#### kotoba-whisper（推奨）

| バージョン | ベースモデル | 訓練データ | 特徴 |
|:----------|:-----------|:---------|:-----|
| v1.0 | large-v3 蒸留 | ReazonSpeech | large-v3 と同等CER、6.3倍高速 |
| v2.0 | large-v3 蒸留 | ReazonSpeech 720万クリップ | 句読点サポート追加 |
| v2.2 | large-v3 蒸留 | ReazonSpeech | 話者分離 + 句読点 |

**CoreML / WhisperKit 統合**:
- `yslinear/kotoba-whisper-v2.2-coreml` として CoreML 変換済みモデルが HuggingFace に公開済み
- WhisperKit の `WhisperKit(model: "yslinear/kotoba-whisper-v2.2-coreml")` で読み込み可能
- ただし、モデルサイズが large-v3 蒸留のため iPhone での実行は要検証（メモリ制約）

**kotoba-whisper の精度**:
- ReazonSpeech テストセットで large-v3 と同等以上の CER/WER
- CommonVoice 8.0 日本語サブセットで競争力のある精度
- JSUT basic 5000 でも良好な結果

#### その他の日本語特化モデル

| モデル | 特徴 | iOS 対応 |
|:------|:-----|:--------|
| Ivydata/whisper-base-japanese | base サイズの日本語 fine-tune | WhisperKit で利用可能 |
| litagin/anime-whisper | アニメ音声特化、句読点対応 | 変換が必要 |
| ReazonSpeech-k2-v2 | 日本語ASR最高精度クラス | Sherpa-ONNX 経由 |

### 2.3 initial_prompt による日本語精度向上

Whisper の `initial_prompt` パラメータを使用して日本語認識の精度を向上させる技法。

#### 基本テクニック

```python
# Python での例（WhisperKit の Swift 実装に応用可能）
result = model.transcribe(
    audio,
    language="ja",
    initial_prompt="以下は日本語の音声メモです。句読点を含めて書き起こしてください。"
)
```

**日本語で効果的なプロンプト例**:

```
以下は日本語の音声メモの書き起こしです。句読点（、。）を適切に挿入してください。
```

**プロンプトに固有名詞を含める**:

```
以下は「ソヨカ」という音声メモアプリに関する会話の書き起こしです。
登場する固有名詞: ソヨカ、SwiftUI、TCA、Composable Architecture
```

#### 重要な制約

1. **最初の30秒のみ有効**: `initial_prompt` は最初のセグメント（30秒）でのみ使用される。2番目以降のセグメントでは前セグメントのデコード結果で上書きされる
2. **トークン上限224**: Whisper のコンテキストウィンドウは448トークンだが、公式実装では入力プロンプトに224トークンまで
3. **ワークアラウンド**: 各セグメントに `initial_prompt` を強制注入する実装が可能（WhisperKit のカスタマイズが必要）

#### WhisperKit での実装

```swift
// WhisperKit での initial_prompt 設定
let options = DecodingOptions(
    language: "ja",
    prompt: "以下は日本語の音声メモです。句読点を含めて書き起こしてください。"
)
```

### 2.4 language 指定 vs 自動検出のトレードオフ

| 方式 | メリット | デメリット |
|:-----|:--------|:---------|
| `language: "ja"` 固定 | 認識速度向上、日本語に最適化 | 英語混在時に精度低下 |
| 自動検出 | 多言語対応 | 30秒ごとに言語判定コスト、誤判定リスク |

**Soyoka への推奨**: `language: "ja"` 固定を推奨。音声メモアプリとして日本語が主言語であり、英語混在は LLM 後処理で補完可能。

---

## 3. 日本語テキスト後処理

### 3.1 フィラー除去

#### 現状の実装評価

`TextPreprocessor.removeFillers()` は基本的なフィラーリストを持っているが、以下の改善が可能。

#### 改善提案: 正規表現ベースのフィラー除去

```swift
public struct TextPreprocessor: Sendable {

    /// フィラーワードを除去（改善版）
    public static func removeFillers(_ text: String) -> String {
        var result = text

        // 1. 長いフィラーから先に処理（部分マッチ防止）
        let fillerPatterns: [(pattern: String, isRegex: Bool)] = [
            // 延長系フィラー（正規表現）
            ("え[ーぇ]+っ?と[ーお]?", true),
            ("あ[のー]+ね?ー?", true),
            ("う[ーん]+と?", true),
            ("そ[のー]+", true),
            ("ええ[ーっ]+と?", true),

            // 固定フィラー（文字列マッチ）
            ("なんていうか", false),
            ("なんだろう", false),
            ("なんだろ", false),
            ("なんか", false),
            ("まぁ", false),
            ("まあ", false),
            ("ほら", false),
            ("こう", false),
            ("やっぱ", false),

            // 相槌系（文脈に応じて除去）
            ("そうですね", false),
            ("はい", false),  // 注意: 文頭のみ除去が安全
        ]

        for (pattern, isRegex) in fillerPatterns {
            if isRegex {
                // 正規表現パターン: フィラー + 後続の句読点/スペース
                let regexPattern = "\(pattern)[、。 　]?"
                result = result.replacingOccurrences(
                    of: regexPattern,
                    with: "",
                    options: .regularExpression
                )
            } else {
                // 固定文字列: 句読点/スペース付きで除去
                for suffix in ["、", "。", " ", "\u{3000}", ""] {
                    result = result.replacingOccurrences(of: pattern + suffix, with: suffix == "。" ? "。" : "")
                }
            }
        }

        // 後処理: 連続句読点/スペースの整理
        result = result.replacingOccurrences(of: "、、", with: "、")
        result = result.replacingOccurrences(of: "。。", with: "。")
        result = result.replacingOccurrences(of: "　　", with: "　")
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

#### フィラーの分類と除去優先度

| 優先度 | 種類 | 例 | 除去判定 |
|:------|:-----|:---|:--------|
| 高 | 思考中フィラー | えーと、あのー、うーん | 常に除去 |
| 高 | 繰り返し言い直し | 「今日、今日は」→「今日は」 | パターンマッチで除去 |
| 中 | 口癖系 | なんか、まあ、こう | 文頭・句読点前のみ除去 |
| 低 | 相槌 | はい、そうですね | 独立した場合のみ除去 |
| 除去しない | 意味のあるフィラー | 「えっ」（驚き）、「うん」（同意） | 文脈判断が必要 → LLM に委託 |

### 3.2 句読点の自動挿入アルゴリズム

#### ルールベース句読点挿入

```swift
public struct PunctuationInserter: Sendable {

    /// 句読点のない文字起こしテキストに句読点を挿入する
    /// - Parameters:
    ///   - text: 入力テキスト
    ///   - segments: 音声セグメント情報（タイムスタンプ付き）
    /// - Returns: 句読点挿入済みテキスト
    public static func insertPunctuation(
        _ text: String,
        segments: [TranscriptionSegment] = []
    ) -> String {
        var result = text

        // 1. ポーズベースの句点挿入（セグメント情報がある場合）
        if !segments.isEmpty {
            result = insertByPause(result, segments: segments)
        }

        // 2. 文末パターンによる句点挿入
        let sentenceEnders = [
            "です", "ます", "ました", "でした",
            "だ", "った", "てた",
            "ない", "ません",
            "よ", "ね", "よね", "かな", "けど",
            "した", "する", "している",
        ]

        for ender in sentenceEnders {
            // 文末パターン + スペース → 句点挿入
            let pattern = "(\(NSRegularExpression.escapedPattern(for: ender)))[ 　]"
            result = result.replacingOccurrences(
                of: pattern,
                with: "$1。",
                options: .regularExpression
            )
        }

        // 3. 読点（、）の挿入
        let clauseBreakers = [
            "けど", "けれど", "が", "ので", "から",
            "して", "ため", "のに", "ながら",
        ]

        for breaker in clauseBreakers {
            // 節の区切り + 続く文 → 読点挿入
            // 注意: 助詞「が」は主語マーカーの場合もあるため慎重に
            if breaker == "が" { continue } // 「が」は誤挿入リスクが高いためスキップ
            let pattern = "(\(NSRegularExpression.escapedPattern(for: breaker)))([^、。])"
            result = result.replacingOccurrences(
                of: pattern,
                with: "$1、$2",
                options: .regularExpression
            )
        }

        return result
    }

    /// ポーズ（無音区間）に基づく句点挿入
    private static func insertByPause(
        _ text: String,
        segments: [TranscriptionSegment]
    ) -> String {
        // セグメント間のギャップが 0.8 秒以上 → 句点
        // セグメント間のギャップが 0.3-0.8 秒 → 読点
        // この処理はセグメントのタイムスタンプ情報が正確な場合に有効
        guard segments.count >= 2 else { return text }

        var result = ""
        for i in 0..<segments.count {
            result += segments[i].text
            if i < segments.count - 1 {
                let gap = segments[i + 1].startTime - segments[i].endTime
                if gap >= 0.8 {
                    result += "。"
                } else if gap >= 0.3 {
                    result += "、"
                }
            }
        }
        return result
    }
}
```

**推奨**: ルールベースの句読点挿入は補助的に使い、最終的な句読点整形は LLM 後処理（`PromptTemplate.onDeviceSimple`）に委託するのが最も精度が高い。

### 3.3 漢字変換の精度向上（同音異義語対応）

音声認識の同音異義語誤変換は、日本語STTの最大の課題の一つ。

#### 誤変換パターンと対策

| パターン | 例 | 対策 |
|:---------|:---|:-----|
| 同音異義語 | 「公園」←→「講演」 | 文脈推定（LLM後処理） |
| 連続音の切り分け | 「今日は」←→「京は」 | 言語モデルの文脈力に依存 |
| 固有名詞 | 「余命家族」←→「4名家族」 | カスタム辞書 + LLM後処理 |
| 外来語 | 「スウィフト」←→「素早いと」 | contextualStrings / LLM後処理 |

**Soyoka の既存対策（適切）**:
- `PromptTemplate.onDeviceSimple` に「音声認識の誤変換と思われる箇所は、文脈から推測して自然な言葉に直す」指示あり
- `DictionaryRecommendationEngine` で誤変換パターンを学習・蓄積
- `CustomDictionaryClient` で読み→表記ペアを LLM に提供

#### 追加提案: 頻出誤変換辞書

```swift
/// 日本語音声認識でよくある誤変換パターン
/// LLM後処理の前段として適用（軽量・高速）
public struct CommonMisrecognitionCorrector: Sendable {

    static let corrections: [String: String] = [
        // 助数詞の誤認識
        "1個": "一個",
        // アプリ固有の誤認識（ユーザーフィードバックから蓄積）
        // ここに追加していく
    ]

    /// 頻出誤変換を一括修正
    public static func correct(_ text: String) -> String {
        var result = text
        for (wrong, correct) in corrections {
            result = result.replacingOccurrences(of: wrong, with: correct)
        }
        return result
    }
}
```

### 3.4 口語→書き言葉変換

**現状のアプローチ（適切）**: `PromptTemplate` の `WritingStyle` で文体を制御している。

| WritingStyle | 変換方向 | 用途 |
|:------------|:--------|:-----|
| `.soft` | 話し言葉のニュアンスを残す | デフォルト |
| `.formal` | 「です・ます」調に統一 | フォーマルな場面 |
| `.casual` | 体言止め・SNS風 | カジュアルメモ |
| `.reflection` | 手紙風・共感トーン | ふりかえり |
| `.essay` | 随筆風 | エッセイ |

**追加提案**: 口語→書き言葉変換の前処理ルール

```swift
/// 口語表現を書き言葉に変換するルール（LLM前処理として適用可能）
public struct OralToWrittenConverter: Sendable {

    static let conversions: [(oral: String, written: String)] = [
        // 縮約形の展開
        ("じゃない", "ではない"),
        ("じゃなくて", "ではなくて"),
        ("してる", "している"),
        ("見てる", "見ている"),
        ("やってる", "やっている"),
        // カジュアル→ニュートラル
        ("マジで", "本当に"),
        ("めっちゃ", "とても"),
        ("すごい", "非常に"),  // 注意: 形容詞として使う場合は変換しない
    ]

    /// style が .formal の場合のみ適用
    public static func convert(_ text: String, style: WritingStyle) -> String {
        guard style == .formal else { return text }
        var result = text
        for (oral, written) in conversions {
            result = result.replacingOccurrences(of: oral, with: written)
        }
        return result
    }
}
```

**推奨**: ルールベースの口語→書き言葉変換は `.formal` スタイルの場合のみ適用し、他のスタイルでは LLM に全面委託する方が自然な結果が得られる。

---

## 4. 日本語NLP活用

### 4.1 NaturalLanguage.framework の日本語対応状況

| 機能 | 日本語対応 | 精度 | Soyoka での活用 |
|:-----|:---------|:-----|:-------------|
| 言語検出 (`NLLanguageRecognizer`) | 対応 | 高い | 多言語メモの言語判定 |
| トークン化 (`NLTokenizer`) | 対応 | 良好 | **既に使用中**（`DictionaryRecommendationEngine`） |
| 品詞タグ付け (`NLTagger`) | **限定的** | 低い | 日本語では実用性低 |
| 固有表現抽出 | **限定的** | 低い | 日本語では不十分 |
| 感情分析 (`NLTagger.sentimentScore`) | **非対応** | - | 日本語未サポート |
| 単語埋め込み (`NLEmbedding`) | **限定的** | - | 日本語モデルの品質が不明 |

**現状の活用（適切）**:
- `DictionaryRecommendationEngine` で `NLTokenizer(unit: .word)` + `.setLanguage(.japanese)` を使用
- 日本語の単語分割に活用し、変更差分から辞書候補を検出

**追加の活用可能性**:

```swift
// 1. 言語検出（多言語メモ対応の将来機能）
let recognizer = NLLanguageRecognizer()
recognizer.processString(text)
let dominantLanguage = recognizer.dominantLanguage // .japanese, .english, etc.

// 2. 文分割（句読点挿入の補助）
let tokenizer = NLTokenizer(unit: .sentence)
tokenizer.string = text
tokenizer.setLanguage(.japanese)
var sentences: [String] = []
tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
    sentences.append(String(text[range]))
    return true
}
```

### 4.2 MeCab / Sudachi の iOS 統合

#### MeCab-Swift（SPM対応）

```
// Package.swift への追加
.package(url: "https://github.com/shinjukunian/Mecab-Swift", from: "0.1.0")
```

**メリット**:
- 品詞タグ付け（名詞、動詞、助詞、etc.）
- 漢字の読み仮名取得
- 形態素解析による正確な単語分割

**デメリット**:
- IPADic 辞書のバンドルが必要（約20MB）
- C++ ライブラリのラッパーであり、ビルド設定が複雑
- 新語・固有名詞への対応が辞書更新に依存

**Soyoka での活用案**:

```swift
import MeCab

// 形態素解析で読み仮名を取得（カスタム辞書の読み推定に活用）
func getReading(for text: String) -> String? {
    let tokenizer = MeCab.Tokenizer()
    let tokens = tokenizer.tokenize(text)
    return tokens.map { $0.reading ?? $0.surface }.joined()
}
```

**推奨判定**: 現時点では導入不要。`NLTokenizer` で基本的な単語分割は可能であり、MeCab の追加コスト（バイナリサイズ・ビルド複雑性）に見合うユースケースがない。将来的に「読み仮名自動推定」が必要になった場合に検討。

#### Sudachi

iOS 向けの SPM パッケージは確認できず。サーバーサイド（Backend Proxy）で活用する方が現実的。

### 4.3 日本語テキスト要約に適した LLM プロンプト設計

#### 現状の評価

`PromptTemplate.onDeviceSimple` は優れた設計。以下の点が特に良い:
- 「要約しない。話した内容を省略せず、全て残す」— 音声メモの本質を理解
- フィラー除去・言い直し統合の指示が明確
- JSON 出力形式で構造化
- カスタム辞書の注入パスが確立

#### 改善提案

**1. 日本語特有の誤変換例を具体的に指示**:

```
現在の指示:
「音声認識の誤変換と思われる箇所は、文脈から推測して自然な言葉に直す」

改善案:
「音声認識の誤変換と思われる箇所は、文脈から推測して自然な言葉に直す。
特に以下のパターンに注意:
- 同音異義語の誤り（例: 「公園」と「講演」、「機関」と「期間」）
- 助数詞の聞き間違い（例: 「余命家族」→文脈が人数なら「4名家族」）
- 外来語のひらがな化（例: 「すいふと」→「Swift」）」
```

**2. トークン効率の最適化**（オンデバイスLLMの制約対応）:

現在のプロンプトは ~650 入力トークンの制約内で設計されているが、日本語テキストは英語よりトークン数が多くなる傾向がある。

```
// 日本語のトークン効率
// GPT-4/Claude: 日本語1文字 ≈ 1-3トークン（平均2トークン）
// オンデバイスLLM: トークナイザーに依存するが、同様の傾向

// 推奨: 入力テキストの最大長を明示的に制限
let maxInputChars = 300  // ≈ 600トークン
let truncatedText = String(transcriptionText.prefix(maxInputChars))
```

**3. Apple Foundation Models (iOS 26) の活用**:

```swift
import FoundationModels

@Generable
struct MemoOrganization {
    @Guide(description: "内容を表す短いタイトル（20文字以内）")
    var title: String

    @Guide(description: "清書した文章")
    var cleaned: String

    @Guide(description: "内容を表すタグ（3つまで）")
    var tags: [String]
}

func organizeWithFoundationModels(
    text: String,
    dictionaryPairs: [(reading: String, display: String)]
) async throws -> MemoOrganization {
    let model = SystemLanguageModel.default
    let dictInfo = dictionaryPairs.map { "\($0.display)（\($0.reading)）" }.joined(separator: "、")

    let prompt = """
    以下の音声メモを清書してください。
    固有名詞: \(dictInfo)
    メモ: \(text)
    """

    return try await model.generate(MemoOrganization.self, prompt: prompt)
}
```

---

## 5. Soyoka への具体的実装提案

### 5.1 優先度付き改善項目

| 優先度 | 改善項目 | 対象ファイル | 工数 | 効果 |
|:------|:--------|:-----------|:-----|:-----|
| **P0** | `taskHint = .dictation` 追加 | `AppleSpeechEngine.swift` | 1行 | 認識精度向上 |
| **P0** | `addsPunctuation = true` 追加 | `AppleSpeechEngine.swift` | 1行 | 句読点自動挿入 |
| **P1** | `attributeOptions: [.audioTimeRange]` 追加 | `SpeechAnalyzerEngine.swift` | 1行 | タイムスタンプ取得 |
| **P1** | フィラー除去の正規表現化 | `TextPreprocessor.swift` | 中 | フィラー除去精度向上 |
| **P2** | `SpeechDetector` 併用 | `SpeechAnalyzerEngine.swift` | 中 | VADによるセグメンテーション |
| **P2** | 頻出誤変換辞書の追加 | 新規ファイル | 小 | 誤変換の自動修正 |
| **P3** | kotoba-whisper CoreML 統合検証 | `STTEngineFactory.swift` | 大 | 日本語認識の大幅向上 |
| **P3** | Apple Foundation Models 統合 | `PromptTemplate.swift` | 大 | iOS 26 での後処理改善 |

### 5.2 即座に適用可能な変更（P0）

#### AppleSpeechEngine.swift への変更

```swift
// startRecognitionSession() メソッド内の request 設定部分
let request = SFSpeechAudioBufferRecognitionRequest()
request.shouldReportPartialResults = true
request.taskHint = .dictation           // ← 追加
request.addsPunctuation = true          // ← 追加（iOS 16+）

if requiresOnDevice {
    request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
}
```

### 5.3 STTエンジン選択戦略の最適化

現在の `STTEngineSelector` のロジックは適切だが、日本語精度を軸にした再評価:

```
推奨エンジン選択フロー（日本語最適化版）:

1. ユーザー手動設定 → そのまま使用
2. iOS 26+ → SpeechAnalyzer（Apple純正、ANE最適化、カスタム辞書は LLM 後処理で補完）
3. iOS 17-25 + 6GB+ RAM → AppleSpeechEngine（contextualStrings 活用）
4. iOS 17-25 + 4GB RAM → AppleSpeechEngine（オンデバイスモード）
5. Pro + ネットワーク → cloudSTT（最高精度）
```

**変更点**: WhisperKit は現状 small モデルでも iPhone 6GB+ 必須かつ精度が SpeechAnalyzer と同等レベルのため、デフォルト選択からは外す。ただし、kotoba-whisper CoreML 統合が完了すれば再評価の余地あり。

### 5.4 後処理パイプラインの全体設計

```
音声入力
  ↓
[STTエンジン] Apple Speech / SpeechAnalyzer
  ↓
[前処理 1] TextPreprocessor.removeFillers()    ← ルールベース、即座に適用
  ↓
[前処理 2] CommonMisrecognitionCorrector       ← 頻出誤変換修正（新規追加）
  ↓
[LLM後処理] PromptTemplate.onDeviceSimple      ← 清書・タグ付け・句読点整形
  │
  ├── カスタム辞書注入（読み→表記ペア）
  ├── 文体指定（WritingStyle）
  └── JSON構造化出力
  ↓
[学習] DictionaryRecommendationEngine          ← 誤変換パターンの蓄積
  ↓
保存（SwiftData）
```

---

## 参考資料

### Apple 公式

- [SFSpeechRecognizer | Apple Developer Documentation](https://developer.apple.com/documentation/speech/sfspeechrecognizer)
- [contextualStrings | Apple Developer Documentation](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/contextualstrings)
- [Bring advanced speech-to-text to your app with SpeechAnalyzer - WWDC25](https://developer.apple.com/videos/play/wwdc2025/277/)
- [SpeechAnalyzer | Apple Developer Documentation](https://developer.apple.com/documentation/speech/speechanalyzer)
- [Bringing advanced speech-to-text capabilities to your app](https://developer.apple.com/documentation/Speech/bringing-advanced-speech-to-text-capabilities-to-your-app)
- [Natural Language | Apple Developer Documentation](https://developer.apple.com/documentation/naturallanguage)
- [NLTokenizer | Apple Developer Documentation](https://developer.apple.com/documentation/naturallanguage/nltokenizer)

### SpeechAnalyzer 解説

- [iOS 26: SpeechAnalyzer Guide](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide)
- [WWDC 2025 - The Next Evolution of Speech-to-Text using SpeechAnalyzer](https://dev.to/arshtechpro/wwdc-2025-the-next-evolution-of-speech-to-text-using-speechanalyzer-6lo)
- [On-Device Speech Transcription with Apple SpeechAnalyzer and AI SDK](https://www.callstack.com/blog/on-device-speech-transcription-with-apple-speechanalyzer)
- [Hands-On: How Apple's New Speech APIs Outpace Whisper](https://www.macstories.net/stories/hands-on-how-apples-new-speech-apis-outpace-whisper-for-lightning-fast-transcription/)

### WhisperKit / Whisper

- [Apple SpeechAnalyzer and Argmax WhisperKit](https://www.argmaxinc.com/blog/apple-and-argmax)
- [WhisperKit GitHub](https://github.com/argmaxinc/WhisperKit)
- [argmaxinc/whisperkit-coreml - Hugging Face](https://huggingface.co/argmaxinc/whisperkit-coreml)
- [Whisper Model Sizes Explained](https://openwhispr.com/blog/whisper-model-sizes-explained)
- [Prompt Engineering in Whisper](https://medium.com/axinc-ai/prompt-engineering-in-whisper-6bb18003562d)
- [Best prompt to transcribe Japanese? - Whisper Discussion](https://github.com/openai/whisper/discussions/2151)

### kotoba-whisper

- [kotoba-tech/kotoba-whisper-v1.0 - Hugging Face](https://huggingface.co/kotoba-tech/kotoba-whisper-v1.0)
- [kotoba-tech/kotoba-whisper-v2.0 - Hugging Face](https://huggingface.co/kotoba-tech/kotoba-whisper-v2.0)
- [kotoba-tech/kotoba-whisper-v2.2 - Hugging Face](https://huggingface.co/kotoba-tech/kotoba-whisper-v2.2)
- [yslinear/kotoba-whisper-v2.2-coreml - Hugging Face](https://huggingface.co/yslinear/kotoba-whisper-v2.2-coreml)
- [kotoba-whisper GitHub](https://github.com/kotoba-tech/kotoba-whisper)

### 日本語NLP

- [Mecab-Swift (SPM)](https://github.com/shinjukunian/Mecab-Swift)
- [mecab-swift](https://github.com/novi/mecab-swift)
- [awesome-japanese-nlp-resources](https://github.com/taishi-i/awesome-japanese-nlp-resources)

### ベンチマーク・研究

- [Whisper Japanese CER - OpenAI](https://github.com/openai/whisper)
- [2025 Edge Speech-to-Text Model Benchmark](https://www.ionio.ai/blog/2025-edge-speech-to-text-model-benchmark-whisper-vs-competitors)
- [Efficient Adaptation of Multilingual Models for Japanese ASR](https://arxiv.org/html/2412.10705v1)
