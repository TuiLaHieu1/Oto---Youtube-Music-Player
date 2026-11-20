import Foundation
import OtoCore

public protocol PlaybackCatalog: Sendable {
    func fetchPlaylistSongs(playlistId: String) async throws -> [Song]
    func fetchAlbumDetail(browseId: String) async throws -> Album
    func fetchUpNextQueue(videoId: String) async throws -> [Song]
}

extension YTMusicClient: PlaybackCatalog {}
