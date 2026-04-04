#if DEBUG
import InfraLogging
import SharedUI
import SwiftUI

struct APILogDetailView: View {
    let log: APIRequestLog
    let onCopy: () -> Void

    var body: some View {
        List {
            overviewSection
            requestHeadersSection
            requestBodySection
            responseHeadersSection
            responseBodySection
            copySection
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle(navigationTitleText)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var overviewSection: some View {
        Section {
            row(label: "ステータス", value: log.status.displayText, isError: !log.status.isSuccess)
            row(label: "所要時間", value: String(format: "%.2fs", log.duration))
            row(label: "時刻", value: formattedTimestamp)
            row(label: "ソース", value: log.source.rawValue.capitalized)
            if let method = log.method {
                row(label: "メソッド", value: method)
            }
        } header: {
            Text("概要")
        }
    }

    @ViewBuilder
    private var requestHeadersSection: some View {
        if let headers = log.request.headers, !headers.isEmpty {
            Section {
                DisclosureGroup("リクエストヘッダー") {
                    ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        row(label: key, value: value)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var requestBodySection: some View {
        if let body = log.request.body, !body.isEmpty {
            Section {
                DisclosureGroup("リクエストボディ") {
                    Text(prettyPrintJSON(body))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.vmTextSecondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private var responseHeadersSection: some View {
        if let headers = log.response?.headers, !headers.isEmpty {
            Section {
                DisclosureGroup("レスポンスヘッダー") {
                    ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        row(label: key, value: value)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var responseBodySection: some View {
        if let body = log.response?.body, !body.isEmpty {
            Section {
                DisclosureGroup("レスポンスボディ") {
                    Text(prettyPrintJSON(body))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.vmTextSecondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var copySection: some View {
        Section {
            Button {
                onCopy()
            } label: {
                HStack {
                    Spacer()
                    Label("この項目をコピー", systemImage: "doc.on.doc")
                    Spacer()
                }
            }
        }
    }

    private func row(label: String, value: String, isError: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.vmCaption1)
                .foregroundColor(isError ? .red : .vmTextTertiary)
        }
    }

    private var navigationTitleText: String {
        if let method = log.method {
            return "\(method) \(log.endpoint)"
        }
        return log.endpoint
    }

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: log.timestamp)
    }

    private func prettyPrintJSON(_ string: String) -> String {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let prettyString = String(data: prettyData, encoding: .utf8)
        else {
            return string
        }
        return prettyString
    }
}
#endif
