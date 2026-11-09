import Foundation

/// Ý định phát nhạc của người dùng (User Playback Intent), tách biệt hoàn toàn khỏi trạng thái của WebKit engine.
public enum UserPlaybackIntent: Sendable, Equatable {
    case playing
    case paused
}

/// Trạng thái hoạt động thực tế của WebKit engine hoặc thẻ media HTML5 bên dưới.
public enum EnginePlaybackState: Sendable, Equatable {
    case idle
    case buffering
    case playing
    case paused
}

/// Trạng thái gián đoạn âm thanh của hệ thống (cuộc gọi, Siri, báo thức).
public enum AudioInterruptionState: Sendable, Equatable {
    case active
    case interrupted
}

/// Các hiệu ứng (Side Effects) cần thực thi ngoài State Machine sau mỗi bước chuyển trạng thái.
public struct PlaybackEffects: Sendable, Equatable {
    public var shouldActivateSession: Bool = false
    public var shouldStartEngine: StartEnginePayload?
    public var shouldResumeEngine: Bool = false
    public var shouldPauseEngine: Bool = false
    public var shouldSeekEngine: TimeInterval?
    public var shouldAdvanceToNextTrack: Bool = false

    public struct StartEnginePayload: Sendable, Equatable {
        public let songId: String
        public let startSeconds: TimeInterval
        public let generation: Int

        public init(songId: String, startSeconds: TimeInterval, generation: Int) {
            self.songId = songId
            self.startSeconds = startSeconds
            self.generation = generation
        }
    }

    public init(
        shouldActivateSession: Bool = false,
        shouldStartEngine: StartEnginePayload? = nil,
        shouldResumeEngine: Bool = false,
        shouldPauseEngine: Bool = false,
        shouldSeekEngine: TimeInterval? = nil,
        shouldAdvanceToNextTrack: Bool = false
    ) {
        self.shouldActivateSession = shouldActivateSession
        self.shouldStartEngine = shouldStartEngine
        self.shouldResumeEngine = shouldResumeEngine
        self.shouldPauseEngine = shouldPauseEngine
        self.shouldSeekEngine = shouldSeekEngine
        self.shouldAdvanceToNextTrack = shouldAdvanceToNextTrack
    }
}

/// Máy trạng thái phát nhạc xác định (Deterministic Playback State Machine).
///
/// Tuân thủ nghiêm ngặt 3 trục trạng thái độc lập:
/// 1. `userIntent`: Người dùng muốn nghe hay tạm dừng.
/// 2. `engineState`: WebKit đang tải, đang phát hay đang chờ.
/// 3. `interruptionState`: Hệ thống có đang ngắt âm thanh hay không.
public struct PlaybackStateMachine: Sendable {
    public private(set) var userIntent: UserPlaybackIntent = .paused
    public private(set) var engineState: EnginePlaybackState = .idle
    public private(set) var interruptionState: AudioInterruptionState = .active
    public private(set) var currentSong: Song?
    public private(set) var currentPosition: TimeInterval = 0
    public private(set) var currentGeneration: Int = 0
    private var hasEndedForCurrentTrack: Bool = false

    public init() {}

    // MARK: - User Intent Actions

    /// Người dùng chọn phát một bài hát cụ thể.
    public mutating func userPlay(song: Song) -> PlaybackEffects {
        userIntent = .playing
        interruptionState = .active
        currentSong = song
        currentPosition = 0
        currentGeneration += 1
        hasEndedForCurrentTrack = false
        engineState = .buffering

        var effects = PlaybackEffects()
        effects.shouldActivateSession = true
        effects.shouldStartEngine = PlaybackEffects.StartEnginePayload(
            songId: song.id,
            startSeconds: 0,
            generation: currentGeneration
        )
        return effects
    }

    /// Người dùng bấm tiếp tục phát (Resume).
    public mutating func userResume() -> PlaybackEffects {
        guard currentSong != nil else { return PlaybackEffects() }
        userIntent = .playing
        interruptionState = .active

        var effects = PlaybackEffects()
        effects.shouldActivateSession = true
        effects.shouldResumeEngine = true
        return effects
    }

    /// Người dùng bấm tạm dừng (Pause).
    public mutating func userPause() -> PlaybackEffects {
        userIntent = .paused
        interruptionState = .active

        var effects = PlaybackEffects()
        effects.shouldPauseEngine = true
        return effects
    }

    /// Người dùng tua thời gian (Seek).
    public mutating func userSeek(to position: TimeInterval) -> PlaybackEffects {
        currentPosition = position
        var effects = PlaybackEffects()
        effects.shouldSeekEngine = position
        return effects
    }

    // MARK: - Interruption Handling

    /// Hệ thống bắt đầu gián đoạn âm thanh (cuộc gọi đến, Siri kích hoạt).
    public mutating func interruptionBegan() -> PlaybackEffects {
        // Lọc bỏ duplicate/nested interruption began
        guard interruptionState != .interrupted else {
            return PlaybackEffects()
        }
        interruptionState = .interrupted

        // QUAN TRỌNG: Giữ nguyên userIntent trước cuộc gọi!
        // Chỉ tạm dừng WebKit engine để tránh lỗi tranh chấp audio session.
        engineState = .paused

        var effects = PlaybackEffects()
        effects.shouldPauseEngine = true
        return effects
    }

    /// Hệ thống kết thúc gián đoạn âm thanh.
    public mutating func interruptionEnded(shouldResume: Bool) -> PlaybackEffects {
        // Lọc bỏ duplicate/nested interruption ended
        guard interruptionState == .interrupted else {
            return PlaybackEffects()
        }
        interruptionState = .active

        // CHỈ resume nếu hệ thống cho phép (shouldResume == true) VÀ ý định trước đó là .playing
        if shouldResume && userIntent == .playing {
            var effects = PlaybackEffects()
            effects.shouldActivateSession = true
            effects.shouldResumeEngine = true
            return effects
        }

        return PlaybackEffects()
    }

    // MARK: - Route Changes

    /// Rút tai nghe hoặc ngắt kết nối Bluetooth:
    /// Bắt buộc tạm dừng engine VÀ chuyển userIntent sang .paused để không bao giờ tự phát ra loa ngoài.
    public mutating func routeUnplugged() -> PlaybackEffects {
        userIntent = .paused
        engineState = .paused

        var effects = PlaybackEffects()
        effects.shouldPauseEngine = true
        return effects
    }

    // MARK: - WebKit Engine Events

    /// WebKit báo trạng thái playback thay đổi (1 = PLAYING, 2 = PAUSED, etc.).
    public mutating func engineStateChanged(
        _ newEngineState: EnginePlaybackState,
        generation: Int
    ) -> PlaybackEffects {
        // Loại bỏ stale events của bài trước bằng playback generation
        guard generation == currentGeneration else {
            return PlaybackEffects()
        }

        engineState = newEngineState

        // WebKit KHÔNG ĐƯỢC tự ý đổi userIntent hoặc tự kích hoạt audio session!
        // Nếu WebKit tự ý phát khi người dùng đang ở trạng thái paused, cưỡng chế pause lại
        if newEngineState == .playing && userIntent == .paused {
            var effects = PlaybackEffects()
            effects.shouldPauseEngine = true
            return effects
        }

        return PlaybackEffects()
    }

    /// WebKit cập nhật vị trí thời gian bài hát.
    public mutating func engineTimeUpdated(
        currentTime: TimeInterval,
        generation: Int
    ) {
        guard generation == currentGeneration else { return }
        currentPosition = currentTime
    }

    /// WebKit báo bài hát đã phát hết (ended).
    public mutating func engineTrackEnded(generation: Int) -> PlaybackEffects {
        guard generation == currentGeneration else { return PlaybackEffects() }
        guard !hasEndedForCurrentTrack else { return PlaybackEffects() }
        hasEndedForCurrentTrack = true

        if userIntent == .playing {
            var effects = PlaybackEffects()
            effects.shouldAdvanceToNextTrack = true
            return effects
        }
        return PlaybackEffects()
    }

    // MARK: - Public State Projection

    /// Chiếu trạng thái nội bộ ra PlaybackState công khai cho giao diện người dùng.
    public var playbackState: PlaybackState {
        guard let song = currentSong else { return .idle }
        switch userIntent {
        case .playing:
            if interruptionState == .interrupted {
                return .paused(song: song, position: currentPosition)
            }
            switch engineState {
            case .idle, .buffering:
                return .buffering(song: song, position: currentPosition)
            case .playing:
                return .playing(song: song, position: currentPosition)
            case .paused:
                return .buffering(song: song, position: currentPosition)
            }
        case .paused:
            return .paused(song: song, position: currentPosition)
        }
    }
}
