import AVFoundation
import Foundation
import ImageIO
import OtoCore
import UniformTypeIdentifiers

actor LocalMusicStore {
    static let shared = LocalMusicStore()
    static let idPrefix = Song.localIDPrefix

    private struct Metadata: Codable {
        let title: String
        let artist: String
        let artworkID: UUID?

        func artworkURL(in folder: URL) -> URL? {
            self.artworkID.map { folder.appendingPathComponent(".cover-\($0.uuidString).jpg") }
        }
    }

    private static func metadata(in folder: URL) -> Metadata? {
        (try? Data(contentsOf: folder.appendingPathComponent(".metadata.json"))).flatMap {
            try? JSONDecoder().decode(Metadata.self, from: $0)
        }
    }

    nonisolated static func folder(for id: UUID) throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        .appendingPathComponent("LocalMusic", isDirectory: true)
        .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    nonisolated static func file(for songID: String) -> URL? {
        guard songID.hasPrefix(Self.idPrefix),
              let id = UUID(uuidString: String(songID.dropFirst(Self.idPrefix.count))),
              let directory = try? Self.folder(for: id),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles
              )
        else { return nil }
        return files.first { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }

    func songs() throws -> [Song] {
        let root = try Self.folder(for: UUID()).deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let folders = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )
        return folders.compactMap { folder in
            guard let id = UUID(uuidString: folder.lastPathComponent) else { return nil }
            let songID = Self.idPrefix + id.uuidString
            guard let file = Self.file(for: songID) else { return nil }
            let metadata = Self.metadata(in: folder)
            return Song(id: songID, title: metadata?.title ?? file.deletingPathExtension().lastPathComponent,
                        artist: metadata?.artist ?? "", artworkURL: metadata?.artworkURL(in: folder))
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    @discardableResult
    func importFile(_ source: URL) async throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let folder = try Self.folder(for: UUID())
        let staging = folder.deletingLastPathComponent().appendingPathComponent("." + folder.lastPathComponent)
        let target = staging.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        var coordinationError: NSError?
        var copyError: (any Error)?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { file in
            do {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
                try FileManager.default.copyItem(at: file, to: target)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        let asset = AVURLAsset(url: target)
        guard try await asset.load(.isPlayable),
              try await !asset.load(.hasProtectedContent),
              try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: folder)
        return Self.idPrefix + folder.lastPathComponent
    }

    func remove(_ songID: String) throws {
        guard let file = Self.file(for: songID) else { return }
        try FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    func update(_ songID: String, title: String, artist: String, artwork source: URL?) throws -> Song {
        guard let file = Self.file(for: songID) else { throw CocoaError(.fileNoSuchFile) }
        let folder = file.deletingLastPathComponent()
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        let previous = Self.metadata(in: folder)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata = Metadata(title: title, artist: artist, artworkID: source == nil ? previous?.artworkID : UUID())
        let artwork = metadata.artworkURL(in: folder)
        if let source, let artwork {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 768
            ] as CFDictionary
            let jpeg = NSMutableData()
            guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(input, 0, options),
                  let output = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil)
            else { throw CocoaError(.fileReadCorruptFile) }
            CGImageDestinationAddImage(output, image, nil)
            guard CGImageDestinationFinalize(output) else { throw CocoaError(.fileWriteUnknown) }
            try (jpeg as Data).write(to: artwork, options: .atomic)
        }
        do {
            try JSONEncoder().encode(metadata)
                .write(to: folder.appendingPathComponent(".metadata.json"), options: .atomic)
        } catch {
            if source != nil, let artwork { try? FileManager.default.removeItem(at: artwork) }
            throw error
        }
        if let previousArtwork = previous?.artworkURL(in: folder), previousArtwork != artwork {
            try? FileManager.default.removeItem(at: previousArtwork)
        }
        return Song(id: songID, title: title, artist: artist, artworkURL: artwork)
    }
}
