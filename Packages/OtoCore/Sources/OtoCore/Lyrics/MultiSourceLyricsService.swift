import Foundation

/// Dịch vụ phân giải lời bài hát đa nguồn theo đúng luồng ưu tiên quy định trong AGENTS.md.
/// Cách ly luồng bằng actor, tự động hủy bỏ kết quả cũ khi đổi bài hát (stale generation protection).
public actor MultiSourceLyricsService {
    public static let shared = MultiSourceLyricsService()
    private let providers: [LyricsProvider]
    private var cache: [String: LyricsDocument] = [:]
    private var cacheKeys: [String] = []
    private let maxCacheSize = 100
    private var currentGeneration: UInt64 = 0

    public init(providers: [LyricsProvider] = [LRCLibProvider()]) {
        self.providers = providers
    }

    /// Phân giải lời bài hát cho bài hát chỉ định.
    public func resolveLyrics(for song: Song) async -> LyricsDocument {
        // Kiểm tra bộ nhớ tạm trước
        if let cached = cache[song.id] {
            return cached
        }

        currentGeneration += 1
        let requestGeneration = currentGeneration

        var bestPlainLyrics: LyricsDocument?

        for provider in providers {
            // Kiểm tra xem bài hát đã đổi chưa
            guard currentGeneration == requestGeneration else {
                return LyricsDocument(type: .none)
            }

            guard let doc = try? await provider.fetchLyrics(for: song) else {
                continue
            }

            // Nếu tìm thấy lời đồng bộ (.synced) hoặc bài không lời (.instrumental) -> đạt tiêu chuẩn cao nhất
            if doc.type == .synced || doc.type == .instrumental {
                saveToCache(songId: song.id, doc: doc)
                return doc
            }

            // Nếu chỉ có lời tĩnh (.plain), lưu tạm để dự phòng nếu không nguồn nào có lời sync
            if doc.type == .plain && bestPlainLyrics == nil {
                bestPlainLyrics = doc
            }
        }

        guard currentGeneration == requestGeneration else {
            return LyricsDocument(type: .none)
        }

        if let fallbackPlain = bestPlainLyrics {
            saveToCache(songId: song.id, doc: fallbackPlain)
            return fallbackPlain
        }

        let noneDoc = LyricsDocument(type: .none)
        saveToCache(songId: song.id, doc: noneDoc)
        return noneDoc
    }

    private func saveToCache(songId: String, doc: LyricsDocument) {
        if cache[songId] == nil {
            if cacheKeys.count >= maxCacheSize {
                let oldest = cacheKeys.removeFirst()
                cache.removeValue(forKey: oldest)
            }
            cacheKeys.append(songId)
        }
        cache[songId] = doc
    }

    /// Xóa toàn bộ bộ nhớ đệm lời bài hát.
    public func clearCache() {
        cache.removeAll()
        cacheKeys.removeAll()
    }
}
