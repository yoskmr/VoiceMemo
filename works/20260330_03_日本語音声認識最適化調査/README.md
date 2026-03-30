# 日本語音声認識・文字起こし最適化調査

**作成日**: 2026-03-30
**目的**: Soyoka の日本語音声認識精度を最大化するための技術調査と実装提案

## 調査範囲

1. Apple Speech Framework（SFSpeechRecognizer）の日本語固有設定
2. SpeechAnalyzer（iOS 26+）の日本語対応状況
3. WhisperKit / kotoba-whisper の日本語最適化
4. 日本語テキスト後処理（フィラー除去・句読点・漢字変換）
5. NaturalLanguage.framework / MeCab の日本語NLP活用

## 主要な調査結果

### 即座に適用可能な改善（P0）
- `AppleSpeechEngine` に `taskHint = .dictation` と `addsPunctuation = true` を追加
- これだけで句読点の自動挿入と認識精度のわずかな向上が見込める

### SpeechAnalyzer（iOS 26+）の重要な制約
- **カスタム辞書（contextualStrings）が非対応** → LLM後処理で補完する既存戦略は正しい
- `attributeOptions: [.audioTimeRange]` を追加することで単語タイムスタンプ取得が可能

### WhisperKit の日本語
- iPhone では small モデル（244M/460MB）が実用的な上限
- kotoba-whisper v2.2 の CoreML 版が HuggingFace で公開済み → 統合検証の価値あり
- `initial_prompt` は最初の30秒のみ有効という制約あり

## 成果物

- [調査レポート（詳細）](result/japanese-stt-optimization.md)
