import ComposableArchitecture
import Domain
import Foundation

/// 音声再生のTCA Reducer
/// TASK-0014: 音声再生 + ハイライト同期
/// 設計書 01-system-architecture.md セクション6.1 準拠
@Reducer
public struct AudioPlayerReducer {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        public var audioFilePath: String
        public var playerStatus: PlayerStatus
        public var currentTime: TimeInterval
        public var duration: TimeInterval
        public var progress: Double  // 0.0 - 1.0

        /// ハイライト同期
        public var timestampedSegments: [TimestampedSegment]
        public var highlightedSegmentIndex: Int?

        /// UI
        public var isSliderDragging: Bool
        public var errorMessage: String?

        public init(
            audioFilePath: String = "",
            playerStatus: PlayerStatus = .idle,
            currentTime: TimeInterval = 0,
            duration: TimeInterval = 0,
            progress: Double = 0,
            timestampedSegments: [TimestampedSegment] = [],
            highlightedSegmentIndex: Int? = nil,
            isSliderDragging: Bool = false,
            errorMessage: String? = nil
        ) {
            self.audioFilePath = audioFilePath
            self.playerStatus = playerStatus
            self.currentTime = currentTime
            self.duration = duration
            self.progress = progress
            self.timestampedSegments = timestampedSegments
            self.highlightedSegmentIndex = highlightedSegmentIndex
            self.isSliderDragging = isSliderDragging
            self.errorMessage = errorMessage
        }

        public enum PlayerStatus: Equatable, Sendable {
            case idle
            case playing
            case paused
            case finished
        }
    }

    /// タイムスタンプ付きセグメント（ハイライト同期用）
    public struct TimestampedSegment: Equatable, Identifiable, Sendable {
        public let id: Int
        public let text: String
        public let startTime: TimeInterval
        public let endTime: TimeInterval

        public init(id: Int, text: String, startTime: TimeInterval, endTime: TimeInterval) {
            self.id = id
            self.text = text
            self.startTime = startTime
            self.endTime = endTime
        }
    }

    // MARK: - Action

    public enum Action: Equatable, Sendable {
        case onAppear(audioFilePath: String, segments: [TimestampedSegment])
        case playTapped
        case pauseTapped
        case stopTapped
        case sliderDragStarted
        case sliderDragChanged(Double)  // 0.0 - 1.0
        case sliderDragEnded
        case seekTo(TimeInterval)

        // 内部アクション
        case _playerTimeUpdated(TimeInterval)
        case _playerDidFinish
        case _playerError(String)
        case _playerDurationLoaded(TimeInterval)

        case onDisappear
    }

    // MARK: - Dependencies

    @Dependency(\.audioPlayerClient) var audioPlayerClient
    @Dependency(\.continuousClock) var clock

    // MARK: - Cancellation IDs

    private enum PlayerTimerID { case timer }

    // MARK: - Reducer Body

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .onAppear(path, segments):
                state.audioFilePath = path
                state.timestampedSegments = segments
                return .run { send in
                    do {
                        let duration = try await audioPlayerClient.loadAudio(path)
                        await send(._playerDurationLoaded(duration))
                    } catch {
                        await send(._playerError(error.localizedDescription))
                    }
                }

            case let ._playerDurationLoaded(duration):
                state.duration = duration
                return .none

            case .playTapped:
                guard state.playerStatus != .playing else { return .none }
                let seekTime = state.currentTime
                state.playerStatus = .playing
                return .merge(
                    .run { send in
                        do {
                            try await audioPlayerClient.play(seekTime)
                        } catch {
                            await send(._playerError(error.localizedDescription))
                        }
                    },
                    // 再生位置の定期更新（100ms間隔）
                    .run { send in
                        for await _ in clock.timer(interval: .milliseconds(100)) {
                            let time = await audioPlayerClient.currentTime()
                            await send(._playerTimeUpdated(time))
                        }
                    }
                    .cancellable(id: PlayerTimerID.timer, cancelInFlight: true)
                )

            case .pauseTapped:
                state.playerStatus = .paused
                return .merge(
                    .run { _ in
                        await audioPlayerClient.pause()
                    },
                    .cancel(id: PlayerTimerID.timer)
                )

            case .stopTapped:
                state.playerStatus = .idle
                state.currentTime = 0
                state.progress = 0
                state.highlightedSegmentIndex = nil
                return .merge(
                    .run { _ in
                        await audioPlayerClient.stop()
                    },
                    .cancel(id: PlayerTimerID.timer)
                )

            case .sliderDragStarted:
                state.isSliderDragging = true
                return .none

            case let .sliderDragChanged(progress):
                state.progress = progress
                state.currentTime = progress * state.duration
                updateHighlight(&state)
                return .none

            case .sliderDragEnded:
                state.isSliderDragging = false
                let seekTime = state.currentTime
                return .run { send in
                    do {
                        try await audioPlayerClient.seek(seekTime)
                    } catch {
                        await send(._playerError(error.localizedDescription))
                    }
                }

            case let .seekTo(time):
                state.currentTime = time
                state.progress = state.duration > 0 ? time / state.duration : 0
                updateHighlight(&state)
                return .run { send in
                    do {
                        try await audioPlayerClient.seek(time)
                    } catch {
                        await send(._playerError(error.localizedDescription))
                    }
                }

            case let ._playerTimeUpdated(time):
                guard !state.isSliderDragging else { return .none }
                state.currentTime = time
                state.progress = state.duration > 0 ? time / state.duration : 0
                updateHighlight(&state)
                return .none

            case ._playerDidFinish:
                state.playerStatus = .finished
                state.highlightedSegmentIndex = nil
                return .cancel(id: PlayerTimerID.timer)

            case let ._playerError(message):
                state.errorMessage = message
                state.playerStatus = .idle
                return .cancel(id: PlayerTimerID.timer)

            case .onDisappear:
                state.playerStatus = .idle
                return .merge(
                    .run { _ in await audioPlayerClient.stop() },
                    .cancel(id: PlayerTimerID.timer)
                )
            }
        }
    }

    // MARK: - Highlight Sync

    /// ハイライト同期: 現在再生位置に対応するセグメントを特定（REQ-023: ±500ms許容）
    private func updateHighlight(_ state: inout State) {
        let tolerance: TimeInterval = 0.5
        let currentTime = state.currentTime

        state.highlightedSegmentIndex = state.timestampedSegments.firstIndex { segment in
            currentTime >= (segment.startTime - tolerance) &&
            currentTime <= (segment.endTime + tolerance)
        }
    }
}
