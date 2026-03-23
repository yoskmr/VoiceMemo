# Apple SpeechAnalyzer (iOS 26+) 日本語音声認識 精度最大化 徹底調査レポート

**調査日**: 2026-03-23
**対象**: Apple SpeechAnalyzer (iOS 26+ / macOS 26+)
**目的**: 日本語音声認識の精度を最大限に高める方法の網羅的調査

---

## 1. SpeechAnalyzer の基本API構造

### 1.1 アーキテクチャ概要

SpeechAnalyzer は WWDC25 (Session 277) で発表された、`SFSpeechRecognizer` の後継となる音声認識フレームワーク。モジュラー設計を採用し、Swift Concurrency にネイティブ対応。

```
SpeechAnalyzer (セッション管理)
├── SpeechTranscriber   — 音声→テキスト変換（新モデル、高精度）
├── DictationTranscriber — ディクテーション特化（句読点・文構造付き、レガシーモデル）
└── SpeechDetector       — VAD（音声活動検出）のみ
```

**主要クラス**:
- `SpeechAnalyzer`: 分析セッションの管理。モジュールの追加・削除がストリーム中でも可能
- `SpeechTranscriber`: 新STTモデルによる文字起こし。42ロケール対応（ja_JP含む）
- `DictationTranscriber`: iOS 10の `SFSpeechRecognizer` と同等のモデル。非対応言語/デバイスのフォールバック
- `SpeechDetector`: VADのみ。他モジュールとペアで使用必須
- `AssetInventory`: 言語モデルのDL/インストール管理

### 1.2 日本語ロケール (ja_JP) 設定

```swift
// SpeechTranscriber は ja_JP を公式サポート
let locale = Locale(identifier: "ja_JP")
let transcriber = SpeechTranscriber(
    locale: locale,
    transcriptionOptions: [],
    reportingOptions: [.volatileResults],
    attributeOptions: [.audioTimeRange]
)
```

**SpeechTranscriber.supportedLocales で確認済みの42ロケール**:
ar_SA, da_DK, de_AT, de_CH, de_DE, en_AU, en_CA, en_GB, en_IE, en_IN, en_NZ, en_SG, en_US, en_ZA, es_CL, es_ES, es_MX, es_US, fi_FI, fr_BE, fr_CA, fr_CH, fr_FR, he_IL, it_CH, it_IT, **ja_JP**, ko_KR, ms_MY, nb_NO, nl_BE, nl_NL, pt_BR, ru_RU, sv_SE, th_TH, tr_TR, vi_VN, yue_CN, zh_CN, zh_HK, zh_TW

### 1.3 ストリーミング vs バッチ処理

| 項目 | ストリーミング（リアルタイム） | バッチ（ファイル処理） |
|:-----|:--------------------------|:-------------------|
| Preset | `.progressiveLiveTranscription` | `.offlineTranscription` |
| 入力 | `AsyncStream<AnalyzerInput>` | `AVAudioFile` |
| 開始API | `analyzer.start(inputSequence:)` | `analyzer.start(inputAudioFile:finishAfterFile:)` |
| 中間結果 | volatile results（逐次更新） | final results のみ |
| 用途 | リアルタイム文字起こし | 録音済み音声の処理 |
| 速度 | リアルタイム | 34分音声 → 45秒（MacStories実測） |

### 1.4 利用可能な設定パラメータ

**Preset による初期化**:
```swift
// シンプル初期化
let transcriber = SpeechTranscriber(locale: locale, preset: .offlineTranscription)
let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveLiveTranscription)
```

**詳細パラメータ初期化**:
```swift
let transcriber = SpeechTranscriber(
    locale: Locale(identifier: "ja_JP"),
    transcriptionOptions: [],           // 追加の文字起こしオプション
    reportingOptions: [.volatileResults], // 中間結果の報告
    attributeOptions: [.audioTimeRange]   // 単語レベルのタイムスタンプ
)
```

- **transcriptionOptions**: 文字起こしの動作制御
- **reportingOptions**: `.volatileResults` で中間結果を取得（リアルタイム表示用）
- **attributeOptions**: `.audioTimeRange` で各単語の音声タイムスタンプを取得

---

## 2. カスタム辞書・語彙対応

### 2.1 SpeechAnalyzer のカスタム語彙機能 — **非対応**

**重要な制限**: SpeechAnalyzer (iOS 26) には **Custom Vocabulary 機能が存在しない**。

これは Argmax のベンチマーク記事でも明確に指摘されている:
> "Apple's new SpeechAnalyzer (iOS 26) API lacks the Custom Vocabulary feature that lets developers improve accuracy on known-and-registered keywords."

SFSpeechRecognizer にあった以下の機能が SpeechAnalyzer では利用不可:
- `SFCustomLanguageModelData` によるカスタム言語モデル
- `SFSpeechLanguageModel.prepareCustomLanguageModel()` によるモデル準備
- カスタム発音定義（X-SAMPA）
- フレーズブースティング（PhraseCount）
- テンプレートベースの語彙生成

### 2.2 WWDC25 Session 277 の内容

Session "Bring advanced speech-to-text to your app with SpeechAnalyzer" の構成:
1. **Introduction** (0:00) — SpeechAnalyzer の位置づけ
2. **SpeechAnalyzer API** (2:41) — モジュラーアーキテクチャ説明
3. **SpeechTranscriber mode** (7:03) — トランスクライバーの詳細
4. **Building a speech-to-text feature** (9:06) — 実装デモ

セッション内で Custom Vocabulary に関する言及はなく、カスタマイズ機能は提供されていない。

### 2.3 SFCustomLanguageModelData と SpeechAnalyzer の互換性

**互換性なし**。`SFCustomLanguageModelData` は `SFSpeechRecognizer` 専用であり、SpeechAnalyzer のモジュール（SpeechTranscriber / DictationTranscriber）には接続できない。

ただし、`DictationTranscriber` は内部的に iOS 10 の `SFSpeechRecognizer` と同等のモデルを使用しているため、理論上は旧APIとの互換性がある可能性があるが、公式にはサポートされていない。

### 2.4 SFCustomLanguageModelData（前身 SFSpeechRecognizer）の機能

iOS 17+ で利用可能な前身APIの機能（参考情報）:

```swift
// フレーズブースティング
let builder = SFCustomLanguageModelData(locale: locale, identifier: "myModel", version: 1) {
    PhraseCount(phrase: "MurMurNote", count: 100)
    PhraseCount(phrase: "音声メモを開始", count: 50)
}

// カスタム発音（X-SAMPA形式）
builder.addPhrase("Winawer", count: 100, pronunciation: "wIn'aU@r")

// テンプレートによる大量サンプル生成
builder.addTemplate(
    classes: ["prefix": ["メモを"], "action": ["開始", "停止", "保存"]],
    template: "<prefix><action>",
    count: 500
)
```

**注意**: `SFCustomLanguageModelData` の日本語ロケール対応は限定的であり、X-SAMPA の日本語サブセットについて公式ドキュメントでの明確な記載は確認できなかった。

### 2.5 ホットワード / ブースティング機能

SpeechAnalyzer には **ホットワード / ブースティング機能は存在しない**。
Argmax Pro SDK が「Custom Vocabulary」として同等機能を提供している（ランタイムでキーワードリストを渡す方式）。

---

## 3. 精度向上テクニック

### 3.1 音声前処理（ノイズキャンセリング等）

SpeechAnalyzer 自体にはノイズキャンセリングAPIはないが、以下の対策が有効:

**AVAudioSession の最適設定**:
```swift
let audioSession = AVAudioSession.sharedInstance()
try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
```

- `.measurement` モードは音声認識に最適化された入力を提供
- `.duckOthers` で他のオーディオソースの音量を下げる

**Apple のモデル特性**:
- SpeechAnalyzer の新モデルは「遠距離音声」「バックグラウンドノイズ環境」「マルチスピーカー議論」に最適化済み
- 追加の前処理なしでもノイズ耐性が改善されている

### 3.2 サンプルレート・フォーマットの最適化

```swift
// SpeechAnalyzer が要求する最適フォーマットを取得
let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
```

**重要**: `bestAvailableAudioFormat` が返すフォーマットに音声データを変換して渡すことが精度の鍵。

```swift
// バッファ変換の実装
class BufferConverter {
    private var converter: AVAudioConverter?

    func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else { return buffer }

        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none
        }

        guard let converter else { throw ConversionError.converterNotAvailable }

        let sampleRateRatio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let scaledLength = Double(buffer.frameLength) * sampleRateRatio
        let frameCapacity = AVAudioFrameCount(scaledLength.rounded(.up))

        guard let conversionBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: frameCapacity
        ) else {
            throw ConversionError.bufferCreationFailed
        }

        var nsError: NSError?
        var bufferProcessed = false
        let status = converter.convert(to: conversionBuffer, error: &nsError) { _, inputStatusPointer in
            defer { bufferProcessed = true }
            inputStatusPointer.pointee = bufferProcessed ? .noDataNow : .haveData
            return bufferProcessed ? nil : buffer
        }

        guard status != .error else { throw ConversionError.conversionFailed(nsError) }
        return conversionBuffer
    }
}
```

### 3.3 言語モデルの事前ダウンロード

```swift
// 言語モデルの事前DL（アプリ起動時に実行推奨）
func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
    // 1. ロケールのサポート確認
    let supported = await SpeechTranscriber.supportedLocales
    guard supported.map({ $0.identifier(.bcp47) }).contains(locale.identifier(.bcp47)) else {
        throw STTError.localeNotSupported
    }

    // 2. インストール済みか確認
    let installed = await Set(SpeechTranscriber.installedLocales)
    if installed.map({ $0.identifier(.bcp47) }).contains(locale.identifier(.bcp47)) {
        return // 既にインストール済み
    }

    // 3. ダウンロード実行
    if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
        try await downloader.downloadAndInstall()
    }
}
```

**ポイント**:
- 言語モデルはシステムワイドのアセットカタログに保存（アプリサイズに影響なし）
- 複数アプリで共有される
- ダウンロード進捗の表示を推奨
- システムが自動でモデルを更新し、最新の認識精度を維持

### 3.4 コンテキスト付与の方法

SpeechAnalyzer には **明示的なコンテキスト付与API がない**（SFSpeechRecognizer の `contextualStrings` に相当する機能なし）。

**代替手段**:
- Apple Foundation Models (iOS 26) による後処理で補正（後述）
- アプリケーションレベルでの辞書ベース後処理

### 3.5 セグメンテーション戦略

```swift
// SpeechDetector + SpeechTranscriber の組み合わせ
let transcriber = SpeechTranscriber(locale: Locale(identifier: "ja_JP"), preset: .progressiveLiveTranscription)
let detector = SpeechDetector(detectionOptions: [], reportResults: true)
let analyzer = SpeechAnalyzer(modules: [transcriber, detector])
```

- `SpeechDetector` で音声区間を検出し、無音区間でのセグメント分割が可能
- `audioTimeRange` 属性で単語レベルのタイミング情報を取得
- volatile / final の2段階結果で段階的なテキスト確定

**結果の処理**:
```swift
for try await result in transcriber.results {
    if result.isFinal {
        // 確定テキスト — 変更されない
        finalizedText += String(result.text.characters)
    } else {
        // 中間テキスト — 随時更新される
        volatileText = String(result.text.characters)
    }

    // タイムスタンプ取得
    if let timeRange = result.text.runs.first?.audioTimeRange {
        // 音声-テキスト同期に利用可能
    }
}
```

---

## 4. 固有名詞対応

### 4.1 SpeechAnalyzer の固有名詞認識の現状

**課題**: SpeechAnalyzer には固有名詞の認識を直接改善する仕組みがない。

MacStories のテスト結果:
> "All three transcription workflows had trouble with last names and words like 'AppStories,' which LLMs tend to separate into two words instead of camel casing."

これは Whisper ベースのツールでも同様の課題であり、SpeechAnalyzer 固有の問題ではない。

### 4.2 連絡先統合 (Contacts Integration)

SpeechAnalyzer には **連絡先統合機能は確認されていない**。

旧 `SFSpeechRecognizer` では、デバイスの連絡先情報がある程度認識に反映されていたが、SpeechAnalyzer ではこの統合について公式情報がない。

### 4.3 後処理による補正テクニック（推奨アプローチ）

SpeechAnalyzer にカスタム語彙がない以上、**後処理が固有名詞対応の主要戦略**となる。

#### 方法1: Apple Foundation Models (iOS 26) による LLM 後処理

```swift
import FoundationModels

// 文字起こし結果を Foundation Models で補正
@Generable
struct CorrectedTranscription {
    @Guide(description: "補正後のテキスト")
    var correctedText: String

    @Guide(description: "検出された固有名詞リスト")
    var properNouns: [String]
}

func correctTranscription(rawText: String, knownVocabulary: [String]) async throws -> CorrectedTranscription {
    let model = SystemLanguageModel.default
    let vocabularyList = knownVocabulary.joined(separator: ", ")

    let prompt = """
    以下の音声文字起こしテキストを補正してください。
    既知の固有名詞リスト: \(vocabularyList)

    テキスト: \(rawText)

    固有名詞の誤認識を修正し、句読点を整えてください。
    """

    let response = try await model.generate(CorrectedTranscription.self, prompt: prompt)
    return response
}
```

**Apple Foundation Models の日本語サポート**: 確認済み（10言語対応: 英語、ドイツ語、スペイン語、フランス語、イタリア語、**日本語**、韓国語、ポルトガル語、中国語）

**制約**:
- Apple Intelligence 対応デバイスが必要
- ~3Bパラメータのオンデバイスモデル
- 2bit量子化、KV-cacheシェアリングで最適化済み

#### 方法2: 辞書ベースの後処理（軽量）

```swift
/// 既知の固有名詞辞書による後処理補正
struct VocabularyCorrector {
    /// キー: 誤認識されやすい表記, 値: 正しい表記
    let corrections: [String: String]

    /// 読み仮名 → 正しい表記のマッピング
    let readingMap: [String: String]

    func correct(_ text: String) -> String {
        var result = text
        for (wrong, correct) in corrections {
            result = result.replacingOccurrences(of: wrong, with: correct)
        }
        return result
    }
}

// 使用例
let corrector = VocabularyCorrector(
    corrections: [
        "まーまーノート": "MurMurNote",
        "マーマーノート": "MurMurNote",
    ],
    readingMap: [
        "いとむら": "糸村",
        "たなか": "田中",
    ]
)
```

#### 方法3: マルチパスLLM補正（研究ベース）

学術研究 (Benchmarking Japanese Speech Recognition on ASR-LLM Setups, 2024) で提案されたアプローチ:
1. ASRの複数仮説（N-best list）を生成
2. LLMで各仮説の信頼度を評価
3. 不確実な箇所にLLMベースの補正を適用
4. 特に固有名詞・専門用語に対して音声的コンテキストを活用

---

## 5. Argmax WhisperKit との比較

### 5.1 ベンチマーク結果（Earnings22 データセット、10%サブセット、約12時間）

| エンジン | WER (%) | 速度 (倍速) | カスタム語彙 |
|:--------|:--------|:----------|:-----------|
| Apple SpeechTranscriber | 14.0% | 70x | **非対応** |
| WhisperKit (whisper-base.en) | 15.2% | 111x | 非対応 (OSS版) |
| WhisperKit (whisper-small.en) | 12.8% | 35x | 非対応 (OSS版) |
| **Argmax Pro SDK (parakeet-v2)** | **11.7%** | **359x** | **対応** |

テスト環境: M4 Mac mini, macOS 26 Beta Seed 1

### 5.2 機能比較

| 機能 | Apple SpeechAnalyzer | WhisperKit (OSS) | Argmax Pro SDK |
|:-----|:-------------------|:----------------|:--------------|
| オフライン文字起こし | ○ | ○ | ○ |
| リアルタイム文字起こし | ○ | ○ | ○ |
| 話者分離 | - | - | ○ |
| 言語自動検出 | - | ○ | ○ |
| 対応言語数 | ~42 | ~100 | ~100 |
| カスタム語彙 | **-** | - (OSS) | **○** |
| 権限要求 | マイクのみ | マイクのみ | マイクのみ |
| アプリサイズ影響 | なし（システム管理） | あり（モデル同梱） | あり |
| 日本語WER (whisper-small比) | 1%以内の差 | ベースライン | より良い |

### 5.3 カスタム語彙の差を埋める方法

SpeechAnalyzer でカスタム語彙の欠如を補う戦略:

1. **Foundation Models による後処理** (推奨)
   - SpeechAnalyzer → Foundation Models でテキスト補正
   - 既知語彙リストをプロンプトに含める
   - オンデバイスで完結、プライバシー維持

2. **ハイブリッドアプローチ**
   - SpeechAnalyzer + アプリレベルの辞書後処理
   - 頻出固有名詞のパターンマッチング
   - 連絡先データベースとの照合

3. **WhisperKit との併用**（MurMurNote の現行アーキテクチャ活用）
   - 通常は SpeechAnalyzer を使用（軽量、システム管理）
   - 高精度が必要な場合は WhisperKit にフォールバック
   - STTEngineFactory での切替機構を活用

---

## 6. 実装パターン（Swift 6.2）

### 6.1 完全なストリーミング実装

```swift
import Speech
import AVFoundation

@Observable
final class SpeechAnalyzerTranscriptionManager: Sendable {
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var recognizerTask: Task<(), Error>?
    private var analyzerFormat: AVAudioFormat?
    private let converter = BufferConverter()
    private let audioEngine = AVAudioEngine()

    // MARK: - Audio Session

    func setupAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Model Management

    func ensureJapaneseModel() async throws {
        let locale = Locale(identifier: "ja_JP")
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveLiveTranscription)

        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
            throw TranscriptionError.localeNotSupported
        }

        let installed = await SpeechTranscriber.installedLocales
        guard !installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
            return
        }

        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await downloader.downloadAndInstall()
        }
    }

    // MARK: - Transcription

    func startTranscription(
        onResult: @escaping @Sendable (String, Bool) -> Void
    ) async throws {
        let locale = Locale(identifier: "ja_JP")

        transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )

        guard let transcriber else { return }

        // モデル確認
        try await ensureJapaneseModel()

        // Analyzer 初期化
        analyzer = SpeechAnalyzer(modules: [transcriber])

        // 最適フォーマット取得
        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        // AsyncStream 作成
        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputBuilder = inputBuilder

        // 結果処理タスク
        recognizerTask = Task {
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                onResult(text, result.isFinal)
            }
        }

        // 分析開始
        try await analyzer?.start(inputSequence: inputSequence)

        // 音声キャプチャ開始
        try startAudioCapture()
    }

    private func startAudioCapture() throws {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            try? self?.processAudioBuffer(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) throws {
        guard let inputBuilder, let analyzerFormat else { return }
        let converted = try converter.convertBuffer(buffer, to: analyzerFormat)
        inputBuilder.yield(AnalyzerInput(buffer: converted))
    }

    // MARK: - Cleanup

    func stopTranscription() async {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        inputBuilder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil
    }
}
```

### 6.2 ファイルベースのバッチ処理

```swift
func transcribeAudioFile(url: URL, locale: Locale) async throws -> String {
    let transcriber = SpeechTranscriber(locale: locale, preset: .offlineTranscription)

    // モデル確保
    if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
        try await downloader.downloadAndInstall()
    }

    let analyzer = SpeechAnalyzer(modules: [transcriber])
    try await analyzer.start(inputAudioFile: AVAudioFile(forReading: url), finishAfterFile: true)

    var fullText = ""
    for try await result in transcriber.results {
        if result.isFinal {
            fullText += String(result.text.characters)
        }
    }

    return fullText
}
```

### 6.3 エラーハンドリング

```swift
enum TranscriptionError: LocalizedError {
    case localeNotSupported
    case modelDownloadFailed(Error)
    case audioSessionFailed(Error)
    case analyzerStartFailed(Error)

    var errorDescription: String? {
        switch self {
        case .localeNotSupported:
            return "指定されたロケールはサポートされていません"
        case .modelDownloadFailed(let error):
            return "言語モデルのダウンロードに失敗しました: \(error.localizedDescription)"
        case .audioSessionFailed(let error):
            return "オーディオセッションの設定に失敗しました: \(error.localizedDescription)"
        case .analyzerStartFailed(let error):
            return "音声分析の開始に失敗しました: \(error.localizedDescription)"
        }
    }
}

// 既知の問題: ロケール形式の不一致
// en_GB (アンダースコア) vs en-GB (ハイフン) で不一致が発生する場合がある
// → identifier(.bcp47) を使って正規化して比較する
```

### 6.4 バックグラウンド動作

SpeechAnalyzer のバックグラウンド動作に関する公式ドキュメントは限定的だが、以下の設定が必要:

```swift
// Info.plist に追加
// UIBackgroundModes: audio

// Audio Session の設定
try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .allowBluetooth])
try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
```

**注意**: 長時間のバックグラウンド録音は Apple のレビューガイドラインに従う必要がある。

### 6.5 権限要求

```swift
// SpeechAnalyzer は音声認識権限が不要（SFSpeechRecognizer との大きな違い）
// マイク権限のみ必要

func requestMicrophonePermission() async -> Bool {
    await withCheckedContinuation { continuation in
        AVAudioApplication.requestRecordPermission { granted in
            continuation.resume(returning: granted)
        }
    }
}

// Info.plist
// NSMicrophoneUsageDescription: "音声メモの録音と文字起こしに使用します"
```

---

## 7. 精度最大化のための統合戦略（MurMurNote 向け推奨）

### 7.1 短期戦略（iOS 26 リリース時点）

```
[マイク入力]
    ↓
[AVAudioEngine + bestAvailableAudioFormat 変換]
    ↓
[SpeechTranscriber (ja_JP, progressiveLiveTranscription)]
    ↓
[volatile / final 結果取得]
    ↓
[辞書ベース後処理（パターンマッチング）]
    ↓
[UI表示]
```

- SpeechAnalyzer を主エンジンに（軽量、権限シンプル、システム管理）
- 固有名詞は辞書ベースの後処理で対応
- ユーザーが登録した語彙を辞書に追加する仕組みを提供

### 7.2 中期戦略（Foundation Models 統合）

```
[SpeechTranscriber の final 結果]
    ↓
[Apple Foundation Models による後処理]
    ├── 固有名詞補正（既知語彙リストから）
    ├── 句読点・段落整形
    └── 要約・タグ付け（既存 AI パイプラインと統合）
    ↓
[補正済みテキスト]
```

### 7.3 長期戦略（ハイブリッドエンジン）

```
[STTEngineFactory]
    ├── SpeechAnalyzer（デフォルト、通常利用）
    ├── WhisperKit（高精度モード、カスタム語彙必要時）
    └── SFSpeechRecognizer + CustomLM（レガシーフォールバック）
```

- ユーザー設定で切替可能
- 用途に応じた自動選択（短い音声 → SpeechAnalyzer、長文 + 専門用語 → WhisperKit）

---

## 8. 既知の制限事項・注意点

### 8.1 SpeechAnalyzer の制限

| 制限 | 詳細 |
|:-----|:-----|
| iOS 26以上が必須 | iOS 17-25 のユーザーは利用不可 |
| カスタム語彙なし | 固有名詞認識は改善手段がない（後処理で対応） |
| watchOS 非対応 | iOS, macOS, tvOS, visionOS のみ |
| デバイス性能依存 | iPhone 14 Pro でも処理速度に課題あり（asken 技術ブログ） |
| コンテキスト付与不可 | `contextualStrings` に相当する機能なし |
| モデル選択不可 | Apple 提供のモデルのみ使用 |

### 8.2 日本語固有の課題

- 漢字変換の精度がコンテキストに依存
- 同音異義語の判別は文脈推定に依存
- カタカナ外来語の表記ゆれ（「コンピューター」vs「コンピュータ」）
- 方言・なまりへの対応は未知

### 8.3 SpeechAnalyzer vs SFSpeechRecognizer トレードオフ

| 観点 | SpeechAnalyzer | SFSpeechRecognizer |
|:-----|:-------------|:-----------------|
| モデル品質 | 新モデル（Whisper mid-tier相当） | 旧モデル |
| カスタム語彙 | **非対応** | CustomLanguageModel 対応 |
| 権限 | マイクのみ | マイク + 音声認識 |
| 長文対応 | 優れている | 1分制限あり（オンデバイス） |
| 実装量 | やや多い | シンプル |
| 将来性 | Apple の主力API | レガシー化の可能性 |

---

## 9. ソース一覧

### Apple 公式

- [SpeechAnalyzer | Apple Developer Documentation](https://developer.apple.com/documentation/speech/speechanalyzer)
- [SpeechTranscriber | Apple Developer Documentation](https://developer.apple.com/documentation/speech/speechtranscriber)
- [Bringing advanced speech-to-text capabilities to your app](https://developer.apple.com/documentation/Speech/bringing-advanced-speech-to-text-capabilities-to-your-app)
- [WWDC25 Session 277: Bring advanced speech-to-text to your app with SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)
- [SFCustomLanguageModelData | Apple Developer Documentation](https://developer.apple.com/documentation/speech/sfcustomlanguagemodeldata)
- [WWDC23: Customize on-device speech recognition](https://developer.apple.com/videos/play/wwdc2023/10101/)

### Argmax

- [Apple SpeechAnalyzer and Argmax WhisperKit](https://www.argmaxinc.com/blog/apple-and-argmax)
- [WhisperKit GitHub](https://github.com/argmaxinc/WhisperKit)
- [Apple SpeechAnalyzer CLI Example](https://github.com/argmaxinc/apple-speechanalyzer-cli-example)

### コミュニティ・技術ブログ

- [iOS 26: SpeechAnalyzer Guide (Anton Gubarenko)](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide)
- [Implementing advanced speech-to-text in your SwiftUI app (Create with Swift)](https://www.createwithswift.com/implementing-advanced-speech-to-text-in-your-swiftui-app/)
- [WWDC 2025 - The Next Evolution of Speech-to-Text (DEV Community)](https://dev.to/arshtechpro/wwdc-2025-the-next-evolution-of-speech-to-text-using-speechanalyzer-6lo)
- [WWDC25: SpeechAnalyzer (Appcircle Blog)](https://appcircle.io/blog/wwdc25-bring-advanced-speech-to-text-capabilities-to-your-app-with-speechanalyzer)
- [iOS 26 SpeechAnalyzer と SpeechRecognizer の比較 (asken技術ブログ)](https://tech.asken.inc/entry/20251205)
- [Hands-On: Apple's New Speech APIs Outpace Whisper (MacStories)](https://www.macstories.net/stories/hands-on-how-apples-new-speech-apis-outpace-whisper-for-lightning-fast-transcription/)
- [On-Device Speech Transcription with Apple SpeechAnalyzer (Callstack)](https://www.callstack.com/blog/on-device-speech-transcription-with-apple-speechanalyzer)
- [swift-scribe (GitHub)](https://github.com/FluidInference/swift-scribe)
- [SwiftUI SpeechAnalyzer Demo (GitHub)](https://github.com/0Itsuki0/SwiftUI_SpeechAnalyzerDemo)

### 学術論文

- [Benchmarking Japanese Speech Recognition on ASR-LLM Setups (arXiv:2408.16180)](https://arxiv.org/abs/2408.16180)
- [LLM-based Generative Error Correction for Rare Words (arXiv:2505.17410)](https://arxiv.org/html/2505.17410v1)
- [WhisperKit: On-device Real-time ASR (ICML 2025, arXiv:2507.10860)](https://arxiv.org/html/2507.10860v1)
