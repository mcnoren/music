//
//  AudioManager.swift
//  music
//

#if os(iOS)

import AVFoundation
import MediaPlayer
import SwiftUI
import Combine
import LiveKitWebRTC

class AudioManager: NSObject, ObservableObject {
    static let shared = AudioManager()
    
    // MARK: - Apple Music Engine
    // The System Music Player (Handles Cloud, DRM, and Queue)
    let player = MPMusicPlayerController.applicationQueuePlayer
    @Published var currentSong: MPMediaItem?
    @Published var queue: [MPMediaItem] = []
    @Published var originalQueue: [MPMediaItem] = []
    @Published var currentIndex: Int = 0
    @Published var preventAutoAdvance: Bool = false
    
    // MARK: - Local Files Engine
    @Published var currentLocalSong: LocalSong?
    @Published var localQueue: [LocalSong] = []
    
    // CHANGE to AVQueuePlayer
    var localPlayer: AVQueuePlayer?
    
    // Add this to hold the observer we created
    var cancellables = Set<AnyCancellable>()
    
    // MARK: - Shared Playback State
    @Published var isPlaying = false
    @Published var isStreamLoading = false
    @Published var isSeeking = false // <--- ADD THIS
    @Published var isShuffled = false
    @Published var isLooping = false
    @Published var playbackRate: Float = 1.0
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    
    @Published var isLiked: Bool = false
    var onToggleFavorite: (() -> Void)?
    
    @Published var remoteQueue: [RemoteSongDTO] = []
    @Published var currentRemoteDTO: RemoteSongDTO?
    var tempMetadataCache: [String: DownloadMetadataPayload] = [:]
    
    private var timer: Timer?
    private var isSkipping = false
    
    // MARK: - Lyrics State
    @Published var currentActiveLyric: String? = nil
    var cachedSongLyrics: [SyncedLyricLine] = []
    
    // MARK: - Unified UI Helpers
    var displayTitle: String {
        if isStreamLoading { return "Loading..." } // <--- SHOW LOADING
        if let currentRemote = currentRemoteDTO, currentLocalSong == nil { return currentRemote.title }
        return currentLocalSong?.title ?? currentSong?.title ?? "Not Playing"
    }
    
    var displayArtist: String {
        if isStreamLoading { return "" } // <--- LEAVE BLANK UNTIL LOADED
        if let currentRemote = currentRemoteDTO, currentLocalSong == nil { return currentRemote.artist }
        return currentLocalSong?.artist ?? currentSong?.artist ?? "Unknown Artist"
    }
    
    func displayArtwork(size: CGSize) -> UIImage? {
        if isStreamLoading { return nil } // <--- SHOW DEFAULT ICON UNTIL LOADED
        
        if let currentRemote = currentRemoteDTO, currentLocalSong == nil {
            if let data = currentRemote.artworkData { return UIImage(data: data) }
            if let liveData = MultipeerManager.shared.remoteLibrary.first(where: { $0.id == currentRemote.id })?.artworkData {
                return UIImage(data: liveData)
            }
            if let liveData = MultipeerManager.shared.remoteContextQueue.first(where: { $0.id == currentRemote.id })?.artworkData {
                return UIImage(data: liveData)
            }
            return nil
        }
        if let local = currentLocalSong, let data = local.artworkData { return UIImage(data: data) }
        return currentSong?.artwork?.image(at: size)
    }
    
    override init() {
        super.init()
        setupNotifications()
        setupRemoteTransportControls()
        setupAudioSession()
        
        // Sync initial system state to app state
        self.player.repeatMode = .none
        self.player.shuffleMode = .off
        
        // Listen for WebRTC Stream Handshake
        NotificationCenter.default.addObserver(forName: NSNotification.Name("WebRTCStreamReady"), object: nil, queue: .main) { notification in
            if let meta = notification.object as? DownloadMetadataPayload {
                self.tempMetadataCache[meta.fileName] = meta
                self.updateLockScreenInfo()
            }
        }
    }
    
    deinit {
        player.endGeneratingPlaybackNotifications()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category. Error: \(error)")
        }
    }
    
    private func setupNotifications() {
        player.beginGeneratingPlaybackNotifications()
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppleMusicStateChange), name: .MPMusicPlayerControllerPlaybackStateDidChange, object: player)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppleMusicNowPlayingChange), name: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player)
    }
    
    // MARK: - Local Playback Controls
    func play(localSong: LocalSong, queue: [LocalSong] = [], isStream: Bool = false) {
        if !isStream { self.currentRemoteDTO = nil; self.remoteQueue = [] }
        player.pause(); currentSong = nil
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default); try AVAudioSession.sharedInstance().setActive(true) } catch { }
        
        self.localQueue = queue.isEmpty ? [localSong] : queue
        self.currentLocalSong = localSong
        
        let item = AVPlayerItem(url: localSong.url)
        configureItemOffsets(item, duration: localSong.duration)
        
        if localPlayer == nil {
            localPlayer = AVQueuePlayer(playerItem: item)
            setupQueueObserver()
        } else {
            localPlayer?.removeAllItems()
            if localPlayer?.canInsert(item, after: nil) == true { localPlayer?.insert(item, after: nil) }
        }
        
        if #available(iOS 15.0, *) { localPlayer?.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible }
        localPlayer?.play()
        
        self.isPlaying = true
        self.duration = localSong.duration
        self.currentTime = UserDefaults.standard.double(forKey: "globalStartOffset")
        self.cachedSongLyrics = localSong.syncedLyrics ?? []
        
        startTimer()
        updateLockScreenInfo()
        
        // INSTANT GAPLESS SETUP: Load the next item immediately
        if let currentIndex = self.localQueue.firstIndex(of: localSong), currentIndex + 1 < self.localQueue.count {
            let nextSong = self.localQueue[currentIndex + 1]
            let nextItem = AVPlayerItem(url: nextSong.url)
            configureItemOffsets(nextItem, duration: nextSong.duration)
            if localPlayer?.canInsert(nextItem, after: nil) == true { localPlayer?.insert(nextItem, after: nil) }
        }
    }
    
    @objc private func localTrackDidFinish() {
        if preventAutoAdvance {
            isPlaying = false
            return
        }
        next()
    }
    
    // MARK: - Apple Music Playback Controls
    func play(song: MPMediaItem, queue: [MPMediaItem] = []) {
        self.currentRemoteDTO = nil
        self.remoteQueue = []
        
        localPlayer?.pause() // Safely pause Local Files engine
        currentLocalSong = nil // Clear Local UI state
        
        self.queue = queue.isEmpty ? [song] : queue
        self.originalQueue = self.queue
        self.currentSong = song
        
        let descriptor = MPMusicPlayerMediaItemQueueDescriptor(itemCollection: MPMediaItemCollection(items: self.queue))
        player.setQueue(with: descriptor)
        player.nowPlayingItem = song
        player.play()
        
        self.isPlaying = true
        self.duration = song.playbackDuration
        self.currentTime = 0
        
        let startOffset = UserDefaults.standard.double(forKey: "globalStartOffset")
        if startOffset > 0 {
            player.currentPlaybackTime = startOffset
            self.currentTime = startOffset
        }
        
        startTimer()
    }
    
    func play(remoteSong: RemoteSongDTO, queue: [RemoteSongDTO]) {
        // Unify the entry points
        playStream(remoteSong: remoteSong, queue: queue)
    }
    
    func handleStreamFileReady(fileName: String, url: URL) {
        Task {
            guard let currentRemote = self.currentRemoteDTO else { return }
            let meta = self.tempMetadataCache[fileName]
            
            // Prevent old skipped streams from playing if the user tapped 'next' very fast
            guard meta?.title == currentRemote.title else { return }
            
            let asset = AVAsset(url: url)
            var actualDuration: TimeInterval = 0
            var hqArtworkData: Data? = currentRemote.artworkData // Fallback to thumbnail
            
            do {
                // 1. Wait for accurate duration to fix the 1-second scrub bar bug
                actualDuration = try await asset.load(.duration).seconds
                
                // 2. Extract the high-quality embedded artwork natively from the file
                if let metadata = try? await asset.load(.commonMetadata) {
                    for item in metadata {
                        if item.commonKey?.rawValue == "artwork" {
                            hqArtworkData = try await item.load(.dataValue)
                            break
                        }
                    }
                }
            } catch {
                print("Failed to extract stream metadata: \(error)")
            }
            
            // Inside AudioManager.swift -> handleStreamFileReady
            let tempSong = LocalSong(
                id: currentRemote.id,
                url: url,
                title: currentRemote.title,
                artist: currentRemote.artist,
                album: currentRemote.album,
                duration: actualDuration,
                artworkData: hqArtworkData,
                trackNumber: meta?.trackNumber ?? 0,
                lyrics: meta?.lyrics,
                // THIS LINE forces the stream to check the global database for lyrics
                syncedLyrics: LibraryManager.shared.syncedLyrics[currentRemote.id]?.lines ?? meta?.syncedLyrics
            )
            
            // 3. Jump back to the main thread to safely start playback
            await MainActor.run {
                self.play(localSong: tempSong, queue: [], isStream: true)
            }
        }
    }
    
    // MARK: - Shared Controls
    func togglePlayPause() {
        // FIX: Add remote check
        if currentLocalSong != nil || currentRemoteDTO != nil {
            if isPlaying { localPlayer?.pause(); isPlaying = false }
            else { localPlayer?.play(); isPlaying = true }
        } else {
            if player.playbackState == .playing { player.pause(); isPlaying = false }
            else { player.play(); isPlaying = true }
        }
        updateLockScreenInfo()
    }
    
    func next() {
        if currentRemoteDTO != nil {
            if currentIndex + 1 < remoteQueue.count {
                if localPlayer?.items().count ?? 0 > 1 {
                    localPlayer?.advanceToNextItem()
                } else {
                    playStream(remoteSong: remoteQueue[currentIndex + 1], queue: remoteQueue)
                }
            } else {
                localPlayer?.pause()
                isPlaying = false
            }
            return
        }
        
        if currentLocalSong != nil {
            if currentIndex + 1 < localQueue.count {
                if localPlayer?.items().count ?? 0 > 1 {
                    localPlayer?.advanceToNextItem()
                } else {
                    play(localSong: localQueue[currentIndex + 1], queue: localQueue)
                }
            } else {
                localPlayer?.pause()
                isPlaying = false
            }
            return
        }
        
        player.skipToNextItem()
    }

    func previous() {
        let startOffset = UserDefaults.standard.double(forKey: "globalStartOffset")
        let seekTime = CMTime(seconds: startOffset, preferredTimescale: 1000)
        
        if currentRemoteDTO != nil {
            if currentTime > (startOffset + 3.0) {
                localPlayer?.seek(to: seekTime)
            } else if currentIndex > 0 {
                playStream(remoteSong: remoteQueue[currentIndex - 1], queue: remoteQueue)
            } else {
                localPlayer?.seek(to: seekTime)
            }
            return
        }
        
        if currentLocalSong != nil {
            if currentTime > (startOffset + 3.0) {
                localPlayer?.seek(to: seekTime)
            } else if currentIndex > 0 {
                play(localSong: localQueue[currentIndex - 1], queue: localQueue)
            } else {
                localPlayer?.seek(to: seekTime)
            }
            return
        }
        
        if player.currentPlaybackTime > (startOffset + 3.0) {
            if startOffset > 0 { player.currentPlaybackTime = startOffset } else { player.skipToBeginning() }
        } else {
            player.skipToPreviousItem()
        }
    }
    
    func seek(to time: TimeInterval) {
        self.isSeeking = true
        self.currentTime = time
        self.updateLockScreenInfo()
        
        if currentLocalSong != nil || currentRemoteDTO != nil {
            let targetTime = CMTime(seconds: time, preferredTimescale: 1000)
            
            // FIX 2: Prevent instant skipping when scrubbing to the end
            if let currentItem = localPlayer?.currentItem {
                let endOffset = UserDefaults.standard.double(forKey: "globalEndOffset")
                let cutoffTime = max(1.0, self.duration - max(0.0, endOffset))
                
                // If the user scrubs past the gapless transition point,
                // remove the early cutoff so the track plays to the very end.
                if time >= (cutoffTime - 1.0) {
                    currentItem.forwardPlaybackEndTime = .invalid
                }
            }
            
            localPlayer?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                guard let self = self else { return }
                self.isSeeking = false
            }
        } else {
            player.currentPlaybackTime = time
            self.isSeeking = false
        }
    }
    
    func toggleLoop() {
        isLooping.toggle()
        if currentLocalSong == nil {
            player.repeatMode = isLooping ? .one : .none
        }
    }
    
    func toggleShuffle() {
        isShuffled.toggle()
        if currentLocalSong == nil {
            player.shuffleMode = isShuffled ? .songs : .off
        }
    }
    
    func setPlaybackSpeed(_ speed: Float) {
        playbackRate = speed
        if currentLocalSong != nil {
            if isPlaying { localPlayer?.rate = speed }
        }
    }
    
    private func startTimer() {
        // 1. Initial Engine Read
        if let lp = self.localPlayer, (self.currentLocalSong != nil || self.currentRemoteDTO != nil) {
            if !self.isSeeking {
                let sec = lp.currentTime().seconds
                if !sec.isNaN && !sec.isInfinite { self.currentTime = sec }
            }
            if let remote = self.currentRemoteDTO {
                self.duration = remote.duration
            } else if let sec = lp.currentItem?.duration.seconds, !sec.isNaN, !sec.isInfinite, sec > 0 {
                self.duration = sec
            }
        } else {
            if !self.isSeeking {
                let sec = self.player.currentPlaybackTime
                if !sec.isNaN && !sec.isInfinite { self.currentTime = sec }
            }
            self.duration = self.player.nowPlayingItem?.playbackDuration ?? 0
        }
        
        timer?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // FIX 1: Do not fight the user's scrub bar if AVPlayer is buffering network data!
            if !self.isSeeking {
                if let lp = self.localPlayer, (self.currentLocalSong != nil || self.currentRemoteDTO != nil) {
                    let sec = lp.currentTime().seconds
                    if !sec.isNaN && !sec.isInfinite { self.currentTime = sec }
                } else {
                    let sec = self.player.currentPlaybackTime
                    if !sec.isNaN && !sec.isInfinite { self.currentTime = sec }
                }
            }
            
            // 2. Handle active lyric highlighting
            if !self.cachedSongLyrics.isEmpty {
                if let activeLine = self.cachedSongLyrics.last(where: { $0.startTime <= self.currentTime && (self.currentTime <= ($0.endTime ?? .infinity)) }) {
                    if self.currentActiveLyric != activeLine.text {
                        self.currentActiveLyric = activeLine.text
                    }
                } else {
                    self.currentActiveLyric = nil
                }
            } else {
                self.currentActiveLyric = nil
            }
            
            // 3. Early Gapless Skips
            let endOffset = UserDefaults.standard.double(forKey: "globalEndOffset")
            let triggerTime = max(1.0, self.duration - max(0.0, endOffset))
            
            // FIX 2: Do not auto-skip if the user just scrubbed to the end and it's still buffering!
            if self.duration > 0 && self.currentTime >= triggerTime && !self.isSeeking && !self.isStreamLoading {
                if self.preventAutoAdvance {
                    if self.isPlaying {
                        if self.currentLocalSong != nil || self.currentRemoteDTO != nil { self.localPlayer?.pause() }
                        else { self.player.pause() }
                        self.isPlaying = false
                    }
                } else {
                    if self.currentLocalSong == nil && self.currentRemoteDTO == nil {
                        if !self.isSkipping {
                            self.isSkipping = true
                            self.next()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.isSkipping = false }
                        }
                    }
                }
            }
            
            // 4. Send payload if casting to Mac
            if MultipeerManager.shared.isCastingToMac {
                let payload = PlaybackSyncPayload(
                    title: self.displayTitle,
                    artist: self.displayArtist,
                    currentTime: self.currentTime,
                    isPlaying: self.isPlaying,
                    currentLyric: self.currentActiveLyric,
                    artworkData: nil,
                    fullSyncedLyrics: nil,
                    isMetadataUpdate: false
                )
                MultipeerManager.shared.sendSyncPayload(payload)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    
    func forceSyncToMac() {
        var artData: Data? = nil
        if let artwork = displayArtwork(size: CGSize(width: 800, height: 800)) {
            artData = artwork.jpegData(compressionQuality: 0.5)
        }
        
        let heavyPayload = PlaybackSyncPayload(
            title: displayTitle,
            artist: displayArtist,
            currentTime: currentTime,
            isPlaying: isPlaying,
            currentLyric: currentActiveLyric,
            artworkData: artData,
            fullSyncedLyrics: cachedSongLyrics,
            isMetadataUpdate: true
        )
        
        MultipeerManager.shared.sendSyncPayload(heavyPayload)
    }
    
    // MARK: - Apple Music Notification Observers
    @objc private func handleAppleMusicStateChange() {
        if currentLocalSong != nil { return } // Ignore if we are playing local downloads
        self.isPlaying = player.playbackState == .playing
    }
    
    @objc private func handleAppleMusicNowPlayingChange() {
        if currentLocalSong != nil { return } // Ignore if we are playing local downloads
        self.currentSong = player.nowPlayingItem
        self.duration = player.nowPlayingItem?.playbackDuration ?? 0
        
        if player.playbackState == .playing {
            startTimer()
        }
    }
    
    // MARK: - Control Center & Lock Screen UI
    func updateLockScreenInfo() {
        if let local = currentLocalSong {
            var info: [String: Any] = [
                MPMediaItemPropertyTitle: local.title,
                MPMediaItemPropertyArtist: local.artist,
                MPMediaItemPropertyAlbumTitle: local.album,
                MPMediaItemPropertyPlaybackDuration: local.duration,
                MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
                MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0.0
            ]
            if let data = local.artworkData, let img = UIImage(data: data) {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            
        // ADD THIS BLOCK TO SUPPORT STREAMING METADATA
        } else if let remote = currentRemoteDTO {
            var info: [String: Any] = [
                MPMediaItemPropertyTitle: remote.title,
                MPMediaItemPropertyArtist: remote.artist,
                MPMediaItemPropertyAlbumTitle: remote.album,
                MPMediaItemPropertyPlaybackDuration: remote.duration, // Note: Might be 0 until loaded
                MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
                MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0.0
            ]
            if let data = remote.artworkData, let img = UIImage(data: data) {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }
    
    // MARK: - Stream Playback Controls
    func playStream(remoteSong: RemoteSongDTO, queue: [RemoteSongDTO]) {
        self.remoteQueue = queue
        self.currentRemoteDTO = remoteSong
        self.currentIndex = queue.firstIndex(where: { $0.id == remoteSong.id }) ?? 0
        
        // 1. CLEANUP: Only keep the current song and the upcoming buffered song alive
        var activeIds = [remoteSong.id]
        if self.currentIndex + 1 < self.remoteQueue.count {
            activeIds.append(self.remoteQueue[self.currentIndex + 1].id)
        }
        WebRTCManager.shared.cleanupOldStreams(keepActiveIds: activeIds)
        
        // Stop any currently playing tracks (Apple Music or local files)
        self.player.pause()
        self.currentSong = nil
        self.currentLocalSong = nil
        
        // SAFELY encode the ID so Swift doesn't return a nil URL
        guard let safeID = remoteSong.id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let customURL = URL(string: "webrtc-stream://stream?id=\(safeID)") else {
            print("❌ iPhone failed to create a valid URL for ID: \(remoteSong.id)")
            return
        }
        
        // UNIFIED METHOD: Always use the custom scheme so AVAssetResourceLoader handles it!
        let asset = AVURLAsset(url: customURL)
        asset.resourceLoader.setDelegate(WebRTCManager.shared, queue: DispatchQueue.main)
        let playerItem = AVPlayerItem(asset: asset)
        
        // Configure and play
        if localPlayer == nil {
            localPlayer = AVQueuePlayer(playerItem: playerItem)
            setupQueueObserver()
        } else {
            localPlayer?.removeAllItems()
            if localPlayer?.canInsert(playerItem, after: nil) == true {
                localPlayer?.insert(playerItem, after: nil)
            }
        }
        
        if #available(iOS 15.0, *) {
            localPlayer?.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        }
        
        localPlayer?.play()
        self.isPlaying = true
        self.duration = remoteSong.duration
        self.isStreamLoading = true
        
        startTimer()
        updateLockScreenInfo()
        
        // Fetch artwork and lyrics from Mac for the player view
        MultipeerManager.shared.sendCommand("REQUEST_ARTWORK:\(remoteSong.id)")
        MultipeerManager.shared.sendCommand("REQUEST_LYRICS:\(remoteSong.id)")
        
        // Pre-buffer the next song for gapless playback
        bufferNextStream(afterIndex: self.currentIndex)
    }

    // NEW HELPER: Pre-buffers the next stream into the AVQueuePlayer
    private func bufferNextStream(afterIndex: Int) {
        guard afterIndex + 1 < self.remoteQueue.count else { return }
        
        let upcomingSong = self.remoteQueue[afterIndex + 1]
        let nextQIndex = afterIndex + 1
        var upcomingItem: AVPlayerItem?
        
        // SAFELY encode the ID here too!
        guard let safeID = upcomingSong.id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let upcomingUrl = URL(string: "webrtc-stream://stream?id=\(safeID)&qIndex=\(nextQIndex)") else {
            print("❌ iPhone failed to create a valid buffering URL for ID: \(upcomingSong.id)")
            return
        }
        
        // UNIFIED METHOD
        let asset = AVURLAsset(url: upcomingUrl)
        asset.resourceLoader.setDelegate(WebRTCManager.shared, queue: DispatchQueue.main)
        upcomingItem = AVPlayerItem(asset: asset)
        
        if let upcomingItem = upcomingItem {
            self.configureItemOffsets(upcomingItem, duration: upcomingSong.duration)
            if self.localPlayer?.canInsert(upcomingItem, after: nil) == true {
                self.localPlayer?.insert(upcomingItem, after: nil)
            }
        }
    }
    
    private func startWebRTCPlayback(metadata: DownloadMetadataPayload) {
        // Cache lyrics and artwork info so FullPlayerView doesn't break
        self.tempMetadataCache[metadata.fileName] = metadata

        // Find the remote song to set it as current playing
        if let foundCurrent = self.remoteQueue.first(where: { $0.title == metadata.title && $0.artist == metadata.artist }) {
            self.currentRemoteDTO = foundCurrent
        }

        // FIX: Use self.currentRemoteDTO directly since `foundCurrent` only exists inside the if-let brackets
        // Create a custom URL Scheme ("webrtc://").
        // Note: AVAssetResourceLoaderDelegate ONLY fires if the URL scheme is unrecognized!
        let url = URL(string: "webrtc-stream://stream?id=\(self.currentRemoteDTO?.id ?? "")")!
        let asset = AVURLAsset(url: url)
        
        // Attach WebRTCManager as the middleman between AVPlayer and the Network
        asset.resourceLoader.setDelegate(WebRTCManager.shared, queue: DispatchQueue.main)

        let item = AVPlayerItem(asset: asset)
        self.localPlayer?.replaceCurrentItem(with: item)
        self.localPlayer?.play()
        self.isPlaying = true
    }
    
    private func setupRemoteTransportControls() {
        let cc = MPRemoteCommandCenter.shared()
        
        cc.playCommand.addTarget { [weak self] _ in self?.togglePlayPause(); return .success }
        cc.pauseCommand.addTarget { [weak self] _ in self?.togglePlayPause(); return .success }
        cc.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        cc.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
        
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: event.positionTime)
                return .success
            }
            return .commandFailed
        }
        
        cc.likeCommand.isEnabled = true
        cc.likeCommand.addTarget { [weak self] _ in
            self?.onToggleFavorite?()
            return .success
        }
        cc.dislikeCommand.isEnabled = true
        cc.dislikeCommand.addTarget { [weak self] _ in
             self?.onToggleFavorite?()
             return .success
        }
    }
    
    // MARK: - Gapless Playback Helpers
    private func configureItemOffsets(_ item: AVPlayerItem, duration: TimeInterval) {
        let startOffset = UserDefaults.standard.double(forKey: "globalStartOffset")
        if startOffset > 0 {
            // Pre-seek the item so when AVQueuePlayer natively transitions to it, it starts instantly at the offset
            item.seek(to: CMTime(seconds: startOffset, preferredTimescale: 1000), completionHandler: nil)
        }
        
        let endOffset = UserDefaults.standard.double(forKey: "globalEndOffset")
        if endOffset > 0 && duration > 0 {
            // Tell AVQueuePlayer exactly when to natively stop this item and gaplessly start the next one
            let endTime = max(1.0, duration - endOffset)
            item.forwardPlaybackEndTime = CMTime(seconds: endTime, preferredTimescale: 1000)
        }
    }
    
    private func setupQueueObserver() {
        cancellables.removeAll()
        
        localPlayer?.publisher(for: \.currentItem)
            .receive(on: RunLoop.main)
            .sink { [weak self] currentItem in
                guard let self = self, let currentItem = currentItem, let urlAsset = currentItem.asset as? AVURLAsset else { return }
                let url = urlAsset.url
                
                // 1. IS IT A STREAM?
                let urlComps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                if let id = urlComps?.queryItems?.first(where: { $0.name == "id" })?.value {
                    
                    let qIndexStr = urlComps?.queryItems?.first(where: { $0.name == "qIndex" })?.value
                    let targetIndex = Int(qIndexStr ?? "") ?? self.remoteQueue.firstIndex(where: { $0.id == id }) ?? -1
                    
                    if self.currentRemoteDTO?.id != id || self.currentIndex != targetIndex {
                        if targetIndex >= 0 && targetIndex < self.remoteQueue.count {
                            self.currentIndex = targetIndex
                            let advancedSong = self.remoteQueue[targetIndex]
                            
                            // 2. CLEANUP: Clear out the song that just finished playing
                            var activeIds = [advancedSong.id]
                            if targetIndex + 1 < self.remoteQueue.count {
                                activeIds.append(self.remoteQueue[targetIndex + 1].id)
                            }
                            WebRTCManager.shared.cleanupOldStreams(keepActiveIds: activeIds)
                            
                            self.currentRemoteDTO = advancedSong
                            self.duration = advancedSong.duration
                            self.isStreamLoading = true
                            self.startTimer()
                            self.updateLockScreenInfo()
                            
                            MultipeerManager.shared.sendCommand("REQUEST_ARTWORK:\(id)")
                            MultipeerManager.shared.sendCommand("REQUEST_LYRICS:\(id)")
                            
                            // FIX: Removed manual `requestStream` calls. AVAssetResourceLoaderDelegate
                            // naturally handles network calls. This stops the buffer-corrupting duplicate request.
                            
                            // Continue the gapless chain for the NEXT song!
                            self.bufferNextStream(afterIndex: self.currentIndex)
                        }
                    }
                }
                // 2. IS IT A LOCAL FILE?
                else {
                    if let advancedSong = self.localQueue.first(where: { $0.url == url }), self.currentLocalSong?.id != advancedSong.id {
                        self.currentLocalSong = advancedSong
                        
                        if let targetIndex = self.localQueue.firstIndex(of: advancedSong) {
                            self.currentIndex = targetIndex
                        }
                        
                        self.duration = advancedSong.duration
                        self.cachedSongLyrics = advancedSong.syncedLyrics ?? []
                        self.startTimer()
                        self.updateLockScreenInfo()
                        
                        if self.currentIndex + 1 < self.localQueue.count {
                            let upcomingSong = self.localQueue[self.currentIndex + 1]
                            let upcomingItem = AVPlayerItem(url: upcomingSong.url)
                            self.configureItemOffsets(upcomingItem, duration: upcomingSong.duration)
                            if self.localPlayer?.canInsert(upcomingItem, after: nil) == true { self.localPlayer?.insert(upcomingItem, after: nil) }
                        }
                    }
                }
            }
            .store(in: &cancellables)
            
        // 3. NEW: OBSERVE BUFFERING COMPLETION & SCRUB STALLS
        localPlayer?.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                if status == .playing {
                    self?.isStreamLoading = false
                    self?.updateLockScreenInfo()
                } else if status == .waitingToPlayAtSpecifiedRate && self?.currentRemoteDTO != nil {
                    // FIX 3: Trigger loading UI if the user scrubs into unbuffered territory
                    // and AVPlayer is forced to wait for network chunks
                    self?.isStreamLoading = true
                }
            }
            .store(in: &cancellables)
    }
}

#endif
