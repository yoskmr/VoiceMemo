import XCTest
@testable import Domain

final class STTEngineTypeTests: XCTestCase {

    func test_sttEngineType_has3Cases() {
        let allCases: [STTEngineType] = [.speechAnalyzer, .whisperKit, .cloudSTT]
        XCTAssertEqual(allCases.count, 3)
    }

    func test_sttEngineType_rawValues() {
        XCTAssertEqual(STTEngineType.speechAnalyzer.rawValue, "speech_analyzer")
        XCTAssertEqual(STTEngineType.whisperKit.rawValue, "whisper_kit")
        XCTAssertEqual(STTEngineType.cloudSTT.rawValue, "cloud_stt")
    }

    func test_sttEngineType_initFromRawValue() {
        XCTAssertEqual(STTEngineType(rawValue: "speech_analyzer"), .speechAnalyzer)
        XCTAssertEqual(STTEngineType(rawValue: "whisper_kit"), .whisperKit)
        XCTAssertEqual(STTEngineType(rawValue: "cloud_stt"), .cloudSTT)
    }

    func test_sttEngineType_invalidRawValue() {
        XCTAssertNil(STTEngineType(rawValue: "appleSpeech"))
        XCTAssertNil(STTEngineType(rawValue: "whisperCpp"))
        XCTAssertNil(STTEngineType(rawValue: "appleSpeechAnalyzer"))
    }

    func test_sttEngineType_codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for sttType in [STTEngineType.speechAnalyzer, .whisperKit, .cloudSTT] {
            let data = try encoder.encode(sttType)
            let decoded = try decoder.decode(STTEngineType.self, from: data)
            XCTAssertEqual(decoded, sttType)
        }
    }
}
