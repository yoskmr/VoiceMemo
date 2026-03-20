import Foundation

/// ダウンロード進捗の状態
public enum ModelDownloadStatus: Sendable, Equatable {
    /// ダウンロード待機中
    case idle
    /// ダウンロード中（progress: 0.0〜1.0）
    case downloading(progress: Double)
    /// ダウンロード完了
    case completed
    /// ダウンロード失敗
    case failed(String)
}

/// オンデバイスLLMモデルのダウンロード・キャッシュ管理
/// Phase 3a ではスタブ実装（実際のダウンロードは後続フェーズ）
///
/// モデル配置先: Library/Caches/Models/（OSによるキャッシュクリア対象）
/// 対象モデル: Phi-3-mini Q4_K_M（約2.5GB）
public final class LLMModelManager: @unchecked Sendable {

    /// モデルファイル名
    static let modelFileName = "phi-3-mini-q4_k_m.gguf"

    /// モデルファイルサイズの説明（ユーザー向け表示用）
    public static let modelFileSizeDescription = "約 2.5GB"

    /// ダウンロード元URL
    static let downloadURL = URL(
        string: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4_k_m.gguf"
    )!

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - ディレクトリ管理

    /// モデル配置ディレクトリ: Library/Caches/Models/
    public var modelsDirectory: URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Models", isDirectory: true)
    }

    /// モデルファイルパス（ダウンロード済みの場合のみ非nil）
    public var modelPath: URL? {
        let path = modelsDirectory.appendingPathComponent(Self.modelFileName)
        return fileManager.fileExists(atPath: path.path) ? path : nil
    }

    /// ダウンロード済みか判定
    public var isModelDownloaded: Bool {
        modelPath != nil
    }

    // MARK: - ダウンロード管理

    /// モデルダウンロード（進捗を AsyncStream で通知）
    ///
    /// Phase 3a ではスタブ実装。実際のダウンロード処理は
    /// llama.cpp 統合時に実装する。
    ///
    /// - Returns: ダウンロード進捗を通知する AsyncStream
    public func downloadModel() -> AsyncStream<ModelDownloadStatus> {
        AsyncStream { continuation in
            continuation.yield(.downloading(progress: 0.0))

            // Phase 3a: スタブ - 即座に失敗を返す
            // 実際のダウンロード処理は llama.cpp 統合時に実装
            continuation.yield(.failed("Phase 3a: モデルダウンロードは未実装です。モック実装を使用してください。"))
            continuation.finish()
        }
    }

    /// モデルダウンロード（コールバック版）
    ///
    /// Phase 3a ではスタブ実装。
    ///
    /// - Parameter progress: ダウンロード進捗（0.0〜1.0）
    /// - Throws: Phase 3a ではスタブのため常にエラー
    public func downloadModel(progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0.0)

        // Phase 3a: モデルのダウンロードディレクトリを事前作成
        try ensureModelsDirectoryExists()

        // Phase 3a: スタブ - 実際のダウンロードは未実装
        throw LLMModelManagerError.downloadNotImplemented
    }

    /// モデルファイルを削除（キャッシュクリア）
    public func deleteModel() throws {
        guard let path = modelPath else { return }
        try fileManager.removeItem(at: path)
    }

    /// モデルファイルサイズ（バイト）
    public var modelFileSize: UInt64? {
        guard let path = modelPath else { return nil }
        let attributes = try? fileManager.attributesOfItem(atPath: path.path)
        return attributes?[.size] as? UInt64
    }

    // MARK: - Internal

    /// モデルディレクトリの存在を保証する
    func ensureModelsDirectoryExists() throws {
        if !fileManager.fileExists(atPath: modelsDirectory.path) {
            try fileManager.createDirectory(
                at: modelsDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }
}

// MARK: - エラー型

/// LLMモデル管理のエラー
public enum LLMModelManagerError: Error, Equatable, Sendable {
    /// ダウンロード未実装（Phase 3a スタブ）
    case downloadNotImplemented
    /// ダウンロードに失敗
    case downloadFailed(String)
    /// ファイル移動に失敗
    case fileMoveFailed(String)
    /// ディスク容量不足
    case insufficientDiskSpace
    /// ダウンロードがキャンセルされた
    case cancelled
}
