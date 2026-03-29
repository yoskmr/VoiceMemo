import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI

/// サブスクリプション購入画面
/// Soyokaのデザイントークン・トーンに準拠
public struct SubscriptionView: View {
    @Bindable var store: StoreOf<SubscriptionReducer>

    public init(store: StoreOf<SubscriptionReducer>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: VMDesignTokens.Spacing.xl) {
                headerSection
                featureComparisonSection
                planSelectionSection
                restoreSection
            }
            .padding(.horizontal, VMDesignTokens.Spacing.lg)
            .padding(.vertical, VMDesignTokens.Spacing.xxl)
        }
        .background(Color.vmBackground)
        .overlay {
            if store.isLoading || store.isPurchasing {
                loadingOverlay
            }
        }
        .overlay {
            if store.showSuccessMessage {
                successOverlay
            }
        }
        .alert(
            "エラー",
            isPresented: .init(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.send(.dismissError) } }
            )
        ) {
            Button("OK") { store.send(.dismissError) }
        } message: {
            if let message = store.errorMessage {
                Text(message)
            }
        }
        .onAppear { store.send(.onAppear) }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: VMDesignTokens.Spacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.vmPrimary)
                .accessibilityHidden(true)

            Text("もっと自由に、整えよう。")
                .font(.vmTitle2)
                .foregroundColor(.vmTextPrimary)
                .multilineTextAlignment(.center)

            Text("Proプランで、すべての機能を制限なくお使いいただけます")
                .font(.vmCallout)
                .foregroundColor(.vmTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(VMDesignTokens.LineSpacing.caption)
        }
        .padding(.bottom, VMDesignTokens.Spacing.sm)
    }

    // MARK: - Feature Comparison

    private var featureComparisonSection: some View {
        VStack(spacing: 0) {
            // ヘッダー行
            HStack {
                Text("機能")
                    .font(.vmHeadline)
                    .foregroundColor(.vmTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Free")
                    .font(.vmHeadline)
                    .foregroundColor(.vmTextSecondary)
                    .frame(width: 60)
                Text("Pro")
                    .font(.vmHeadline)
                    .foregroundColor(.vmPrimary)
                    .frame(width: 60)
            }
            .padding(.horizontal, VMDesignTokens.Spacing.lg)
            .padding(.vertical, VMDesignTokens.Spacing.md)
            .background(Color.vmSurfaceVariant)

            Divider().foregroundColor(.vmDivider)

            // Free でも使える機能
            comparisonRow("つぶやきの録音", free: true, pro: true)
            comparisonRow("文字起こし", free: true, pro: true)
            comparisonRow("全文検索", free: true, pro: true)
            comparisonRow("AI整理（ローカル）", free: true, pro: true)
            comparisonRow("バックアップ", free: true, pro: true)

            // Free/Pro 境界の区切り線
            Divider()
                .frame(height: 1)
                .background(Color.vmDivider)
                .padding(.horizontal, VMDesignTokens.Spacing.lg)

            // Pro で広がる機能
            comparisonRow("AI整理（クラウド高精度）", free: false, pro: true)
            comparisonRow("感情分析", free: false, pro: true)
            comparisonRow("文体（ふりかえり・エッセイ）", free: false, pro: true)
            comparisonRow("週次レポート", free: false, pro: true)
        }
        .background(Color.vmSurface)
        .cornerRadius(VMDesignTokens.CornerRadius.medium)
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    // MARK: - Plan Selection

    private var planSelectionSection: some View {
        VStack(spacing: VMDesignTokens.Spacing.md) {
            if store.products.isEmpty && !store.isLoading {
                VStack(spacing: VMDesignTokens.Spacing.sm) {
                    Text("まもなく登場")
                        .font(.vmHeadline)
                        .foregroundColor(.vmTextSecondary)
                    Text("Proプランは準備中です。\nもう少しお待ちください。")
                        .font(.vmCallout)
                        .foregroundColor(.vmTextTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, VMDesignTokens.Spacing.xl)
            } else {
                ForEach(sortedProducts) { product in
                    planButton(for: product)
                }
            }
        }
    }

    private var sortedProducts: [SubscriptionProduct] {
        store.products.sorted { lhs, _ in lhs.period == .yearly }
    }

    private func planButton(for product: SubscriptionProduct) -> some View {
        Button {
            store.send(.purchaseTapped(productID: product.id))
        } label: {
            VStack(spacing: VMDesignTokens.Spacing.xs) {
                HStack {
                    VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.xxs) {
                        HStack(spacing: VMDesignTokens.Spacing.sm) {
                            Text(product.displayName)
                                .font(.vmHeadline)
                                .foregroundColor(.white)

                            if product.period == .yearly {
                                Text("2ヶ月分お得")
                                    .font(.vmCaption2)
                                    .foregroundColor(.vmPrimary)
                                    .padding(.horizontal, VMDesignTokens.Spacing.sm)
                                    .padding(.vertical, VMDesignTokens.Spacing.xxs)
                                    .background(Color.white)
                                    .cornerRadius(VMDesignTokens.CornerRadius.small)
                            }
                        }

                        Text(periodLabel(for: product))
                            .font(.vmCaption1)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Spacer()

                    Text(product.displayPrice)
                        .font(.vmTitle3)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, VMDesignTokens.Spacing.lg)
                .padding(.vertical, VMDesignTokens.Spacing.lg)
            }
            .background(
                product.period == .yearly
                    ? Color.vmPrimaryDark
                    : Color.vmSecondaryDark
            )
            .cornerRadius(VMDesignTokens.CornerRadius.medium)
        }
        .disabled(store.isPurchasing)
        .accessibilityLabel("\(product.displayName) \(product.displayPrice)")
    }

    // MARK: - Restore

    @ViewBuilder
    private var restoreSection: some View {
        if !store.products.isEmpty {
            Button {
                store.send(.restoreTapped)
            } label: {
                Text("以前の購入を復元")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)
            }
            .disabled(store.isLoading)
            .padding(.top, VMDesignTokens.Spacing.lg)
        }
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: VMDesignTokens.Spacing.md) {
                ProgressView()
                    .tint(.vmPrimary)
                    .scaleEffect(1.2)

                Text(store.isPurchasing ? "購入処理中..." : "読み込み中...")
                    .font(.vmCallout)
                    .foregroundColor(.vmTextPrimary)
            }
            .padding(VMDesignTokens.Spacing.xxl)
            .background(Color.vmSurface)
            .cornerRadius(VMDesignTokens.CornerRadius.medium)
        }
    }

    // MARK: - Success Overlay

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { store.send(.dismissSuccess) }

            VStack(spacing: VMDesignTokens.Spacing.lg) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.vmSuccess)
                    .accessibilityHidden(true)

                Text("Proプランが有効になりました")
                    .font(.vmTitle3)
                    .foregroundColor(.vmTextPrimary)
                    .multilineTextAlignment(.center)

                Text("すべての機能をお楽しみください")
                    .font(.vmCallout)
                    .foregroundColor(.vmTextSecondary)

                Button {
                    store.send(.dismissSuccess)
                } label: {
                    Text("OK")
                        .font(.vmHeadline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, VMDesignTokens.Spacing.md)
                }
                .background(Color.vmPrimaryDark)
                .cornerRadius(VMDesignTokens.CornerRadius.medium)
            }
            .padding(VMDesignTokens.Spacing.xxl)
            .background(Color.vmSurface)
            .cornerRadius(VMDesignTokens.CornerRadius.large)
            .padding(.horizontal, VMDesignTokens.Spacing.xxl)
        }
    }

    // MARK: - Helpers

    private func comparisonRow(_ feature: String, free: Bool, pro: Bool) -> some View {
        comparisonRowContent(feature, freeText: free ? "checkmark" : "xmark", proText: pro ? "checkmark" : "xmark", isFreeCheck: free, isProCheck: pro)
    }

    private func comparisonRow(_ feature: String, free: String, pro: String) -> some View {
        HStack {
            Text(feature)
                .font(.vmCallout)
                .foregroundColor(.vmTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(free)
                .font(.vmCaption1)
                .foregroundColor(.vmTextSecondary)
                .frame(width: 60)
            Text(pro)
                .font(.vmCaption1)
                .foregroundColor(.vmPrimary)
                .frame(width: 60)
        }
        .padding(.horizontal, VMDesignTokens.Spacing.lg)
        .padding(.vertical, VMDesignTokens.Spacing.md)
        .background(Color.vmSurface)
    }

    private func comparisonRowContent(
        _ feature: String,
        freeText: String,
        proText: String,
        isFreeCheck: Bool,
        isProCheck: Bool
    ) -> some View {
        HStack {
            Text(feature)
                .font(.vmCallout)
                .foregroundColor(.vmTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: isFreeCheck ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(isFreeCheck ? .vmSuccess : .vmTextTertiary)
                .frame(width: 60)
                .accessibilityLabel(isFreeCheck ? "対応" : "非対応")
            Image(systemName: isProCheck ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(isProCheck ? .vmPrimary : .vmTextTertiary)
                .frame(width: 60)
                .accessibilityLabel(isProCheck ? "対応" : "非対応")
        }
        .padding(.horizontal, VMDesignTokens.Spacing.lg)
        .padding(.vertical, VMDesignTokens.Spacing.md)
        .background(Color.vmSurface)
    }

    private func periodLabel(for product: SubscriptionProduct) -> String {
        switch product.period {
        case .monthly:
            return "月額プラン"
        case .yearly:
            return "年額プラン"
        }
    }
}
