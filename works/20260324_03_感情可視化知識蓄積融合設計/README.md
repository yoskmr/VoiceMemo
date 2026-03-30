# MurMurNote「感情可視化 × 知識蓄積」融合設計書

> 作成日: 2026-03-24
> ステータス: 提案段階（Product Owner + Tech Lead レビュー済み）

---

## 1. エグゼクティブサマリー

### コンセプト: 「記憶する感情、引き出せる知恵」（Emotional Knowledge Graph）

パターンA（感情可視化: muute/Awarefy型）とパターンB（知識蓄積: Voicenotes/Granola型）を融合し、
**「感情を理解する第二の脳」** という、現時点で市場に存在しないポジションを確立する。

### 後発の優位性

| 先行者の限界 | MurMurNoteの掛け算 |
|:------------|:------------------|
| muute/Awarefy: 感情分析あるが**音声入力なし**、蓄積データの再利用手段なし | 音声 × 感情 × RAG |
| Voicenotes/Granola: 知識蓄積あるが**感情の文脈がない** | 知識 × 感情メタデータ |
| Apple ボイスメモ: テキスト化できるが**AI処理ゼロ** | テキスト + AI構造化 + 感情 + RAG |
| 無限もじおこし(20万DL): 文字起こし特化、**AI活用レイヤーなし** | STT + 感情 + RAG + 週次レポート |

### キラー機能（A×Bでしか生まれない価値）

> **「先週、不安を感じていたときに何を考えていた？」**

感情を検索キーにした知識の引き出し。パターンA単体でもB単体でも不可能。

---

## 2. 統合ユーザーフロー

````
録音（ワンタップ）
  ↓
リアルタイム文字起こし（SpeechAnalyzer / WhisperKit）
  ↓
┌──────────────────────────────────┐
│ AI処理フェーズ（自動・バックグラウンド）│
├──────────┬───────────┬───────────┤
│ テキスト構造化 │ タグ自動付与 │ 感情分析    │
│ 要約+キーポイント│ トピック分類 │ テキスト+音声 │
└──────────┴───────────┴───────────┘
  ↓
知識グラフ更新（エンティティ抽出 + 感情スコア + エンベディング）
  ↓
SwiftData保存
  ↓
┌──────────┬───────────────┬──────────┐
│ 日次:     │ 週次:          │ 随時:     │
│ タイムライン │ 振り返りレポート  │ RAG質問   │
│ 感情可視化  │ 話題×感情の推移  │ 「第二の脳」│
└──────────┴───────────────┴──────────┘
````

### A×B の掛け算が生む価値

| 機能 | A単体 | B単体 | **A×B融合** |
|:-----|:------|:------|:-----------|
| 検索 | 「悲しかった日を探す」 | 「プロジェクトXの日」 | **「プロジェクトXで不安を感じた日に何を考えていた？」** |
| 振り返り | 「今週は不安が多かった」 | 「今週はXとYの話題」 | **「今週の不安の原因はXだった。先月もXで不安」** |
| RAG | 不可能 | 「先週の会議で何を決めた？」 | **「最近モチベーション下がった原因を教えて」** |
| 習慣化 | 感情グラフを見る（受動的） | 知識を引き出す（能動的） | **「見たい」×「使いたい」の両輪** |

---

## 3. 必須ユーザーストーリー

### US-309: 蓄積メモへのAI質問（RAG）

````
ユーザーとして、
蓄積したメモに対して自然言語で質問し、
過去の記録からAIが関連情報を引き出して回答してくれることで、
自分の「第二の脳」として活用したい。
````

**受け入れ基準**:
- 「先週何について話した？」→ 関連メモを引用して回答
- 直近30日分のメモをコンテキストとして使用
- オンデバイスLLM（Phase 3a）で基本動作、クラウドLLM（Phase 3b）で精度向上
- **感情フィルタ付きクエリ対応**: 「不安だったときに何を考えていた？」

**MoSCoW**: Should Have
**Phase**: P4（MVP）→ P5（完全版）

### US-310: 週次振り返りレポート

````
ユーザーとして、
週に一度、AIが感情・話題の傾向をまとめた振り返りレポートを自動生成してくれることで、
自分の思考や感情のパターンを客観的に把握したい。
````

**受け入れ基準**:
- 毎週日曜日に自動生成（ローカル通知でお知らせ）
- 話題TOP3、感情傾向、前週との比較を含む
- 最低3件以上のメモがある週のみ生成
- **ネガティブ感情を「否定」しない設計**（muuteの反面教師）

**MoSCoW**: Should Have
**Phase**: P3b（簡易版）→ P4（完全版）

### US-311: 音声感情検出

````
ユーザーとして、
声のトーンや話し方から、テキストでは表現しきれない感情ニュアンスを検出してもらうことで、
自分でも気づかなかった感情の変化を発見したい。
````

**受け入れ基準**:
- 音声波形から感情ラベル（喜び/悲しみ/怒り/不安/平穏）を推定
- テキスト感情分析と音声感情分析の両方を表示
- Phase 5以降（DistilHuBERT オンデバイス or Hume AI クラウド）

**MoSCoW**: Could Have
**Phase**: P5

---

## 4. 競合「空白地帯」分析

### 4.1 市場マッピング

| アプリ | 音声入力 | 感情分析 | RAG/知識蓄積 | オンデバイス | 日本語特化 |
|:------|:--------|:--------|:-----------|:-----------|:---------|
| muute | なし | テキストのみ | 限定的 | 不明 | あり |
| Awarefy | なし | テキスト+CBT | 限定的 | 不明 | あり |
| Untold | **音声** | **音声+テキスト(Hume AI)** | なし | なし(クラウド) | なし |
| Voicenotes | **音声** | なし | **Ask AI(RAG)** | なし(クラウド) | 限定的 |
| Granola | 音声キャプチャ | なし | 限定的 | なし(クラウド) | 不明 |
| Apple ボイスメモ | **音声** | なし | なし | **あり** | あり |
| 無限もじおこし | **音声** | なし | なし | 不明 | あり |
| **MurMurNote** | **音声** | **音声+テキスト** | **RAG** | **ハイブリッド** | **あり** |

**結論: 「音声ファースト × 感情可視化 × 知識蓄積」を融合するアプリは現時点で存在しない。**

### 4.2 先行事例の弱点と対策

| 競合 | 弱点 | MurMurNoteの対策 |
|:----|:-----|:---------------|
| **muute** | ネガティブ感情を「否定」するAI応答 | 感情を「承認」する設計（Untold参考） |
| **muute** | テキスト入力のみ（音声なし） | 音声ファーストで入力障壁を下げる |
| **Awarefy** | 無料と有料の差が大きすぎて離脱 | フリーミアム設計を慎重に（月15回→Pro無制限） |
| **Awarefy** | AI応答がテンプレート的 | Apple Foundation Models + カスタムプロンプト |
| **Voicenotes** | 録音20分制限、クラッシュ | 無制限録音 + SwiftData永続化 |
| **Voicenotes** | オフライン不可 | SpeechAnalyzer + Apple Foundation Models |
| **Untold** | 知識蓄積機能なし | RAGで差別化 |
| **Untold** | 収益化モデル未確立 | Pro ¥500/月で持続可能に |
| **Granola** | 音声再生不可、話者識別弱い | 音声再生エンジン（Phase 3） |

---

## 5. ペルソナと利用シーン

### ペルソナ1: タクヤ（30代エンジニア、思考整理型）🔵高信頼度

- **課題**: アイデアは浮かぶが整理できない。過去に考えたことを忘れる
- **刺さるポイント**: 知識蓄積 > 感情可視化
- **シーン**: 通勤中にアイデア録音 → 翌週RAGで「先週のバグ対応で何を試した？」

### ペルソナ2: ユウカ（30代マーケティング職、感情整理型）🟡中信頼度

- **課題**: テキスト入力が面倒で日記が続かない。感情の波に振り回される
- **刺さるポイント**: 感情可視化 > 知識蓄積
- **シーン**: 寝る前に一日の気持ちを録音 → 月曜に感情タイムラインで水曜のストレス原因を発見

### ペルソナ3: ケンジ（40代経営者、意思決定型）🔴要検証

- **課題**: 意思決定の記録と根拠の追跡
- **刺さるポイント**: 知識蓄積 = 感情可視化（意思決定の「確信度/不安度」が重要）
- **シーン**: 商談後に所感録音 → 四半期後にRAGで「A社への印象の推移」を確認

---

## 6. 習慣化ループ設計

### 6.1 日次・週次・月次サイクル

| サイクル | トリガー | アクション | 報酬 |
|:--------|:--------|:----------|:-----|
| **日次** | 思いついた/感じた | ワンタップ録音（10秒〜3分） | 要約カード + 感情バッジ即時表示 |
| **週次** | 日曜通知「振り返りができました」 | レポート閲覧（2-3分） | 感情パターン発見 + トピック傾向 |
| **月次** | 月初通知「先月のまとめ」 | ダッシュボード確認（5分） | 長期的な感情傾向 + 思考テーマの変遷 |

### 6.2 データ蓄積によるロックイン

| 蓄積期間 | メモ数 | RAG精度 | ユーザー体感 |
|:---------|:------|:--------|:-----------|
| 1週間 | 3-7件 | 低 | 「便利だけどまだ浅い」 |
| 1ヶ月 | 15-30件 | 中 | 「RAGが使えるようになってきた」 |
| **3ヶ月（臨界点）** | **50-100件** | **高** | **「これなしでは困る」（ロックイン完了）** |
| 6ヶ月以上 | 100件以上 | 非常に高 | 「自分の思考の歴史が詰まっている」 |

**臨界点は50件（約3ヶ月）**。週次レポートでこの壁を超えさせる設計が重要。

### 6.3 Free → Pro アップセル設計

| タイミング | 表示 |
|:----------|:-----|
| AI処理10回目（月15回中） | 「今月あと5回。Proなら無制限」 |
| 週次レポート生成時 | 「Proなら感情分析付きレポートが生成されます」 |
| 3ヶ月記念（50件蓄積後） | 「3ヶ月の記録、Proでもっと活用しませんか？」 |

---

## 7. 技術設計

### 7.1 推奨技術スタック

| レイヤー | 技術 | コスト | サイズ | Phase |
|:--------|:-----|:------|:------|:------|
| STT | SpeechAnalyzer (iOS 26+) / WhisperKit (iOS 17+) | 無料 | OS組込み | 実装済み |
| テキスト感情分析 | **Apple Foundation Models** (Guided Generation) | 無料 | OS組込み | P3b |
| 音声感情分析（基本） | **DistilHuBERT** → Core ML変換 | 無料 | 23MB | P5 |
| 音声感情分析（Pro） | **Hume AI** Expression Measurement API | $3-10/月 | クラウド | P5 |
| AI構造化（要約/タグ） | Apple Foundation Models | 無料 | OS組込み | P3a |
| RAG検索 | FTS5 + Apple Foundation Models (Tool Calling) | 無料 | OS組込み | P4 |
| 高度AI処理（Pro） | Backend Proxy → クラウドLLM | API従量 | クラウド | P3b |

### 7.2 統合パイプライン

````
AVAudioEngine (録音)
  ↓ PCM 16kHz Mono
  ├→ SpeechAnalyzer / WhisperKit (STT) → テキスト
  │     ↓
  │   Apple Foundation Models
  │     ├→ 要約生成 (@Generable)
  │     ├→ タグ分類 (@Generable)
  │     ├→ テキスト感情分析 (@Generable → EmotionLabel enum)
  │     └→ エンティティ抽出
  │
  └→ [Phase 5] DistilHuBERT (Core ML) → 音声感情スコア
        ↓
      マルチモーダル感情融合（テキスト + 音声）
        ↓
      SwiftData 保存
        ├→ MemoEntity (要約, タグ, 感情スコア)
        ├→ EmotionEntry (感情ラベル, スコア, タイムスタンプ)
        └→ [Phase 4] ベクトルエンベディング (RAG用)
````

### 7.3 データモデル拡張案

```swift
// 既存 MemoEntity への感情フィールド追加
extension MemoEntity {
    // Phase 3b: テキスト感情分析
    var emotionLabel: EmotionLabel  // .positive / .negative / .neutral
    var emotionScore: Float         // 0.0 - 1.0 (確信度)

    // Phase 5: 5段階感情 (精度80%+達成後)
    var detailedEmotion: DetailedEmotion?  // .joy / .sadness / .anger / .anxiety / .calm
    var voiceEmotionScore: Float?          // 音声感情スコア (DistilHuBERT)
}

// 感情エントリ（時系列追跡用）
@Model
class EmotionEntry {
    var memoID: UUID
    var timestamp: Date
    var textEmotion: EmotionLabel
    var textConfidence: Float
    var voiceEmotion: DetailedEmotion?  // Phase 5
    var voiceConfidence: Float?         // Phase 5
}

// 週次レポート
@Model
class WeeklyReport {
    var weekStartDate: Date
    var topTopics: [String]           // TOP3 トピック
    var emotionDistribution: [EmotionLabel: Int]
    var comparisonWithLastWeek: String // AI生成テキスト
    var memoCount: Int
}
```

### 7.4 感情分析の段階的アプローチ

| Phase | 感情分類 | 精度基準 | フォールバック |
|:------|:--------|:--------|:------------|
| P3b | 3段階（ポジ/ネガ/ニュートラル） | - | - |
| P4 | 5段階（精度80%+のとき） | 評価セット合格率80%+ | 3段階に戻す |
| P5 | テキスト + 音声マルチモーダル | テキスト80%+ & 音声61%+ | テキストのみに絞る |

**精度が不十分な場合**: ユーザー手動選択方式に切替（録音後に感情アイコンを選択、AIはサジェストに留める）

### 7.5 RAG実装方式（US-309）

**推奨: FTS5ベースの簡易RAG → Apple Foundation Models Tool Calling**

````
ユーザー質問: 「先週不安だったときに何を考えていた？」
  ↓
1. クエリ分解（Apple Foundation Models）
   → 期間: 先週 / 感情: 不安 / タイプ: 思考内容
  ↓
2. FTS5 + 感情フィルタで候補メモ取得（上位10件）
   → WHERE emotionLabel = 'negative' AND date >= '先週月曜'
  ↓
3. 候補メモをLLMコンテキストに投入
   → Apple Foundation Models (Tool Calling)
  ↓
4. 引用付き回答生成
   → 「3/18のメモで「プロジェクトの納期が...」と話されていました」
````

### 7.6 週次レポート バックグラウンド処理

- BGProcessingTask で毎週日曜に実行
- オンデバイスLLM（Apple Foundation Models）で集計・レポート生成
- ローカル通知（UNUserNotificationCenter）で配信
- 3件未満の週はスキップ

---

## 8. フェーズ別ロードマップ

### Phase 3a（現在進行中）: オンデバイスAI基盤
- AI要約 + タグ自動付与
- Apple Foundation Models 統合
- 月15回制限（Free）

### Phase 3b: 感情分析導入 + 週次レポート簡易版
- **テキスト感情分析（3段階）** 追加
- **週次レポート簡易版**: 話題TOP3 + 感情傾向（前週比較なし）
- Backend Proxy + クラウドLLM（Pro向け高品質処理）
- 追加工数見積: +16h

### Phase 3c: 課金基盤
- StoreKit 2 統合
- Free / Pro プラン切替

### Phase 4: 知識蓄積 + 感情可視化
- **RAG MVP（US-309）**: FTS5 + 感情フィルタ + Tool Calling
- **感情タイムライン**: カレンダーヒートマップ
- **週次レポート完全版**: 感情推移グラフ + 前週比較
- 5段階感情（精度達成時）
- 追加工数見積: +40h

### Phase 5: マルチモーダル感情 + 高度RAG
- **音声感情検出（US-311）**: DistilHuBERT(23MB) + Hume AI(Pro)
- **RAG完全版**: 感情×トピック×時系列のクロスクエリ
- 月次ダッシュボード
- Apple Watch対応
- 追加工数見積: +72h

---

## 9. 差別化マトリクス

### vs Apple ボイスメモ（最大の壁）
- Apple: 「録るだけ」→ MurMurNote: 「録って、理解して、活用する」
- Apple Intelligence は要約追加の可能性あるが、感情×RAG×週次レポートの統合体験は当面来ない
- **防衛線**: 3ヶ月分の感情つき知識データはAppleに移行できない

### vs 無限もじおこし（最大の直接競合、20万DL）
- 無限もじおこし: 文字起こし精度特化 → MurMurNote: 文字起こし後の「AI活用レイヤー」
- 同じ土俵（STT精度）では勝負せず、「STT + alpha」のalphaで差別化

### vs muute/Awarefy（感情可視化の先行者）
- 音声入力なし → MurMurNoteは音声ファースト
- 知識蓄積なし → MurMurNoteはRAG検索
- muuteが音声機能追加する前に「AI音声日記」ポジションを確立

### vs Voicenotes/Granola（知識蓄積の先行者）
- 感情コンテキストなし → MurMurNoteは感情×トピック検索
- クラウド依存 → MurMurNoteはオンデバイス優先
- 日本語特化なし → MurMurNoteはカスタム辞書+日本語プロンプト最適化
- 高価格($10-18/月) → MurMurNoteは¥500/月

---

## 10. リスクと対策

| リスク | 影響度 | 対策 |
|:-------|:------|:-----|
| Apple ボイスメモが感情分析追加 | 非常に高 | 先行してデータ蓄積→スイッチングコスト。3ヶ月の壁を超えたユーザーは離れない |
| 感情分析精度が低い | 高 | 3段階で安全にスタート。精度不足時はユーザー手動選択+AIサジェストに切替 |
| muute/Awarefyが音声機能追加 | 高 | 2026年Q2中のApp Store公開で先行 |
| Apple Foundation Modelsの日本語品質不足 | 高 | Gemma-2 / Qwen2.5 への切替パス確保 |
| RAGコンテキスト長制限 | 中 | FTS5で上位10件に絞込 → LLM投入。全メモは投入しない |
| 週次レポートのバッテリー消費 | 中 | BGProcessingTask + 省電力最適化 |

---

## 11. 参考リソース

### 競合アプリ
- [muute 公式](https://muute.jp/) — 週次/月次インサイト、感情アイコン自動予測
- [Awarefy 公式](https://www.awarefy.com/app) — CBTベース、AIチャットボット「ファイさん」
- [Untold 公式](https://www.untoldapp.com/) — 音声ジャーナリング × Hume AI感情分析
- [Voicenotes 公式](https://voicenotes.com/) — Ask AI (RAG)、「第二の脳」
- [Granola 公式](https://www.granola.ai/) — Enhance Notes、テンプレート構造化

### 技術
- [Apple Foundation Models](https://developer.apple.com/documentation/FoundationModels) — Guided Generation、Tool Calling
- [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer) — iOS 26+ STT
- [Hume AI](https://dev.hume.ai/intro) — Expression Measurement API、Swift SDK(ベータ)
- [DistilHuBERT for Mobile SER](https://arxiv.org/abs/2512.23435) — 23MB、61.4% UAR

### 関連ドキュメント
- [競合調査レポート](./competitive-analysis-2026-03-24.md)
- [要件定義](../../docs/spec/ai-voice-memo/requirements.md)
- [ユーザーストーリー](../../docs/spec/ai-voice-memo/user-stories.md)
- [AI処理パイプライン設計](../../docs/spec/ai-voice-memo/design/02-ai-pipeline.md)
