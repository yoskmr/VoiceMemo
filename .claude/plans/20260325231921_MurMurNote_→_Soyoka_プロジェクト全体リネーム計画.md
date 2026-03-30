# MurMurNote → Soyoka プロジェクト全体リネーム計画

## Context

アプリ名を MurMurNote から **Soyoka（和名: そよか）** に変更する。App Store名調査で「Soyoka」が重複なし・多言語リスクなしと確認済み。プロジェクト内の全ての MurMurNote/murmurnote 参照をリネームする。

## スコープ

- **対象**: MurMurNote / murmurnote / io.murmurnote の全参照
- **対象外**: VoiceMemoEntity 等のドメインモデル名（別タスク）、works/ と .claude/plans/ の歴史的ファイル

## 新しい識別子

| 項目 | 現在 | 変更後 |
|:-----|:-----|:------|
| プロジェクト名 | MurMurNote | Soyoka |
| バンドルID | io.murmurnote.app | io.soyoka.app |
| テストバンドルID | io.murmurnote.MurMurNoteTests | io.soyoka.SoyokaTests |
| Logger subsystem | com.murmurnote | com.soyoka |
| SPMパッケージ | MurMurNoteModules | SoyokaModules |
| App struct | MurMurNoteApp | SoyokaApp |
| CFBundleDisplayName | つぶやき | そよか |
| WelcomeView テキスト | MurMurNote | そよか |

---

## 実行フェーズ

### Phase 0: 準備

```bash
git checkout -b feature/rename-to-soyoka development
rm -rf repository/ios/MurMurNoteModules/.build
```

### Phase 1: ディレクトリ・ファイル名リネーム（git mv）

```bash
# ファイルリネーム（ディレクトリリネーム前に実施）
git mv repository/ios/MurMurNoteApp/MurMurNoteApp.swift \
       repository/ios/MurMurNoteApp/SoyokaApp.swift

# ディレクトリリネーム（3箇所）
git mv repository/ios/MurMurNoteApp repository/ios/SoyokaApp
git mv repository/ios/MurMurNoteModules repository/ios/SoyokaModules
git mv repository/ios/MurMurNote.xcodeproj repository/ios/Soyoka.xcodeproj

# エージェントファイルリネーム（4箇所）
git mv .claude/agents/murmurnote-spec-gate.md .claude/agents/soyoka-spec-gate.md
git mv .claude/agents/murmurnote-tech-lead.md .claude/agents/soyoka-tech-lead.md
git mv .claude/agents/murmurnote-product-owner.md .claude/agents/soyoka-product-owner.md
git mv .claude/agents/murmurnote-audio-ai-engineer.md .claude/agents/soyoka-audio-ai-engineer.md
```

### Phase 2: ビルド設定更新（並列可）

**2-A: `repository/ios/project.yml`**（20+箇所）
- `name: MurMurNote` → `name: Soyoka`
- `bundleIdPrefix: io.murmurnote` → `bundleIdPrefix: io.soyoka`
- 全 `MurMurNoteModules` → `SoyokaModules`
- 全 `MurMurNoteApp` → `SoyokaApp`
- `MurMurNote:` (target) → `Soyoka:`
- `MurMurNoteTests:` → `SoyokaTests:`
- `io.murmurnote.app` → `io.soyoka.app`
- `INFOPLIST_FILE: MurMurNoteApp/Info.plist` → `SoyokaApp/Info.plist`
- `CFBundleDisplayName: つぶやき` → `CFBundleDisplayName: そよか`

**2-B: `repository/ios/SoyokaModules/Package.swift`**（1箇所）
- `name: "MurMurNoteModules"` → `name: "SoyokaModules"`

### Phase 3: Xcode プロジェクト再生成

```bash
cd repository/ios && xcodegen generate
```

project.pbxproj の43箇所は手動編集不要 — XcodeGen が自動生成。

### Phase 4: Swift ソースコード更新（Phase 2と並列可）

| ファイル（リネーム後パス） | 変更内容 |
|:--|:--|
| `SoyokaApp/SoyokaApp.swift:10` | `struct MurMurNoteApp` → `struct SoyokaApp` |
| `SoyokaApp/WelcomeView.swift:22` | `Text("MurMurNote")` → `Text("そよか")` |
| `SoyokaModules/Sources/Data/AIProcessingQueueLive.swift:8` | `com.murmurnote` → `com.soyoka` |
| `SoyokaModules/Sources/InfraLLM/OnDeviceLLMProvider.swift:8` | `com.murmurnote` → `com.soyoka` |
| `SoyokaModules/Sources/InfraStorage/SwiftDataStore/ModelContainerConfiguration.swift:5` | `com.murmurnote` → `com.soyoka` |
| `SoyokaModules/Sources/InfraStorage/FTS5/FTS5IndexManager.swift:6` | `com.murmurnote` → `com.soyoka` |
| `SoyokaModules/Sources/InfraNetwork/Auth/KeychainManager.swift:5` | `com.murmurnote` → `com.soyoka` |

### Phase 5: ドキュメント・設定更新（Phase 2と並列可）

**5-A: `repository/.swiftlint.yml`**
- コメント `MurMurNote` → `Soyoka`
- パス `VoiceMemoApp` → `SoyokaApp`, `VoiceMemoModules` → `SoyokaModules`

**5-B: `.claude/agents/` 4ファイル**（内容の MurMurNote → Soyoka 置換）

**5-C: `.claude/skills/` 2ファイル**（MurMurNote → Soyoka、パス更新）

**5-D: `CLAUDE.md`**（MurMurNote → Soyoka、ディレクトリ構成図のパス更新）

**5-E: `docs/spec/` + `docs/tasks/`**（15+ファイル、33箇所）
- MurMurNote → Soyoka, io.murmurnote → io.soyoka

**5-F: メモリファイル**（MurMurNote → Soyoka）

### Phase 6: 検証

```bash
# SPM ビルド
cd repository/ios/SoyokaModules && swift build

# Xcode ビルド
cd repository/ios && xcodebuild -project Soyoka.xcodeproj -scheme Soyoka \
  -destination 'platform=iOS Simulator,name=iPhone 16' build -skipMacroValidation

# 残存チェック
grep -ri "murmurnote" repository/ios/ --include="*.swift" --include="*.yml" --include="*.plist"

# テスト実行
cd repository/ios/SoyokaModules && swift test
```

---

## 実行依存関係

```
Phase 0 (準備)
    │
Phase 1 (git mv)
    │
    ├──→ Phase 2 (ビルド設定) ──→ Phase 3 (xcodegen) ──┐
    ├──→ Phase 4 (Swift ソース) ────────────────────────┤──→ Phase 6 (検証)
    └──→ Phase 5 (ドキュメント) ────────────────────────┘
```

## エージェント分担

| エージェント | 担当 |
|:-----------|:-----|
| tech-lead | Phase 0, 1, 3, 6（git操作 + xcodegen + 検証） |
| サブエージェント A | Phase 2 + 4（ビルド設定 + Swift ソース） |
| サブエージェント B | Phase 5（ドキュメント 20+ファイル） |

## エラーリカバリ

- feature/rename-to-soyoka ブランチで作業 → 失敗時は `git checkout development` で完全復旧
- xcodegen 失敗時: project.yml のパスを再確認、ディレクトリ存在チェック
- SPM ビルド失敗時: `rm -rf .build && swift package resolve`

## 注意事項

- VoiceMemoEntity 等のドメインモデル名は変更しない（別タスク）
- works/, .claude/plans/ の歴史的ファイルは変更しない
- リリース前のためユーザーデータのマイグレーションは不要
- terminology.md の用語ルール見直しは PO 判断（本計画スコープ外）
