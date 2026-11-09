import Foundation

/// Dịch vụ phân giải lời bài hát đa nguồn theo đúng luồng ưu tiên quy định trong AGENTS.md.
/// Cách ly luồng bằng actor, tự động hủy bỏ kết quả cũ khi đổi bài hát (stale generation protection).
public actor MultiSourceLyricsService {
    private let providers: [LyricsProvider]
    private var cache: [String: LyricsDocument] = [:]
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
                cache[song.id] = doc
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
            cache[song.id] = fallbackPlain
            return fallbackPlain
        }

        let noneDoc = LyricsDocument(type: .none)
        cache[song.id] = noneDoc
        return noneDoc
    }

    /// Xóa toàn bộ bộ nhớ đệm lời bài hát.
    public func clearCache() {
        cache.removeAll()
    }
}
