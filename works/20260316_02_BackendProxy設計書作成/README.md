# Backend Proxy 設計書作成

## 依頼内容

AI音声メモアプリのBackend Proxy（Cloudflare Workers）の技術設計書を作成する。

## 実施した作業内容

1. 要件定義書（`docs/spec/ai-voice-memo/requirements.md`）を精読し、Backend Proxyに関連する要件を抽出
2. 以下の8セクションを含む設計書を `docs/spec/ai-voice-memo/design/03-backend-proxy.md` に作成:
   - システム構成図（mermaid）
   - API設計（4エンドポイント + 2補助エンドポイント、JSON Schema定義）
   - 認証・認可設計（Apple Sign In + デバイストークンMVP）
   - 課金検証設計（App Store Server API v2、Server Notification V2）
   - レート制限設計（3層構造）
   - プライバシー・データポリシー実装
   - インフラ構成（KV/D1スキーマ、wrangler.toml）
   - コスト見積もり・損益分岐点分析

## 成果物

| ファイル | 説明 |
|:---------|:-----|
| `docs/spec/ai-voice-memo/design/03-backend-proxy.md` | Backend Proxy設計書 v1.0 |

## 得られた知見

- Cloudflare Workers Free PlanのKV書き込み制限（1,000回/日）がボトルネックになりうるため、MVP段階からPaid Plan ($5/月) を推奨
- GPT-4o-miniのコスト効率が高く、Proユーザー2人で固定費回収可能
- KVの結果整合性モデルにより、厳密なアトミックカウンターは保証されないが、Free枠の1-2回超過は許容範囲として設計

## 今後の課題

- [ ] Durable Objects への移行検討（厳密なカウンター管理が必要になった場合）
- [ ] E2Eテスト設計
- [ ] CI/CDパイプライン設計
- [ ] OpenAI APIのフォールバック先（Anthropic Claude等）の検討
