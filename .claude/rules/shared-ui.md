---
paths: ["**/SharedUI/**/*.swift", "**/*View*.swift"]
---

# SharedUI 規約

## カラー・フォント・スペーシング
- カラートークン: `vmPrimary`, `vmSecondary`, `vmAccent`（暖色 HSB色相20-40）等を使用 — 生の `Color` 値使用禁止
- フォント: `VMFonts.swift` のトークンを使用
- スペーシング: `VMSpacing.swift` のトークンを使用
- 感情カラー: `EmotionCategoryColor.swift` を使用

## 日本語行間トークン
日本語テキストの行間は必ず `VMDesignTokens.LineSpacing` トークンを使用する:
- 本文（17pt）: `.lineSpacing(VMDesignTokens.LineSpacing.body)` = 12pt（1.7倍）
- 見出し（22pt）: `.lineSpacing(VMDesignTokens.LineSpacing.heading)` = 9pt（1.4倍）
- キャプション（12pt）: `.lineSpacing(VMDesignTokens.LineSpacing.caption)` = 6pt（1.5倍）
- マジックナンバーの `.lineSpacing(6)` 等は禁止

## コンポーネント・パターン
- 再利用コンポーネント: `MemoCard`, `TagChip`, `WaveformView`, `EmotionBadge`, `RecordButton`
- ダーク/ライトモード: `vmAdaptive(light:dark:)` パターン
- View バインディング: `@Bindable var store: StoreOf<XxxReducer>` パターン
- NFR-012: 暖色系パレット要件に準拠
