import XCTest
@testable import Domain

final class EmotionAnalysisEntityTests: XCTestCase {

    func test_emotionAnalysisEntity_creation_withDefaults() {
        let analysis = EmotionAnalysisEntity()

        XCTAssertEqual(analysis.primaryEmotion, .neutral)
        XCTAssertEqual(analysis.confidence, 0.0)
        XCTAssertTrue(analysis.emotionScores.isEmpty)
        XCTAssertTrue(analysis.evidence.isEmpty)
    }

    func test_emotionAnalysisEntity_withScores() {
        let scores: [EmotionCategory: Double] = [
            .joy: 0.6,
            .calm: 0.2,
            .neutral: 0.1,
            .anticipation: 0.1,
        ]

        let analysis = EmotionAnalysisEntity(
            primaryEmotion: .joy,
            confidence: 0.85,
            emotionScores: scores
        )

        XCTAssertEqual(analysis.primaryEmotion, .joy)
        XCTAssertEqual(analysis.confidence, 0.85)
        XCTAssertEqual(analysis.emotionScores[.joy], 0.6)
        XCTAssertEqual(analysis.emotionScores[.calm], 0.2)
    }

    func test_emotionAnalysisEntity_withEvidence() {
        let evidence = [
            SentimentEvidence(text: "楽しかった", emotion: .joy),
            SentimentEvidence(text: "心配している", emotion: .anxiety),
        ]

        let analysis = EmotionAnalysisEntity(
            primaryEmotion: .joy,
            evidence: evidence
        )

        XCTAssertEqual(analysis.evidence.count, 2)
        XCTAssertEqual(analysis.evidence[0].text, "楽しかった")
        XCTAssertEqual(analysis.evidence[0].emotion, .joy)
        XCTAssertEqual(analysis.evidence[1].emotion, .anxiety)
    }

    func test_sentimentEvidence_codable() throws {
        let evidence = SentimentEvidence(text: "テスト", emotion: .joy)
        let data = try JSONEncoder().encode(evidence)
        let decoded = try JSONDecoder().decode(SentimentEvidence.self, from: data)
        XCTAssertEqual(decoded, evidence)
    }
}
