import Foundation

/// Đồng hồ nội suy thời gian phát nhạc chính xác cao dựa trên monotonic ContinuousClock.
/// Không sử dụng CADisplayLink trong nền, tiết kiệm pin tối đa và triệt tiêu độ trôi thời gian (drift).
public final class InterpolatedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var basePosition: TimeInterval
    private var anchorInstant: ContinuousClock.Instant?
    private var rate: Float

    public init(initialPosition: TimeInterval = 0, initialRate: Float = 0) {
        self.basePosition = max(0, initialPosition)
        self.rate = initialRate
        if initialRate > 0 {
            self.anchorInstant = ContinuousClock.now
        } else {
            self.anchorInstant = nil
        }
    }

    /// Đặt lại mốc thời gian khi phát (play).
    public func play(from position: TimeInterval, rate: Float = 1.0) {
        lock.lock()
        defer { lock.unlock() }
        self.basePosition = max(0, position)
        self.rate = rate
        self.anchorInstant = ContinuousClock.now
    }

    /// Tạm dừng và chốt lại vị trí (pause).
    public func pause(at position: TimeInterval? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let pos = position {
            self.basePosition = max(0, pos)
        } else {
            self.basePosition = calculatePosition(now: ContinuousClock.now)
        }
        self.rate = 0
        self.anchorInstant = nil
    }

    /// Nhảy đến vị trí mới (seek).
    public func seek(to position: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        self.basePosition = max(0, position)
        if rate > 0 {
            self.anchorInstant = ContinuousClock.now
        } else {
            self.anchorInstant = nil
        }
    }

    /// Lấy vị trí thời gian hiện tại đã được nội suy.
    public func currentPosition(now: ContinuousClock.Instant = ContinuousClock.now) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return calculatePosition(now: now)
    }

    /// Trạng thái đang chạy của đồng hồ (rate > 0).
    public var isPlaying: Bool {
        lock.lock()
        defer { lock.unlock() }
        return rate > 0
    }

    private func calculatePosition(now: ContinuousClock.Instant) -> TimeInterval {
        guard rate > 0, let anchor = anchorInstant else {
            return basePosition
        }
        let elapsed = now - anchor
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return basePosition + (seconds * Double(rate))
    }
}
