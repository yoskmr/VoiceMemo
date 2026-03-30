import Dependencies
import Foundation

/// 音声再生の TCA Dependency ラッパー
/// TASK-0014: 音声再生 + ハイライト同期
/// @Dependency(\.audioPlayerClient) でReducerから注入可能にする
public struct AudioPlayerClient: Sendable {
    /// 音声ファイルの読み込み（duration を返す）
    public var loadAudio: @Sendable (_ path: String) async throws -> TimeInterval
    /// 指定時間からの再生開始
    public var play: @Sendable (_ from: TimeInterval) async throws -> Void
    /// 一時停止
    public var pause: @Sendable () async -> Void
    /// 停止（先頭に戻す）
    public var stop: @Sendable () async -> Void
    /// 指定時間へシーク
    public var seek: @Sendable (_ to: TimeInterval) async throws -> Void
    /// 現在の再生位置を取得
    public var currentTime: @Sendable () async -> TimeInterval

    public init(
        loadAudio: @escaping @Sendable (_ path: String) async throws -> TimeInterval,
        play: @escaping @Sendable (_ from: TimeInterval) async throws -> Void,
        pause: @escaping @Sendable () async -> Void,
        stop: @escaping @Sendable () async -> Void,
        seek: @escaping @Sendable (_ to: TimeInterval) async throws -> Void,
        currentTime: @escaping @Sendable () async -> TimeInterval
    ) {
        self.loadAudio = loadAudio
        self.play = play
        self.pause = pause
        self.stop = stop
        self.seek = seek
        self.currentTime = currentTime
    }
}

// MARK: - DependencyKey

extension AudioPlayerClient: TestDependencyKey {
    public static let testValue = AudioPlayerClient(
        loadAudio: unimplemented("AudioPlayerClient.loadAudio"),
        play: unimplemented("AudioPlayerClient.play"),
        pause: unimplemented("AudioPlayerClient.pause"),
        stop: unimplemented("AudioPlayerClient.stop"),
        seek: unimplemented("AudioPlayerClient.seek"),
        currentTime: unimplemented("AudioPlayerClient.currentTime")
    )
}

extension DependencyValues {
    public var audioPlayerClient: AudioPlayerClient {
        get { self[AudioPlayerClient.self] }
        set { self[AudioPlayerClient.self] = newValue }
    }
}
