import Foundation
import OtoCore

@MainActor
extension PlayerViewModel {
    // MARK: - User Intent Actions

    public func play(song: Song, sourceTitle: String? = nil) {
        playbackSourceTitle = sourceTitle
        confirmedVideoSelectionID = nil
        cancelCatalogSelection()
        usesRadio = false
        waitsForArtistRadio = false
        queueManager.exitRepeatOne()
        queueManager.setQueue(songs: [song])
        applyEffects(stateMachine.userPlay(song: song))
    }
    public func playWithRadio(song: Song, sourceTitle: String? = nil, isVideo: Bool = false) {
        play(song: song, sourceTitle: sourceTitle)
        if isVideo { confirmedVideoSelectionID = song.id }
        usesRadio = true
        loadRadioQueue(for: song.id)
    }

    public func loadRadioQueue(for videoId: String) {
        radioLoadTask?.cancel()
        let revision = selectionRevision
        radioLoadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if !Task.isCancelled, revision == self.selectionRevision {
                    self.radioLoadTask = nil
                    let generation = self.artistRadioEndGeneration
                    let wasManual = self.artistRadioAdvanceWasManual
                    self.artistRadioEndGeneration = nil
                    self.artistRadioAdvanceWasManual = false
                    if generation == self.stateMachine.currentGeneration,
                       self.stateMachine.userIntent == .playing, self.stateMachine.interruptionState == .active {
                        self.advanceQueue(userInitiated: wasManual, retryArtistRadio: false)
                    }
                }
            }
            do {
                let radioSongs = try await self.catalog.fetchUpNextQueue(videoId: videoId)
                guard !Task.isCancelled, revision == self.selectionRevision, self.usesRadio,
                      self.currentSong?.id == videoId else { return }
                var queuedIDs = Set(self.queueManager.items.map { $0.song.id })
                let remaining = self.waitsForArtistRadio
                    ? radioSongs.filter { queuedIDs.insert($0.id).inserted }
                    : radioSongs.filter { $0.id != videoId }
                if !remaining.isEmpty {
                    self.queueManager.appendQueue(songs: remaining)
                    self.logger.info("Đã nạp \(remaining.count) bài hát Radio Up Next cho video \(videoId)")
                }
            } catch {
                self.logger.warning("Không thể nạp Radio Up Next cho video \(videoId): \(error.localizedDescription)")
            }
        }
    }

    public func playPlaylist(id: String, fallbackSong: Song? = nil) {
        if let fallbackSong { play(song: fallbackSong) }
        cancelCatalogSelection()
        let revision = selectionRevision
        playlistLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let songs = try await self.catalog.fetchPlaylistSongs(playlistId: id)
                guard !Task.isCancelled, revision == self.selectionRevision, !songs.isEmpty else { return }
                self.playQueue(songs: songs, startIndex: 0)
                self.logger.info("Đã nạp và phát danh sách phát \(id) với \(songs.count) bài.")
            } catch {
                self.logger.warning("Không thể nạp playlist \(id): \(error.localizedDescription)")
            }
        }
    }

    /// Bắt đầu phát toàn bộ một Album sau khi tải danh sách bài hát từ YouTube Music theo browseId.
    public func playAlbum(browseId: String) {
        cancelCatalogSelection()
        let revision = selectionRevision
        albumLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let album = try await self.catalog.fetchAlbumDetail(browseId: browseId)
                guard !Task.isCancelled, revision == self.selectionRevision, !album.songs.isEmpty else { return }
                self.playQueue(songs: album.songs, startIndex: 0, sourceTitle: album.title)
                self.logger.info("Đã nạp và phát album \(browseId) với \(album.songs.count) bài.")
            } catch {
                self.logger.warning("Không thể nạp album \(browseId): \(error.localizedDescription)")
            }
        }
    }

    public func playQueue(
        songs: [Song], startIndex: Int = 0, continuesWithRadio: Bool = false, sourceTitle: String? = nil
    ) {
        guard !songs.isEmpty else { return }
        playbackSourceTitle = sourceTitle
        confirmedVideoSelectionID = nil
        cancelCatalogSelection()
        usesRadio = continuesWithRadio
        waitsForArtistRadio = continuesWithRadio
        queueManager.exitRepeatOne()
        queueManager.setQueue(songs: songs, startIndex: startIndex)
        if let targetSong = queueManager.currentSong {
            applyEffects(stateMachine.userPlay(song: targetSong))
            if continuesWithRadio, queueManager.remainingCount <= 2 {
                loadRadioQueue(for: targetSong.id)
            }
        }
    }
    public func playQueueItem(at index: Int) {
        cancelCatalogSelection()
        if let target = queueManager.skipToIndex(index) { applyEffects(stateMachine.userPlay(song: target)) }
    }
    public func resume() { applyEffects(stateMachine.userResume()) }
    public func pause(reason: String = "user") {
        logger.info("""
            Playback pause intent t=\(ProcessInfo.processInfo.systemUptime) \
            source=\(reason, privacy: .public) gen=\(self.stateMachine.currentGeneration)
            """)
        cancelPendingCollectionLoads()
        cancelLoadingWatchdog()
        applyEffects(stateMachine.userPause())
        self.savePlaybackResumePoint()
    }
    /// Khi app quay về foreground: nếu người dùng đang dừng thì bảo đảm engine cũng dừng, không tự phát.
    public func syncIntentAfterForeground() {
        logger.notice("""
            Lifecycle foreground t=\(ProcessInfo.processInfo.systemUptime) \
            intent=\(String(describing: self.stateMachine.userIntent), privacy: .public) \
            gen=\(self.stateMachine.currentGeneration)
            """)
        guard stateMachine.userIntent == .paused, currentSong != nil else { return }
        backend.pause()
    }
    public func togglePlayPause() {
        if shouldShowPauseButton { pause() } else { resume() }
    }
    public func next() { advanceQueue(userInitiated: true) }

    func advanceQueue(userInitiated: Bool, retryArtistRadio: Bool = true) {
        let before = queueManager.snapshot()
        if let nextSong = queueManager.next(userInitiated: userInitiated) {
            cancelPendingCollectionLoads()
            let after = queueManager.snapshot()
            logger.info("""
                Queue advance t=\(ProcessInfo.processInfo.systemUptime) \
                manual=\(userInitiated) mode=\(before.repeatMode.rawValue, privacy: .public) \
                from=\(before.currentIndex ?? -1) to=\(after.currentIndex ?? -1) \
                sameRecording=\(nextSong.id == self.currentSong?.id) gen=\(self.stateMachine.currentGeneration)
                """)
            if !userInitiated, repeatMode == .one, nextSong.id == currentSong?.id {
                logger.info("""
                    Playback repeat-one t=\(ProcessInfo.processInfo.systemUptime) \
                    gen=\(self.stateMachine.currentGeneration)
                    """)
            }
            applyEffects(stateMachine.userPlay(song: nextSong))
            if usesRadio, Self.shouldLoadRadioQueue(
                remainingCount: queueManager.remainingCount, repeatMode: repeatMode, userInitiated: userInitiated
            ) { loadRadioQueue(for: nextSong.id) }
        } else {
            if waitsForArtistRadio, retryArtistRadio, let currentSong, stateMachine.userIntent == .playing {
                if radioLoadTask == nil { loadRadioQueue(for: currentSong.id) }
                artistRadioEndGeneration = stateMachine.currentGeneration
                artistRadioAdvanceWasManual = userInitiated
                return
            }
            // Next khi radio chưa có bài kế không được dừng bài hiện tại hoặc hủy Up Next.
            guard !userInitiated || !usesRadio else { return }
            logger.info("""
                Queue end t=\(ProcessInfo.processInfo.systemUptime) \
                mode=\(before.repeatMode.rawValue, privacy: .public) index=\(before.currentIndex ?? -1)
                """)
            pause(reason: "queueEnd")
            seek(to: 0)
        }
    }
    public func previous() {
        cancelPendingCollectionLoads()
        if currentPosition <= 3.0, let prevSong = queueManager.previous() {
            applyEffects(stateMachine.userPlay(song: prevSong))
        } else {
            seek(to: 0)
        }
    }
    /// Cú vuốt Mini Player luôn chuyển occurrence trong queue; nút Previous giữ quy tắc 3 giây.
    public func swipeToPreviousTrack() {
        cancelPendingCollectionLoads()
        guard let prevSong = queueManager.previous() else { return }
        applyEffects(stateMachine.userPlay(song: prevSong))
    }
    public func seek(to position: TimeInterval) {
        guard position.isFinite else { return }
        let duration = effectiveDuration
        let target = max(0, duration.isFinite && duration > 0 ? min(position, duration) : position)
        applyEffects(stateMachine.userSeek(to: target))
    }
    public func toggleShuffle() { queueManager.toggleShuffle() }
    public func toggleRepeat() {
        let mode = queueManager.toggleRepeat()
        logger.info("""
            Repeat mode t=\(ProcessInfo.processInfo.systemUptime) \
            mode=\(mode.rawValue, privacy: .public) gen=\(self.stateMachine.currentGeneration)
            """)
    }

    func cancelPendingCollectionLoads() {
        playlistLoadTask?.cancel()
        playlistLoadTask = nil
        albumLoadTask?.cancel()
        albumLoadTask = nil
        selectionRevision += 1
        radioLoadTask?.cancel()
        radioLoadTask = nil
        artistRadioEndGeneration = nil
        artistRadioAdvanceWasManual = false
    }

    func cancelCatalogSelection() {
        cancelPendingCollectionLoads()
    }
}

@MainActor
extension PlayerViewModel {
    private struct ResumePoint: Codable {
        let queue: QueueManager.Snapshot
        let position: TimeInterval
        let sourceTitle: String?
        let videoID: String?
    }

    func preparePlaybackResumePoint() async {
        let session = SessionStore.shared
        let generation = session.sessionGeneration
        let scope = await HomeCache.shared.accountScopeKey()
        guard !Task.isCancelled, generation == session.sessionGeneration else { return }
        let key = "oto.playback.resume.v1.\(scope)"
        if let previousKey = self.playbackResumeStorageKey, previousKey != key {
            self.clearPlaybackResumePoint()
            guard self.currentSong == nil else { return }
        }
        self.restorePlaybackResumePoint(storageKey: key)
    }

    func restorePlaybackResumePoint(storageKey key: String) {
        self.playbackResumeStorageKey = key
        guard self.currentSong == nil,
              let data = UserDefaults.standard.data(forKey: key),
              let point = try? JSONDecoder().decode(ResumePoint.self, from: data),
              point.position.isFinite, point.position >= 0,
              let index = point.queue.currentIndex, point.queue.items.indices.contains(index) else { return }
        let song = point.queue.items[index].song
        guard !song.isLocal || LocalMusicStore.file(for: song.id) != nil else { return }
        self.queueManager.restore(point.queue)
        self.playbackSourceTitle = point.sourceTitle
        self.confirmedVideoSelectionID = point.videoID == song.id ? point.videoID : nil
        self.pendingEngineLoad = self.stateMachine.restorePaused(song: song, position: point.position)
        self.clock.pause(at: point.position)
        self.syncPublicState()
    }

    func savePlaybackResumePoint() {
        guard let key = self.playbackResumeStorageKey,
              let index = self.queueManager.currentIndex,
              self.queueManager.currentSong?.id == self.stateMachine.currentSong?.id,
              self.currentPosition.isFinite, self.currentPosition >= 0 else { return }
        let queue = self.queueManager.snapshot()
        guard queue.items.indices.contains(index) else { return }
        let point = ResumePoint(
            queue: queue, position: self.currentPosition,
            sourceTitle: self.playbackSourceTitle, videoID: self.confirmedVideoSelectionID
        )
        if let data = try? JSONEncoder().encode(point) { UserDefaults.standard.set(data, forKey: key) }
    }

    func clearPlaybackResumePoint() {
        if let key = self.playbackResumeStorageKey { UserDefaults.standard.removeObject(forKey: key) }
        self.playbackResumeStorageKey = nil
    }
}
