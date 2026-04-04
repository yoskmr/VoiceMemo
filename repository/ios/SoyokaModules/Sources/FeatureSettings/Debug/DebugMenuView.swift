#if DEBUG
import ComposableArchitecture
import InfraLogging
import SharedUI
import SharedUtil
import SwiftUI

/// 包括的なデバッグメニュー画面
/// Development / Staging 環境のみ表示される
/// 本番ビルドでは `#if DEBUG` により完全に除外
public struct DebugMenuView: View {
    private let debugSettings = DebugSettings.shared

    // MARK: - サブスクリプション

    @AppStorage("debug_forceProPlan")
    private var forceProPlan: Bool = false

    // MARK: - AI処理

    @AppStorage("debug_forceLLMProvider")
    private var forceLLMProvider: String = "auto"

    @AppStorage("debug_forceSentimentAnalysis")
    private var forceSentimentAnalysis: Bool = false

    // MARK: - STTエンジン

    @AppStorage("debug_forceSTTEngine")
    private var forceSTTEngine: String = "auto"

    // MARK: - ネットワーク

    @AppStorage("debug_backendURL")
    private var backendURL: String = "dev"

    @AppStorage("debug_forceOffline")
    private var forceOffline: Bool = false

    // MARK: - アラート

    @State private var showDeleteAllConfirmation = false
    @State private var showClearAIResultsConfirmation = false
    @State private var showTestDataGeneratedAlert = false
    @State private var showResetAllSettingsConfirmation = false
    @State private var showDataDeletedAlert = false

    // MARK: - 既存アクション（SettingsReducer から移譲）

    var onResetQuota: (() -> Void)?
    var aiQuotaUsed: Int = 0
    var aiQuotaLimit: Int = 10

    public init(
        onResetQuota: (() -> Void)? = nil,
        aiQuotaUsed: Int = 0,
        aiQuotaLimit: Int = 10
    ) {
        self.onResetQuota = onResetQuota
        self.aiQuotaUsed = aiQuotaUsed
        self.aiQuotaLimit = aiQuotaLimit
    }

    public var body: some View {
        List {
            subscriptionSection
            aiProcessingSection
            sttEngineSection
            networkSection
            apiLogSection
            dataSection
            uiInfoSection
            dangerZoneSection
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("デバッグメニュー")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("全データを削除", isPresented: $showDeleteAllConfirmation) {
            Button("削除する", role: .destructive) {
                performDeleteAllData()
                showDataDeletedAlert = true
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("全てのきおく・設定を初期化します。この操作は取り消せません。")
        }
        .alert("AI結果をクリア", isPresented: $showClearAIResultsConfirmation) {
            Button("クリアする", role: .destructive) {
                performClearAIResults()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("全きおくのAI要約・タグ・感情分析を削除します。")
        }
        .alert("テストデータ生成完了", isPresented: $showTestDataGeneratedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("10件のサンプルきおくを生成しました。")
        }
        .alert("全データ削除完了", isPresented: $showDataDeletedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("全てのデータを削除しました。アプリを再起動してください。")
        }
        .alert("デバッグ設定リセット", isPresented: $showResetAllSettingsConfirmation) {
            Button("リセットする", role: .destructive) {
                performResetAllDebugSettings()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("全てのデバッグ設定を初期値に戻します。")
        }
    }

    // MARK: - セクション1: サブスクリプション

    private var subscriptionSection: some View {
        Section {
            Toggle(isOn: $forceProPlan) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pro プラン強制 ON")
                    Text("アプリ全体で Pro として動作（クラウド AI、感情分析が利用可能）")
                        .font(.vmCaption1)
                        .foregroundColor(.vmTextTertiary)
                }
            }
            .tint(.vmPrimary)

            HStack {
                Text("現在のプラン状態")
                Spacer()
                Text(currentPlanDisplayText)
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)
            }
        } header: {
            Text("サブスクリプション")
        }
    }

    // MARK: - セクション2: AI処理

    private var aiProcessingSection: some View {
        Section {
            Picker("LLM プロバイダ", selection: $forceLLMProvider) {
                Text("自動（デフォルト）").tag("auto")
                Text("Apple Intelligence").tag("on_device_apple_intelligence")
                Text("llama.cpp").tag("on_device_llama_cpp")
                Text("Cloud (GPT-4o mini)").tag("cloud_gpt4o_mini")
                Text("Mock").tag("mock")
            }

            Toggle(isOn: $forceSentimentAnalysis) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("感情分析 強制 ON")
                    Text("Pro でなくても感情分析を実行")
                        .font(.vmCaption1)
                        .foregroundColor(.vmTextTertiary)
                }
            }
            .tint(.vmPrimary)

            Button(role: .destructive) {
                onResetQuota?()
            } label: {
                HStack {
                    Text("AI処理回数をリセット")
                    Spacer()
                    Text("\(aiQuotaUsed)/\(aiQuotaLimit)")
                        .foregroundColor(.vmTextTertiary)
                }
            }

            Button(role: .destructive) {
                showClearAIResultsConfirmation = true
            } label: {
                Text("AI結果クリア（要約・タグ・感情分析）")
            }
        } header: {
            Text("AI処理")
        }
    }

    // MARK: - セクション3: STTエンジン

    private var sttEngineSection: some View {
        Section {
            Picker("STT エンジン選択", selection: $forceSTTEngine) {
                Text("自動（デフォルト）").tag("auto")
                Text("SpeechAnalyzer (iOS 26+)").tag("speech_analyzer")
                Text("Apple Speech").tag("whisper_kit")
            }

            HStack {
                Text("現在のSTTエンジン")
                Spacer()
                Text(currentSTTEngineDisplayText)
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)
            }
        } header: {
            Text("STTエンジン")
        }
    }

    // MARK: - セクション4: ネットワーク

    private var networkSection: some View {
        Section {
            Picker("Backend URL", selection: $backendURL) {
                Text("dev").tag("dev")
                Text("staging").tag("staging")
                Text("カスタム").tag("custom")
            }

            Toggle(isOn: $forceOffline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("オフラインモード")
                    Text("ネットワークアクセスを強制無効化")
                        .font(.vmCaption1)
                        .foregroundColor(.vmTextTertiary)
                }
            }
            .tint(.vmPrimary)
        } header: {
            Text("ネットワーク")
        }
    }

    // MARK: - セクション: API ログ

    private var apiLogSection: some View {
        Section {
            NavigationLink {
                APILogListView(
                    store: Store(initialState: APILogViewer.State()) {
                        APILogViewer()
                    }
                )
            } label: {
                HStack {
                    Image(systemName: "network")
                    Text("API リクエストログ")
                }
            }
        } header: {
            Text("ログ")
        }
    }

    // MARK: - セクション5: データ

    private var dataSection: some View {
        Section {
            Button {
                UserDefaults.standard.set(false, forKey: "hasCompletedSetup")
                UserDefaults.standard.set(false, forKey: "hasSeenAIOnboarding")
            } label: {
                Text("ウェルカム画面・オンボーディングをリセット")
            }

            Button {
                performGenerateTestData()
                showTestDataGeneratedAlert = true
            } label: {
                HStack {
                    Text("テストデータ生成")
                    Spacer()
                    Text("10件")
                        .font(.vmCaption1)
                        .foregroundColor(.vmTextTertiary)
                }
            }

            Button(role: .destructive) {
                showDeleteAllConfirmation = true
            } label: {
                Text("全データ削除")
            }
        } header: {
            Text("データ")
        }
    }

    // MARK: - セクション6: UI/UX 情報

    private var uiInfoSection: some View {
        Section {
            infoRow(label: "環境", value: environmentDisplayText)
            infoRow(label: "アプリバージョン", value: appVersionText)
            infoRow(label: "ビルド番号", value: buildNumberText)
            infoRow(label: "デバイス", value: deviceModelText)
            infoRow(label: "物理メモリ", value: physicalMemoryText)
            infoRow(label: "Apple Intelligence", value: appleIntelligenceSupportText)
        } header: {
            Text("UI / デバイス情報")
        }
    }

    // MARK: - 危険ゾーン

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showResetAllSettingsConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("全デバッグ設定をリセット")
                }
            }
        } header: {
            Text("リセット")
        }
    }

    // MARK: - ヘルパービュー

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.vmCaption1)
                .foregroundColor(.vmTextTertiary)
        }
    }

    // MARK: - 表示テキスト算出

    private var currentPlanDisplayText: String {
        if forceProPlan {
            return "Pro（デバッグ強制）"
        }
        return "Free"
    }

    private var currentSTTEngineDisplayText: String {
        switch forceSTTEngine {
        case "speech_analyzer":
            return "SpeechAnalyzer"
        case "whisper_kit":
            return "Apple Speech"
        case "auto":
            if #available(iOS 26.0, *) {
                return "SpeechAnalyzer（自動）"
            }
            return "Apple Speech（自動）"
        default:
            return "不明"
        }
    }

    private var environmentDisplayText: String {
        switch AppEnvironment.current {
        case .development: return "Development"
        case .staging: return "Staging"
        case .production: return "Production"
        }
    }

    private var appVersionText: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "不明"
    }

    private var buildNumberText: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "不明"
    }

    private var deviceModelText: String {
        #if os(iOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        return machine
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }

    private var physicalMemoryText: String {
        let bytes = ProcessInfo.processInfo.physicalMemory
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        return String(format: "%.1f GB", gb)
    }

    private var appleIntelligenceSupportText: String {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            return "対応（iOS 26+）"
        }
        return "非対応（iOS 26未満）"
        #else
        return "非対応（macOS）"
        #endif
    }

    // MARK: - アクション

    private func performClearAIResults() {
        // stub: AI結果クリアはリポジトリ経由で実装予定
        // 現時点では UserDefaults のフラグのみ操作
        debugPrint("[Debug] AI結果クリア実行")
    }

    private func performGenerateTestData() {
        // stub: テストデータ生成はリポジトリ経由で実装予定
        debugPrint("[Debug] テストデータ生成実行（10件）")
    }

    private func performDeleteAllData() {
        // UserDefaults の全キーをクリア
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        debugPrint("[Debug] 全データ削除実行")
    }

    private func performResetAllDebugSettings() {
        debugSettings.resetAll()
        // @AppStorage の値もリセットする
        forceProPlan = false
        forceLLMProvider = "auto"
        forceSentimentAnalysis = false
        forceSTTEngine = "auto"
        backendURL = "dev"
        forceOffline = false
    }
}
#endif
