# Soyoka バックアップ/リストア機能 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** バンドルID変更によるデータ移行手段として、全メモデータ+音声ファイルの ZIP エクスポート/インポート機能を TCA + Clean Architecture で実装する。

**Architecture:** Domain層に BackupPayload (Codable データ構造体) と BackupExportClient / BackupImportClient (DependencyKey プロトコル) を配置。InfraStorage層に ZIPFoundation を使用した実装 (BackupExporter / BackupImporter) を配置。FeatureSettings層に BackupReducer + BackupView を配置し、SettingsReducer のサブステートとして統合する。SoyokaApp で onOpenURL によるファイル関連付けインポートを AppReducer 経由で BackupReducer に委譲する。

**Tech Stack:** Swift 5.9, SwiftUI, TCA (ComposableArchitecture 1.17+), swift-dependencies, SwiftData, ZIPFoundation (MIT), Swift Testing (@Test, #expect)

---

### Task 1: Domain層 - BackupPayload + BackupResult（Codable データ構造体）

**Files:**
- Create: `repository/ios/SoyokaModules/Sources/Domain/ValueObjects/BackupPayload.swift`
- Create: `repository/ios/SoyokaModules/Sources/Domain/ValueObjects/BackupResult.swift`
- Test: `repository/ios/SoyokaModules/Tests/DomainTests/BackupPayloadTests.swift`

- [ ] **Step 1: BackupPayload.swift を作成**

```swift
import Foundation

/// バックアップファイル (metadata.json) のルートデータ構造
/// 設計書 2026-03-26-backup-restore-design.md 準拠
public struct BackupPayload: Codable, Sendable, Equatable {
    public let version: Int
    public let exportedAt: Date
    public let sourceApp: String
    public let sourceBundleId: String
    public let memos: [BackupMemo]
    public let tags: [BackupTag]

    public init(
        version: Int = 1,
        exportedAt: Date = Date(),
        sourceApp: String = "Soyoka",
        sourceBundleId: String = "app.soyoka",
        memos: [BackupMemo],
        tags: [BackupTag]
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.sourceApp = sourceApp
        self.sourceBundleId = sourceBundleId
        self.memos = memos
        self.tags = tags
    }

    /// 現在サポートするバックアップバージョン
    public static let currentSupportedVersion = 1
}

// MARK: - BackupMemo

public struct BackupMemo: Codable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let createdAt: Date
    public let updatedAt: Date
    public let durationSeconds: Double
    public let audioFileName: String?
    public let audioFormat: String
    public let status: String
    public let isFavorite: Bool
    public let transcription: BackupTranscription?
    public let aiSummary: BackupAISummary?
    public let emotionAnalysis: BackupEmotionAnalysis?
    public let tagNames: [String]

    public init(
        id: UUID,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        durationSeconds: Double,
        audioFileName: String?,
        audioFormat: String,
        status: String,
        isFavorite: Bool,
        transcription: BackupTranscription?,
        aiSummary: BackupAISummary?,
        emotionAnalysis: BackupEmotionAnalysis?,
        tagNames: [String]
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.durationSeconds = durationSeconds
        self.audioFileName = audioFileName
        self.audioFormat = audioFormat
        self.status = status
        self.isFavorite = isFavorite
        self.transcription = transcription
        self.aiSummary = aiSummary
        self.emotionAnalysis = emotionAnalysis
        self.tagNames = tagNames
    }
}

// MARK: - BackupTranscription

public struct BackupTranscription: Codable, Sendable, Equatable {
    public let id: UUID
    public let fullText: String
    public let language: String
    public let engineType: String
    public let confidence: Double
    public let processedAt: Date

    public init(
        id: UUID,
        fullText: String,
        language: String,
        engineType: String,
        confidence: Double,
        processedAt: Date
    ) {
        self.id = id
        self.fullText = fullText
        self.language = language
        self.engineType = engineType
        self.confidence = confidence
        self.processedAt = processedAt
    }
}

// MARK: - BackupAISummary

public struct BackupAISummary: Codable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let summaryText: String
    public let keyPoints: [String]?
    public let providerType: String
    public let isOnDevice: Bool
    public let generatedAt: Date

    public init(
        id: UUID,
        title: String,
        summaryText: String,
        keyPoints: [String]?,
        providerType: String,
        isOnDevice: Bool,
        generatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.summaryText = summaryText
        self.keyPoints = keyPoints
        self.providerType = providerType
        self.isOnDevice = isOnDevice
        self.generatedAt = generatedAt
    }
}

// MARK: - BackupEmotionAnalysis

public struct BackupEmotionAnalysis: Codable, Sendable, Equatable {
    public let id: UUID
    public let primaryEmotion: String
    public let confidence: Double
    /// emotionScores は [String: Double] で保持（EmotionCategory.rawValue をキーに使用）
    public let emotionScores: [String: Double]
    public let evidence: [BackupSentimentEvidence]?
    public let analyzedAt: Date

    public init(
        id: UUID,
        primaryEmotion: String,
        confidence: Double,
        emotionScores: [String: Double],
        evidence: [BackupSentimentEvidence]?,
        analyzedAt: Date
    ) {
        self.id = id
        self.primaryEmotion = primaryEmotion
        self.confidence = confidence
        self.emotionScores = emotionScores
        self.evidence = evidence
        self.analyzedAt = analyzedAt
    }
}

// MARK: - BackupSentimentEvidence

public struct BackupSentimentEvidence: Codable, Sendable, Equatable {
    public let text: String
    public let emotion: String

    public init(text: String, emotion: String) {
        self.text = text
        self.emotion = emotion
    }
}

// MARK: - BackupTag

public struct BackupTag: Codable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let colorHex: String
    public let source: String
    public let createdAt: Date

    public init(
        id: UUID,
        name: String,
        colorHex: String,
        source: String,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.source = source
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 2: BackupResult.swift を作成**

```swift
import Foundation

/// バックアップインポート結果
public struct BackupResult: Sendable, Equatable {
    /// インポート成功件数
    public let importedCount: Int
    /// UUID 重複によりスキップされた件数
    public let skippedCount: Int
    /// 音声ファイル欠損でメタデータのみ復元された件数
    public let audioMissingCount: Int

    public init(
        importedCount: Int,
        skippedCount: Int,
        audioMissingCount: Int = 0
    ) {
        self.importedCount = importedCount
        self.skippedCount = skippedCount
        self.audioMissingCount = audioMissingCount
    }

    /// 合計処理件数
    public var totalCount: Int {
        importedCount + skippedCount
    }
}
```

- [ ] **Step 3: BackupPayloadTests.swift を作成（Codable ラウンドトリップ + emotionScores 変換テスト）**

```swift
import Foundation
import Testing
@testable import Domain

@Suite("BackupPayload Codable テスト")
struct BackupPayloadTests {

    // MARK: - ヘルパー

    private func makeTestPayload() -> BackupPayload {
        let transcription = BackupTranscription(
            id: UUID(),
            fullText: "今日は天気が良くて散歩した",
            language: "ja-JP",
            engineType: STTEngineType.speechAnalyzer.rawValue,
            confidence: 0.85,
            processedAt: Date()
        )
        let aiSummary = BackupAISummary(
            id: UUID(),
            title: "散歩中の気づき",
            summaryText: "天気の良い日に散歩",
            keyPoints: ["ポイント1", "ポイント2"],
            providerType: LLMProviderType.onDeviceAppleIntelligence.rawValue,
            isOnDevice: true,
            generatedAt: Date()
        )
        let emotionAnalysis = BackupEmotionAnalysis(
            id: UUID(),
            primaryEmotion: EmotionCategory.joy.rawValue,
            confidence: 0.72,
            emotionScores: [
                EmotionCategory.joy.rawValue: 0.72,
                EmotionCategory.calm.rawValue: 0.20,
                EmotionCategory.surprise.rawValue: 0.08,
            ],
            evidence: [
                BackupSentimentEvidence(
                    text: "天気が良くて",
                    emotion: EmotionCategory.joy.rawValue
                )
            ],
            analyzedAt: Date()
        )
        let memo = BackupMemo(
            id: UUID(),
            title: "テストメモ",
            createdAt: Date(),
            updatedAt: Date(),
            durationSeconds: 45.2,
            audioFileName: "test-uuid.m4a",
            audioFormat: AudioFormat.m4a.rawValue,
            status: MemoStatus.completed.rawValue,
            isFavorite: false,
            transcription: transcription,
            aiSummary: aiSummary,
            emotionAnalysis: emotionAnalysis,
            tagNames: ["アイデア", "散歩"]
        )
        let tag = BackupTag(
            id: UUID(),
            name: "アイデア",
            colorHex: "#FF9500",
            source: TagSource.ai.rawValue,
            createdAt: Date()
        )
        return BackupPayload(
            version: 1,
            memos: [memo],
            tags: [tag]
        )
    }

    @Test("Codable ラウンドトリップ: エンコード → デコードで同一データを復元できる")
    func test_codableRoundTrip_同一データを復元() throws {
        let original = makeTestPayload()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupPayload.self, from: data)
        #expect(decoded.version == original.version)
        #expect(decoded.memos.count == original.memos.count)
        #expect(decoded.tags.count == original.tags.count)
        #expect(decoded.memos.first?.title == "テストメモ")
        #expect(decoded.memos.first?.tagNames == ["アイデア", "散歩"])
    }

    @Test("emotionScores が [String: Double] 形式で正しくシリアライズされる")
    func test_emotionScores_stringDoubleFormat() throws {
        let payload = makeTestPayload()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let memos = json["memos"] as! [[String: Any]]
        let emotion = memos[0]["emotionAnalysis"] as! [String: Any]
        let scores = emotion["emotionScores"] as! [String: Double]
        #expect(scores["joy"] == 0.72)
        #expect(scores["calm"] == 0.20)
    }

    @Test("未知フィールドが含まれるJSONでもデコード成功する（前方互換性）")
    func test_unknownFields_デコード成功() throws {
        let json = """
        {
            "version": 1,
            "exportedAt": "2026-03-26T12:00:00Z",
            "sourceApp": "Soyoka",
            "sourceBundleId": "app.soyoka",
            "memos": [],
            "tags": [],
            "futureField": "should be ignored"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: json)
        #expect(payload.version == 1)
        #expect(payload.memos.isEmpty)
    }

    @Test("バージョンチェック: currentSupportedVersion は 1")
    func test_currentSupportedVersion() {
        #expect(BackupPayload.currentSupportedVersion == 1)
    }

    @Test("BackupResult: totalCount は importedCount + skippedCount")
    func test_backupResult_totalCount() {
        let result = BackupResult(importedCount: 5, skippedCount: 3, audioMissingCount: 1)
        #expect(result.totalCount == 8)
        #expect(result.audioMissingCount == 1)
    }
}
```

- [ ] **Step 4: テスト実行**

```bash
cd repository/ios/SoyokaModules && swift test --filter BackupPayloadTests
```

期待結果: 5 テスト全パス

- [ ] **Step 5: コミット**

```
feat(domain): バックアップ用Codableデータ構造体を追加

- BackupPayload: metadata.json のルート構造体（version, memos, tags）
- BackupResult: インポート結果（成功/スキップ/音声欠損件数）
- emotionScores は [String: Double] 形式でJSON自然なオブジェクト表現
- 前方互換性: 未知フィールドを無視するCodableデフォルト動作を活用
```

---

### Task 2: Domain層 - BackupExportClient / BackupImportClient プロトコル

**Files:**
- Create: `repository/ios/SoyokaModules/Sources/Domain/Protocols/BackupExportClient.swift`
- Create: `repository/ios/SoyokaModules/Sources/Domain/Protocols/BackupImportClient.swift`

- [ ] **Step 1: BackupExportClient.swift を作成（DependencyKey パターン準拠）**

`VoiceMemoRepositoryClient.swift` のパターンに準拠する。`struct` + クロージャ型プロパティ + `TestDependencyKey` + `DependencyValues` 拡張。

```swift
import Dependencies
import Foundation

/// バックアップエクスポートの TCA Dependency ラッパー
/// @Dependency(\.backupExport) で Reducer から注入可能にする
public struct BackupExportClient: Sendable {
    /// 全メモ + 音声ファイルを ZIP エクスポートし、一時ファイルの URL を返す
    public var export: @Sendable () async throws -> URL

    public init(
        export: @escaping @Sendable () async throws -> URL
    ) {
        self.export = export
    }
}

// MARK: - DependencyKey

extension BackupExportClient: TestDependencyKey {
    public static let testValue = BackupExportClient(
        export: unimplemented("BackupExportClient.export")
    )
}

extension DependencyValues {
    public var backupExport: BackupExportClient {
        get { self[BackupExportClient.self] }
        set { self[BackupExportClient.self] = newValue }
    }
}
```

- [ ] **Step 2: BackupImportClient.swift を作成**

```swift
import Dependencies
import Foundation

/// バックアップインポートの TCA Dependency ラッパー
/// @Dependency(\.backupImport) で Reducer から注入可能にする
public struct BackupImportClient: Sendable {
    /// .soyokabackup ファイルからインポートし、結果を返す
    public var importBackup: @Sendable (_ fileURL: URL) async throws -> BackupResult

    public init(
        importBackup: @escaping @Sendable (_ fileURL: URL) async throws -> BackupResult
    ) {
        self.importBackup = importBackup
    }
}

// MARK: - DependencyKey

extension BackupImportClient: TestDependencyKey {
    public static let testValue = BackupImportClient(
        importBackup: unimplemented("BackupImportClient.importBackup")
    )
}

extension DependencyValues {
    public var backupImport: BackupImportClient {
        get { self[BackupImportClient.self] }
        set { self[BackupImportClient.self] = newValue }
    }
}
```

- [ ] **Step 3: ビルド確認**

```bash
cd repository/ios/SoyokaModules && swift build
```

期待結果: ビルド成功（Domain モジュールのコンパイルが通ること）

- [ ] **Step 4: コミット**

```
feat(domain): バックアップ用DependencyClientプロトコルを追加

- BackupExportClient: エクスポート処理の抽象化（ZIP URL を返却）
- BackupImportClient: インポート処理の抽象化（BackupResult を返却）
- VoiceMemoRepositoryClient と同一のDependencyKeyパターンを踏襲
- テスト用 unimplemented() モックを提供
```

---

### Task 3: Package.swift に ZIPFoundation 依存追加

**Files:**
- Modify: `repository/ios/SoyokaModules/Package.swift`

- [ ] **Step 1: Package.swift に ZIPFoundation パッケージ依存を追加**

`dependencies:` 配列に以下を追加:

```swift
.package(
    url: "https://github.com/weichsel/ZIPFoundation",
    from: "0.9.19"
),
```

`InfraStorage` ターゲットの `dependencies:` に以下を追加:

```swift
.product(name: "ZIPFoundation", package: "ZIPFoundation"),
```

`InfraStorageTests` ターゲットの `dependencies:` に以下を追加:

```swift
.product(name: "ZIPFoundation", package: "ZIPFoundation"),
```

変更後の InfraStorage ターゲット:

```swift
.target(
    name: "InfraStorage",
    dependencies: [
        "Domain",
        "SharedUtil",
        .product(name: "ZIPFoundation", package: "ZIPFoundation"),
    ],
    plugins: []
),
```

変更後の InfraStorageTests ターゲット:

```swift
.testTarget(name: "InfraStorageTests", dependencies: [
    "InfraStorage",
    "Domain",
    .product(name: "ZIPFoundation", package: "ZIPFoundation"),
]),
```

- [ ] **Step 2: 依存解決 + ビルド確認**

```bash
cd repository/ios/SoyokaModules && swift package resolve && swift build
```

期待結果: ZIPFoundation のダウンロード + ビルド成功

- [ ] **Step 3: コミット**

```
chore(deps): InfraStorageにZIPFoundation依存を追加

- バックアップ機能のZIP生成/展開にZIPFoundation (MIT) を使用
- バイナリサイズ約200KB、SPM対応済み
- InfraStorageTests にもZIPFoundation依存を追加（テスト用ZIP操作のため）
```

---

### Task 4: InfraStorage層 - BackupExporter 実装

**Files:**
- Create: `repository/ios/SoyokaModules/Sources/InfraStorage/Backup/BackupExporter.swift`
- Test: `repository/ios/SoyokaModules/Tests/InfraStorageTests/BackupExporterTests.swift`

- [ ] **Step 1: BackupExporterTests.swift を作成（TDD: テストファースト）**

```swift
import Foundation
import Testing
import SwiftData
@testable import Domain
@testable import InfraStorage

@Suite("BackupExporter テスト")
struct BackupExporterTests {

    /// テスト用のインメモリ ModelContainer を生成
    @MainActor
    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainerConfiguration.create(inMemory: true)
    }

    /// テスト用メモをSwiftDataに保存
    @MainActor
    private func insertTestMemo(
        context: ModelContext,
        id: UUID = UUID(),
        title: String = "テストきおく",
        audioFilePath: String = "Audio/test-uuid.m4a"
    ) -> VoiceMemoModel {
        let memo = VoiceMemoModel(
            id: id,
            title: title,
            durationSeconds: 45.2,
            audioFilePath: audioFilePath,
            audioFormat: .m4a,
            status: .completed,
            isFavorite: false
        )
        context.insert(memo)

        let transcription = TranscriptionModel(
            fullText: "今日は天気が良くて散歩した",
            language: "ja-JP",
            engineType: .speechAnalyzer,
            confidence: 0.85
        )
        transcription.memo = memo
        context.insert(transcription)

        let tag = TagModel(name: "アイデア", colorHex: "#FF9500", source: .ai)
        context.insert(tag)
        memo.tags.append(tag)

        try! context.save()
        return memo
    }

    @Test("エクスポート: BackupPayload が正しく生成される")
    @MainActor
    func test_export_BackupPayload生成() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let memoID = UUID()
        _ = insertTestMemo(context: context, id: memoID)

        let exporter = BackupExporter(modelContainer: container)
        let payload = try exporter.buildPayload()

        #expect(payload.version == 1)
        #expect(payload.sourceApp == "Soyoka")
        #expect(payload.memos.count == 1)
        #expect(payload.memos[0].id == memoID)
        #expect(payload.memos[0].title == "テストきおく")
        #expect(payload.memos[0].transcription?.fullText == "今日は天気が良くて散歩した")
        #expect(payload.memos[0].transcription?.engineType == "speech_analyzer")
        #expect(payload.memos[0].tagNames == ["アイデア"])
        #expect(payload.tags.count == 1)
        #expect(payload.tags[0].name == "アイデア")
        #expect(payload.tags[0].source == "ai")
    }

    @Test("エクスポート: audioFileName は UUID.m4a 形式で出力される")
    @MainActor
    func test_export_audioFileName形式() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let memoID = UUID()
        _ = insertTestMemo(
            context: context,
            id: memoID,
            audioFilePath: "Audio/\(memoID.uuidString).m4a"
        )

        let exporter = BackupExporter(modelContainer: container)
        let payload = try exporter.buildPayload()

        #expect(payload.memos[0].audioFileName == "\(memoID.uuidString).m4a")
    }

    @Test("エクスポート: emotionScores が [String: Double] 形式で出力される")
    @MainActor
    func test_export_emotionScores変換() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let memo = VoiceMemoModel(
            title: "感情テスト",
            durationSeconds: 10.0,
            audioFilePath: "Audio/emotion-test.m4a"
        )
        context.insert(memo)
        let emotion = EmotionAnalysisModel(
            primaryEmotion: .joy,
            confidence: 0.72,
            emotionScores: ["joy": 0.72, "calm": 0.20],
            evidence: [["text": "嬉しい", "emotion": "joy"]],
            analyzedAt: Date()
        )
        emotion.memo = memo
        context.insert(emotion)
        try context.save()

        let exporter = BackupExporter(modelContainer: container)
        let payload = try exporter.buildPayload()

        let memoPayload = payload.memos.first { $0.title == "感情テスト" }!
        #expect(memoPayload.emotionAnalysis?.emotionScores["joy"] == 0.72)
        #expect(memoPayload.emotionAnalysis?.emotionScores["calm"] == 0.20)
        #expect(memoPayload.emotionAnalysis?.primaryEmotion == "joy")
    }

    @Test("エクスポート: メモが0件でも空の payload を生成できる")
    @MainActor
    func test_export_メモ0件() throws {
        let container = try makeTestContainer()
        let exporter = BackupExporter(modelContainer: container)
        let payload = try exporter.buildPayload()

        #expect(payload.memos.isEmpty)
        #expect(payload.tags.isEmpty)
        #expect(payload.version == 1)
    }
}
```

- [ ] **Step 2: BackupExporter.swift を作成**

```swift
import Domain
import Foundation
import SwiftData
import ZIPFoundation

/// バックアップエクスポート処理
/// 設計書 2026-03-26-backup-restore-design.md エクスポートフロー準拠
/// SwiftData から全データを読み取り、JSON + 音声ファイルを ZIP 化する
public final class BackupExporter: @unchecked Sendable {

    private let modelContainer: ModelContainer

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Public API

    /// エクスポートを実行し、.soyokabackup ファイルの URL を返す
    /// 返却される URL は FileManager.temporaryDirectory 配下の一時ファイル
    /// 呼び出し側（ShareSheet の onDismiss 等）で削除すること
    @MainActor
    public func export() throws -> URL {
        let payload = try buildPayload()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // metadata.json を書き出し
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(payload)
        let metadataURL = tempDir.appendingPathComponent("metadata.json")
        try jsonData.write(to: metadataURL)

        // audio/ ディレクトリに音声ファイルをコピー
        let audioDir = tempDir.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        for memo in payload.memos {
            guard let audioFileName = memo.audioFileName else { continue }
            let sourceURL = documentsDir.appendingPathComponent("Audio").appendingPathComponent(audioFileName)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                let destURL = audioDir.appendingPathComponent(audioFileName)
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
            }
        }

        // ZIP 化
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let zipFileName = "\(timestamp).soyokabackup"
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(zipFileName)

        // 既存の同名ファイルがあれば削除
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }

        try FileManager.default.zipItem(at: tempDir, to: zipURL)

        // 一時展開ディレクトリを削除
        try? FileManager.default.removeItem(at: tempDir)

        return zipURL
    }

    // MARK: - Internal (テスト用に公開)

    /// SwiftData から BackupPayload を構築する
    @MainActor
    public func buildPayload() throws -> BackupPayload {
        let context = modelContainer.mainContext

        // 全メモ取得
        let memoDescriptor = FetchDescriptor<VoiceMemoModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let memoModels = try context.fetch(memoDescriptor)

        // 全タグ取得
        let tagDescriptor = FetchDescriptor<TagModel>()
        let tagModels = try context.fetch(tagDescriptor)

        // メモ → BackupMemo 変換
        let backupMemos = memoModels.map { model -> BackupMemo in
            // audioFilePath から audioFileName を抽出（"Audio/uuid.m4a" → "uuid.m4a"）
            let audioFileName: String? = {
                let path = model.audioFilePath
                guard !path.isEmpty else { return nil }
                return URL(fileURLWithPath: path).lastPathComponent
            }()

            let transcription: BackupTranscription? = model.transcription.map {
                BackupTranscription(
                    id: $0.id,
                    fullText: $0.fullText,
                    language: $0.language,
                    engineType: $0.engineType.rawValue,
                    confidence: $0.confidence,
                    processedAt: $0.processedAt
                )
            }

            let aiSummary: BackupAISummary? = model.aiSummary.map {
                BackupAISummary(
                    id: $0.id,
                    title: $0.title,
                    summaryText: $0.summaryText,
                    keyPoints: $0.keyPoints.isEmpty ? nil : $0.keyPoints,
                    providerType: $0.providerType.rawValue,
                    isOnDevice: $0.isOnDevice,
                    generatedAt: $0.generatedAt
                )
            }

            let emotionAnalysis: BackupEmotionAnalysis? = model.emotionAnalysis.map {
                let evidence: [BackupSentimentEvidence]? = $0.evidence.isEmpty ? nil : $0.evidence.compactMap { dict in
                    guard let text = dict["text"], let emotion = dict["emotion"] else { return nil }
                    return BackupSentimentEvidence(text: text, emotion: emotion)
                }
                return BackupEmotionAnalysis(
                    id: $0.id,
                    primaryEmotion: $0.primaryEmotion.rawValue,
                    confidence: $0.confidence,
                    emotionScores: $0.emotionScores,
                    evidence: evidence,
                    analyzedAt: $0.analyzedAt
                )
            }

            return BackupMemo(
                id: model.id,
                title: model.title,
                createdAt: model.createdAt,
                updatedAt: model.updatedAt,
                durationSeconds: model.durationSeconds,
                audioFileName: audioFileName,
                audioFormat: model.audioFormat.rawValue,
                status: model.status.rawValue,
                isFavorite: model.isFavorite,
                transcription: transcription,
                aiSummary: aiSummary,
                emotionAnalysis: emotionAnalysis,
                tagNames: model.tags.map(\.name)
            )
        }

        // タグ → BackupTag 変換
        let backupTags = tagModels.map { model -> BackupTag in
            BackupTag(
                id: model.id,
                name: model.name,
                colorHex: model.colorHex,
                source: model.source.rawValue,
                createdAt: model.createdAt
            )
        }

        return BackupPayload(
            memos: backupMemos,
            tags: backupTags
        )
    }
}
```

- [ ] **Step 3: テスト実行**

```bash
cd repository/ios/SoyokaModules && swift test --filter BackupExporterTests
```

期待結果: 4 テスト全パス

- [ ] **Step 4: コミット**

```
feat(infra): BackupExporterを実装（SwiftData → JSON + ZIP エクスポート）

- SwiftData から全メモ・タグを読み取り BackupPayload に変換
- audioFilePath から相対ファイル名を抽出して音声ファイルをコピー
- ZIPFoundation で metadata.json + audio/ を ZIP 化
- 一時ファイルは FileManager.temporaryDirectory に配置
- enum rawValue を使用した自然なJSON出力（emotionScores, engineType 等）
```

---

### Task 5: InfraStorage層 - BackupImporter 実装

**Files:**
- Create: `repository/ios/SoyokaModules/Sources/InfraStorage/Backup/BackupImporter.swift`
- Test: `repository/ios/SoyokaModules/Tests/InfraStorageTests/BackupImporterTests.swift`

- [ ] **Step 1: BackupImporterTests.swift を作成（TDD: テストファースト）**

```swift
import Foundation
import Testing
import SwiftData
import ZIPFoundation
@testable import Domain
@testable import InfraStorage

@Suite("BackupImporter テスト")
struct BackupImporterTests {

    @MainActor
    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainerConfiguration.create(inMemory: true)
    }

    /// テスト用の .soyokabackup (ZIP) ファイルを生成するヘルパー
    private func createTestBackupFile(payload: BackupPayload, audioFiles: [String: Data] = [:]) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(payload)
        try jsonData.write(to: tempDir.appendingPathComponent("metadata.json"))

        if !audioFiles.isEmpty {
            let audioDir = tempDir.appendingPathComponent("audio", isDirectory: true)
            try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
            for (name, data) in audioFiles {
                try data.write(to: audioDir.appendingPathComponent(name))
            }
        }

        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).soyokabackup")
        try FileManager.default.zipItem(at: tempDir, to: zipURL)
        try? FileManager.default.removeItem(at: tempDir)
        return zipURL
    }

    private func makeMinimalPayload(memoID: UUID = UUID()) -> BackupPayload {
        let memo = BackupMemo(
            id: memoID,
            title: "テストきおく",
            createdAt: Date(),
            updatedAt: Date(),
            durationSeconds: 30.0,
            audioFileName: "\(memoID.uuidString).m4a",
            audioFormat: "m4a",
            status: "completed",
            isFavorite: false,
            transcription: BackupTranscription(
                id: UUID(),
                fullText: "テスト文字起こし",
                language: "ja-JP",
                engineType: "speech_analyzer",
                confidence: 0.9,
                processedAt: Date()
            ),
            aiSummary: nil,
            emotionAnalysis: nil,
            tagNames: ["テストタグ"]
        )
        let tag = BackupTag(
            id: UUID(),
            name: "テストタグ",
            colorHex: "#FF0000",
            source: "ai",
            createdAt: Date()
        )
        return BackupPayload(memos: [memo], tags: [tag])
    }

    @Test("インポート: 新規メモが正しく SwiftData に保存される")
    @MainActor
    func test_import_新規メモ保存() async throws {
        let container = try makeTestContainer()
        let memoID = UUID()
        let payload = makeMinimalPayload(memoID: memoID)
        let zipURL = try createTestBackupFile(payload: payload)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let importer = BackupImporter(modelContainer: container)
        let result = try await importer.importBackup(fileURL: zipURL)

        #expect(result.importedCount == 1)
        #expect(result.skippedCount == 0)

        let descriptor = FetchDescriptor<VoiceMemoModel>(
            predicate: #Predicate { $0.id == memoID }
        )
        let memos = try container.mainContext.fetch(descriptor)
        #expect(memos.count == 1)
        #expect(memos[0].title == "テストきおく")
        #expect(memos[0].transcription?.fullText == "テスト文字起こし")
    }

    @Test("インポート: UUID 重複メモはスキップされる")
    @MainActor
    func test_import_重複スキップ() async throws {
        let container = try makeTestContainer()
        let memoID = UUID()

        // 既存メモを先に挿入
        let existingMemo = VoiceMemoModel(
            id: memoID,
            title: "既存きおく",
            durationSeconds: 10.0,
            audioFilePath: "Audio/existing.m4a"
        )
        container.mainContext.insert(existingMemo)
        try container.mainContext.save()

        let payload = makeMinimalPayload(memoID: memoID)
        let zipURL = try createTestBackupFile(payload: payload)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let importer = BackupImporter(modelContainer: container)
        let result = try await importer.importBackup(fileURL: zipURL)

        #expect(result.importedCount == 0)
        #expect(result.skippedCount == 1)

        // タイトルが上書きされていないことを確認
        let descriptor = FetchDescriptor<VoiceMemoModel>(
            predicate: #Predicate { $0.id == memoID }
        )
        let memos = try container.mainContext.fetch(descriptor)
        #expect(memos[0].title == "既存きおく")
    }

    @Test("インポート: タグマージ - 同名タグは既存UUIDを採用")
    @MainActor
    func test_import_タグマージ_同名は既存UUID採用() async throws {
        let container = try makeTestContainer()
        let existingTagID = UUID()

        // 既存タグを先に挿入
        let existingTag = TagModel(id: existingTagID, name: "テストタグ", colorHex: "#00FF00", source: .manual)
        container.mainContext.insert(existingTag)
        try container.mainContext.save()

        let payload = makeMinimalPayload()
        let zipURL = try createTestBackupFile(payload: payload)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let importer = BackupImporter(modelContainer: container)
        _ = try await importer.importBackup(fileURL: zipURL)

        // タグが重複作成されていないことを確認
        let tagDescriptor = FetchDescriptor<TagModel>(
            predicate: #Predicate { $0.name == "テストタグ" }
        )
        let tags = try container.mainContext.fetch(tagDescriptor)
        #expect(tags.count == 1)
        #expect(tags[0].id == existingTagID)
    }

    @Test("インポート: バージョンが大きい場合はエラー")
    @MainActor
    func test_import_バージョン不一致エラー() async throws {
        let container = try makeTestContainer()
        let payload = BackupPayload(
            version: 999,
            memos: [],
            tags: []
        )
        let zipURL = try createTestBackupFile(payload: payload)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let importer = BackupImporter(modelContainer: container)
        await #expect(throws: BackupImportError.self) {
            try await importer.importBackup(fileURL: zipURL)
        }
    }

    @Test("インポート: 音声ファイル欠損時はメタデータのみ復元")
    @MainActor
    func test_import_音声欠損_メタデータのみ復元() async throws {
        let container = try makeTestContainer()
        let memoID = UUID()
        let payload = makeMinimalPayload(memoID: memoID)
        // 音声ファイルを含めずに ZIP を作成
        let zipURL = try createTestBackupFile(payload: payload, audioFiles: [:])
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let importer = BackupImporter(modelContainer: container)
        let result = try await importer.importBackup(fileURL: zipURL)

        #expect(result.importedCount == 1)
        #expect(result.audioMissingCount == 1)

        let descriptor = FetchDescriptor<VoiceMemoModel>(
            predicate: #Predicate { $0.id == memoID }
        )
        let memos = try container.mainContext.fetch(descriptor)
        #expect(memos.count == 1)
    }
}
```

- [ ] **Step 2: BackupImporter.swift を作成**

```swift
import Domain
import Foundation
import SwiftData
import ZIPFoundation

/// バックアップインポートエラー
public enum BackupImportError: Error, Equatable, Sendable, LocalizedError {
    case zipExtractionFailed
    case metadataNotFound
    case jsonDecodeFailed(String)
    case unsupportedVersion(Int)
    case diskSpaceInsufficient

    public var errorDescription: String? {
        switch self {
        case .zipExtractionFailed:
            return "ファイルが破損しています"
        case .metadataNotFound:
            return "対応していないバックアップ形式です"
        case .jsonDecodeFailed(let detail):
            return "対応していないバックアップ形式です: \(detail)"
        case .unsupportedVersion(let version):
            return "新しいバージョンのアプリが必要です（バックアップ v\(version)）"
        case .diskSpaceInsufficient:
            return "ストレージの空き容量が不足しています"
        }
    }
}

/// バックアップインポート処理
/// 設計書 2026-03-26-backup-restore-design.md インポートフロー準拠
public final class BackupImporter: @unchecked Sendable {

    private let modelContainer: ModelContainer
    /// FTS5 インデックス更新用（オプショナル: テスト時は nil 可）
    private let fts5Upsert: ((_ memoID: String, _ title: String, _ text: String, _ summary: String, _ tags: String) throws -> Void)?

    public init(
        modelContainer: ModelContainer,
        fts5Upsert: ((_ memoID: String, _ title: String, _ text: String, _ summary: String, _ tags: String) throws -> Void)? = nil
    ) {
        self.modelContainer = modelContainer
        self.fts5Upsert = fts5Upsert
    }

    // MARK: - Public API

    @MainActor
    public func importBackup(fileURL: URL) async throws -> BackupResult {
        // セキュリティスコープのアクセス開始（ファイルピッカー経由の場合に必要）
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { fileURL.stopAccessingSecurityScopedResource() }
        }

        // 一時ディレクトリに展開
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try FileManager.default.unzipItem(at: fileURL, to: tempDir)
        } catch {
            throw BackupImportError.zipExtractionFailed
        }

        // metadata.json を読み取り
        // ZIP 展開時にルートディレクトリが含まれる場合を考慮
        let metadataURL = findMetadataJSON(in: tempDir)
        guard let metadataURL else {
            throw BackupImportError.metadataNotFound
        }

        let payload: BackupPayload
        do {
            let data = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            payload = try decoder.decode(BackupPayload.self, from: data)
        } catch {
            throw BackupImportError.jsonDecodeFailed(error.localizedDescription)
        }

        // バージョンチェック
        if payload.version > BackupPayload.currentSupportedVersion {
            throw BackupImportError.unsupportedVersion(payload.version)
        }

        // タグのインポート + ルックアップテーブル構築
        let tagLookup = try buildTagLookup(from: payload.tags)

        // メモのインポート
        let audioBaseDir = metadataURL.deletingLastPathComponent().appendingPathComponent("audio")
        var importedCount = 0
        var skippedCount = 0
        var audioMissingCount = 0

        let context = modelContainer.mainContext

        for backupMemo in payload.memos {
            // UUID で既存データを検索
            let memoID = backupMemo.id
            let descriptor = FetchDescriptor<VoiceMemoModel>(
                predicate: #Predicate { $0.id == memoID }
            )
            let existing = try context.fetch(descriptor)
            if !existing.isEmpty {
                skippedCount += 1
                continue
            }

            // 音声ファイルのコピー
            var audioMissing = false
            if let audioFileName = backupMemo.audioFileName {
                let sourceAudioURL = audioBaseDir.appendingPathComponent(audioFileName)
                if FileManager.default.fileExists(atPath: sourceAudioURL.path) {
                    let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let destAudioDir = documentsDir.appendingPathComponent("Audio", isDirectory: true)
                    if !FileManager.default.fileExists(atPath: destAudioDir.path) {
                        try FileManager.default.createDirectory(at: destAudioDir, withIntermediateDirectories: true)
                    }
                    let destURL = destAudioDir.appendingPathComponent(audioFileName)
                    if !FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.copyItem(at: sourceAudioURL, to: destURL)
                    }
                } else {
                    audioMissing = true
                }
            }

            if audioMissing {
                audioMissingCount += 1
            }

            // SwiftData にメモを書き込み
            let audioFilePath = backupMemo.audioFileName.map { "Audio/\($0)" } ?? ""
            let memoModel = VoiceMemoModel(
                id: backupMemo.id,
                title: backupMemo.title,
                createdAt: backupMemo.createdAt,
                durationSeconds: backupMemo.durationSeconds,
                audioFilePath: audioFilePath,
                audioFormat: AudioFormat(rawValue: backupMemo.audioFormat) ?? .m4a,
                status: MemoStatus(rawValue: backupMemo.status) ?? .completed,
                isFavorite: backupMemo.isFavorite
            )
            memoModel.updatedAt = backupMemo.updatedAt
            context.insert(memoModel)

            // Transcription
            if let t = backupMemo.transcription {
                let model = TranscriptionModel(
                    id: t.id,
                    fullText: t.fullText,
                    language: t.language,
                    engineType: STTEngineType(rawValue: t.engineType) ?? .whisperKit,
                    confidence: t.confidence,
                    processedAt: t.processedAt
                )
                model.memo = memoModel
                context.insert(model)
            }

            // AISummary
            if let s = backupMemo.aiSummary {
                let model = AISummaryModel(
                    id: s.id,
                    title: s.title,
                    summaryText: s.summaryText,
                    keyPoints: s.keyPoints ?? [],
                    providerType: LLMProviderType(rawValue: s.providerType) ?? .onDeviceLlamaCpp,
                    isOnDevice: s.isOnDevice,
                    generatedAt: s.generatedAt
                )
                model.memo = memoModel
                context.insert(model)
            }

            // EmotionAnalysis
            if let e = backupMemo.emotionAnalysis {
                let evidence: [[String: String]] = (e.evidence ?? []).map { ev in
                    ["text": ev.text, "emotion": ev.emotion]
                }
                let model = EmotionAnalysisModel(
                    id: e.id,
                    primaryEmotion: EmotionCategory(rawValue: e.primaryEmotion) ?? .neutral,
                    confidence: e.confidence,
                    emotionScores: e.emotionScores,
                    evidence: evidence,
                    analyzedAt: e.analyzedAt
                )
                model.memo = memoModel
                context.insert(model)
            }

            // タグのリレーション設定
            for tagName in backupMemo.tagNames {
                if let tagModel = tagLookup[tagName] {
                    memoModel.tags.append(tagModel)
                }
            }

            // FTS5 インデックス更新
            if let fts5Upsert {
                try? fts5Upsert(
                    backupMemo.id.uuidString,
                    backupMemo.title,
                    backupMemo.transcription?.fullText ?? "",
                    backupMemo.aiSummary?.summaryText ?? "",
                    backupMemo.tagNames.joined(separator: " ")
                )
            }

            importedCount += 1
        }

        try context.save()

        return BackupResult(
            importedCount: importedCount,
            skippedCount: skippedCount,
            audioMissingCount: audioMissingCount
        )
    }

    // MARK: - Private

    /// ZIP 展開後のディレクトリから metadata.json を探す
    /// ZIPFoundation が中間ディレクトリを作る場合を考慮して再帰的に検索
    private func findMetadataJSON(in directory: URL) -> URL? {
        let directPath = directory.appendingPathComponent("metadata.json")
        if FileManager.default.fileExists(atPath: directPath.path) {
            return directPath
        }
        // 1階層下を検索（ZIP がルートフォルダを含む場合）
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) {
            for item in contents {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    let nested = item.appendingPathComponent("metadata.json")
                    if FileManager.default.fileExists(atPath: nested.path) {
                        return nested
                    }
                }
            }
        }
        return nil
    }

    /// タグのインポート: 名前ベースのマージ戦略
    /// 同名タグは既存 UUID を採用、新規タグはバックアップの UUID で作成
    @MainActor
    private func buildTagLookup(from backupTags: [BackupTag]) throws -> [String: TagModel] {
        let context = modelContainer.mainContext
        var lookup: [String: TagModel] = [:]

        // 既存タグを全件取得してルックアップテーブルに
        let existingDescriptor = FetchDescriptor<TagModel>()
        let existingTags = try context.fetch(existingDescriptor)
        for tag in existingTags {
            lookup[tag.name] = tag
        }

        // バックアップのタグを処理
        for backupTag in backupTags {
            if lookup[backupTag.name] != nil {
                // 同名タグが既存にある → 既存を採用（バックアップ UUID は破棄）
                continue
            }
            // 新規タグとして作成
            let newTag = TagModel(
                id: backupTag.id,
                name: backupTag.name,
                colorHex: backupTag.colorHex,
                source: TagSource(rawValue: backupTag.source) ?? .ai,
                createdAt: backupTag.createdAt
            )
            context.insert(newTag)
            lookup[backupTag.name] = newTag
        }

        return lookup
    }
}
```

- [ ] **Step 3: テスト実行**

```bash
cd repository/ios/SoyokaModules && swift test --filter BackupImporterTests
```

期待結果: 5 テスト全パス

- [ ] **Step 4: コミット**

```
feat(infra): BackupImporterを実装（ZIP展開 → SwiftData書き込み）

- ZIP展開 + metadata.json デコード + バージョンチェック
- UUID ベースの重複チェック（既存メモはスキップ）
- タグマージ戦略: 同名タグは既存UUIDを採用、新規のみ作成
- 音声ファイル欠損時はメタデータのみ復元（audioMissingCount で報告）
- FTS5インデックス更新はオプショナル注入（テスト時は省略可）
- セキュリティスコープのアクセス開始/終了を適切に管理
```

---

### Task 6: FeatureSettings - BackupReducer + BackupView

**Files:**
- Create: `repository/ios/SoyokaModules/Sources/FeatureSettings/Backup/BackupReducer.swift`
- Create: `repository/ios/SoyokaModules/Sources/FeatureSettings/Backup/BackupView.swift`
- Test: `repository/ios/SoyokaModules/Tests/FeatureSettingsTests/BackupReducerTests.swift`

- [ ] **Step 1: BackupReducerTests.swift を作成（TDD: テストファースト）**

```swift
import ComposableArchitecture
import Foundation
import Testing
@testable import Domain
@testable import FeatureSettings

@Suite("BackupReducer テスト")
@MainActor
struct BackupReducerTests {

    @Test("エクスポートタップ → isExporting = true → 成功 → fileURL が設定される")
    func test_exportTapped_成功() async {
        let testURL = URL(fileURLWithPath: "/tmp/test.soyokabackup")
        let store = TestStore(
            initialState: BackupReducer.State()
        ) {
            BackupReducer()
        } withDependencies: {
            $0.backupExport.export = { testURL }
        }

        await store.send(.exportTapped) {
            $0.isExporting = true
        }
        await store.receive(\.exportCompleted) {
            $0.isExporting = false
            $0.exportedFileURL = testURL
            $0.showShareSheet = true
        }
    }

    @Test("エクスポート失敗 → errorMessage が設定される")
    func test_exportTapped_失敗() async {
        let store = TestStore(
            initialState: BackupReducer.State()
        ) {
            BackupReducer()
        } withDependencies: {
            $0.backupExport.export = { throw NSError(domain: "test", code: -1) }
        }

        await store.send(.exportTapped) {
            $0.isExporting = true
        }
        await store.receive(\.exportFailed) {
            $0.isExporting = false
            $0.errorMessage = "バックアップの作成に失敗しました"
        }
    }

    @Test("ShareSheet 閉じる → showShareSheet = false, fileURL = nil")
    func test_shareSheetDismissed() async {
        let store = TestStore(
            initialState: BackupReducer.State(
                showShareSheet: true,
                exportedFileURL: URL(fileURLWithPath: "/tmp/test.soyokabackup")
            )
        ) {
            BackupReducer()
        }

        await store.send(.shareSheetDismissed) {
            $0.showShareSheet = false
            $0.exportedFileURL = nil
        }
    }

    @Test("インポートタップ → ファイルピッカー表示")
    func test_importTapped() async {
        let store = TestStore(
            initialState: BackupReducer.State()
        ) {
            BackupReducer()
        }

        await store.send(.importTapped) {
            $0.showFilePicker = true
        }
    }

    @Test("インポート成功 → 結果アラート表示")
    func test_importFileSelected_成功() async {
        let testURL = URL(fileURLWithPath: "/tmp/test.soyokabackup")
        let result = BackupResult(importedCount: 5, skippedCount: 2, audioMissingCount: 1)
        let store = TestStore(
            initialState: BackupReducer.State()
        ) {
            BackupReducer()
        } withDependencies: {
            $0.backupImport.importBackup = { _ in result }
        }

        await store.send(.importFileSelected(testURL)) {
            $0.showFilePicker = false
            $0.isImporting = true
        }
        await store.receive(\.importCompleted) {
            $0.isImporting = false
            $0.importResult = result
            $0.showImportResultAlert = true
        }
    }

    @Test("インポート失敗 → エラーメッセージ表示")
    func test_importFileSelected_失敗() async {
        let testURL = URL(fileURLWithPath: "/tmp/test.soyokabackup")
        let store = TestStore(
            initialState: BackupReducer.State()
        ) {
            BackupReducer()
        } withDependencies: {
            $0.backupImport.importBackup = { _ in
                throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "テストエラー"])
            }
        }

        await store.send(.importFileSelected(testURL)) {
            $0.showFilePicker = false
            $0.isImporting = true
        }
        await store.receive(\.importFailed) {
            $0.isImporting = false
            $0.errorMessage = "テストエラー"
        }
    }

    @Test("外部 URL からのインポート（onOpenURL 経由）")
    func test_importFromURL() async {
        let testURL = URL(fileURLWithPath: "/tmp/external.soyokabackup")
        let result = BackupResult(importedCount: 3, skippedCount: 0)
        let store = TestStore(
            initialState: BackupReducer.State()
        ) {
            BackupReducer()
        } withDependencies: {
            $0.backupImport.importBackup = { _ in result }
        }

        await store.send(.importFromURL(testURL)) {
            $0.isImporting = true
        }
        await store.receive(\.importCompleted) {
            $0.isImporting = false
            $0.importResult = result
            $0.showImportResultAlert = true
        }
    }
}
```

- [ ] **Step 2: BackupReducer.swift を作成**

```swift
import ComposableArchitecture
import Domain
import Foundation

/// バックアップ/リストア機能の TCA Reducer
/// 設計書 2026-03-26-backup-restore-design.md 準拠
/// SettingsReducer のサブステートとして統合される
@Reducer
public struct BackupReducer {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        /// エクスポート中フラグ
        public var isExporting: Bool = false
        /// インポート中フラグ
        public var isImporting: Bool = false
        /// エクスポート完了後の一時ファイル URL
        public var exportedFileURL: URL?
        /// ShareSheet 表示フラグ
        public var showShareSheet: Bool = false
        /// ファイルピッカー表示フラグ
        public var showFilePicker: Bool = false
        /// インポート結果アラート表示フラグ
        public var showImportResultAlert: Bool = false
        /// インポート結果
        public var importResult: BackupResult?
        /// エラーメッセージ
        public var errorMessage: String?

        public init(
            isExporting: Bool = false,
            isImporting: Bool = false,
            exportedFileURL: URL? = nil,
            showShareSheet: Bool = false,
            showFilePicker: Bool = false,
            showImportResultAlert: Bool = false,
            importResult: BackupResult? = nil,
            errorMessage: String? = nil
        ) {
            self.isExporting = isExporting
            self.isImporting = isImporting
            self.exportedFileURL = exportedFileURL
            self.showShareSheet = showShareSheet
            self.showFilePicker = showFilePicker
            self.showImportResultAlert = showImportResultAlert
            self.importResult = importResult
            self.errorMessage = errorMessage
        }
    }

    // MARK: - Action

    public enum Action: Equatable, Sendable {
        /// 「バックアップを作成」タップ
        case exportTapped
        /// エクスポート成功
        case exportCompleted(URL)
        /// エクスポート失敗
        case exportFailed
        /// ShareSheet が閉じられた（一時ファイルクリーンアップ）
        case shareSheetDismissed
        /// 「バックアップから復元」タップ
        case importTapped
        /// ファイルピッカーでファイルが選択された
        case importFileSelected(URL)
        /// ファイルピッカーがキャンセルされた
        case importFilePickerCancelled
        /// 外部 URL からのインポート（onOpenURL 経由で AppReducer から委譲）
        case importFromURL(URL)
        /// インポート成功
        case importCompleted(BackupResult)
        /// インポート失敗
        case importFailed(String)
        /// インポート結果アラートを閉じる
        case dismissImportResultAlert
        /// エラーアラートを閉じる
        case dismissError
    }

    // MARK: - Dependencies

    @Dependency(\.backupExport) var backupExport
    @Dependency(\.backupImport) var backupImport

    public init() {}

    // MARK: - Reducer Body

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .exportTapped:
                state.isExporting = true
                state.errorMessage = nil
                return .run { send in
                    do {
                        let url = try await backupExport.export()
                        await send(.exportCompleted(url))
                    } catch {
                        await send(.exportFailed)
                    }
                }

            case let .exportCompleted(url):
                state.isExporting = false
                state.exportedFileURL = url
                state.showShareSheet = true
                return .none

            case .exportFailed:
                state.isExporting = false
                state.errorMessage = "バックアップの作成に失敗しました"
                return .none

            case .shareSheetDismissed:
                // 一時ファイルのクリーンアップ
                if let url = state.exportedFileURL {
                    try? FileManager.default.removeItem(at: url)
                }
                state.showShareSheet = false
                state.exportedFileURL = nil
                return .none

            case .importTapped:
                state.showFilePicker = true
                state.errorMessage = nil
                return .none

            case let .importFileSelected(url):
                state.showFilePicker = false
                state.isImporting = true
                return .run { send in
                    do {
                        let result = try await backupImport.importBackup(url)
                        await send(.importCompleted(result))
                    } catch {
                        await send(.importFailed(error.localizedDescription))
                    }
                }

            case .importFilePickerCancelled:
                state.showFilePicker = false
                return .none

            case let .importFromURL(url):
                state.isImporting = true
                state.errorMessage = nil
                return .run { send in
                    do {
                        let result = try await backupImport.importBackup(url)
                        await send(.importCompleted(result))
                    } catch {
                        await send(.importFailed(error.localizedDescription))
                    }
                }

            case let .importCompleted(result):
                state.isImporting = false
                state.importResult = result
                state.showImportResultAlert = true
                return .none

            case let .importFailed(message):
                state.isImporting = false
                state.errorMessage = message
                return .none

            case .dismissImportResultAlert:
                state.showImportResultAlert = false
                state.importResult = nil
                return .none

            case .dismissError:
                state.errorMessage = nil
                return .none
            }
        }
    }
}
```

- [ ] **Step 3: BackupView.swift を作成**

```swift
import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI
import UniformTypeIdentifiers

/// .soyokabackup カスタム UTType
extension UTType {
    static let soyokaBackup = UTType(exportedAs: "app.soyoka.backup")
}

/// バックアップ/リストア画面
/// 設計書 2026-03-26-backup-restore-design.md UI設計準拠
/// 用語規約: 「メモ」→「きおく」
public struct BackupView: View {
    @Bindable var store: StoreOf<BackupReducer>

    public init(store: StoreOf<BackupReducer>) {
        self.store = store
    }

    public var body: some View {
        List {
            // MARK: - エクスポートセクション
            Section {
                Button {
                    store.send(.exportTapped)
                } label: {
                    HStack {
                        Label("バックアップを作成", systemImage: "square.and.arrow.up")
                            .foregroundColor(.vmTextPrimary)
                        Spacer()
                        if store.isExporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(store.isExporting || store.isImporting)
            } footer: {
                Text("すべてのきおくと音声データを書き出します")
                    .font(.vmCaption1)
            }

            // MARK: - インポートセクション
            Section {
                Button {
                    store.send(.importTapped)
                } label: {
                    HStack {
                        Label("バックアップから復元", systemImage: "square.and.arrow.down")
                            .foregroundColor(.vmTextPrimary)
                        Spacer()
                        if store.isImporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(store.isExporting || store.isImporting)
            } footer: {
                Text(".soyokabackup ファイルを選択してきおくを復元します。既に存在するきおくはスキップされます。")
                    .font(.vmCaption1)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("きおくのバックアップ")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        // ShareSheet
        .sheet(isPresented: Binding(
            get: { store.showShareSheet },
            set: { if !$0 { store.send(.shareSheetDismissed) } }
        )) {
            if let url = store.exportedFileURL {
                ShareSheetView(activityItems: [url])
            }
        }
        // ファイルピッカー
        .fileImporter(
            isPresented: Binding(
                get: { store.showFilePicker },
                set: { if !$0 { store.send(.importFilePickerCancelled) } }
            ),
            allowedContentTypes: [.soyokaBackup, .archive],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first {
                    store.send(.importFileSelected(url))
                }
            case .failure:
                store.send(.importFilePickerCancelled)
            }
        }
        // インポート結果アラート
        .alert(
            "復元完了",
            isPresented: Binding(
                get: { store.showImportResultAlert },
                set: { if !$0 { store.send(.dismissImportResultAlert) } }
            )
        ) {
            Button("OK") {}
        } message: {
            if let result = store.importResult {
                let message = "\(result.importedCount)件のきおくを復元しました"
                let skipMessage = result.skippedCount > 0 ? "（\(result.skippedCount)件はスキップ）" : ""
                let audioMessage = result.audioMissingCount > 0 ? "\n\(result.audioMissingCount)件は音声なしで復元" : ""
                Text(message + skipMessage + audioMessage)
            }
        }
        // エラーアラート
        .alert(
            "エラー",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.send(.dismissError) } }
            )
        ) {
            Button("OK") {}
        } message: {
            if let message = store.errorMessage {
                Text(message)
            }
        }
    }
}

// MARK: - ShareSheetView (UIActivityViewController ラッパー)

#if os(iOS)
struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
struct ShareSheetView: View {
    let activityItems: [Any]
    var body: some View {
        Text("ShareSheet は iOS のみ対応")
    }
}
#endif
```

- [ ] **Step 4: テスト実行**

```bash
cd repository/ios/SoyokaModules && swift test --filter BackupReducerTests
```

期待結果: 7 テスト全パス

- [ ] **Step 5: コミット**

```
feat(settings): BackupReducer + BackupView を実装

- TCA @Reducer パターンでエクスポート/インポートの状態管理
- ShareSheet でバックアップファイルを共有、onDismiss で一時ファイル削除
- fileImporter で .soyokabackup ファイル選択
- onOpenURL 経由の外部インポート (importFromURL) にも対応
- 用語規約準拠: 「きおく」「きおくのバックアップ」を使用
```

---

### Task 7: SettingsReducer + SettingsView + SoyokaApp 統合

**Files:**
- Modify: `repository/ios/SoyokaModules/Sources/FeatureSettings/Settings/SettingsReducer.swift`
- Modify: `repository/ios/SoyokaModules/Sources/FeatureSettings/Settings/SettingsView.swift`
- Modify: `repository/ios/SoyokaApp/SoyokaApp.swift`
- Modify: `repository/ios/SoyokaApp/Info.plist`
- Create: `repository/ios/SoyokaApp/BackupDependencies.swift`

- [ ] **Step 1: SettingsReducer.swift に backup サブステートを追加**

State に追加:
```swift
/// バックアップのサブ State
public var backup = BackupReducer.State()
```

init に追加:
```swift
public init(
    // ...既存パラメータ...,
    backup: BackupReducer.State = .init()
) {
    // ...既存初期化...,
    self.backup = backup
}
```

Action に追加:
```swift
/// バックアップのサブ Action
case backup(BackupReducer.Action)
```

body の Reduce の前に Scope を追加:
```swift
Scope(state: \.backup, action: \.backup) {
    BackupReducer()
}
```

Reduce 内に追加:
```swift
case .backup:
    return .none
```

- [ ] **Step 2: SettingsView.swift にバックアップセクションを追加**

「一般」セクションの後に追加:
```swift
// MARK: - きおくのバックアップセクション
Section {
    NavigationLink {
        BackupView(
            store: store.scope(
                state: \.backup,
                action: \.backup
            )
        )
    } label: {
        Label("きおくのバックアップ", systemImage: "externaldrive.fill")
    }
} header: {
    Text("データ管理")
}
```

- [ ] **Step 3: SoyokaApp.swift に onOpenURL + AppReducer 変更を追加**

AppReducer の Action に追加:
```swift
case openURL(URL)
```

AppReducer の Reduce に追加:
```swift
case let .openURL(url):
    // .soyokabackup ファイルの処理を BackupReducer に委譲
    if url.pathExtension == "soyokabackup" {
        return .send(.settings(.backup(.importFromURL(url))))
    }
    return .none
```

AppView の TabView に `.onOpenURL` を追加:
```swift
.onOpenURL { url in
    store.send(.openURL(url))
}
```

- [ ] **Step 4: Info.plist に UTType 登録を追加**

`CFBundleDocumentTypes` と `UTExportedTypeDeclarations` を追加:
```xml
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>Soyoka Backup</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSHandlerRank</key>
        <string>Owner</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>app.soyoka.backup</string>
        </array>
    </dict>
</array>
<key>UTExportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.data</string>
            <string>public.archive</string>
        </array>
        <key>UTTypeDescription</key>
        <string>Soyoka Backup</string>
        <key>UTTypeIdentifier</key>
        <string>app.soyoka.backup</string>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>soyokabackup</string>
            </array>
        </dict>
    </dict>
</array>
```

- [ ] **Step 5: BackupDependencies.swift を作成（LiveDependencies 接続）**

```swift
import Dependencies
import Domain
import Foundation
import InfraStorage
import SwiftData

// MARK: - Backup Dependencies
// バックアップエクスポート・インポートの Dependency 実装

// MARK: BackupExportClient → BackupExporter Live実装

extension BackupExportClient: DependencyKey {
    public static let liveValue: BackupExportClient = {
        // 注意: StorageDependencies.swift と同じ ModelContainer を使用する必要がある
        // TODO: ModelContainer のシングルトン化（現在は各 Dependency ファイルで別インスタンスを生成している）
        let container: ModelContainer = {
            do {
                return try ModelContainerConfiguration.create(inMemory: false)
            } catch {
                fatalError("SwiftData ModelContainer の初期化に失敗 (Backup): \(error)")
            }
        }()

        let exporter = BackupExporter(modelContainer: container)

        return BackupExportClient(
            export: {
                try await MainActor.run {
                    try exporter.export()
                }
            }
        )
    }()
}

// MARK: BackupImportClient → BackupImporter Live実装

extension BackupImportClient: DependencyKey {
    public static let liveValue: BackupImportClient = {
        let container: ModelContainer = {
            do {
                return try ModelContainerConfiguration.create(inMemory: false)
            } catch {
                fatalError("SwiftData ModelContainer の初期化に失敗 (Backup): \(error)")
            }
        }()

        @Dependency(\.fts5IndexManager) var fts5IndexManager

        let importer = BackupImporter(
            modelContainer: container,
            fts5Upsert: { memoID, title, text, summary, tags in
                try fts5IndexManager.upsertIndex(memoID, title, text, summary, tags)
            }
        )

        return BackupImportClient(
            importBackup: { url in
                try await MainActor.run {
                    try await importer.importBackup(fileURL: url)
                }
            }
        )
    }()
}
```

- [ ] **Step 6: ビルド確認**

```bash
cd repository/ios/SoyokaModules && swift build
```

期待結果: ビルド成功

- [ ] **Step 7: コミット**

```
feat(app): バックアップ機能をSettingsとSoyokaAppに統合

- SettingsReducer に backup サブステートを追加（Scope で委譲）
- SettingsView に「きおくのバックアップ」セクションを追加
- AppReducer に openURL アクション追加（.soyokabackup → BackupReducer に委譲）
- Info.plist に UTExportedTypeDeclarations + CFBundleDocumentTypes を登録
- BackupDependencies.swift で LiveDependencies を接続
```

---

### Task 8: 結合テスト + 全テスト実行 + ビルド確認

**Files:**
- Test: `repository/ios/SoyokaModules/Tests/FeatureSettingsTests/BackupReducerTests.swift` (追加テスト)

- [ ] **Step 1: 全テスト実行**

```bash
cd repository/ios/SoyokaModules && swift test
```

期待結果: 既存テスト + 新規テスト全パス

- [ ] **Step 2: SettingsReducer の既存テストが壊れていないか確認**

```bash
cd repository/ios/SoyokaModules && swift test --filter SettingsReducerTests
```

期待結果: 既存 5 テスト + 新規テスト全パス。`State()` の init にデフォルト値があるため既存テストは変更不要のはず。もし壊れている場合は `backup: .init()` のデフォルト値が正しく適用されていることを確認する。

- [ ] **Step 3: Domain テスト確認**

```bash
cd repository/ios/SoyokaModules && swift test --filter BackupPayloadTests
```

- [ ] **Step 4: InfraStorage テスト確認**

```bash
cd repository/ios/SoyokaModules && swift test --filter BackupExporterTests && swift test --filter BackupImporterTests
```

- [ ] **Step 5: 問題がある場合は修正 → 再テスト → コミット**

---

## ファイル一覧まとめ

### 新規ファイル (11)

| # | パス | モジュール |
|---|------|----------|
| 1 | `repository/ios/SoyokaModules/Sources/Domain/ValueObjects/BackupPayload.swift` | Domain |
| 2 | `repository/ios/SoyokaModules/Sources/Domain/ValueObjects/BackupResult.swift` | Domain |
| 3 | `repository/ios/SoyokaModules/Sources/Domain/Protocols/BackupExportClient.swift` | Domain |
| 4 | `repository/ios/SoyokaModules/Sources/Domain/Protocols/BackupImportClient.swift` | Domain |
| 5 | `repository/ios/SoyokaModules/Sources/InfraStorage/Backup/BackupExporter.swift` | InfraStorage |
| 6 | `repository/ios/SoyokaModules/Sources/InfraStorage/Backup/BackupImporter.swift` | InfraStorage |
| 7 | `repository/ios/SoyokaModules/Sources/FeatureSettings/Backup/BackupReducer.swift` | FeatureSettings |
| 8 | `repository/ios/SoyokaModules/Sources/FeatureSettings/Backup/BackupView.swift` | FeatureSettings |
| 9 | `repository/ios/SoyokaModules/Tests/DomainTests/BackupPayloadTests.swift` | DomainTests |
| 10 | `repository/ios/SoyokaModules/Tests/InfraStorageTests/BackupExporterTests.swift` | InfraStorageTests |
| 11 | `repository/ios/SoyokaModules/Tests/InfraStorageTests/BackupImporterTests.swift` | InfraStorageTests |
| 12 | `repository/ios/SoyokaModules/Tests/FeatureSettingsTests/BackupReducerTests.swift` | FeatureSettingsTests |
| 13 | `repository/ios/SoyokaApp/BackupDependencies.swift` | SoyokaApp |

### 既存変更ファイル (5)

| # | パス | 変更内容 |
|---|------|---------|
| 1 | `repository/ios/SoyokaModules/Package.swift` | ZIPFoundation 依存追加 |
| 2 | `repository/ios/SoyokaModules/Sources/FeatureSettings/Settings/SettingsReducer.swift` | backup サブステート追加 |
| 3 | `repository/ios/SoyokaModules/Sources/FeatureSettings/Settings/SettingsView.swift` | バックアップセクション追加 |
| 4 | `repository/ios/SoyokaApp/SoyokaApp.swift` | onOpenURL + openURL アクション追加 |
| 5 | `repository/ios/SoyokaApp/Info.plist` | UTType .soyokabackup 登録 |

---

### Critical Files for Implementation
- `/Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/ios/SoyokaModules/Sources/Domain/Protocols/VoiceMemoRepositoryClient.swift` - DependencyKey パターンの正確なテンプレート（BackupExportClient / BackupImportClient の構造をこれに合わせる）
- `/Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/ios/SoyokaModules/Sources/InfraStorage/Models/VoiceMemoModel.swift` - SwiftData モデルの全フィールド定義（BackupPayload への変換・復元時に全プロパティを正しくマッピングする必要がある）
- `/Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/ios/SoyokaModules/Sources/FeatureSettings/Settings/SettingsReducer.swift` - backup サブステートの追加先（Scope 委譲パターンは customDictionary と同一）
- `/Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/ios/SoyokaApp/SoyokaApp.swift` - AppReducer への openURL アクション追加 + AppView への onOpenURL 追加先
- `/Users/y.itomura501/dev/mydev/test/VoiceMemo/repository/ios/SoyokaModules/Package.swift` - ZIPFoundation 依存追加（InfraStorage + InfraStorageTests 両方のターゲットに追加が必要）