# 20260315_02_LLM_APIコスト調査

## 依頼内容

音声メモアプリにおいて、文字起こし後テキストをLLMで「要約」「タグ付け」「感情分析」する際のAPIコストを調査。

## 調査対象

- OpenAI GPT-4o / GPT-4o-mini
- Anthropic Claude Sonnet 4 / Claude Haiku 4.5
- Google Gemini 2.5 Flash / Gemini 2.5 Pro
- Groq（Llama 4 Scout, Maverick, Llama 3.3 70B, Llama 3.1 8B）
- ローカルLLM（Ollama等）

## 実施した作業

1. 各LLMプロバイダの最新API料金をWeb検索で調査
2. 音声メモ1分あたりのトークン数見積もり
3. 個別処理（3回呼び出し）vs まとめ処理（1回呼び出し）のコスト比較
4. 月間コスト試算（1日3分 x 月30日 = 月90分）
5. スケール別コスト比較（1K/10K/100Kユーザー）

## 成果物

- `scripts/calc_llm_cost.py` - コスト計算スクリプト
- `data/cost_calculation.json` - 計算結果データ
- `result/202603152258/llm_api_cost_report.md` - 詳細レポート

## 主な知見

- 1ユーザー月間コストは$0.004〜$0.454と非常に低廉
- まとめ処理で30-50%のコスト削減が可能
- GPT-4o mini が品質・コスト・安定性のバランスで最良
- 100Kユーザーでも月間$1,266〜$1,985程度で賄える
