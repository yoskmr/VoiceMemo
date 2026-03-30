import Dependencies

/// 匿名アプリ利用分析クライアント
/// TelemetryDeck への依存は SoyokaApp ターゲットの LiveValue に隔離する
public struct AnalyticsClient: Sendable {
    /// イベント名のみ送信
    public var send: @Sendable (_ event: String) -> Void
    /// イベント名 + パラメータ送信
    public var sendWithParameters: @Sendable (_ event: String, _ parameters: [String: String]) -> Void

    public init(
        send: @escaping @Sendable (_ event: String) -> Void,
        sendWithParameters: @escaping @Sendable (_ event: String, _ parameters: [String: String]) -> Void
    ) {
        self.send = send
        self.sendWithParameters = sendWithParameters
    }
}

// MARK: - DependencyKey

extension AnalyticsClient: DependencyKey {
    /// デフォルトはイベントを無視する（SoyokaApp で上書きされる）
    public static let liveValue = AnalyticsClient(
        send: { _ in },
        sendWithParameters: { _, _ in }
    )

    public static let testValue = AnalyticsClient(
        send: { _ in },
        sendWithParameters: { _, _ in }
    )
}

extension DependencyValues {
    public var analyticsClient: AnalyticsClient {
        get { self[AnalyticsClient.self] }
        set { self[AnalyticsClient.self] = newValue }
    }
}
