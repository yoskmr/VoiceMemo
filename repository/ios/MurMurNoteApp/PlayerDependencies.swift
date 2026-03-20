import AVFoundation
import Dependencies
import Domain
import Foundation

// MARK: - Player Dependencies
// 音声再生のDependency実装

// MARK: AudioPlayerClient → AVAudioPlayer 実装

/// AVAudioPlayer をラップする MainActor 隔離クラス
/// すべての操作を MainActor 上で実行し、AVAudioPlayer のスレッドセーフティを保証する
private final class LiveAudioPlayer: Sendable {
    /// AVAudioPlayer はメインスレッドでのみ操作する
    /// nonisolated(unsafe) で Sendable 準拠しつつ、実際のアクセスは全て MainActor 経由
    nonisolated(unsafe) private var player: AVAudioPlayer?

    /// 音声ファイルをロードし duration を返す
    @MainActor
    func loadAudio(path: String) throws -> TimeInterval {
        let url = Self.resolveFileURL(path: path)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioPlayerError.fileNotFound(path)
        }

        let newPlayer = try AVAudioPlayer(contentsOf: url)
        newPlayer.prepareToPlay()
        self.player = newPlayer
        return newPlayer.duration
    }

    /// 指定位置から再生開始
    @MainActor
    func play(from time: TimeInterval) throws {
        guard let player else { throw AudioPlayerError.notLoaded }
        player.currentTime = time
        guard player.play() else { throw AudioPlayerError.playbackFailed }
    }

    /// 一時停止
    @MainActor
    func pause() {
        player?.pause()
    }

    /// 停止（先頭に戻す）
    @MainActor
    func stop() {
        player?.stop()
        player?.currentTime = 0
    }

    /// 指定時間へシーク
    @MainActor
    func seek(to time: TimeInterval) throws {
        guard let player else { throw AudioPlayerError.notLoaded }
        let clampedTime = min(max(time, 0), player.duration)
        player.currentTime = clampedTime
    }

    /// 現在の再生位置を取得
    @MainActor
    func currentTime() -> TimeInterval {
        player?.currentTime ?? 0
    }

    // MARK: - Helpers

    /// 相対パス（"Audio/xxx.m4a"）を Documents ディレクトリ基準で解決する
    private static func resolveFileURL(path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docsDir.appendingPathComponent(path)
    }
}

/// AudioPlayer で発生するエラー
private enum AudioPlayerError: LocalizedError {
    case fileNotFound(String)
    case notLoaded
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "音声ファイルが見つかりません: \(path)"
        case .notLoaded:
            return "音声ファイルが読み込まれていません"
        case .playbackFailed:
            return "音声の再生に失敗しました"
        }
    }
}

extension AudioPlayerClient: DependencyKey {
    public static let liveValue: AudioPlayerClient = {
        let player = LiveAudioPlayer()
        return AudioPlayerClient(
            loadAudio: { path in
                try await player.loadAudio(path: path)
            },
            play: { from in
                try await player.play(from: from)
            },
            pause: {
                await player.pause()
            },
            stop: {
                await player.stop()
            },
            seek: { to in
                try await player.seek(to: to)
            },
            currentTime: {
                await player.currentTime()
            }
        )
    }()
}
