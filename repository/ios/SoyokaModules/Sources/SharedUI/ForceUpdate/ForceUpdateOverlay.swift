import SwiftUI

/// 強制アップデート時にアプリ全体をブロックするフルスクリーンオーバーレイ
public struct ForceUpdateOverlay: View {
    private let storeURL: URL
    @Environment(\.openURL) private var openURL

    public init(storeURL: URL) {
        self.storeURL = storeURL
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("アップデートが必要です")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("最新バージョンにアップデートしてください。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                openURL(storeURL)
            } label: {
                Text("ストアを開く")
                    .font(.headline)
                    .frame(maxWidth: 240)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .interactiveDismissDisabled()
    }
}
