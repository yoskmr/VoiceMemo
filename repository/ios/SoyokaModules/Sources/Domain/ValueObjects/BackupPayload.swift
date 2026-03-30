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
    public let customDictionary: [BackupDictionaryEntry]

    public init(
        version: Int = 1,
        exportedAt: Date = Date(),
        sourceApp: String = "Soyoka",
        sourceBundleId: String = "app.soyoka",
        memos: [BackupMemo],
        tags: [BackupTag],
        customDictionary: [BackupDictionaryEntry] = []
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.sourceApp = sourceApp
        self.sourceBundleId = sourceBundleId
        self.memos = memos
        self.tags = tags
        self.customDictionary = customDictionary
    }

    /// v1 バックアップとの後方互換: customDictionary が存在しない場合は空配列
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        sourceApp = try container.decode(String.self, forKey: .sourceApp)
        sourceBundleId = try container.decode(String.self, forKey: .sourceBundleId)
        memos = try container.decode([BackupMemo].self, forKey: .memos)
        tags = try container.decode([BackupTag].self, forKey: .tags)
        customDictionary = try container.decodeIfPresent([BackupDictionaryEntry].self, forKey: .customDictionary) ?? []
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

// MARK: - BackupDictionaryEntry

/// カスタム辞書エントリのバックアップ表現
/// v1 バックアップとの後方互換のため、BackupPayload では decodeIfPresent で扱う
public struct BackupDictionaryEntry: Codable, Sendable, Equatable {
    public let id: UUID
    /// 読み（音声認識結果 - ひらがな/カタカナ）
    public let reading: String
    /// 表示（正しい表記 - 漢字/英語等）
    public let display: String

    public init(id: UUID, reading: String, display: String) {
        self.id = id
        self.reading = reading
        self.display = display
    }
}
