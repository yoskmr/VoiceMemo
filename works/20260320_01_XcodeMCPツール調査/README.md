# Xcode 26.3 MCP ツール調査

## 依頼内容

Xcode 26.3 の MCP ブリッジ (`xcrun mcpbridge`) で利用可能なツールの調査。

## 実施した作業

1. Web 検索で "Xcode 26.3 MCP tools" "xcrun mcpbridge" に関する情報を収集
2. Apple Newsroom, Developer Documentation, 技術ブログ等から詳細情報を取得
3. GitHub Gist から実際の tools/list レスポンス（JSON スキーマ）を確認
4. 調査結果をレポートとしてまとめ

## 得られた知見

- Xcode 26.3 は 20 個の MCP ツールを公開
- `xcrun mcpbridge` が MCP <-> Xcode XPC 間のブリッジとして動作
- Claude Code からは `claude mcp add --transport stdio xcode -- xcrun mcpbridge` で設定可能
- RC 1 には structuredContent 欠落のバグあり（RC 2 で修正済み）
- tools/list の応答遅延は Xcode の XPC 接続確立に時間がかかるため

## 成果物

- `result/202603201442/xcode-mcp-tools-report.md` - 全ツールの詳細レポート
