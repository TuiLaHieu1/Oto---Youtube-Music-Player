import Foundation

/// Trình quản lý hàng đợi phát nhạc (Queue) hỗ trợ shuffle, repeat và bài hát trùng lặp.
public final class QueueManager: @unchecked Sendable {
    let lock = NSLock()
    var itemsStorage: [QueueItem] = []
    var originalItemsStorage: [QueueItem] = []
    var currentIndexStorage: Int?
    var shuffleEnabledStorage: Bool = false
    var repeatModeStorage: RepeatMode = .off
    var hasNavigatedInShuffle: Bool = false

    public var onQueueChanged: (@Sendable () -> Void)?

    func notifyQueueChanged() {
        onQueueChanged?()
    }

    public struct Snapshot: Sendable {
        public let items: [QueueItem]
        public let originalItems: [QueueItem]
        public let currentIndex: Int?
        public let isShuffleEnabled: Bool
        public let repeatMode: RepeatMode

        public init(
            items: [QueueItem],
            originalItems: [QueueItem],
            currentIndex: Int?,
            isShuffleEnabled: Bool,
            repeatMode: RepeatMode
        ) {
            self.items = items
            self.originalItems = originalItems
            self.currentIndex = currentIndex
            self.isShuffleEnabled = isShuffleEnabled
            self.repeatMode = repeatMode
        }
    }

    public init() {}

    public func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            items: itemsStorage,
            originalItems: originalItemsStorage,
            currentIndex: currentIndexStorage,
            isShuffleEnabled: shuffleEnabledStorage,
            repeatMode: repeatModeStorage
        )
    }

    public var items: [QueueItem] {
        lock.lock()
        defer { lock.unlock() }
        return itemsStorage
    }

    public var currentIndex: Int? {
        lock.lock()
        defer { lock.unlock() }
        return currentIndexStorage
    }

    public var currentSong: Song? {
        lock.lock()
        defer { lock.unlock() }
        guard let idx = currentIndexStorage, itemsStorage.indices.contains(idx) else {
            return nil
        }
        return itemsStorage[idx].song
    }

    public var isShuffleEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return shuffleEnabledStorage
    }

    public var repeatMode: RepeatMode {
        lock.lock()
        defer { lock.unlock() }
        return repeatModeStorage
    }

    public var remainingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        guard let cur = currentIndexStorage else { return itemsStorage.count }
        return max(0, itemsStorage.count - (cur + 1))
    }
}

// MARK: - Navigation

extension QueueManager {
    /// Khởi tạo hàng đợi mới từ danh sách bài hát.
    public func setQueue(songs: [Song], startIndex: Int = 0) {
        lock.lock()
        let queueItems = songs.map { QueueItem(song: $0) }
        originalItemsStorage = queueItems
        itemsStorage = queueItems
        if itemsStorage.indices.contains(startIndex) {
            currentIndexStorage = startIndex
        } else {
            currentIndexStorage = itemsStorage.isEmpty ? nil : 0
        }
        shuffleEnabledStorage = false
        hasNavigatedInShuffle = false
        lock.unlock()
        notifyQueueChanged()
    }

    /// Chuyển bài kế tiếp theo luật repeat và shuffle.
    @discardableResult
    public func next(userInitiated: Bool = false) -> Song? {
        lock.lock()
        guard !itemsStorage.isEmpty else {
            lock.unlock()
            return nil
        }

        if !userInitiated && repeatModeStorage == .one,
           let idx = currentIndexStorage,
           itemsStorage.indices.contains(idx) {
            let song = itemsStorage[idx].song
            lock.unlock()
            notifyQueueChanged()
            return song
        }

        guard let cur = currentIndexStorage else {
            currentIndexStorage = 0
            let song = itemsStorage[0].song
            if shuffleEnabledStorage { hasNavigatedInShuffle = true }
            lock.unlock()
            notifyQueueChanged()
            return song
        }

        if cur + 1 < itemsStorage.count {
            currentIndexStorage = cur + 1
            let song = itemsStorage[cur + 1].song
            if shuffleEnabledStorage { hasNavigatedInShuffle = true }
            lock.unlock()
            notifyQueueChanged()
            return song
        }

        if repeatModeStorage == .all {
            currentIndexStorage = 0
            let song = itemsStorage[0].song
            if shuffleEnabledStorage { hasNavigatedInShuffle = true }
            lock.unlock()
            notifyQueueChanged()
            return song
        }

        lock.unlock()
        return nil
    }

    /// Quay lại bài trước.
    @discardableResult
    public func previous() -> Song? {
        lock.lock()
        guard !itemsStorage.isEmpty else {
            lock.unlock()
            return nil
        }

        guard let cur = currentIndexStorage else {
            currentIndexStorage = 0
            let song = itemsStorage[0].song
            if shuffleEnabledStorage { hasNavigatedInShuffle = true }
            lock.unlock()
            notifyQueueChanged()
            return song
        }

        if cur > 0 {
            currentIndexStorage = cur - 1
            let song = itemsStorage[cur - 1].song
            if shuffleEnabledStorage { hasNavigatedInShuffle = true }
            lock.unlock()
            notifyQueueChanged()
            return song
        }

        if repeatModeStorage == .all {
            let lastIdx = itemsStorage.count - 1
            currentIndexStorage = lastIdx
            let song = itemsStorage[lastIdx].song
            if shuffleEnabledStorage { hasNavigatedInShuffle = true }
            lock.unlock()
            notifyQueueChanged()
            return song
        }

        let song = itemsStorage[0].song
        lock.unlock()
        notifyQueueChanged()
        return song
    }

    /// Nhảy trực tiếp đến vị trí chỉ định trong hàng đợi và cập nhật currentIndex.
    @discardableResult
    public func skipToIndex(_ index: Int) -> Song? {
        lock.lock()
        guard itemsStorage.indices.contains(index) else {
            lock.unlock()
            return nil
        }
        currentIndexStorage = index
        let song = itemsStorage[index].song
        if shuffleEnabledStorage { hasNavigatedInShuffle = true }
        lock.unlock()
        notifyQueueChanged()
        return song
    }
}

// MARK: - Queue Mutation

extension QueueManager {
    /// Bật/tắt trộn bài (Shuffle).
    public func toggleShuffle() {
        lock.lock()
        guard itemsStorage.count > 1 else {
            lock.unlock()
            return
        }

        shuffleEnabledStorage.toggle()

        if shuffleEnabledStorage {
            hasNavigatedInShuffle = false
            guard let cur = currentIndexStorage, itemsStorage.indices.contains(cur) else {
                lock.unlock()
                notifyQueueChanged()
                return
            }
            let currentItem = itemsStorage[cur]
            var remainingItems = itemsStorage
            remainingItems.remove(at: cur)
            remainingItems.shuffle()

            itemsStorage = [currentItem] + remainingItems
            currentIndexStorage = 0
        } else {
            guard let cur = currentIndexStorage, itemsStorage.indices.contains(cur) else {
                itemsStorage = originalItemsStorage
                currentIndexStorage = itemsStorage.isEmpty ? nil : 0
                hasNavigatedInShuffle = false
                lock.unlock()
                notifyQueueChanged()
                return
            }
            let currentItem = itemsStorage[cur]
            if hasNavigatedInShuffle {
                let playedItems = Array(itemsStorage.prefix(cur + 1))
                let playedIDs = Set(playedItems.map(\.id))
                let unplayedItems = originalItemsStorage.filter { !playedIDs.contains($0.id) }
                itemsStorage = playedItems + unplayedItems
                currentIndexStorage = playedItems.count - 1
            } else {
                itemsStorage = originalItemsStorage
                currentIndexStorage = originalItemsStorage.firstIndex(where: { $0.id == currentItem.id }) ?? 0
            }
            hasNavigatedInShuffle = false
        }
        lock.unlock()
        notifyQueueChanged()
    }

    /// Chuyển đổi vòng lặp repeat (off -> all -> one -> off).
    @discardableResult
    public func toggleRepeat() -> RepeatMode {
        lock.lock()
        switch repeatModeStorage {
        case .off:
            repeatModeStorage = .all
        case .all:
            repeatModeStorage = .one
        case .one:
            repeatModeStorage = .off
        }
        let mode = repeatModeStorage
        lock.unlock()
        notifyQueueChanged()
        return mode
    }

    /// Chèn bài hát để phát tiếp theo (Play Next).
    public func insertNext(song: Song) {
        lock.lock()
        let newItem = QueueItem(song: song)
        if let cur = currentIndexStorage, cur + 1 <= itemsStorage.count {
            itemsStorage.insert(newItem, at: cur + 1)
            let currentItem = itemsStorage[cur]
            if let originalIdx = originalItemsStorage.firstIndex(where: { $0.id == currentItem.id }) {
                originalItemsStorage.insert(newItem, at: min(originalIdx + 1, originalItemsStorage.count))
            } else {
                originalItemsStorage.append(newItem)
            }
        } else {
            itemsStorage.append(newItem)
            originalItemsStorage.append(newItem)
            if currentIndexStorage == nil {
                currentIndexStorage = 0
            }
        }
        lock.unlock()
        notifyQueueChanged()
    }

    /// Thêm vào cuối hàng đợi.
    public func append(song: Song) {
        lock.lock()
        let newItem = QueueItem(song: song)
        itemsStorage.append(newItem)
        originalItemsStorage.append(newItem)
        if currentIndexStorage == nil {
            currentIndexStorage = 0
        }
        lock.unlock()
        notifyQueueChanged()
    }

    /// Thêm danh sách bài hát vào cuối hàng đợi.
    public func appendQueue(songs: [Song]) {
        guard !songs.isEmpty else { return }
        lock.lock()
        let newItems = songs.map { QueueItem(song: $0) }
        itemsStorage.append(contentsOf: newItems)
        originalItemsStorage.append(contentsOf: newItems)
        if currentIndexStorage == nil, !itemsStorage.isEmpty {
            currentIndexStorage = 0
        }
        lock.unlock()
        notifyQueueChanged()
    }
}
