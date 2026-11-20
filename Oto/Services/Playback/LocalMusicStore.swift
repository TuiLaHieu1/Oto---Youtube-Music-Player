import AVFoundation
import Foundation
import OtoCore

actor LocalMusicStore {
    static let shared = LocalMusicStore()
    static let idPrefix = Song.localIDPrefix

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
            return Song(id: songID, title: file.deletingPathExtension().lastPathComponent, artist: "")
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
}
