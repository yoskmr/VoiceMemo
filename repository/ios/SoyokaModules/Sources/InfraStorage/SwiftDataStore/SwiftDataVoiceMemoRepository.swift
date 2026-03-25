import Foundation
import SwiftData
import Domain

/// SwiftData を使用した VoiceMemoRepositoryProtocol の実装
/// Feature → Infra 直接依存禁止のため、Domain層プロトコルを介してアクセスする
///
/// - Note: iOS 17 では ModelContext が MainActor 隔離必須。
///   TODO: iOS 18+ で ModelContext のバックグラウンド対応が安定したら MainActor.run を軽減する
public final class SwiftDataVoiceMemoRepository: VoiceMemoRepositoryProtocol, @unchecked Sendable {

    private let modelContainer: ModelContainer

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    @MainActor
    private var context: ModelContext {
        modelContainer.mainContext
    }

    public func save(_ memo: VoiceMemoEntity) async throws {
        // VoiceMemoEntity は値型（Sendable）のためキャプチャ安全
        // MainActor.run の外で ID を事前抽出し、Predicate に渡す
        let memoID = memo.id

        try await MainActor.run {
            let descriptor = FetchDescriptor<VoiceMemoModel>(
                predicate: #Predicate { $0.id == memoID }
            )
            let existing = try context.fetch(descriptor)

            if let model = existing.first {
                model.update(from: memo)
            } else {
                let model = VoiceMemoModel(
                    id: memo.id,
                    title: memo.title,
                    createdAt: memo.createdAt,
                    durationSeconds: memo.durationSeconds,
                    audioFilePath: memo.audioFilePath,
                    audioFormat: memo.audioFormat,
                    status: memo.status,
                    isFavorite: memo.isFavorite
                )
                model.updatedAt = memo.updatedAt
                context.insert(model)

                // Transcription の保存
                if let transcription = memo.transcription {
                    let transcriptionModel = TranscriptionModel(
                        id: transcription.id,
                        fullText: transcription.fullText,
                        language: transcription.language,
                        engineType: transcription.engineType,
                        confidence: transcription.confidence,
                        processedAt: transcription.processedAt
                    )
                    transcriptionModel.memo = model
                    context.insert(transcriptionModel)
                }

                // AISummary の保存
                if let summary = memo.aiSummary {
                    let summaryModel = AISummaryModel(
                        id: summary.id,
                        title: summary.title,
                        summaryText: summary.summaryText,
                        keyPoints: summary.keyPoints,
                        providerType: summary.providerType,
                        isOnDevice: summary.isOnDevice,
                        generatedAt: summary.generatedAt
                    )
                    summaryModel.memo = model
                    context.insert(summaryModel)
                }

                // EmotionAnalysis の保存
                if let emotion = memo.emotionAnalysis {
                    var scoresDict: [String: Double] = [:]
                    for (category, score) in emotion.emotionScores {
                        scoresDict[category.rawValue] = score
                    }
                    let evidenceArray: [[String: String]] = emotion.evidence.map {
                        ["text": $0.text, "emotion": $0.emotion.rawValue]
                    }
                    let emotionModel = EmotionAnalysisModel(
                        id: emotion.id,
                        primaryEmotion: emotion.primaryEmotion,
                        confidence: emotion.confidence,
                        emotionScores: scoresDict,
                        evidence: evidenceArray,
                        analyzedAt: emotion.analyzedAt
                    )
                    emotionModel.memo = model
                    context.insert(emotionModel)
                }

                // Tags の保存
                for tag in memo.tags {
                    let tagID = tag.id
                    let tagDescriptor = FetchDescriptor<TagModel>(
                        predicate: #Predicate { $0.id == tagID }
                    )
                    let existingTag = try context.fetch(tagDescriptor).first
                    if let existingTag = existingTag {
                        model.tags.append(existingTag)
                    } else {
                        let tagModel = TagModel(
                            id: tag.id,
                            name: tag.name,
                            colorHex: tag.colorHex,
                            source: tag.source,
                            createdAt: tag.createdAt
                        )
                        context.insert(tagModel)
                        model.tags.append(tagModel)
                    }
                }
            }

            try context.save()
        }
    }

    public func fetchByID(_ id: UUID) async throws -> VoiceMemoEntity? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<VoiceMemoModel>(
                predicate: #Predicate { $0.id == id }
            )
            return try context.fetch(descriptor).first?.toEntity()
        }
    }

    public func fetchAll() async throws -> [VoiceMemoEntity] {
        try await fetchAll(limit: nil)
    }

    /// fetchLimit 付き全件取得（ページネーション用途）
    public func fetchAll(limit: Int?) async throws -> [VoiceMemoEntity] {
        try await MainActor.run {
            var descriptor = FetchDescriptor<VoiceMemoModel>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = limit
            return try context.fetch(descriptor).map { $0.toEntity() }
        }
    }

    public func delete(_ id: UUID) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<VoiceMemoModel>(
                predicate: #Predicate { $0.id == id }
            )
            guard let model = try context.fetch(descriptor).first else { return }
            context.delete(model)
            try context.save()
        }
    }

    public func fetchFavorites() async throws -> [VoiceMemoEntity] {
        try await MainActor.run {
            let descriptor = FetchDescriptor<VoiceMemoModel>(
                predicate: #Predicate { $0.isFavorite == true },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            return try context.fetch(descriptor).map { $0.toEntity() }
        }
    }

    public func fetchByTag(_ tagName: String) async throws -> [VoiceMemoEntity] {
        try await MainActor.run {
            let descriptor = FetchDescriptor<TagModel>(
                predicate: #Predicate { $0.name == tagName }
            )
            guard let tag = try context.fetch(descriptor).first else { return [] }
            return tag.memos.map { $0.toEntity() }
        }
    }

    public func fetchByStatus(_ status: MemoStatus) async throws -> [VoiceMemoEntity] {
        try await MainActor.run {
            let statusValue = status.rawValue
            let descriptor = FetchDescriptor<VoiceMemoModel>(
                predicate: #Predicate { $0.statusRawValue == statusValue },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            return try context.fetch(descriptor).map { $0.toEntity() }
        }
    }

    public func count() async throws -> Int {
        try await MainActor.run {
            let descriptor = FetchDescriptor<VoiceMemoModel>()
            return try context.fetchCount(descriptor)
        }
    }
}
