import Foundation
import Testing
@testable import Domain

@Suite("FillerRemovalLevel テスト")
struct FillerRemovalLevelTests {

    @Test("全3ケースが存在する")
    func test_fillerRemovalLevel_has3Cases() {
        #expect(FillerRemovalLevel.allCases.count == 3)
    }

    @Test("全ケースのrawValueが正しい")
    func test_fillerRemovalLevel_rawValues() {
        #expect(FillerRemovalLevel.none.rawValue == "none")
        #expect(FillerRemovalLevel.light.rawValue == "light")
        #expect(FillerRemovalLevel.aggressive.rawValue == "aggressive")
    }

    @Test("Codable ラウンドトリップで同一データを復元できる")
    func test_fillerRemovalLevel_codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for level in FillerRemovalLevel.allCases {
            let data = try encoder.encode(level)
            let decoded = try decoder.decode(FillerRemovalLevel.self, from: data)
            #expect(decoded == level)
        }
    }

    @Test("無効なrawValueからの初期化はnilを返す")
    func test_fillerRemovalLevel_invalidRawValue() {
        #expect(FillerRemovalLevel(rawValue: "invalid") == nil)
    }

    @Test("JSONデコード: 文字列から正しくデコードできる")
    func test_fillerRemovalLevel_decodeFromString() throws {
        let json = "\"light\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FillerRemovalLevel.self, from: data)
        #expect(decoded == .light)
    }
}
