//
//  MacAudioEngine.swift
//  musicMac
//

import Foundation
import AVFoundation
import Combine
import MediaPlayer
import AppKit

class MacAudioEngine: ObservableObject {
    static let shared = MacAudioEngine()
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    
    @Published var isPlaying = false
    @Published var currentSong: MacSong?
    @Published var currentTime: TimeInterval = 0
    @Published var queue: [MacSong] = []
    
    init() {
        setupRemoteTransportControls()
    }
    
    func play(song: MacSong, queue: [MacSong]) {
        self.queue = queue
        self.currentSong = song
        
        let playerItem = AVPlayerItem(url: song.url)
        if player == nil {
            player = AVPlayer(playerItem: playerItem)
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }
        
        player?.play()
        isPlaying = true
        setupTimeObserver()
        updateNowPlayingInfo()
        
        NotificationCenter.default.addObserver(self, selector: #selector(trackDidFinish), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
    }
    
    // MARK: - Queue Injection (Right Click Features)
    
    func playNext(song: MacSong) {
        if queue.isEmpty && !isPlaying { play(song: song, queue: [song]); return }
        
        // Find current position and insert immediately after
        if let current = currentSong, let index = queue.firstIndex(of: current) {
            queue.insert(song, at: index + 1)
        } else {
            queue.insert(song, at: 0)
        }
    }
    
    func playNext(songs: [MacSong]) {
        if queue.isEmpty && !isPlaying { if let first = songs.first { play(song: first, queue: songs) }; return }
        if let current = currentSong, let index = queue.firstIndex(of: current) {
            queue.insert(contentsOf: songs, at: index + 1)
        } else {
            queue.insert(contentsOf: songs, at: 0)
        }
    }
    
    func playLater(song: MacSong) {
        if queue.isEmpty && !isPlaying { play(song: song, queue: [song]); return }
        queue.append(song)
    }
    
    func playLater(songs: [MacSong]) {
        if queue.isEmpty && !isPlaying { if let first = songs.first { play(song: first, queue: songs) }; return }
        queue.append(contentsOf: songs)
    }
    
    // MARK: - Playback Controls
    
    func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        updateNowPlayingInfo()
    }
    
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
        player?.seek(to: cmTime)
        updateNowPlayingInfo()
    }
    
    private func setupTimeObserver() {
        if let observer = timeObserver { player?.removeTimeObserver(observer) }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 1000)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
    }
    
    @objc private func trackDidFinish() {
        guard let current = currentSong, let index = queue.firstIndex(of: current) else {
            isPlaying = false; updateNowPlayingInfo(); return
        }
        
        if index + 1 < queue.count {
            play(song: queue[index + 1], queue: queue)
        } else {
            isPlaying = false; updateNowPlayingInfo()
        }
    }
    
    // MARK: - Mac "Now Playing" Integration
    private func setupRemoteTransportControls() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.addTarget { [weak self] _ in self?.togglePlayPause(); return .success }
        cc.pauseCommand.addTarget { [weak self] _ in self?.togglePlayPause(); return .success }
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent { self?.seek(to: event.positionTime); return .success }
            return .commandFailed
        }
    }
    
    private func updateNowPlayingInfo() {
        guard let song = currentSong else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: song.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player?.currentTime().seconds ?? 0.0,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        
        if let nsImage = song.artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: nsImage.size) { _ in nsImage }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
