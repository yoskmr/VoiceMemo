import Foundation

/// Error を Equatable 準拠させるためのラッパー
///
/// TCA の Action は Equatable が必要なため、
/// Result<T, EquatableError> として利用する。
public struct EquatableError: Error, Equatable, Sendable {
    public let localizedDescription: String

    public init(_ error: Error) {
        self.localizedDescription = error.localizedDescription
    }

    public init(_ message: String) {
        self.localizedDescription = message
    }

    public static func == (lhs: EquatableError, rhs: EquatableError) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}
