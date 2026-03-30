# MurMurNote 競合調査レポート 2026-03-24

## 1. エグゼクティブサマリー

- 日本の App Store で文字起こし関連アプリは **86+ 個**、海外発日本語対応を含めると**約 108 個**
- **SpeechAnalyzer (iOS 26+) 採用アプリはまだ 6 個**で先行者優位あり
- **96.5% が無料アプリ**。有料で成立しているのは超高品質（Aiko）か法人向け（おとノート PRO）のみ
- **Apple ボイスメモ（175K レビュー）が最大の壁**
- MurMurNote の独自ポジション: **SpeechAnalyzer + WhisperKit 二重エンジン + カスタム辞書 + iOS 17+ 対応**

---

## 2. 直接競合分析:「文字起こし | AI文字起こし AI議事録作成」

| 項目 | 詳細 |
|:-----|:-----|
| 開発者 | YUSUKE SUZUKI（個人開発者） |
| Bundle ID | `com.giji-memo-intelligence` |
| 最低 OS | iOS 26.0（SpeechAnalyzer 使用確定） |
| 価格 | 無料（広告モデル） |
| 評価 | 4.0 / 8 件レビュー |
| アプリサイズ | 7.7MB（STT モデル非同梱 = OS 組込み SpeechAnalyzer） |
| 初回リリース | 2025-09-23 |
| 主要機能 | 無制限文字起こし、完全オフライン、Apple Intelligence 要約 |
| 開発者サイト | `homepage-5021a.web.app`（Firebase Hosting） |
| X（旧 Twitter） | @suke_arts |

### 弱点

- 要約機能で「Exceeded model context window size」エラー
- 録音データ再生不可
- 再文字起こし機能なし
- データ保存が脆弱（v1.0.4 で改善中）
- 辞書機能なし（レビューで要望あり）
- 要約品質が GPT-3 レベル

---

## 3. SpeechAnalyzer (iOS 26+) 技術分析

### 概要

- **WWDC 2025** で発表、`SFSpeechRecognizer` の後継
- 完全オンデバイス、Swift Concurrency 対応
- Apple 純正アプリ（Notes, Voice Memos, Journal）で採用済み

### 主要 API

| API | 役割 |
|:----|:-----|
| `SpeechAnalyzer` | セッション管理 |
| `SpeechTranscriber` | 文字起こしモジュール |
| `SpeechDetector` | 音声活動検出（VAD） |
| `DictationTranscriber` | 非 Apple Silicon デバイス向けフォールバック |
| `AssetInventory` | 言語モデル DL 管理 |

### 性能

- **Whisper 比 55% 高速**（34 分動画: 45 秒 vs 1 分 41 秒）
- **42 言語対応**（`ja_JP` 含む）
- 結果 2 種類: **Volatile Results**（高速・暫定）+ **Final Results**（高精度・確定）

### 制限

- カスタム語彙**非対応**
- 話者認識**非対応**
- watchOS **非対応**
- Apple Silicon 必須（非対応デバイスは `DictationTranscriber` にフォールバック）

### 公式リソース

- Apple Developer Documentation: https://developer.apple.com/documentation/speech/speechanalyzer
- WWDC25 Session 277: https://developer.apple.com/videos/play/wwdc2025/277/
- 実装ガイド: https://developer.apple.com/documentation/Speech/bringing-advanced-speech-to-text-capabilities-to-your-app

---

## 4. iOS 26+ アプリ一覧（SpeechAnalyzer 使用確定）

| アプリ名 | 開発者 | サイズ | レビュー | 備考 |
|:--------|:------|:------|:--------|:-----|
| 文字起こし \| AI文字起こし | YUSUKE SUZUKI | 7.7MB | 8 件 | 広告モデル |
| Koemo：ローカルAI文字起こし | AsterKit | 21.3MB | 2 件 | ローカル AI 特化 |
| MojiOkoshi | ButterFalcon | 13.4MB | 3 件 | 音声入力・録音 |
| Transcription Pro | App ahead GmbH（独） | 21.6MB | 0 件 | iOS 26.2 要求 |
| 議事録 - AI文字起こし&要約 | SEP, K.K. | 7.3MB | 1 件 | 議事録特化 |
| Spokenly | Vadim Akhmerov | 40.2MB | 3 件 | SpeechAnalyzer + Parakeet + クラウド 3 エンジン |

> **合計 6 アプリ** — MurMurNote が参入すれば 7 番目。先行者優位が取れる段階。

---

## 5. 日本市場 主要競合アプリ一覧（レビュー数 TOP30）

| # | アプリ名 | 開発者 | iOS | 価格 | ★ | レビュー | サイズ | カテゴリ |
|:--|:--------|:------|:----|:----|:--|:--------|:------|:--------|
| 1 | Apple ボイスメモ | Apple | 10.0 | 無料 | 4.65 | 175,478 | 14.2MB | 純正 |
| 2 | Notta | MindCruiser | 13.0 | 無料 | 4.34 | 23,359 | 181.8MB | クラウド STT |
| 3 | Texter | Yuichi Matsuoka | 16.0 | 無料 | 4.11 | 7,801 | 194.2MB | 日本語特化 |
| 4 | Speechy Lite | 吉华 郑 | 15.0 | 無料 | 4.28 | 5,337 | 22.3MB | シンプル |
| 5 | Otter.ai | Otter.ai, Inc. | 16.0 | 無料 | 4.71 | 5,122 | 252.3MB | 英語のみ |
| 6 | 無限もじおこし | Haruki Kurosawa | 17.2 | 無料 | 4.62 | 4,369 | 78.1MB | 個人開発 |
| 7 | LINE WORKS AiNote | LINE WORKS Corp. | 16.0 | 無料 | 4.57 | 4,215 | 122.7MB | CLOVA Note 後継 |
| 8 | Vosual | BarrierBreak | 12.0 | 無料 | 4.37 | 3,893 | 13.2MB | 老舗 |
| 9 | AutoMemo | SOURCENEXT | 15.0 | 無料 | 4.31 | 2,100 | 31.8MB | Whisper 搭載 |
| 10 | おとノート | Newkline Co., Ltd. | 15.0 | 無料 | 4.48 | 1,646 | 42.6MB | 会議録・講義録 |
| 11 | Speechy（有料） | 圣辉 金 | 14.1 | ¥2,500 | 4.18 | 1,141 | 19.3MB | 買い切り |
| 12 | Spiik | Fadel.io OU | 16.0 | 無料 | 4.39 | 858 | 56.7MB | ボイスメモ+文字起こし |
| 13 | AI文字起こし・録音&要約 | Voice Inc. | 16.2 | 無料 | 4.42 | 607 | 187.7MB | 要約付き |
| 14 | UDトーク | Shamrock Records | 13.0 | 無料 | 3.68 | 333 | 50.8MB | アクセシビリティ |
| 15 | 録音アプリ - ボイスレコーダー | Yaremenko Oleksandr | 15.0 | 無料 | 4.14 | 304 | 366.4MB | 汎用 |
| 16 | Notebook LLM | APTE Ltd | 15.0 | 無料 | 4.25 | 297 | 118.1MB | LLM 連携 |
| 17 | 文字起こしさん | Atsushi Koyama | 18 | 無料 | 4.73 | 291 | 49.7MB | 個人開発（複数展開） |
| 18 | Noted | Digital Workroom Ltd | 16.4 | 無料 | 4.11 | 289 | 364.3MB | 録音・転写 |
| 19 | iRecord | Youdao (Hong Kong) | 15.0 | 無料 | 4.38 | 275 | 273.4MB | 中国系 |
| 20 | SpeakApp AI | VoicePop Inc. | 16.0 | 無料 | 4.39 | 243 | 94.9MB | Voice Notes |
| 21 | 同時通訳 | Kotoba Technologies | 17.6 | 無料 | 3.69 | 240 | 38.2MB | 翻訳+文字起こし |
| 22 | Transcriber | WBS | 14.2 | 無料 | 4.49 | 239 | 119.8MB | 音声文字変換 |
| 23 | おとノート PRO | Newkline Co., Ltd. | 15.0 | ¥6,000 | 4.36 | 204 | 42.6MB | 買い切り高級版 |
| 24 | YY文字起こし | 株式会社エクォス・リサーチ | 15.5 | 無料 | 4.17 | 196 | 155.8MB | 法人開発 |
| 25 | もじおこし | Takumi Yoshikoshi | 16.1 | 無料 | 4.42 | 176 | 12.0MB | シンプル |
| 26 | ディクテーション | Christian Neubauer | 16.4 | 無料 | 3.93 | 174 | 31.5MB | テキスト化 |
| 27 | SmartNoter | DEEP FLOW SOFTWARE | 15.6 | 無料 | 4.68 | 132 | 229.7MB | 多言語 |
| 28 | Summary | Labhouse Mobile | 15.0 | 無料 | 4.45 | 130 | 209.8MB | 議事録&会議要約 |
| 29 | Coconote | Quizlet Inc | 17.0 | 無料 | 4.66 | 120 | 80.7MB | 学生向け |
| 30 | Transcribe | DENIVIP | 17.5 | 無料 | 4.31 | 118 | 160.9MB | 音声→テキスト |

---

## 6. 海外アプリ（日本語対応・脅威度順）

### 脅威度: 高

| アプリ名 | 開発者 | 日本語 | STT エンジン | 課金 | 特徴 |
|:--------|:------|:------|:-----------|:----|:-----|
| VOMO AI | EverGrow Tech | 対応（専用チューニング） | 独自 AI + GPT-4o | 無料 30 分/月 | 日本語専用モデル調整済み |
| Whisper Notes | whispernotes.app | 対応（80 言語） | NVIDIA Parakeet v3 + Whisper | 買い切り $6.99 | 買い切り + オフライン高精度 |
| Whisper Transcription | Good Snooze (Jordi Bruin) | 対応 | Whisper | フリーミアム | MacWhisper の iOS 版。高機能 |
| Fireflies.ai | Fireflies.ai Inc. | 対応（100 言語） | 独自 AI | 無料（対面無制限） | ビジネス浸透力 |
| Spokenly | Vadim Akhmerov | 対応（100 言語） | SpeechAnalyzer + Parakeet + Cloud | 無料（SA/Parakeet） | SpeechAnalyzer 先行統合 |

### 脅威度: 中

| アプリ名 | 開発者 | 日本語 | STT エンジン | 課金 | 特徴 |
|:--------|:------|:------|:-----------|:----|:-----|
| Aiko | Sindre Sorhus | 対応 | Whisper（オンデバイス） | 無料 | 完全無料 + 高品質 |
| Rev | Rev.com | 対応（37 言語） | Rev 独自 AI + 人間 | 従量（$0.25/分） | プロ向け |
| Superwhisper | 独立系 | 対応（100 言語） | Whisper | フリーミアム | ディクテーション特化 |
| Read AI | Read AI | 対応（16 言語） | 独自 AI | 無料 5 会議/月 | 会議 + メール横断検索 |
| Granola | Granola | 不明 | 独自 AI | $14/月 | AI notepad コンセプト |
| Wave AI | Wave | 不明 | 独自 AI | フリーミアム | バックグラウンド録音 |
| tl;dv | tldx Solutions | 対応（30 言語） | 独自 AI | 無料（制限あり） | セールス向け |
| Sonix | Sonix, Inc. | 対応（日本語方言対応） | 独自 AI | サブスク | 日本語方言モデル |

### 脅威度: 低

| アプリ名 | 理由 |
|:--------|:-----|
| Just Press Record | Apple Speech 依存、機能限定的 |
| Krisp | モバイルでノイズキャンセル非対応 |
| Fathom | iOS アプリなし |
| Tactiq | Chrome 拡張のみ |
| Jamie | 高価格帯（法人向け） |

---

## 7. 注目すべき個人開発者の戦略

### Atsushi Koyama（3 アプリ展開戦略）

| アプリ | レビュー | 狙いキーワード |
|:------|:--------|:-------------|
| 文字起こしさん | 291 件 | 「文字起こし」 |
| AI音声文字起こし | 65 件 | 「AI文字起こし」 |
| 議事録アプリ | 90 件 | 「議事録」 |

**戦略**: 同一エンジンで複数アプリを展開し、キーワード別に ASO を最大化。

### Haruki Kurosawa（2 アプリ）

| アプリ | レビュー | 市場 |
|:------|:--------|:-----|
| 無限もじおこし | 4,369 件 | 文字起こし市場 |
| シャべマル | 50 件 | 音声メモ日記市場 |

### 株式会社エクォス・リサーチ（3 アプリ、法人開発）

- **YY文字起こし** / **YYProbe** / **YYレセプション** — 法人・福祉向け展開

---

## 8. 市場トレンド

1. **AI 要約の標準化** — 文字起こしだけでは差別化不可能。LLM 要約が必須機能に
2. **話者分離の重要性向上** — 会議用途で「誰が何を言ったか」が必須
3. **オンデバイス処理への回帰** — プライバシー + レイテンシ削減
4. **NVIDIA Parakeet v3 の台頭** — Whisper の代替 STT エンジン
5. **CLOVA Note 撤退による市場再編** — 2025 年 7 月末サービス終了
6. **専用ハードウェア連携** — Plaud Note, AutoMemo
7. **SpeechAnalyzer 未成熟** — Sansan Tech Blog で「落とし穴」報告あり

---

## 9. 価格戦略分析

| 価格帯 | アプリ数 | 代表例 |
|:------|:--------|:------|
| 無料（広告） | 83 個（96.5%） | 大半の競合 |
| 買い切り（低） | 2 個 | Whisper Notes ¥800 |
| 買い切り（中） | 1 個 | Speechy ¥2,500 |
| 買い切り（高） | 2 個 | Aiko ¥4,000, おとノート PRO ¥6,000 |
| サブスク（低） | 多数 | $1.99〜$7.99/月 |
| サブスク（中） | 多数 | Notta ¥1,200〜1,800/月 |
| サブスク（高） | 少数 | tl;dv $59/月 |

---

## 10. MurMurNote 戦略的提言

### ポジショニング

**「個人の思考整理ツール」** として差別化。会議議事録市場（Otolio, Notta）との正面衝突を避ける。

### 独自の強み（全競合に対する優位性）

1. **SpeechAnalyzer + WhisperKit 二重エンジン** — iOS 26 以降は SpeechAnalyzer、iOS 17〜25 は WhisperKit で全デバイスカバー
2. **カスタム辞書（LLM 後処理）** — SpeechAnalyzer のカスタム語彙非対応を補完
3. **iOS 17+ 対応** — iOS 26 専用アプリより広い市場にリーチ
4. **SwiftData + FTS5 全文検索** — ローカル完結の高速検索
5. **TCA + Clean Architecture の拡張性** — 長期的なメンテナンス性と機能追加の容易さ

### 競合の弱点を突くポイント

| 競合 | 弱点 | MurMurNote の対抗策 |
|:----|:-----|:------------------|
| Apple ボイスメモ | カスタマイズ性なし、検索弱い | カスタム辞書 + FTS5 全文検索 |
| 無限もじおこし | AI 要約なし（推定） | LLM 要約・タグ付け |
| 競合 iOS 26 アプリ | データ永続化が脆弱、機能不足 | SwiftData による堅牢な永続化 |
| Notta / AutoMemo | クラウド依存、高額サブスク | 完全オンデバイス + 低価格 |

### 推奨価格戦略

- オンデバイス処理で**サーバーコスト不要**
- **買い切り or 低価格サブスク**が有効
- Speechy（¥2,500 買い切り）の成功モデルを参考に

### 今後のウォッチ対象

- **Sansan Tech Blog** の「SpeechAnalyzer の落とし穴」記事
- **NVIDIA Parakeet v3** の iOS 対応状況
- **Spokenly** の SpeechAnalyzer 統合の進展
- **VOMO AI** の日本市場浸透度
