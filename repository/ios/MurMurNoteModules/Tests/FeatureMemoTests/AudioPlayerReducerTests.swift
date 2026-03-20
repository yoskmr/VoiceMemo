import ComposableArchitecture
import XCTest
@testable import Domain
@testable import FeatureMemo

@MainActor
final class AudioPlayerReducerTests: XCTestCase {

    // テスト用セグメント
    private let testSegments: [AudioPlayerReducer.TimestampedSegment] = [
        .init(id: 0, text: "最初のセグメント", startTime: 0, endTime: 15),
        .init(id: 1, text: "次のセグメント", startTime: 15, endTime: 30),
        .init(id: 2, text: "最後のセグメント", startTime: 30, endTime: 45),
    ]

    // MARK: - Test 1: onAppear でオーディオファイルロード

    func test_onAppear_オーディオファイルロード() async {
        let store = TestStore(
            initialState: AudioPlayerReducer.State()
        ) {
            AudioPlayerReducer()
        } withDependencies: {
            $0.audioPlayerClient.loadAudio = { _ in 180.0 }
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.onAppear(audioFilePath: "Audio/test.m4a", segments: testSegments)) {
            $0.audioFilePath = "Audio/test.m4a"
            $0.timestampedSegments = self.testSegments
        }

        await store.receive(._playerDurationLoaded(180.0)) {
            $0.duration = 180.0
        }
    }

    // MARK: - Test 2: playTapped で再生開始

    func test_playTapped_再生開始() async {
        let clock = TestClock()
        let store = TestStore(
            initialState: AudioPlayerReducer.State(duration: 180)
        ) {
            AudioPlayerReducer()
        } withDependencies: {
            $0.audioPlayerClient.play = { _ in }
            $0.audioPlayerClient.currentTime = { 0 }
            $0.continuousClock = clock
        }

        await store.send(.playTapped) {
            $0.playerStatus = .playing
        }

        await store.skipInFlightEffects()
    }

    // MARK: - Test 3: pauseTapped で一時停止

    func test_pauseTapped_一時停止() async {
        let store = TestStore(
            initialState: AudioPlayerReducer.State(
                playerStatus: .playing,
                duration: 180
            )
        ) {
            AudioPlayerReducer()
        } withDependencies: {
            $0.audioPlayerClient.pause = { }
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.pauseTapped) {
            $0.playerStatus = .paused
        }
    }

    // MARK: - Test 4: stopTapped で停止とリセット

    func test_stopTapped_停止とリセット() async {
        let store = TestStore(
            initialState: AudioPlayerReducer.State(
                playerStatus: .playing,
                currentTime: 90,
                duration: 180,
                progress: 0.5,
                highlightedSegmentIndex: 1
            )
        ) {
            AudioPlayerReducer()
        } withDependencies: {
            $0.audioPlayerClient.stop = { }
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.stopTapped) {
            $0.playerStatus = .idle
            $0.currentTime = 0
            $0.progress = 0
            $0.highlightedSegmentIndex = nil
        }
    }

    // MARK: - Test 5: playerTimeUpdated で進行率更新

    func test_playerTimeUpdated_進行率更新() async {
        let store = TestStore(
            initialState: AudioPlayerReducer.State(
                playerStatus: .playing,
                duration: 180
            )
        ) {
            AudioPlayerReducer()
        }

        await store.send(._playerTimeUpdated(90.0)) {
            $0.currentTime = 90.0
            $0.progress = 0.5
        }
    }

    // MARK: - Test 6: sliderDrag中は時間更新を無視

    func test_sliderDrag_ドラッグ中は時間更新を無視() async {
        let store = TestStore(
            initialState: AudioPlayerReducer.State(
                playerStatus: .playing,
                currentTime: 30,
                duration: 180,
                progress: 30.0 / 180.0,
                isSliderDragging: true
            )
        ) {
            AudioPlayerReducer()
        }

        // ドラッグ中は _playerTimeUpdated を無視
        await store.send(._playerTimeUpdated(60.0))
        // state に変更なし
    }

    // MARK: - Test 7: sliderDragEnded でシーク実行

    func test_sliderDragEnded_シーク実行() async {
        var seekedTime: TimeInterval?
        let store = TestStore(
            initialState: AudioPlayerReducer.State(
                playerStatus: .playing,
                currentTime: 90,
                duration: 180,
                progress: 0.5,
                isSliderDragging: true
            )
        ) {
            AudioPlayerReducer()
        } withDependencies: {
            $0.audioPlayerClient.seek = { time in
                seekedTime = time
            }
        }

        await store.send(.sliderDragEnded) {
            $0.isSliderDragging = false
        }

        XCTAssertEqual(seekedTime, 90)
    }

    // MARK: - Test 8: ハイライト同期（正しいセグメント）

    func test_highlightSync_正しいセグメントがハイライト() async {
        let store = TestStore(
            initialState: AudioPlayerReducer.State(
                playerStatus: .playing,
                duration: 45,
                timestampedSegments: testSegments
            )
        ) {
            AudioPlayerReducer()
        }

        // セグメント1（15-30秒）の中間地点
        await store.send(._playerTimeUpdated(22.0)) {
            $0.currentTime = 22.0
            $0.progress = 22.0 / 45.0
            $0.highlightedSegmentIndex = 1
        }
    }

    // MARK: - Test 9: ハイライト同期（許容誤差500ms）

    func test_highlightSync_許容誤差500ms() async {
        let store = TestStore(
            initialState: AudioPlayerReducer.State(
                playerStatus: .playing,
                duration: 45,
                timestampedSegments: testSegments
            )
        ) {
            AudioPlayerReducer()
        }

        // セグメント0（endTime=15）の許容誤差500ms内 → セグメント0がハイライトされる
        // 14.5 は segment0(0-15) の endTime+tolerance=15.5 内なので firstIndex で segment0 にマッチ
        await store.send(._playerTimeUpdated(14.5)) {
            $0.currentTime = 14.5
            $0.progress = 14.5 / 45.0
            $0.highlightedSegmentIndex = 0  // 許容誤差内でセグメント0にマッチ
        }
    }

    // MARK: - Test 10: ハイライト同期（範囲外でハイライトなし）

    func test_highlightSync_範囲外でハイライトなし() async {
        let store = TestStore(
            initialState: AudioPlayerReducer.State(
                playerStatus: .playing,
                duration: 120,
                timestampedSegments: testSegments
            )
        ) {
            AudioPlayerReducer()
        }

        // セグメント範囲外（45秒超）
        await store.send(._playerTimeUpdated(100.0)) {
            $0.currentTime = 100.0
            $0.progress = 100.0 / 120.0
            $0.highlightedSegmentIndex = nil
        }
    }

    // MARK: - Test 11: playerDidFinish で再生終了

    func test_playerDidFinish_再生終了() async {
        let store = TestStore(
            initialState: AudioPlayerReducer.State(
                playerStatus: .playing,
                currentTime: 180,
                duration: 180,
                progress: 1.0,
                highlightedSegmentIndex: 2
            )
        ) {
            AudioPlayerReducer()
        }

        await store.send(._playerDidFinish) {
            $0.playerStatus = .finished
            $0.highlightedSegmentIndex = nil
        }
    }

    // MARK: - Test 12: onDisappear で再生停止

    func test_onDisappear_再生停止() async {
        let store = TestStore(
            initialState: AudioPlayerReducer.State(
                playerStatus: .playing,
                duration: 180
            )
        ) {
            AudioPlayerReducer()
        } withDependencies: {
            $0.audioPlayerClient.stop = { }
        }

        await store.send(.onDisappear) {
            $0.playerStatus = .idle
        }
    }

    // MARK: - Test 13: seekTo で指定時間にシーク

    func test_seekTo_指定時間にシーク() async {
        let store = TestStore(
            initialState: AudioPlayerReducer.State(
                playerStatus: .playing,
                duration: 45,
                timestampedSegments: testSegments
            )
        ) {
            AudioPlayerReducer()
        } withDependencies: {
            $0.audioPlayerClient.seek = { _ in }
        }

        await store.send(.seekTo(20.0)) {
            $0.currentTime = 20.0
            $0.progress = 20.0 / 45.0
            $0.highlightedSegmentIndex = 1  // 15-30秒のセグメント
        }
    }
}
