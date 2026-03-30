# プライバシーポリシー・利用規約 作成

## 依頼内容
競合アプリを参考に、Soyokaのプライバシーポリシーと利用規約を作成する。

## 調査対象（競合6アプリ + 法的要件）

### 参考にした競合アプリ

| アプリ | 開発元 | ポリシー特徴 | 参考度 |
|:------|:------|:-----------|:------|
| **Spokenly** | Vadim Ahmerov | ローカル/クラウド別方針、サードパーティ6社名指し、利用規約あり | **主要参考** |
| **Otter.ai** | AISense, Inc. | 企業向け詳細ポリシー、GDPR/CCPA対応、AI学習開示 | **構成参考** |
| **Aiko** | Sindre Sorhus | 一文ポリシー、完全オンデバイス、ネットワーク制限 | **簡潔さ参考** |
| **Just Press Record** | Open Planet Software | 最小限ポリシー、Apple Speech依存 | 参考 |
| **Whisper Transcription** | Good Snooze | オンデバイス処理、プレスリリース形式 | 参考 |
| **VOMO AI** | EverGrow Tech | 音声データ未記載、利用規約リンク切れ（反面教師） | **避けるべき例** |

### 法的要件
- 個人情報保護法（2022年改正、2026年改正動向含む）
- App Store Review Guidelines 5.1.2(i)（2025年11月追加）
- GDPR / CCPA（グローバル配信時）
- Apple標準EULA vs カスタムEULA

## 成果物
- `result/privacy-policy.md` — プライバシーポリシー
- `result/terms-of-service.md` — 利用規約

## 設計方針
- **Spokenly方式**: オンデバイス処理/クラウド処理を明確に分離して記載
- **透明性重視**: サードパーティサービス名を明示（VOMO AIの不透明さを避ける）
- **APPI準拠**: 利用目的の具体化、安全管理措置、開示請求窓口
- **App Store Guideline 5.1.2(i)準拠**: AI処理のデータ送信について明示的開示
- **カスタムEULA**: サブスクリプション・AI処理があるため標準EULAでは不十分

## 実施日
2026-03-29
