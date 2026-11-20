import Foundation

extension QueueManager {
    /// Di chuyển một bài hát, giữ nguyên identity bài đang phát và đồng bộ thứ tự gốc khi shuffle.
    public func moveItem(from sourceIndex: Int, to destinationIndex: Int) {
        lock.lock()
        guard itemsStorage.count > 1,
              itemsStorage.indices.contains(sourceIndex),
              destinationIndex >= 0,
              destinationIndex <= itemsStorage.count,
              sourceIndex != destinationIndex,
              destinationIndex != sourceIndex + 1 else {
            lock.unlock()
            return
        }

        let currentItemId = currentIndexStorage.flatMap {
            itemsStorage.indices.contains($0) ? itemsStorage[$0].id : nil
        }
        let item = itemsStorage.remove(at: sourceIndex)
        let insertIndex = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        let clampedInsertIndex = min(max(0, insertIndex), itemsStorage.count)
        itemsStorage.insert(item, at: clampedInsertIndex)

        if let currentItemId {
            currentIndexStorage = itemsStorage.firstIndex(where: { $0.id == currentItemId })
        }

        if !shuffleEnabledStorage {
            originalItemsStorage = itemsStorage
        } else if let originalIndex = originalItemsStorage.firstIndex(where: { $0.id == item.id }) {
            originalItemsStorage.remove(at: originalIndex)
            if clampedInsertIndex == 0 {
                originalItemsStorage.insert(item, at: 0)
            } else {
                let previousItem = itemsStorage[clampedInsertIndex - 1]
                if let previousIndex = originalItemsStorage.firstIndex(where: { $0.id == previousItem.id }) {
                    originalItemsStorage.insert(item, at: min(previousIndex + 1, originalItemsStorage.count))
                } else {
                    originalItemsStorage.append(item)
                }
            }
        }

        lock.unlock()
        notifyQueueChanged()
    }

    /// Xóa các bài hát tiếp theo trong Up Next, giữ lại bài đang phát.
    public func clearUpcoming() {
        lock.lock()
        guard let currentIndex = currentIndexStorage, currentIndex < itemsStorage.count else {
            lock.unlock()
            return
        }
        let keepCount = currentIndex + 1
        guard keepCount < itemsStorage.count else {
            lock.unlock()
            return
        }
        let removedItems = Array(itemsStorage[keepCount...])
        itemsStorage = Array(itemsStorage[0..<keepCount])
        let removedIDs = Set(removedItems.map(\.id))
        originalItemsStorage.removeAll(where: { removedIDs.contains($0.id) })
        lock.unlock()
        notifyQueueChanged()
    }
}
