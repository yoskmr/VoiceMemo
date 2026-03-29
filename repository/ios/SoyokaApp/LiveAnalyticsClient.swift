import Dependencies
import SharedUtil
import TelemetryDeck

extension AnalyticsClient {
    /// TelemetryDeck を使った本番用 AnalyticsClient
    static func live() -> Self {
        AnalyticsClient(
            send: { event in
                TelemetryDeck.signal(event)
            },
            sendWithParameters: { event, parameters in
                TelemetryDeck.signal(event, parameters: parameters)
            }
        )
    }
}
