import Dependencies
import SharedUtil
import TelemetryDeck
import os.log

private let logger = Logger(subsystem: "app.soyoka", category: "Analytics")

extension AnalyticsClient {
    /// TelemetryDeck を使った本番用 AnalyticsClient
    static func live() -> Self {
        AnalyticsClient(
            send: { event in
                logger.debug("📊 signal: \(event)")
                TelemetryDeck.signal(event)
            },
            sendWithParameters: { event, parameters in
                logger.debug("📊 signal: \(event) params: \(parameters)")
                TelemetryDeck.signal(event, parameters: parameters)
            }
        )
    }
}
