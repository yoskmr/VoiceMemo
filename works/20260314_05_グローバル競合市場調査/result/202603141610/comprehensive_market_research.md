# 音声入力メモ・日記アプリ グローバル市場調査 統合レポート

**調査日**: 2026-03-14
**目的**: 音声入力を活用した日記・メモアプリの新規参入にあたり、グローバル競合環境・市場動向・ユーザーニーズを包括的に把握する

---

## エグゼクティブサマリー

### 市場の全体像

音声メモ・日記アプリ市場は、3つの成長市場の交差点に位置する巨大な機会領域である。

| 市場セグメント | 2024年規模 | 2030-33年予測 | CAGR |
|---|---|---|---|
| 音声認識市場 | $84.9億 | $231-537億 | 14-23% |
| ノートアプリ市場 | $79-95億 | $267億(2032) | 16.5% |
| デジタルジャーナルアプリ市場 | $51-55億 | $136億(2033) | 11.5% |

### 最重要ファインディング

1. **日本語 x AI音声日記は明確な空白地帯** - Untold（感情AI日記）の日本語版に相当するアプリが存在しない
2. **既存アプリは「録音」に強いが「活用」に弱い** - 録音後のワークフロー（文字起こし→整理→検索→活用）にペインが集中
3. **プライバシーファースト設計への需要急増** - Otter.ai訴訟を契機に、オンデバイス処理への期待が高まる
4. **サブスク疲れと買い切りモデルの再評価** - $4.99買い切りアプリが支持を獲得
5. **Z世代が音声ファースト世代** - 2027年までに64%が月次利用予測

---

## 1. 競合マップ（28プロダクト）

### 1.1 カテゴリ別競合一覧

```mermaid
mindmap
  root((音声メモ・日記アプリ<br>競合マップ))
    AI音声メモ・ノートテイキング
      Otter.ai
        2500万ユーザー
        ARR $100M
        4言語のみ
      Voicenotes
        100+言語
        $10/月
        個人の第二の脳
      AudioPen
        フィラー自動除去
        $99/年
      Audionotes
        多入力対応
        80+言語
        Lifetime $199
      Granola
        Bot不要
        評価額$250M
        90-92%精度
      VOMO AI
        99.9%精度
        50+言語
        $1.92/週
      Cleft Notes
        オンデバイス処理
        プライバシー重視
    音声日記
      Untold
        感情AI Hume連携
        完全無料
        iPhone専用
      AudioDiary
        AIセラピスト機能
        感情分析
      Murmur
        日本語対応
        感性的デザイン
      TalkJournal
        完全オフライン
        アカウント不要
    音声入力メモ
      Whisper Memos
        Apple Watch対応
        メール送信UX
      Whisper Notes
        買い切り$4.99
        完全オフライン
      Just Press Record
        買い切り$4.99
        Apple全デバイス
      Dictanote
        10万ユーザー
        Chrome拡張連動
      Speechnotes
        完全無料
        500万DL
      Transkriptor
        100+言語
        会議連携
    AI音声アシスタント型
      Notion AI
        1億ユーザー基盤
        ワークスペース統合
      Fireflies.ai
        50万社利用
        ユニコーン
      Notta
        日本語特化
        800万ユーザー
        物理デバイス展開
      Supernormal
        クロス会議メモリー
        Google Meet特化
    ウェアラブルデバイス
      Plaud Note
        100万台出荷
        ARR $100M
        112言語
      Omi AI
        $89低価格
        オープンソース
      Limitless
        Meta買収で終了
```

### 1.2 主要競合 詳細比較表

| アプリ | ユーザー規模 | 価格帯 | 音声認識技術 | 対応言語 | 差別化ポイント |
|---|---|---|---|---|---|
| **Otter.ai** | 2,500万 | Free / Pro $8.33/月 | 独自ASR | 4言語 | 企業向けナレッジベース化 |
| **Voicenotes** | 15万+ | $10/月 | Whisper+GPT-4 | 100+ | 個人の「第二の脳」 |
| **AudioPen** | 非公開 | $99/年 | Whisper+GPT | 多言語 | フィラー自動除去 |
| **Granola** | 急成長中 | $18/月 | GPT-4o+Claude | 多言語 | Bot不要会議録音 |
| **Untold** | 非公開 | **完全無料** | Hume AI | 英語中心 | 感情AI日記 |
| **AudioDiary** | 非公開 | フリーミアム | Deepgram | 多言語 | AIセラピスト機能 |
| **Just Press Record** | 非公開 | **$4.99買い切り** | Apple Speech | 30+ | Apple全デバイス統合 |
| **Whisper Notes** | 非公開 | **$4.99買い切り** | Whisper(on-device) | 90+ | 完全オフライン |
| **Notta** | 800万 | Free / Pro $8.17/月 | 日本語特化AI | 58 | 日本語98.86%精度 |
| **Plaud Note** | 100万台 | デバイス$159+ | 独自AI+Whisper | 112 | 超小型録音デバイス |

### 1.3 ポジショニングマップ

```mermaid
quadrantChart
    title 音声メモアプリ ポジショニングマップ
    x-axis 個人利用 --> ビジネス利用
    y-axis シンプル機能 --> AI高機能
    quadrant-1 "AI x ビジネス"
    quadrant-2 "AI x 個人"
    quadrant-3 "シンプル x 個人"
    quadrant-4 "シンプル x ビジネス"
    Otter.ai: [0.85, 0.80]
    Granola: [0.80, 0.85]
    Fireflies.ai: [0.90, 0.75]
    Notion AI: [0.75, 0.70]
    Notta: [0.70, 0.72]
    Voicenotes: [0.35, 0.78]
    AudioPen: [0.30, 0.75]
    Untold: [0.15, 0.70]
    AudioDiary: [0.15, 0.55]
    Just Press Record: [0.25, 0.20]
    Whisper Notes: [0.20, 0.35]
    Speechnotes: [0.20, 0.15]
    Plaud Note: [0.70, 0.65]
```

**空白地帯**: 「AI高機能 x 個人利用」の日本語特化ゾーン（Untold的体験の日本版）が明確に空いている

---

## 2. 市場トレンドと技術動向

### 2.1 技術の転換点

```mermaid
timeline
    title 音声AI技術の進化タイムライン
    2022年 : OpenAI Whisper公開
    2023年 : Whisper Large-v3 (500万時間学習)
    2024年 : Whisper Large-v3 Turbo (5.4倍高速)
           : Apple Voice Memosに AI文字起こし追加 (iOS 18)
    2025年 : GPT-4o Transcribe (Whisper超え)
           : Apple SpeechAnalyzer発表 (3B on-device)
           : WWDC: Siri AI刷新延期発表
    2026年春 : 新Siri (LLM V2) リリース予定
             : Google Gemini統合
```

**重要な技術シフト**:
- オンデバイスAI処理が実用水準に到達（Apple 3Bパラメータモデル、5ms未満のレイテンシ）
- Whisperの精度がコモディティ化（月間1,000万DL超）
- LLMによる音声→構造化テキストの変換が標準化

### 2.2 プラットフォーム各社の動き

| プラットフォーム | 直近の動き | 脅威レベル |
|---|---|---|
| **Apple** | Voice Memos/NotesにAI文字起こし追加。2026年春に新Siri（LLMベース） | **高** - エコシステム内完結の脅威 |
| **Google** | Recorder「Clear voice」開発中。Pixel専用 | **中** - Pixel限定で影響範囲小 |
| **Samsung** | Galaxy AI統合Voice Recorder。AI要約+翻訳 | **中** - Galaxy限定 |

### 2.3 ユーザー行動の変化

| 指標 | 数値 |
|---|---|
| 音声入力はキーボードの何倍速いか | **2.93倍** |
| Z世代の2027年月次利用予測 | **64%** |
| ミレニアル世代の月次利用率 | **61.9%** |
| 「音声の方が使いやすい」と回答した割合 | **90%** |
| 音声データプライバシーを懸念するユーザー | **45%** |

### 2.4 資金調達・M&A動向

| 企業 | 資金状況 | 備考 |
|---|---|---|
| Otter.ai | 累計$73M / ARR $100M | 2025年3月にARR $1億到達 |
| Granola | Series B $43M | 評価額$250M（2025年5月） |
| Fireflies.ai | 非公開 | 評価額$10億（ユニコーン） |
| Fathom | Series A $17M | 2024年9月 |
| Plaud AI | **外部資金ゼロ** | 年間売上$100M（ブートストラップ成功） |
| AssemblyAI | 累計$160M | 音声AI基盤技術 |

---

## 3. ユーザー不満・未充足ニーズ分析

### 3.1 不満の深刻度マップ

```mermaid
quadrantChart
    title ユーザー不満の分布（頻度 x 深刻度）
    x-axis 低頻度 --> 高頻度
    y-axis 低深刻度 --> 高深刻度
    quadrant-1 最優先で解決すべき
    quadrant-2 注意が必要
    quadrant-3 監視対象
    quadrant-4 改善余地あり
    音声認識精度: [0.9, 0.9]
    録音消失: [0.6, 0.95]
    検索整理不足: [0.85, 0.7]
    プライバシー: [0.7, 0.85]
    料金の高さ: [0.8, 0.65]
    多言語対応: [0.65, 0.75]
    オフライン非対応: [0.55, 0.6]
    編集のしにくさ: [0.7, 0.55]
```

### 3.2 最重要ペインポイント TOP 7

| 順位 | ペインポイント | 深刻度 | 代表的な声 |
|---|---|---|---|
| 1 | **音声認識精度（特に日本語）** | 最高 | 「存在しない単語を生成する」 |
| 2 | **プライバシー懸念** | 高 | Otter.ai集団訴訟が不信を加速 |
| 3 | **検索・整理機能の不足** | 高 | 「整理なしでは録音しなかったのと同じ」 |
| 4 | **サブスク疲れ** | 高 | 「保存するだけでサブスク必要」への反発 |
| 5 | **録音の信頼性** | 高 | 30分の録音が数秒に / 完全消失 |
| 6 | **多言語対応** | 中-高 | バイリンガルの言語混在で認識崩壊 |
| 7 | **オフライン対応** | 中-高 | AI文字起こしの大半がクラウド依存 |

### 3.3 ステータス・クオ（現状の代替手段）

音声メモアプリを使わない人は以下で代替している:

```mermaid
graph LR
    A[音声メモを使わない人の代替手段] --> B[キーボード入力<br>正確だが遅い]
    A --> C[手書きメモ<br>検索不可]
    A --> D[写真撮影<br>テキスト検索不可]
    A --> E[自分宛メール<br>ワークフロー断片化]
    A --> F[何もしない<br>アイデアを忘れる]
```

**3つの利用障壁**:
- **社会的障壁**: 公共の場で声を出すのが恥ずかしい
- **技術的障壁**: 認識精度への不信、修正の手間
- **習慣的障壁**: タイピングの方が慣れている

### 3.4 音声メモが特に求められるシーン

1. 運転中（CarPlay非対応が大きな障壁）
2. 歩行・ジョギング中
3. 寝起き・就寝前の日記
4. 料理・家事中
5. 感情的な瞬間（声の方が感情を伝えやすい）
6. 長文の思考整理（150 WPM vs 40 WPM）

---

## 4. 市場の空白領域と参入機会

### 4.1 競合が解決できていない根本課題

> **「音声でキャプチャしたアイデアや情報を、テキストと同等以上に検索・整理・活用できるようにする」**

既存アプリの大半は「録音」フェーズに強いが、「活用」フェーズが弱い。

```mermaid
flowchart LR
    A[録音] --> B[文字起こし] --> C[編集] --> D[整理] --> E[検索] --> F[共有・連携]

    style A fill:#4CAF50,color:white
    style B fill:#FFC107,color:black
    style C fill:#FF5722,color:white
    style D fill:#FF5722,color:white
    style E fill:#FF5722,color:white
    style F fill:#FF5722,color:white
```

- 緑: 既存アプリが得意な領域
- 黄: 改善中だが課題が多い領域
- 赤: 明確に弱い領域

### 4.2 空白地帯マトリクス

| 空白領域 | 説明 | 競合状況 | 参入難易度 |
|---|---|---|---|
| **日本語 x AI音声日記** | Untold的な感情分析付き音声日記の日本語版 | **競合なし** | 中 |
| **オフライン x 感情分析** | オンデバイスで完結する感情AI日記 | **競合なし** | 高 |
| **低価格 x 多言語 x 個人日記** | 買い切りor低額で100+言語対応の個人向け | **競合少ない** | 低-中 |
| **Apple Watch x 日記特化** | Apple Watch単体で完結する音声日記 | **競合少ない** | 中 |
| **CarPlay x 音声メモ** | 運転中のハンズフリー音声メモ | **競合なし** | 中 |
| **音声メモ x ナレッジグラフ** | 音声→構造化知識ベースへの自動統合 | **競合極少** | 高 |

### 4.3 参入にあたって考慮すべきリスク

```mermaid
graph TD
    A[参入リスク] --> B[プラットフォームリスク]
    A --> C[技術コモディティ化リスク]
    A --> D[大手参入リスク]

    B --> B1["Apple Siri刷新(2026年春)で<br>Voice Memos/NotesがAI強化"]
    B --> B2["Google RecorderのAI機能拡充"]

    C --> C1["Whisper精度がコモディティ化<br>技術での差別化が困難に"]
    C --> C2["LLM APIコストの低下で<br>参入障壁が下がる"]

    D --> D1["Notion/Obsidianが<br>音声機能を強化する可能性"]
    D --> D2["MetaのLimitless買収に見る<br>大手の音声AI関心"]
```

---

## 5. 成功アプリの共通要因分析

### 5.1 成功パターン

```mermaid
graph TD
    A[成功アプリの共通要因] --> B[明確なポジショニング]
    A --> C[技術的差別化]
    A --> D[ビジネスモデル設計]
    A --> E[ユーザー体験]

    B --> B1["Untold: 音声日記 x 感情AI"]
    B --> B2["Granola: Bot不要の会議ノート"]
    B --> B3["AudioPen: 思考→整形テキスト"]

    C --> C1["オンデバイス処理<br>(Cleft Notes, Just Press Record)"]
    C --> C2["独自ASR<br>(Otter.ai, Notta)"]
    C --> C3["マルチモデルLLM活用<br>(Granola: GPT-4o + Claude)"]

    D --> D1["完全無料で拡大<br>(Untold, Speechnotes)"]
    D --> D2["買い切りで信頼獲得<br>(Just Press Record $4.99)"]
    D --> D3["ハードx サブスクの複合<br>(Plaud: デバイス + Pro Plan)"]

    E --> E1["ワンタップ録音の即時性"]
    E --> E2["録音後の自動整理・要約"]
    E --> E3["既存ツールとの連携"]
```

### 5.2 April Dunford式ポジショニング分析

競合分析の大家 April Dunford のフレームワークに基づく分析:

**「顧客がこの製品を使わなかったら何をするか？」**

| ターゲット | ステータス・クオ（現状の代替手段） | なぜ代替手段では不十分か |
|---|---|---|
| 日記を書きたい人 | 手書き / Day One / テキスト入力 | 時間がかかる、続かない、感情が伝わらない |
| アイデアをメモしたい人 | Apple標準メモ / Google Keep | 音声入力の活用が限定的、整理されない |
| 会議録を残したい人 | Otter.ai / Notion | 高い、プライバシー懸念、日本語が弱い |
| 思考を整理したい人 | 手書きノート / テキストエディタ | 話す方が速い(150 WPM vs 40 WPM)のに活かせない |

**最大の敵は「やらないこと」**: ボイスメモを試したが活用できず放置 → 結局キーボード入力に戻る。このサイクルを断ち切ることが最重要。

---

## 6. 参入戦略への示唆

### 6.1 推奨ポジショニング

上記の分析から、以下のポジショニングが最も大きな市場機会を持つ:

> **「日本語に強い、プライバシーファーストのAI音声日記・思考整理アプリ」**

**理由**:
1. 日本語 x AI音声日記の競合が実質ゼロ
2. プライバシー（オンデバイス処理）への需要急増
3. 「録音→活用」のギャップを埋めるAI整理機能
4. Z世代・ミレニアル世代の音声ファースト志向

### 6.2 差別化の武器（既存競合が持たない強み）

| 差別化要素 | 対抗できる競合 | 実現難易度 |
|---|---|---|
| 日本語高精度 + 多言語自動切替 | Otter.ai(4言語), Untold(英語) | 中（Whisper + 日本語fine-tune） |
| オンデバイス完結 + E2E暗号化 | Otter.ai, Voicenotes(クラウド依存) | 中-高（Apple SpeechAnalyzer活用） |
| 感情トーン分析付き日記 | AudioDiary(精度低), TalkJournal(機能なし) | 中（Hume AI等のAPI活用） |
| 自動整理 + AI要約 + 検索 | Apple Voice Memos(整理弱い) | 中（LLM API活用） |
| 買い切り or 低額サブスク | Otter.ai($8+/月), Notion($10+/月) | ビジネス判断 |

### 6.3 ビジネスモデルの選択肢

| モデル | 例 | メリット | リスク |
|---|---|---|---|
| **完全無料** | Untold | 急速なユーザー獲得 | マネタイズ課題 |
| **買い切り** | Just Press Record ($4.99) | サブスク疲れ層に刺さる | 継続収益なし |
| **フリーミアム+低額サブスク** | Voicenotes ($10/月) | バランス型 | 無料→有料転換率が鍵 |
| **Lifetime Deal** | Audionotes ($199) | エバンジェリスト獲得 | LTV予測困難 |

### 6.4 ユーザーが最優先で求める機能

| 優先度 | 機能 | なぜ重要か |
|---|---|---|
| 1 | 高精度な日本語文字起こし | 全アプリ共通の最大不満 |
| 2 | オフライン完結の録音・文字起こし | プライバシー + 接続環境 |
| 3 | 自動整理・タグ付け・AI要約 | 「録音して終わり」からの脱却 |
| 4 | 録音の100%信頼性 | 消失・クラッシュへの恐怖 |
| 5 | 感情・トーン分析（日記向け） | Untold成功の根幹機能 |
| 6 | Apple Watch / CarPlay対応 | ハンズフリーシーンの需要 |
| 7 | Notion / Obsidian連携 | ナレッジワーカーの必須要件 |

---

## 7. 競合の技術スタック比較

| 音声認識技術 | 利用アプリ | 特徴 |
|---|---|---|
| **OpenAI Whisper** | Whisper Memos, Whisper Notes, AudioPen, VOMO, Cleft Notes, Omi | オープンソース、90+言語、月間1000万DL |
| **GPT-4o Transcribe** | 新世代アプリ | Whisper超えの精度、2025年3月リリース |
| **独自ASRエンジン** | Otter.ai, Notta | 言語特化で高精度、開発コスト大 |
| **Apple Speech Framework** | Just Press Record, Texter, TalkJournal | オンデバイス、プライバシー保護、Appleエコ限定 |
| **Apple SpeechAnalyzer** | 今後のアプリ | 3Bパラメータ、Whisper中位と同等、2025年WWDC発表 |
| **Google Speech-to-Text** | Dictanote, Speechnotes | 安定・低コスト、クラウド依存 |
| **Deepgram** | AudioDiary | リアルタイム処理、開発者フレンドリー |
| **Hume AI** | Untold | 感情分析特化 |
| **LLM（後処理）** | Voicenotes(GPT-4/Claude), Granola(GPT-4o+Claude) | 要約・整理・リライト |

---

## 8. まとめ

### 市場機会の総括

```mermaid
graph TD
    A[音声メモ日記アプリの市場機会] --> B[技術成熟]
    A --> C[ユーザー行動変化]
    A --> D[市場空白]
    A --> E[競合の弱点]

    B --> B1["オンデバイスAI処理が実用化<br>(Apple SpeechAnalyzer 3B)"]
    B --> B2["Whisper級精度がOSS利用可能"]
    B --> B3["LLMによる自動要約・整理が標準化"]

    C --> C1["Z世代の音声ファースト志向<br>(2027年64%月次利用)"]
    C --> C2["音声入力の速度優位性認知拡大<br>(キーボードの2.93倍)"]
    C --> C3["メンタルヘルス・ウェルビーイング需要"]

    D --> D1["日本語AIボイス日記が存在しない"]
    D --> D2["オフラインx感情分析が未開拓"]
    D --> D3["CarPlay音声メモが未対応"]

    E --> E1["録音に強いが活用に弱い"]
    E --> E2["プライバシー問題<br>(Otter.ai訴訟)"]
    E --> E3["サブスク疲れ"]
```

### 最終提言

**今がこの市場に参入する最適なタイミング**である。理由:

1. **技術的転換点**: オンデバイスAIが実用水準に到達し、クラウド依存からの脱却が可能に
2. **競合の隙**: 日本語 x AI音声日記の空白が明確に存在
3. **プラットフォームの追い風**: Apple SpeechAnalyzer、新Siriの登場がエコシステムを活性化
4. **ユーザー需要の高まり**: Z世代の音声ファースト化、メンタルヘルス意識の向上
5. **ブートストラップ成功モデルの存在**: Plaud AIのように外部資金なしでARR $1億到達の前例あり

**最大のリスクは「2026年春のApple Siri刷新」**。Voice Memos/NotesのAI強化が直接的な脅威となるため、AppleのOSレベルでは実現できない差別化（感情分析、マルチモーダル日記、ナレッジグラフ統合等）を武器にすべき。

---

## Sources

### 競合調査
- [Otter.ai Pricing - Outdoo.ai](https://www.outdoo.ai/blog/otter-ai-pricing)
- [Otter revenue & funding - Sacra](https://sacra.com/c/otter/)
- [12 Best Voice to Notes Apps (2026)](https://voicetonotes.ai/blog/best-voice-to-notes-app/)
- [Voicenotes - TechCrunch](https://techcrunch.com/2024/05/13/buymeacoffees-founder-has-built-an-ai-powered-voice-note-app/)
- [AudioPen - TechCrunch](https://techcrunch.com/2023/07/03/audio-pen-is-a-great-web-app-for-converting-your-voice-into-text-notes/)
- [Granola raises $43M - TechCrunch](https://techcrunch.com/2025/05/14/ai-note-taking-app-granola-raises-43m-at-250m-valuation-launches-collaborative-features/)
- [Untold - Hume AI](https://www.hume.ai/blog/case-study-hume-untold-app)
- [AudioDiary - Deepgram](https://deepgram.com/ai-apps/audio-diary)
- [Cleft Notes - The Sweet Setup](https://thesweetsetup.com/cleft-notes-is-the-thinking-companion-i-didnt-know-i-needed/)
- [Plaud Note Pro - TechCrunch](https://techcrunch.com/2025/12/29/plaud-note-pro-is-an-excellent-ai-powered-recorder-that-i-carry-everywhere/)
- [Notion AI Meeting Notes - TechCrunch](https://techcrunch.com/2025/05/13/notion-takes-on-ai-notetakers-like-granola-with-its-own-transcription-feature/)
- [Fireflies.ai Pricing - Lindy](https://www.lindy.ai/blog/fireflies-ai-pricing)

### 市場規模・トレンド
- [MarketsandMarkets - Speech and Voice Recognition Industry](https://www.marketsandmarkets.com/PressReleases/speech-voice-recognition.asp)
- [Grand View Research - Voice And Speech Recognition Market](https://www.grandviewresearch.com/press-release/global-voice-recognition-industry)
- [OpenAI - Next-generation audio models](https://openai.com/index/introducing-our-next-generation-audio-models/)
- [Apple ML Research - Foundation Models 2025](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)
- [eMarketer - Gen Z Leading Voice Assistant Growth](https://www.emarketer.com/content/data-drop-gen-z-leading-voice-assistant-growth)
- [DemandSage - Voice Search Statistics 2025](https://www.demandsage.com/voice-search-statistics/)

### ユーザーニーズ
- [Apple Voice Memos Reviews](https://justuseapp.com/en/app/1069512134/voice-memos/reviews)
- [Otter.ai Reviews - Trustpilot](https://www.trustpilot.com/review/otter.ai)
- [Otter.ai Class Action Lawsuit](https://www.workplaceprivacyreport.com/2025/08/articles/artificial-intelligence/ai-notetaking-tools-under-fire-lessons-from-the-otter-ai-class-action-complaint/)
- [Voice Privacy Concerns - WeLiveSecurity](https://www.welivesecurity.com/en/privacy/favorite-speech-to-text-app-privacy-risk/)

### プラットフォーム動向
- [CNBC - Apple delays Siri AI improvements to 2026](https://www.cnbc.com/2025/03/07/apple-delays-siri-ai-improvements-to-2026.html)
- [Apple SpeechAnalyzer - Callstack](https://www.callstack.com/blog/on-device-speech-transcription-with-apple-speechanalyzer)
- [Samsung Voice Recorder with Galaxy AI](https://www.samsung.com/us/support/answer/ANS10000942/)
- [Google Recorder Clear Voice - Android Central](https://www.androidcentral.com/apps-software/google-recorder-app-clear-voice-feature-spotted)
