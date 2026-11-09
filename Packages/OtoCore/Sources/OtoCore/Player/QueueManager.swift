import Foundation

/// Trình quản lý hàng đợi phát nhạc (Queue) hỗ trợ shuffle, repeat và bài hát trùng lặp.
public final class QueueManager: @unchecked Sendable {
    private let lock = NSLock()
    private var _items: [QueueItem] = []
    private var _originalItems: [QueueItem] = []
    private var _currentIndex: Int?
    private var _isShuffleEnabled: Bool = false
    private var _repeatMode: RepeatMode = .off

    public init() {}

    public var items: [QueueItem] {
        lock.lock()
        defer { lock.unlock() }
        return _items
    }

    public var currentIndex: Int? {
        lock.lock()
        defer { lock.unlock() }
        return _currentIndex
    }

    public var currentSong: Song? {
        lock.lock()
        defer { lock.unlock() }
        guard let idx = _currentIndex, _items.indices.contains(idx) else {
            return nil
        }
        return _items[idx].song
    }

    public var isShuffleEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isShuffleEnabled
    }

    public var repeatMode: RepeatMode {
        lock.lock()
        defer { lock.unlock() }
        return _repeatMode
    }

    /// Khởi tạo hàng đợi mới từ danh sách bài hát.
    public func setQueue(songs: [Song], startIndex: Int = 0) {
        lock.lock()
        defer { lock.unlock() }
        let queueItems = songs.map { QueueItem(song: $0) }
        _originalItems = queueItems
        _items = queueItems
        if _items.indices.contains(startIndex) {
            _currentIndex = startIndex
        } else {
            _currentIndex = _items.isEmpty ? nil : 0
        }
        _isShuffleEnabled = false
    }

    /// Chuyển bài kế tiếp theo luật repeat và shuffle.
    public func next() -> Song? {
        lock.lock()
        defer { lock.unlock() }
        guard !_items.isEmpty else { return nil }

        if _repeatMode == .one, let idx = _currentIndex, _items.indices.contains(idx) {
            return _items[idx].song
        }

        guard let cur = _currentIndex else {
            _currentIndex = 0
            return _items[0].song
        }

        if cur + 1 < _items.count {
            _currentIndex = cur + 1
            return _items[cur + 1].song
        }

        if _repeatMode == .all {
            _currentIndex = 0
            return _items[0].song
        }

        return nil
    }

    /// Quay lại bài trước.
    public func previous() -> Song? {
        lock.lock()
        defer { lock.unlock() }
        guard !_items.isEmpty else { return nil }

        if _repeatMode == .one, let idx = _currentIndex, _items.indices.contains(idx) {
            return _items[idx].song
        }

        guard let cur = _currentIndex else {
            _currentIndex = 0
            return _items[0].song
        }

        if cur > 0 {
            _currentIndex = cur - 1
            return _items[cur - 1].song
        }

        if _repeatMode == .all {
            let lastIdx = _items.count - 1
            _currentIndex = lastIdx
            return _items[lastIdx].song
        }

        return _items[0].song
    }

    /// Bật/tắt trộn bài (Shuffle).
    /// Khi bật: Giữ bài đang phát ở vị trí hiện tại và xáo trộn các bài còn lại.
    /// Khi tắt: Khôi phục lại thứ tự ban đầu và giữ đúng vị trí bài đang phát.
    public func toggleShuffle() {
        lock.lock()
        defer { lock.unlock() }
        guard _items.count > 1 else { return }

        _isShuffleEnabled.toggle()

        if _isShuffleEnabled {
            guard let cur = _currentIndex, _items.indices.contains(cur) else { return }
            let currentItem = _items[cur]
            var remainingItems = _items
            remainingItems.remove(at: cur)
            remainingItems.shuffle()

            _items = [currentItem] + remainingItems
            _currentIndex = 0
        } else {
            guard let cur = _currentIndex, _items.indices.contains(cur) else { return }
            let currentItem = _items[cur]
            _items = _originalItems
            _currentIndex = _items.firstIndex(where: { $0.id == currentItem.id }) ?? 0
        }
    }

    /// Chuyển đổi vòng lặp repeat (off -> all -> one -> off).
    @discardableResult
    public func toggleRepeat() -> RepeatMode {
        lock.lock()
        defer { lock.unlock() }
        switch _repeatMode {
        case .off:
            _repeatMode = .all
        case .all:
            _repeatMode = .one
        case .one:
            _repeatMode = .off
        }
        return _repeatMode
    }

    /// Chèn bài hát để phát tiếp theo (Play Next).
    public func insertNext(song: Song) {
        lock.lock()
        defer { lock.unlock() }
        let newItem = QueueItem(song: song)
        if let cur = _currentIndex, cur + 1 <= _items.count {
            _items.insert(newItem, at: cur + 1)
            _originalItems.append(newItem)
        } else {
            _items.append(newItem)
            _originalItems.append(newItem)
            if _currentIndex == nil {
                _currentIndex = 0
            }
        }
    }

    /// Thêm vào cuối hàng đợi.
    public func append(song: Song) {
        lock.lock()
        defer { lock.unlock() }
        let newItem = QueueItem(song: song)
        _items.append(newItem)
        _originalItems.append(newItem)
        if _currentIndex == nil {
            _currentIndex = 0
        }
    }
}
