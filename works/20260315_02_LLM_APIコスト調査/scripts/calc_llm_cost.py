"""
音声メモアプリにおけるLLM APIコスト計算スクリプト

前提条件:
- 1分間の音声メモ = 約300文字（日本語）= 約200-400トークン（中央値300トークンで計算）
- プロンプト部分 = 約100文字 = 約70-150トークン（中央値100トークンで計算）
- 日本語はトークン効率が英語より悪い（1文字≒1-2トークン）ため、やや多めに見積もり

想定する処理:
1. 要約: 入力300文字+プロンプト100文字 → 出力50文字
2. タグ付け・カテゴリ分類: 同上 → タグ5個程度
3. 感情分析: 同上 → 感情スコア+短文

トークン見積もり（日本語考慮）:
- 入力テキスト300文字 → 約400トークン（日本語は1文字≒1.3トークン程度）
- プロンプト100文字 → 約130トークン
- 合計入力: 約530トークン/回

出力トークン見積もり:
- 要約（50文字）→ 約70トークン
- タグ付け（タグ5個+JSON構造）→ 約80トークン
- 感情分析（スコア+短文）→ 約60トークン
"""

import json

# ============================================
# モデル料金データ（2026年3月時点）
# ============================================
models = {
    # OpenAI
    "GPT-4o": {
        "provider": "OpenAI",
        "input_per_1m": 2.50,
        "output_per_1m": 10.00,
        "note": "高性能マルチモーダル"
    },
    "GPT-4o mini": {
        "provider": "OpenAI",
        "input_per_1m": 0.15,
        "output_per_1m": 0.60,
        "note": "コスト効率重視"
    },
    # Anthropic
    "Claude Sonnet 4": {
        "provider": "Anthropic",
        "input_per_1m": 3.00,
        "output_per_1m": 15.00,
        "note": "claude-sonnet-4-20250514"
    },
    "Claude Haiku 4.5": {
        "provider": "Anthropic",
        "input_per_1m": 1.00,
        "output_per_1m": 5.00,
        "note": "最速モデル"
    },
    # Google
    "Gemini 2.5 Flash": {
        "provider": "Google",
        "input_per_1m": 0.30,
        "output_per_1m": 2.50,
        "note": "テキスト入力価格"
    },
    "Gemini 2.5 Pro": {
        "provider": "Google",
        "input_per_1m": 1.25,
        "output_per_1m": 10.00,
        "note": "≤200kプロンプト価格"
    },
    # Groq
    "Groq Llama 4 Scout": {
        "provider": "Groq",
        "input_per_1m": 0.11,
        "output_per_1m": 0.34,
        "note": "17Bx16E MoE"
    },
    "Groq Llama 4 Maverick": {
        "provider": "Groq",
        "input_per_1m": 0.20,
        "output_per_1m": 0.60,
        "note": "17Bx128E MoE"
    },
    "Groq Llama 3.3 70B": {
        "provider": "Groq",
        "input_per_1m": 0.59,
        "output_per_1m": 0.79,
        "note": "高性能Llama"
    },
    "Groq Llama 3.1 8B": {
        "provider": "Groq",
        "input_per_1m": 0.05,
        "output_per_1m": 0.08,
        "note": "最安・最速"
    },
    # ローカルLLM
    "Ollama (ローカル)": {
        "provider": "ローカル",
        "input_per_1m": 0.00,
        "output_per_1m": 0.00,
        "note": "API料金なし（電気代のみ）"
    },
}

# ============================================
# トークン見積もり
# ============================================

# 1回のAPI呼び出し（個別処理）のトークン数
tasks_separate = {
    "要約": {
        "input_tokens": 530,   # テキスト400 + プロンプト130
        "output_tokens": 70,
    },
    "タグ付け・カテゴリ分類": {
        "input_tokens": 530,
        "output_tokens": 80,
    },
    "感情分析": {
        "input_tokens": 530,
        "output_tokens": 60,
    },
}

# まとめて1回で処理する場合
task_combined = {
    "まとめて処理": {
        "input_tokens": 630,   # テキスト400 + より長いプロンプト230（3タスク分の指示）
        "output_tokens": 210,  # 全出力合計
    }
}

# 使用シナリオ
# 1ユーザー: 1日平均3分の音声メモ × 月30日
minutes_per_day = 3
days_per_month = 30
total_minutes_per_month = minutes_per_day * days_per_month  # 90分/月


def calc_cost_per_call(model_info, input_tokens, output_tokens):
    """1回のAPI呼び出しのコストを計算"""
    input_cost = (input_tokens / 1_000_000) * model_info["input_per_1m"]
    output_cost = (output_tokens / 1_000_000) * model_info["output_per_1m"]
    return input_cost + output_cost


def calc_monthly_cost(model_info, input_tokens_per_min, output_tokens_per_min, total_minutes):
    """月間コストを計算"""
    total_input = input_tokens_per_min * total_minutes
    total_output = output_tokens_per_min * total_minutes
    input_cost = (total_input / 1_000_000) * model_info["input_per_1m"]
    output_cost = (total_output / 1_000_000) * model_info["output_per_1m"]
    return input_cost + output_cost


# ============================================
# 計算実行
# ============================================

# 個別処理の場合: 1分あたりの合計トークン
separate_input_per_min = sum(t["input_tokens"] for t in tasks_separate.values())
separate_output_per_min = sum(t["output_tokens"] for t in tasks_separate.values())

# まとめ処理の場合: 1分あたりのトークン
combined_input_per_min = task_combined["まとめて処理"]["input_tokens"]
combined_output_per_min = task_combined["まとめて処理"]["output_tokens"]

results = []
for model_name, info in models.items():
    # 個別処理（3回呼び出し）
    separate_cost_per_min = sum(
        calc_cost_per_call(info, t["input_tokens"], t["output_tokens"])
        for t in tasks_separate.values()
    )
    separate_monthly = calc_monthly_cost(
        info, separate_input_per_min, separate_output_per_min, total_minutes_per_month
    )

    # まとめ処理（1回呼び出し）
    combined_cost_per_min = calc_cost_per_call(
        info,
        task_combined["まとめて処理"]["input_tokens"],
        task_combined["まとめて処理"]["output_tokens"]
    )
    combined_monthly = calc_monthly_cost(
        info, combined_input_per_min, combined_output_per_min, total_minutes_per_month
    )

    results.append({
        "model": model_name,
        "provider": info["provider"],
        "input_per_1m": info["input_per_1m"],
        "output_per_1m": info["output_per_1m"],
        "separate_cost_per_min": separate_cost_per_min,
        "separate_monthly": separate_monthly,
        "combined_cost_per_min": combined_cost_per_min,
        "combined_monthly": combined_monthly,
        "savings_pct": (1 - combined_monthly / separate_monthly) * 100 if separate_monthly > 0 else 0,
        "note": info["note"],
    })

# JSON出力
output_path = "/Users/y.itomura501/dev/mydev/test/VoiceMemo/works/20260315_02_LLM_APIコスト調査/data/cost_calculation.json"
with open(output_path, "w", encoding="utf-8") as f:
    json.dump(results, f, ensure_ascii=False, indent=2)

print("=== 計算完了 ===")
print(f"総分数/月: {total_minutes_per_month}分")
print(f"個別処理: 入力{separate_input_per_min}トークン/分, 出力{separate_output_per_min}トークン/分")
print(f"まとめ処理: 入力{combined_input_per_min}トークン/分, 出力{combined_output_per_min}トークン/分")
print()

for r in results:
    print(f"【{r['model']}】({r['provider']})")
    print(f"  個別処理 月間: ${r['separate_monthly']:.6f} (¥{r['separate_monthly'] * 150:.4f})")
    print(f"  まとめ処理 月間: ${r['combined_monthly']:.6f} (¥{r['combined_monthly'] * 150:.4f})")
    print(f"  コスト削減率: {r['savings_pct']:.1f}%")
    print()
