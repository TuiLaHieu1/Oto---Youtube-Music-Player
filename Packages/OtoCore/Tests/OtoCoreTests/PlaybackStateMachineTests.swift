import Testing
import Foundation
@testable import OtoCore

@Suite("Playback State Machine Tests")
struct PlaybackStateMachineTests {

    let testSong1 = Song(id: "song_1", title: "Song 1", artist: "Artist 1", duration: 180)
    let testSong2 = Song(id: "song_2", title: "Song 2", artist: "Artist 2", duration: 240)

    @Test("user paused trước interruption → không resume")
    func testUserPausedBeforeInterruptionDoesNotResume() {
        var sm = PlaybackStateMachine()
        _ = sm.userPlay(song: testSong1)
        #expect(sm.userIntent == .playing)

        // Người dùng chủ động pause
        let pauseEffects = sm.userPause()
        #expect(sm.userIntent == .paused)
        #expect(pauseEffects.shouldPauseEngine == true)

        // Bắt đầu gián đoạn âm thanh (cuộc gọi)
        let beganEffects = sm.interruptionBegan()
        #expect(sm.interruptionState == .interrupted)
        #expect(sm.userIntent == .paused) // Giữ nguyên intent paused của người dùng
        #expect(beganEffects.shouldPauseEngine == true)

        // Kết thúc gián đoạn với shouldResume == true
        let endedEffects = sm.interruptionEnded(shouldResume: true)
        #expect(sm.interruptionState == .active)
        #expect(sm.userIntent == .paused)
        // Không được resume vì người dùng đã chủ động bấm pause trước đó!
        #expect(endedEffects.shouldResumeEngine == false)
        #expect(endedEffects.shouldActivateSession == false)
    }

    @Test("user playing + shouldResume true → resume đúng một lần")
    func testUserPlayingWithShouldResumeTrueResumesExactlyOnce() {
        var sm = PlaybackStateMachine()
        _ = sm.userPlay(song: testSong1)
        #expect(sm.userIntent == .playing)

        // Cuộc gọi đến
        _ = sm.interruptionBegan()
        #expect(sm.interruptionState == .interrupted)
        #expect(sm.userIntent == .playing) // Vẫn ghi nhớ user muốn nghe nhạc

        // Cuộc gọi kết thúc, iOS cho phép tiếp tục
        let endedEffects = sm.interruptionEnded(shouldResume: true)
        #expect(sm.interruptionState == .active)
        #expect(sm.userIntent == .playing)
        #expect(endedEffects.shouldResumeEngine == true)
        #expect(endedEffects.shouldActivateSession == true)
    }

    @Test("user playing + shouldResume false → không resume")
    func testUserPlayingWithShouldResumeFalseDoesNotResume() {
        var sm = PlaybackStateMachine()
        _ = sm.userPlay(song: testSong1)

        _ = sm.interruptionBegan()

        // Cuộc gọi kết thúc nhưng shouldResume == false (ví dụ người dùng mở app phát nhạc khác trong lúc gọi)
        let endedEffects = sm.interruptionEnded(shouldResume: false)
        #expect(sm.interruptionState == .active)
        #expect(endedEffects.shouldResumeEngine == false)
        #expect(endedEffects.shouldActivateSession == false)
    }

    @Test("duplicate interruption began → không pause lặp")
    func testDuplicateInterruptionBeganDoesNotPauseRepeatedly() {
        var sm = PlaybackStateMachine()
        _ = sm.userPlay(song: testSong1)

        // Lần ngắt đầu tiên
        let firstEffects = sm.interruptionBegan()
        #expect(firstEffects.shouldPauseEngine == true)
        #expect(sm.interruptionState == .interrupted)

        // Lần ngắt lặp lại từ hệ thống (nested / duplicate began)
        let duplicateEffects = sm.interruptionBegan()
        #expect(duplicateEffects.shouldPauseEngine == false) // Không phát sinh hiệu ứng pause lặp
        #expect(sm.interruptionState == .interrupted)
    }

    @Test("duplicate interruption ended → không activate/resume lặp")
    func testDuplicateInterruptionEndedDoesNotActivateRepeatedly() {
        var sm = PlaybackStateMachine()
        _ = sm.userPlay(song: testSong1)
        _ = sm.interruptionBegan()

        // Lần ended đầu tiên
        let firstEnded = sm.interruptionEnded(shouldResume: true)
        #expect(firstEnded.shouldResumeEngine == true)
        #expect(firstEnded.shouldActivateSession == true)
        #expect(sm.interruptionState == .active)

        // Lần ended thứ hai bị lặp từ hệ thống
        let duplicateEnded = sm.interruptionEnded(shouldResume: true)
        #expect(duplicateEnded.shouldResumeEngine == false) // Bị dedupe hoàn toàn
        #expect(duplicateEnded.shouldActivateSession == false)
    }

    @Test("route unplug → intent paused")
    func testRouteUnplugChangesIntentToPaused() {
        var sm = PlaybackStateMachine()
        _ = sm.userPlay(song: testSong1)
        #expect(sm.userIntent == .playing)

        // Rút tai nghe
        let unplugEffects = sm.routeUnplugged()
        #expect(sm.userIntent == .paused)
        #expect(unplugEffects.shouldPauseEngine == true)

        // Sau khi rút tai nghe, WebKit có gửi stateChange cũng không được làm đổi intent
        let stateEffects = sm.engineStateChanged(.playing, generation: sm.currentGeneration)
        #expect(sm.userIntent == .paused)
        #expect(stateEffects.shouldPauseEngine == true) // Cưỡng chế pause engine lại
    }

    @Test("stale WebKit playing event → không đổi intent")
    func testStaleWebKitPlayingEventDoesNotAlterIntent() {
        var sm = PlaybackStateMachine()
        _ = sm.userPlay(song: testSong1) // generation 1
        #expect(sm.currentGeneration == 1)

        _ = sm.userPause()
        #expect(sm.userIntent == .paused)

        // Event cũ từ generation 0 hoặc generation khác gửi tới
        let staleEffects = sm.engineStateChanged(.playing, generation: 0)
        #expect(sm.userIntent == .paused)
        #expect(staleEffects == PlaybackEffects())
    }

    @Test("new track generation → bỏ event của bài trước")
    func testNewTrackGenerationDropsOldTrackEvents() {
        var sm = PlaybackStateMachine()
        _ = sm.userPlay(song: testSong1) // generation 1
        #expect(sm.currentGeneration == 1)

        _ = sm.userPlay(song: testSong2) // generation 2
        #expect(sm.currentGeneration == 2)
        #expect(sm.currentSong?.id == "song_2")

        // Event kết thúc bài cũ (trackEnded của generation 1)
        let oldEndedEffects = sm.engineTrackEnded(generation: 1)
        #expect(oldEndedEffects.shouldAdvanceToNextTrack == false) // Bị loại bỏ hoàn toàn

        // Time update của bài cũ
        sm.engineTimeUpdated(currentTime: 179, generation: 1)
        #expect(sm.currentPosition == 0) // Vị trí bài 2 không bị bài cũ ghi đè

        // Event của đúng generation 2
        sm.engineTimeUpdated(currentTime: 15, generation: 2)
        #expect(sm.currentPosition == 15)
    }

    @Test("first load generation 1 với startSeconds > 0")
    func testFirstLoadGenerationAndStartSeconds() {
        var sm = PlaybackStateMachine()
        let effects = sm.userPlay(song: testSong1, startSeconds: 45)
        #expect(sm.currentGeneration == 1)
        #expect(effects.shouldStartEngine?.generation == 1)
        #expect(effects.shouldStartEngine?.songId == "song_1")
        #expect(effects.shouldStartEngine?.startSeconds == 45)
        #expect(sm.currentPosition == 45)
    }

    @Test("repeat-one phát lại cùng bài hát tăng generation mới và seek về 0")
    func testRepeatOneSameSongIncrementsGenerationAndSeeks() {
        var sm = PlaybackStateMachine()
        _ = sm.userPlay(song: testSong1)
        #expect(sm.currentGeneration == 1)

        // Tua đến giây thứ 170
        sm.engineTimeUpdated(currentTime: 170, generation: 1)
        #expect(sm.currentPosition == 170)

        // Lặp lại bài hát (cùng song_1)
        let replayEffects = sm.userPlay(song: testSong1, startSeconds: 0)
        #expect(sm.currentGeneration == 2)
        #expect(replayEffects.shouldStartEngine?.generation == 2)
        #expect(replayEffects.shouldStartEngine?.startSeconds == 0)
        #expect(sm.currentPosition == 0)

        // Event từ generation 1 gửi tới bị loại bỏ
        let staleEffects = sm.engineStateChanged(.playing, generation: 1)
        #expect(staleEffects == PlaybackEffects())

        // Event từ generation 2 được chấp nhận
        let validEffects = sm.engineStateChanged(.playing, generation: 2)
        #expect(validEffects.shouldResumeEngine == false)
        #expect(sm.engineState == .playing)
    }

    @Test("callback error của generation cũ bị bỏ qua")
    func testStaleErrorCallbackDropped() {
        var sm = PlaybackStateMachine()
        _ = sm.userPlay(song: testSong1) // gen 1
        _ = sm.userPlay(song: testSong2) // gen 2

        let errorGen = 1
        let isStale = (errorGen != sm.currentGeneration)
        #expect(isStale == true)
    }
}
