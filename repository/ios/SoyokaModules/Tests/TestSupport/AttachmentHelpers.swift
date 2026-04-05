import Foundation
import Testing

/// テスト失敗時の診断用に Encodable な値を JSON 添付する
public func attachJSON<T: Encodable>(
    _ value: T,
    named name: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(value),
          let json = String(data: data, encoding: .utf8) else { return }
    Attachment.record(json, named: "\(name).json", sourceLocation: sourceLocation)
}

/// テスト失敗時の診断用にテキスト比較結果を添付する
public func attachTextComparison(
    input: String,
    expected: String,
    actual: String,
    named name: String = "text-comparison",
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let report = """
    === Input ===
    \(input)
    === Expected ===
    \(expected)
    === Actual ===
    \(actual)
    """
    Attachment.record(report, named: "\(name).txt", sourceLocation: sourceLocation)
}

/// テスト失敗時の診断用にファイルシステムの状態を添付する
public func attachFileSystemState(
    directory: URL,
    named name: String = "filesystem-state",
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.fileSizeKey]
    ) else { return }

    let lines = contents.map { url -> String in
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return "\(url.lastPathComponent) (\(size) bytes)"
    }.sorted()
    Attachment.record(lines.joined(separator: "\n"), named: "\(name).txt", sourceLocation: sourceLocation)
}
