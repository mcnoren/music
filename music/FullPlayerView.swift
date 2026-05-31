//
//  FullPlayerView.swift
//  music
//

import SwiftUI
import MediaPlayer
import AVKit
import Combine

struct FullPlayerView: View {
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var library: LibraryManager
    @ObservedObject var uiState: PlayerUIState
    @ObservedObject var settings: AppSettings
    
    @State private var isDraggingSlider = false
    @State private var sliderValue: Double = 0
    @State private var showSongInfo = false
    @State private var showSyncSheet = false
    @State private var slideOffset: CGFloat = 0
    @State private var showMirroringInstructions = false
    @State private var showRawLyricsEditor = false
    @State private var lockedAppleSong: MPMediaItem? = nil
    @State private var lockedLocalSong: LocalSong? = nil
    @State private var lockedRemoteSong: RemoteSongDTO? = nil
    
    @Environment(\.dismiss) var dismiss
    @State private var dragOffset = CGSize.zero
    
    let playbackSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    let artworkHeightRatio: CGFloat = 0.38
    
    var hasActiveSong: Bool {
        audioManager.currentSong != nil ||
        audioManager.currentLocalSong != nil ||
        audioManager.currentRemoteDTO != nil
    }
    
    var currentSongId: String {
        if let remote = audioManager.currentRemoteDTO { return remote.id }
        if let local = audioManager.currentLocalSong { return local.id }
        if let song = audioManager.currentSong { return String(song.persistentID) }
        return ""
    }
    
    // Safely grab the current album's ID for video art lookup
    var currentAlbumId: String {
        if let remote = audioManager.currentRemoteDTO { return remote.album }
        if let local = audioManager.currentLocalSong { return local.album }
        if let song = audioManager.currentSong { return String(song.albumPersistentID) }
        return ""
    }
    
    var currentOriginalLyrics: String? {
        if let remote = audioManager.currentRemoteDTO { return nil }
        if let local = audioManager.currentLocalSong { return local.lyrics }
        if let song = audioManager.currentSong { return song.lyrics }
        return nil
    }
    
    var activeRawLyrics: String? {
        if let custom = library.customRawLyrics[currentSongId], !custom.isEmpty {
            return custom
        }
        return currentOriginalLyrics
    }
    
    var safeDuration: TimeInterval {
        let d = audioManager.duration
        if d.isNaN || d.isInfinite || d <= 0 {
            if let remote = audioManager.currentRemoteDTO, remote.duration > 0 { return remote.duration }
            if let local = audioManager.currentLocalSong, local.duration > 0 { return local.duration }
            if let apple = audioManager.currentSong { return apple.playbackDuration }
            return 1.0
        }
        return d
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                // MARK: - Unified Background Blur
                Group {
                    if let artwork = audioManager.displayArtwork(size: CGSize(width: 500, height: 500)) {
                        Image(uiImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .blur(radius: 40)
                            .overlay(Color.black.opacity(0.5))
                    } else { Color.black }
                }
                .contentShape(Rectangle())
                
                VStack(spacing: 0) {
                    if !uiState.showLyrics {
                        Spacer().frame(height: max(geometry.safeAreaInsets.top, 20) + 25)
                        Spacer()
                    }
                    
                    // MARK: - Artwork Area
                    ZStack {
                        if hasActiveSong {
                            if uiState.showLyrics {
                                InlineLyricsView(
                                    song: audioManager.currentSong,
                                    audioManager: audioManager,
                                    library: library,
                                    uiState: uiState,
                                    settings: settings,
                                    showRawLyricsEditor: $showRawLyricsEditor,
                                    showSyncSheet: $showSyncSheet,
                                    showFullScreenButton: true,
                                    dragOffset: $dragOffset
                                )
                                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.95)), removal: .opacity.combined(with: .scale(scale: 0.95))))
                            } else {
                                // MARK: - Unified Front Artwork (Fixed Frame Collapsing)
                                Color.clear
                                    .aspectRatio(1.0, contentMode: .fit) // Forces the structural box to be a perfect square
                                    .overlay(
                                        ZStack { // ZStack ensures the inner video/image fills the clear box
                                            if let videoURL = library.albumVideoArt[currentAlbumId] {
                                                AnimatedVideoArtView(videoURL: videoURL, crop: library.albumArtCrops[currentAlbumId])
                                            } else if let artwork = audioManager.displayArtwork(size: CGSize(width: 500, height: 500)) {
                                                Image(uiImage: artwork)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            } else {
                                                ZStack {
                                                    Rectangle().fill(Color.gray.opacity(0.3))
                                                    Image(systemName: "music.note")
                                                        .font(.system(size: 80))
                                                        .foregroundColor(.white.opacity(0.5))
                                                }
                                            }
                                        }
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                                    .frame(height: geometry.size.height * artworkHeightRatio)
                                    .padding(.horizontal, 40)
                                    .onTapGesture {
                                        dismiss()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            NotificationCenter.default.post(
                                                name: NSNotification.Name("NavigateToAlbum"),
                                                object: currentSongId
                                            )
                                        }
                                    }
                                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.95)), removal: .opacity.combined(with: .scale(scale: 0.95))))
                            }
                        } else {
                            Rectangle().fill(Color.gray.opacity(0.3)).aspectRatio(1.0, contentMode: .fit).cornerRadius(16).frame(maxHeight: geometry.size.height * artworkHeightRatio).padding(.horizontal, 40)
                        }
                    }
                    .frame(maxHeight: (uiState.showLyrics && uiState.isLyricsFullScreen) ? .infinity : (uiState.showLyrics ? .infinity : geometry.size.height * artworkHeightRatio))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: uiState.showLyrics)
                    
                    if !uiState.showLyrics { Spacer() }
                    
                    VStack(spacing: 0) {
                        // MARK: - Unified Titles
                        VStack(alignment: .center, spacing: 8) {
                            HStack(alignment: .center, spacing: 6) {
                                if let song = audioManager.currentSong {
                                    Button(action: {
                                        library.toggleFavorite(song: song)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }) {
                                        Image(systemName: library.isSystemFavorite(song: song) ? "star.fill" : "star")
                                            .font(.title3)
                                            .foregroundColor(library.isSystemFavorite(song: song) ? .yellow : .white.opacity(0.6))
                                    }
                                } else {
                                    Image(systemName: "star").font(.title3).opacity(0)
                                }
                                
                                MarqueeText(text: audioManager.displayTitle, font: .title2)
                                    .frame(height: 30)
                                    .foregroundColor(.white)
                                
                                Image(systemName: "star").font(.title3).opacity(0)
                            }
                            .padding(.horizontal, 30)
                            
                            Text(audioManager.displayArtist)
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)
                        }
                        .padding(.bottom, 20)
                        .padding(.top, uiState.showLyrics ? 15 : 0)
                        
                        // MARK: - Scrubbing & Time
                        VStack(spacing: 6) {
                            let currentSafeDuration = safeDuration
                            
                            Slider(
                                value: $sliderValue,
                                in: 0...max(audioManager.duration, 1),
                                onEditingChanged: { editing in
                                    isDraggingSlider = editing
                                    if !editing {
                                        audioManager.seek(to: sliderValue)
                                    }
                                }
                            )
                            .tint(.white)
                            .onChange(of: audioManager.currentTime) { time in
                                if !isDraggingSlider {
                                    let cleanTime = (time.isNaN || time.isInfinite || time < 0) ? 0 : time
                                    sliderValue = min(max(0, cleanTime), max(1, currentSafeDuration))
                                }
                            }
                            
                            HStack {
                                Text(formatTime(audioManager.currentTime))
                                Spacer()
                                Text("-" + formatTime(max(0, audioManager.duration - audioManager.currentTime)))
                            }
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.horizontal, 30)
                        .padding(.bottom, uiState.isLyricsFullScreen ? 40 + geometry.safeAreaInsets.bottom : 20)
                        
                        if !uiState.isLyricsFullScreen {
                            VStack(spacing: 0) {
                                // MARK: - Main Controls
                                HStack(spacing: 45) {
                                    Button(action: { slideOffset = 1; withAnimation(.smooth) { audioManager.previous() } }) { Image(systemName: "backward.fill").font(.system(size: 35)).foregroundColor(.white) }
                                    Button(action: { let impact = UIImpactFeedbackGenerator(style: .medium); impact.impactOccurred(); audioManager.togglePlayPause() }) { Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 75)).foregroundColor(.white).contentTransition(.symbolEffect(.replace)).animation(.snappy(duration: 0.1), value: audioManager.isPlaying) }
                                    Button(action: { slideOffset = -1; withAnimation(.smooth) { audioManager.next() } }) { Image(systemName: "forward.fill").font(.system(size: 35)).foregroundColor(.white) }
                                }.padding(.bottom, 30)
                                
                                // Bottom Toggles
                                HStack(spacing: 25) {
                                    Button(action: { audioManager.toggleLoop() }) { Image(systemName: audioManager.isLooping ? "repeat.1" : "repeat").font(.title3).foregroundColor(audioManager.isLooping ? .green : .white.opacity(0.6)).padding(8).background(audioManager.isLooping ? Color.white.opacity(0.1) : Color.clear).clipShape(Circle()) }
                                    
                                    Button(action: {
                                        let multipeer = MultipeerManager.shared
                                        if multipeer.connectionState != .connected {
                                            let impact = UIImpactFeedbackGenerator(style: .medium)
                                            impact.impactOccurred()
                                            multipeer.startBrowsing()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                                if multipeer.connectionState == .connected {
                                                    multipeer.isCastingToMac = true
                                                    audioManager.forceSyncToMac()
                                                }
                                            }
                                        } else {
                                            multipeer.isCastingToMac.toggle()
                                            if multipeer.isCastingToMac {
                                                audioManager.forceSyncToMac()
                                            } else {
                                                multipeer.sendCommand("STOP_CASTING")
                                            }
                                        }
                                    }) {
                                        Image(systemName: "airplayvideo")
                                            .font(.title3)
                                            .foregroundColor(MultipeerManager.shared.isCastingToMac && MultipeerManager.shared.connectionState == .connected ? .pink : .white.opacity(0.6))
                                            .frame(width: 40, height: 40)
                                    }
                                    
                                    Button(action: { UIImpactFeedbackGenerator(style: .light).impactOccurred(); withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { uiState.showLyrics.toggle() } }) {
                                        Image(systemName: "quote.bubble").font(.title3).foregroundColor(uiState.showLyrics ? .pink : .white.opacity(0.6))
                                    }
                                    
                                    Menu { ForEach(playbackSpeeds, id: \.self) { speed in Button { audioManager.setPlaybackSpeed(speed) } label: { HStack { Text("\(String(format: "%g", speed))x"); if audioManager.playbackRate == speed { Image(systemName: "checkmark") } } } } } label: { Text("\(String(format: "%g", audioManager.playbackRate))x").font(.headline).foregroundColor(audioManager.playbackRate == 1.0 ? .white.opacity(0.6) : .green).frame(minWidth: 40) }
                                    
                                    Button(action: { audioManager.toggleShuffle() }) { Image(systemName: "shuffle").font(.title3).foregroundColor(audioManager.isShuffled ? .green : .white.opacity(0.6)) }
                                    
                                    Button(action: { showSongInfo.toggle() }) { Image(systemName: "info.circle").font(.title3).foregroundColor(.white.opacity(0.6)) }
                                }.padding(.bottom, 40 + geometry.safeAreaInsets.bottom)
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
                .frame(width: geometry.size.width)
                .ignoresSafeArea(.all, edges: .top)
                
                // MARK: - Pull Down Grab Area
                VStack {
                    HStack {
                        Spacer()
                        Color.clear
                            .frame(width: 250, height: 60)
                            .contentShape(Rectangle())
                            .overlay(
                                Capsule().fill(Color.white.opacity(0.3)).frame(width: 40, height: 5),
                                alignment: .top
                            )
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        if value.translation.height > 0 {
                                            dragOffset = value.translation
                                        }
                                    }
                                    .onEnded { value in
                                        if value.translation.height > 100 {
                                            dismiss()
                                        } else {
                                            withAnimation(.spring()) { dragOffset = .zero }
                                        }
                                    }
                            )
                        Spacer()
                    }
                    .padding(.top, max(geometry.safeAreaInsets.top, 20))
                    Spacer()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height).offset(y: dragOffset.height)
            .gesture(DragGesture().onChanged { value in if value.translation.height > 0 { dragOffset = value.translation } }.onEnded { value in if value.translation.height > 100 { dismiss() } else { withAnimation(.spring()) { dragOffset = .zero } } })
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showSongInfo) {
            songInfoSheetContent
        }
        .onChange(of: showSongInfo) { isShown in if isShown { lockCurrentSong() } }
        .onChange(of: showRawLyricsEditor) { isShown in if isShown { lockCurrentSong() } }
        .onChange(of: showSyncSheet) { isShown in if isShown { lockCurrentSong() } }
        .fullScreenCover(isPresented: $showRawLyricsEditor) {
            rawLyricsSheetContent
        }
        .fullScreenCover(isPresented: $showSyncSheet) {
            syncSheetContent
        }
        .alert("Screen Mirroring Required", isPresented: $showMirroringInstructions) {
            Button("Got It", role: .cancel) { }
        } message: {
            Text("To view your lyrics and artwork on the TV, swipe down from the top right of your iPhone to open Control Center, then tap the Screen Mirroring icon.")
        }
        .onAppear {
            self.sliderValue = audioManager.currentTime
        }
        .onChange(of: audioManager.currentTime) { newValue in
            if !isDraggingSlider {
                self.sliderValue = newValue
            }
        }
    }
    
    // MARK: - Extracted Sheet Content
    
    @ViewBuilder
    private var songInfoSheetContent: some View {
        SongInfoSheet(appleSong: lockedAppleSong, localSong: lockedLocalSong, remoteSong: lockedRemoteSong)
    }
    
    @ViewBuilder
    private var rawLyricsSheetContent: some View {
        if let song = lockedAppleSong {
            RawLyricsEditorSheet(appleSong: song, audioManager: audioManager, library: library)
        } else if let localSong = lockedLocalSong {
            RawLyricsEditorSheet(localSong: localSong, audioManager: audioManager, library: library)
        } else if let remoteSong = lockedRemoteSong {
            RawLyricsEditorSheet(remoteSong: remoteSong, audioManager: audioManager, library: library)
        } else {
            Color.black.ignoresSafeArea() // Explicit Fallback
        }
    }
    
    @ViewBuilder
    private var syncSheetContent: some View {
        if let song = lockedAppleSong {
            WordSyncEditorSheet(appleSong: song, audioManager: audioManager, library: library)
        } else if let localSong = lockedLocalSong {
            WordSyncEditorSheet(localSong: localSong, audioManager: audioManager, library: library)
        } else if let remoteSong = lockedRemoteSong {
            WordSyncEditorSheet(remoteSong: remoteSong, audioManager: audioManager, library: library)
        } else {
            Color.black.ignoresSafeArea() // Explicit Fallback
        }
    }
    
    private func lockCurrentSong() {
        lockedAppleSong = audioManager.currentSong
        lockedLocalSong = audioManager.currentLocalSong
        lockedRemoteSong = audioManager.currentRemoteDTO
    }
    
    func formatTime(_ time: TimeInterval) -> String { guard !time.isNaN && !time.isInfinite else { return "0:00" }; let minutes = Int(time) / 60; let seconds = Int(time) % 60; return String(format: "%d:%02d", minutes, seconds) }
}
