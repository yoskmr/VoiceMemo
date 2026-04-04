import Foundation

public enum LogSanitizer {

    private static let sensitiveHeaders: Set<String> = [
        "authorization",
        "cookie",
        "set-cookie",
        "x-api-key",
        "x-app-attest-assertion",
    ]

    private static let sensitiveFields: Set<String> = [
        "token",
        "access_token",
        "refresh_token",
        "password",
        "secret",
        "api_key",
    ]

    private static let maxBodyBytes = 16_384

    public static func sanitizeHeaders(_ headers: [String: String]?) -> [String: String]? {
        guard let headers else { return nil }
        var result = headers
        for (key, _) in result {
            if sensitiveHeaders.contains(key.lowercased()) {
                result[key] = "***"
            }
        }
        return result
    }

    public static func sanitizeBody(_ body: String?) -> String? {
        guard var body else { return nil }

        if body.trimmingCharacters(in: .whitespaces).hasPrefix("{") ||
           body.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
            body = maskSensitiveJSONFields(body)
        }

        if body.utf8.count > maxBodyBytes {
            let index = body.utf8.index(body.utf8.startIndex, offsetBy: maxBodyBytes)
            body = String(body[..<index]) + "...(truncated)"
        }

        return body
    }

    private static func maskSensitiveJSONFields(_ json: String) -> String {
        var result = json
        for field in sensitiveFields {
            let pattern = "(\"\(field)\"\\s*:\\s*)\"[^\"]*\""
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: "$1\"***\""
                )
            }
        }
        return result
    }
}
