#if DEBUG
import ComposableArchitecture
import InfraLogging
import SharedUI
import SwiftUI

public struct APILogListView: View {
    @Bindable var store: StoreOf<APILogViewer>

    public init(store: StoreOf<APILogViewer>) {
        self.store = store
    }

    public var body: some View {
        List {
            filterSection
            logsSection
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("API ログ")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    store.send(.exportTapped)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    store.send(.clearTapped)
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .overlay {
            if store.filteredLogs.isEmpty {
                ContentUnavailableView(
                    "ログなし",
                    systemImage: "network.slash",
                    description: Text("API リクエストのログがまだありません")
                )
            }
        }
        .alert("ログをクリア", isPresented: $store.showClearConfirmation.sending(\.clearDismissed)) {
            Button("クリア", role: .destructive) {
                store.send(.clearConfirmed)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("全ての API ログを削除しますか？")
        }
        .onAppear {
            store.send(.onAppear)
        }
        .refreshable {
            store.send(.refreshRequested)
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    private var filterSection: some View {
        Section {
            Picker("フィルタ", selection: $store.filter.sending(\.filterChanged)) {
                Text("ALL").tag(LogSource?.none)
                Text("Network").tag(LogSource?.some(.network))
                Text("LLM").tag(LogSource?.some(.llm))
            }
            .pickerStyle(.segmented)
        }
    }

    private var logsSection: some View {
        Section {
            ForEach(store.filteredLogs) { log in
                NavigationLink {
                    APILogDetailView(log: log) {
                        store.send(.copyTapped(log))
                    }
                } label: {
                    APILogRowView(log: log)
                }
            }
        } header: {
            if !store.filteredLogs.isEmpty {
                Text("\(store.filteredLogs.count) 件")
            }
        }
    }
}

private struct APILogRowView: View {
    let log: APIRequestLog

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            VStack(alignment: .leading, spacing: 4) {
                endpointText
                detailText
            }
        }
        .padding(.vertical, 2)
    }

    private var statusIcon: some View {
        Group {
            if log.status.isSuccess {
                Image(systemName: "circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .font(.system(size: 10))
    }

    private var endpointText: some View {
        HStack(spacing: 4) {
            if let method = log.method {
                Text(method)
                    .font(.vmCaption1)
                    .fontWeight(.semibold)
                    .foregroundColor(.vmTextSecondary)
            }
            Text(log.endpoint)
                .font(.vmCaption1)
                .foregroundColor(.vmTextPrimary)
                .lineLimit(1)
        }
    }

    private var detailText: some View {
        HStack(spacing: 8) {
            Text(log.status.displayText)
                .foregroundColor(log.status.isSuccess ? .vmTextTertiary : .red)
            Text("·")
                .foregroundColor(.vmTextTertiary)
            Text(String(format: "%.2fs", log.duration))
                .foregroundColor(.vmTextTertiary)
            Text("·")
                .foregroundColor(.vmTextTertiary)
            Text(formattedTime)
                .foregroundColor(.vmTextTertiary)
        }
        .font(.system(.caption2))
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: log.timestamp)
    }
}
#endif
