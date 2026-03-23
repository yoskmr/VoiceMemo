# iOS オンデバイス日本語音声認識 (STT) 徹底調査レポート

**調査日**: 2026-03-23
**対象**: iOS 17+ / iPhone A16+ (6GB+ RAM) / 完全オンデバイス日本語STT

---

## 1. 調査要件

- **完全オンデバイス**（ネットワーク不要）
- **日本語の高精度認識**（固有名詞、地名、人名を含む）
- **リアルタイムストリーミング対応**（録音しながらテキスト表示）
- カスタム辞書/語彙対応があれば望ましい

---

## 2. 各選択肢の詳細分析

### 2.1 Apple Speech Framework (SFSpeechRecognizer) — iOS 17-18

| 項目 | 詳細 |
|------|------|
| **日本語精度** | 中程度。オンデバイスモードはサーバーモードより劣る。固有名詞の認識は弱い |
| **ストリーミング** | ネイティブ対応。リアルタイム中間結果あり |
| **メモリ** | 軽量（システム管理、アプリ負担なし） |
| **モデルサイズ** | システム内蔵（追加DL不要） |
| **カスタム辞書** | iOS 17+ で `SFCustomLanguageModelData` による Custom Language Model 対応。X-SAMPAで発音定義可能。ただし日本語でのCustom Language Model対応は限定的 |
| **導入容易性** | 最も容易。Apple純正フレームワーク、Swift完全対応 |
| **課題** | `requiresOnDeviceRecognition = true` 時の精度がサーバー版より劣る。モデルの選択・改善不可 |

### 2.2 Apple SpeechAnalyzer — iOS 26+ (WWDC 2025)

| 項目 | 詳細 |
|------|------|
| **日本語精度** | Whisper mid-tier相当。Apple公式ベンチマークで「中位Whisperモデルと同等の速度・精度」と発表 |
| **ストリーミング** | `SpeechTranscriber` でリアルタイムストリーミング対応。低レイテンシ |
| **メモリ** | システム管理（言語モデルはシステムワイドのアセットカタログに格納） |
| **モデルサイズ** | 言語パック要DL（システムが自動管理、複数アプリで共有） |
| **カスタム辞書** | **非対応**（SFSpeechRecognizerにあったCustom Vocabulary機能が欠落） |
| **対応ロケール** | ja_JP 確認済み。40以上のロケール対応 |
| **導入容易性** | Apple純正、Swift対応。ただしiOS 26+必須 |
| **実績** | Notes, Voice Memos, Journal に既に搭載 |
| **課題** | iOS 26以上が必須。カスタム辞書なし |

**補足**: Argmax (WhisperKit) + Custom Vocabulary は SpeechAnalyzer を大幅に上回り、トップクラウドAPIと同等のキーワード認識精度を達成。

### 2.3 WhisperKit

| 項目 | 詳細 |
|------|------|
| **日本語精度** | モデル依存。base: 中〜低、small: 中、large-v3-turbo: 高 |
| **ストリーミング** | 対応。Audio Encoderがネイティブにストリーミング推論をサポート |
| **レイテンシ** | 0.46秒（最低レイテンシクラス） |
| **カスタム辞書** | initial prompt による間接的な語彙誘導（baseモデルのコンテキスト上限224トークンでは効果限定的） |
| **導入容易性** | Swift Package Manager対応。Apple Silicon最適化済み |

**モデル別スペック**:

| モデル | パラメータ | サイズ(fp16) | iPhoneで動作 | 日本語精度 |
|--------|-----------|-------------|-------------|-----------|
| tiny | 39M | ~30MB | 全機種OK | 低（英語偏重） |
| base | 74M | ~140MB | 全機種OK | 中〜低 |
| small | 244M | ~460MB | 6GB+推奨 | 中 |
| medium | 769M | ~1.5GB | Mac専用 | 中〜高 |
| large-v3-turbo | 1B | 1.6GB (圧縮後0.6GB) | **Mac専用** | 高 |

**重大な制約**:
- 4GB RAM デバイスでは base 以上のモデルで CoreML が OOM クラッシュ
- large-v3-turbo は現時点で iPhone/iPad 未対応（Mac Apple Silicon のみ）
- 6GB RAMデバイス（iPhone 15 Pro+）でも small が実用的な上限
- 日本語はWhisper訓練データの約17%（英語65%）。baseモデルでの日本語精度はhallucination多発

### 2.4 Sherpa-ONNX / Next-gen Kaldi

| 項目 | 詳細 |
|------|------|
| **日本語精度** | モデル依存。SenseVoice (int8): 高。ReazonSpeech-k2-v2: 非常に高い |
| **ストリーミング** | ネイティブ対応（ストリーミングASRモデル: Zipformer等） |
| **メモリ** | 軽量〜中程度（int8量子化モデルで大幅に削減） |
| **モデルサイズ** | SenseVoice int8: 約200MB、ReazonSpeech-k2-v2 int8: Whisper-Large-v3の1/10 |
| **カスタム辞書** | hotwords（ホットワード）機能で対応可能 |
| **導入容易性** | Swift対応だが、xcframeworkを手動ビルド・組み込みが必要 |
| **利用可能モデル** | SenseVoice (zh/en/ja/ko/yue)、ReazonSpeech-k2-v2 (日本語特化)、Zipformer streaming等 |
| **実績** | iOS/Android両対応。12プログラミング言語サポート |

**注目: ReazonSpeech-k2-v2** (159M パラメータ):
- 日本語ASRモデルの中でトップクラスの精度（JSUT-BASIC5000、Common Voice v8.0、TEDxJP-10K で既存モデルを上回る）
- int8量子化で Whisper-Large-v3 の約1/10サイズ
- GPU不要でオンデバイス動作
- ONNX形式でプラットフォーム非依存

**注目: SenseVoice-Small** (Alibaba):
- 非自己回帰型E2Eアーキテクチャ。Whisper-small の5倍高速、Whisper-large の15倍高速
- ASR + 言語識別 + 感情認識 + 音響イベント検出
- 日本語対応 (zh/en/ja/ko/yue の5言語)

### 2.5 Moonshine v2 (Useful Sensors / Moonshine AI)

| 項目 | 詳細 |
|------|------|
| **日本語精度** | v2 (2026年2月リリース) で日本語対応。Base (58M) モデル提供 |
| **ストリーミング** | v2で Ergodic Streaming Encoder 採用。低レイテンシ |
| **メモリ** | 非常に軽量（Tiny: 26M、Base: 58M パラメータ） |
| **モデルサイズ** | Tiny: 26M、Base: 58M、Medium: 245M |
| **導入容易性** | Swift Package Manager 対応（moonshine-swift） |
| **特徴** | 6倍のサイズのモデルと同等の精度。Whisper Large v3 より100倍高速 |
| **課題** | 日本語モデルは2026年リリースで比較的新しい。実績が少ない |

### 2.6 Vosk

| 項目 | 詳細 |
|------|------|
| **日本語精度** | 低〜中。旧世代のアーキテクチャ |
| **ストリーミング** | 対応 |
| **メモリ** | 非常に軽量（モデル約50MB） |
| **課題** | 精度が現代のTransformerベースモデルに大きく劣る。メンテナンス頻度低下傾向 |

### 2.7 Kotoba-Whisper (日本語特化Whisper蒸留モデル)

| 項目 | 詳細 |
|------|------|
| **日本語精度** | 高い。large-v3 と同等以上（ReazonSpeech評価セット） |
| **速度** | large-v3 の 6.3倍高速 |
| **iOS対応** | 直接のiOS/CoreMLサポートなし。ONNX変換→sherpa-onnx経由で利用可能性あり |
| **課題** | iOS向けの直接デプロイメントパスが確立されていない |

---

## 3. 総合比較表

| 項目 | SFSpeech (iOS17) | SpeechAnalyzer (iOS26) | WhisperKit (base) | WhisperKit (small) | Sherpa-ONNX + ReazonSpeech | Sherpa-ONNX + SenseVoice | Moonshine v2 |
|------|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| **日本語精度** | C+ | B+ | C | B | **A** | A- | B (未検証) |
| **リアルタイムストリーミング** | **A** | **A** | B+ | B | **A** | B+ | **A** |
| **メモリ使用量** | **A** | **A** | A | B+ | A- | A | **A** |
| **モデルサイズ** | **A** (内蔵) | A- (言語パック) | A (140MB) | B (460MB) | A- (~200MB) | A- (~200MB) | **A** (~50-100MB) |
| **バッテリー消費** | **A** | **A** | B | C+ | B+ | B+ | A- |
| **カスタム辞書** | B (Custom LM) | **F** (非対応) | C (prompt) | C (prompt) | **A** (hotwords) | B | ? |
| **導入容易性** | **A** | **A** | **A** (SPM) | **A** (SPM) | C+ (手動ビルド) | C+ (手動ビルド) | B+ (SPM) |
| **固有名詞対応** | C | C | C | B- | **A-** (hotwords) | B | ? |
| **iOS 17+ 対応** | OK | NG (iOS26+) | OK | OK | OK | OK | OK |

精度評価: A (WER/CER < 5%), B (5-10%), C (10-20%), F (機能なし)

---

## 4. 最終推奨

### 短期推奨（今すぐ改善）: Sherpa-ONNX + ReazonSpeech-k2-v2

**理由**:
1. **日本語精度が最高クラス**: 日本語特化159Mパラメータモデル。JSUT/CommonVoice/TEDxJPベンチマークで他モデルを上回る
2. **hotwords機能**: 固有名詞・地名をホットワードとして登録可能（カスタム辞書対応）
3. **真のストリーミングASR**: Whisperのバッチ処理設計と異なり、Zipformerベースのネイティブストリーミング
4. **軽量**: int8量子化でWhisper-Large-v3の1/10サイズ、iPhone 6GBで余裕動作
5. **iOS 17+対応**: 現在のターゲットOS対応

**課題**: xcframeworkの手動ビルドが必要。WhisperKitのSPM統合より導入コストが高い。

### 中期推奨（iOS 26 リリース後）: Apple SpeechAnalyzer への移行

**理由**:
1. Apple純正のため最もメンテナンスコストが低い
2. ANE最適化でバッテリー効率最良
3. Notes/Voice Memos/Journal で実績あり

**ただし**: カスタム辞書が非対応のため、固有名詞対応が必要な場合は WhisperKit + Custom Vocabulary との併用が必要。

### 推奨ハイブリッド戦略

```
iOS 17-25: Sherpa-ONNX + ReazonSpeech-k2-v2（日本語高精度）
iOS 26+:   Apple SpeechAnalyzer（Apple純正、ANE最適化）
フォールバック: Apple Speech Framework（最軽量）
```

既存の `STTEngineProtocol` に新エンジンを追加する形で段階的移行が可能。

---

## 5. 参考資料

- [WhisperKit: On-device Real-time ASR (arxiv)](https://arxiv.org/html/2507.10860v1)
- [Best open source STT model in 2026 (Northflank)](https://northflank.com/blog/best-open-source-speech-to-text-stt-model-in-2026-benchmarks)
- [Apple SpeechAnalyzer and Argmax WhisperKit (Argmax Blog)](https://www.argmaxinc.com/blog/apple-and-argmax)
- [WWDC25: Bring advanced STT to your app with SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)
- [GitHub - k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)
- [ReazonSpeech v2.1 (Reazon Research)](https://research.reazon.jp/blog/2024-08-01-ReazonSpeech.html)
- [GitHub - FunAudioLLM/SenseVoice](https://github.com/FunAudioLLM/SenseVoice)
- [GitHub - moonshine-ai/moonshine](https://github.com/moonshine-ai/moonshine)
- [Moonshine v2: Ergodic Streaming Encoder ASR (arxiv)](https://arxiv.org/html/2602.12241)
- [kotoba-tech/kotoba-whisper-v1.0 (Hugging Face)](https://huggingface.co/kotoba-tech/kotoba-whisper-v1.0)
- [WWDC23: Customize on-device speech recognition](https://developer.apple.com/videos/play/wwdc2023/10101/)
- [2025年 日本語文字起こしモデル徹底比較 (Zenn)](https://zenn.dev/hongbod/articles/def04f586cf168)
- [Running Speech Models with Swift Using Sherpa-Onnx (Medium)](https://carlosmbe.medium.com/running-speech-models-with-swift-using-sherpa-onnx-for-apple-development-d31fdbd0898f)
