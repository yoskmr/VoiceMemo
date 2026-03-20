# STT（Speech-to-Text）APIコスト調査

## 依頼内容

音声メモアプリにおける音声文字起こし（Speech-to-Text）APIの料金比較調査。

## 調査対象サービス

1. OpenAI Whisper API (whisper-1)
2. OpenAI GPT-4o Transcribe API
3. OpenAI GPT-4o Mini Transcribe API
4. Google Cloud Speech-to-Text
5. Deepgram Nova-3
6. AssemblyAI
7. Apple SpeechAnalyzer（オンデバイス）
8. Whisper.cpp（オンデバイス）

## 実施した作業

- 各サービスの2025-2026年時点の最新料金をWeb検索で調査
- 1分/1時間あたりの料金比較表を作成
- 日本語対応・精度の評価
- 月間コストシミュレーション（1ユーザー/1日3分/月30日 = 月90分）
- スケール時（1,000ユーザー）のコスト予測
- ハイブリッド戦略の提案

## 得られた知見

- **最安クラウドAPI**: AssemblyAI Universal ($0.0025/分) - 月90分で$0.225
- **コスパ最良**: OpenAI GPT-4o Mini Transcribe ($0.003/分) - 精度と価格のバランス
- **最高精度**: OpenAI GPT-4o Transcribe ($0.006/分)
- **無料**: Apple SpeechAnalyzer / Whisper.cpp（オンデバイス）
- **推奨**: オンデバイス + クラウドAPIのハイブリッド戦略

## 成果物

- `result/202603152301/stt_api_cost_analysis.md` - 詳細な料金比較レポート
