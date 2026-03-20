# セキュリティ設計書作成

## 依頼内容

AI音声メモ・日記アプリのセキュリティ設計書（`05-security.md`）を作成する。

## 実施した作業内容

1. 要件定義書（`requirements.md`）を精読し、NFR-007〜010、NFR-021のセキュリティ要件を抽出
2. STRIDE脅威モデルに基づく脅威分析を実施
3. 以下の8セクションからなるセキュリティ設計書を作成:
   - 脅威モデル（STRIDE分析、リスクマトリクス）
   - データ保護設計（iOS Data Protection、Keychain、iCloudバックアップ除外）
   - 通信セキュリティ（TLS 1.3、Certificate Pinning、MITM対策）
   - 認証・認可設計（デバイストークン、Apple Sign In）
   - プライバシー設計（Privacy Manifest、ATT、App Store審査対応）
   - クラウドデータポリシー実装（データ最小化、非保持保証、ログ除外）
   - セキュリティテスト計画（静的解析、動的テスト、プライバシーテスト）
   - インシデント対応計画（対応フロー、リモートキル/強制アップデート）

## 成果物

- `/docs/spec/ai-voice-memo/design/05-security.md`

## 得られた知見

- `NSFileProtectionComplete`はバックグラウンド録音（EC-003）と衝突するため、`NSFileProtectionCompleteUntilFirstUserAuthentication`が適切な選択
- 個人開発のため、Certificate Pinningは運用負荷を考慮してMVP段階では導入せず、公開時に検討する段階的アプローチが現実的
- OpenAI APIは2024年3月以降、APIエンドポイント経由のデータをデフォルトで学習に使用しないが、Zero Data Retentionの申請も検討すべき
- Privacy Manifest（PrivacyInfo.xcprivacy）はiOS 17以降で必須であり、Required Reason APIの使用宣言が必要

## 今後の課題

- 各フェーズ（P1〜P4）でのセキュリティチェックリストの運用
- プライバシーポリシー文書の実際の策定（公開時）
- ペネトレーションテストの具体的な実施計画
- OpenAI DPA（Data Processing Agreement）の締結検討
