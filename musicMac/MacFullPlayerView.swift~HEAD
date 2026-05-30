//
//  MacFullPlayerView.swift
//  musicMac
//

import SwiftUI
import AVFoundation
import Combine

struct MacFullPlayerView: View {
    @ObservedObject var audioManager: MacAudioEngine
    @ObservedObject var library: MacLibrary
    @Binding var showFullPlayer: Bool
    
    @State private var showSyncEditor = false
    @State private var showInfoSheet = false
    @State private var lockedMacSong: MacSong? = nil
        
    var body: some View {
        ZStack {
            // Background Blur
            Group {
                if let song = audioManager.currentSong, let artwork = song.artwork {
                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill).blur(radius: 80).overlay(Color.black.opacity(0.5))
                } else { Color.black }
            }.ignoresSafeArea()
            
            VStack {
                HStack(spacing: 16) {
                    Button(action: { showFullPlayer = false }) { Image(systemName: "chevron.down").font(.title2.bold()).foregroundColor(.white).padding(12).background(Circle().fill(Color.black.opacity(0.4))) }.buttonStyle(.plain)
                    Spacer()
                    
                    // NEW: Info Button
                    Button(action: { showInfoSheet = true }) { Image(systemName: "info.circle").font(.title2.bold()).foregroundColor(.white).padding(12).background(Circle().fill(Color.black.opacity(0.4))) }.buttonStyle(.plain)
                    
                    Button(action: { showSyncEditor = true }) { Image(systemName: "pencil").font(.title2.bold()).foregroundColor(.white).padding(12).background(Circle().fill(Color.black.opacity(0.4))) }.buttonStyle(.plain)
                }.padding(20)
                Spacer()
            }.zIndex(10)
            
            HStack(spacing: 0) {
                // Artwork & Controls (Left)
                VStack(spacing: 30) {
                    Spacer()
                    if let song = audioManager.currentSong, let artwork = song.artwork {
                        Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: 400, maxHeight: 400).cornerRadius(20).shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 15)
                    } else {
                        Rectangle().fill(Color.white.opacity(0.1)).frame(width: 400, height: 400).cornerRadius(20).overlay(Image(systemName: "music.note").font(.system(size: 100)).foregroundColor(.white.opacity(0.2)))
                    }
                    
                    VStack(spacing: 20) {
                        VStack(spacing: 8) {
                            Text(audioManager.currentSong?.title ?? "Not Playing").font(.system(size: 32, weight: .bold)).foregroundColor(.white).multilineTextAlignment(.center)
                            Text(audioManager.currentSong?.artist ?? "Unknown Artist").font(.title2).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center)
                        }
                        
                        HStack {
                            Text(formatDuration(audioManager.currentTime)).font(.caption.monospacedDigit()).foregroundColor(.white.opacity(0.7))
                            Slider(value: Binding(get: { audioManager.currentTime }, set: { newValue in audioManager.seek(to: newValue) }), in: 0...(max(1, audioManager.currentSong?.duration ?? 1))).tint(.pink)
                            Text("-" + formatDuration(max(0, (audioManager.currentSong?.duration ?? 0) - audioManager.currentTime))).font(.caption.monospacedDigit()).foregroundColor(.white.opacity(0.7))
                        }.frame(width: 400)
                        
                        HStack(spacing: 40) {
                            Button(action: {}) { Image(systemName: "backward.fill").font(.system(size: 30)).foregroundColor(.white) }.buttonStyle(.plain)
                            Button(action: { audioManager.togglePlayPause() }) { Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 60)).foregroundColor(.white) }.buttonStyle(.plain)
                            Button(action: {}) { Image(systemName: "forward.fill").font(.system(size: 30)).foregroundColor(.white) }.buttonStyle(.plain)
                        }
                    }
                    Spacer()
                }.frame(maxWidth: .infinity)
                
                // Lyrics Viewer (Right)
                if let song = audioManager.currentSong {
                    MacLyricsView(song: song, audioManager: audioManager, library: library).frame(maxWidth: .infinity)
                }
            }
        }
        .onChange(of: showSyncEditor) { isShown in
            if isShown {
                lockedMacSong = audioManager.currentSong
            }
        }
        .sheet(isPresented: $showSyncEditor) {
            if let song = lockedMacSong {
                MacSyncEditorSheet(song: song, audioManager: audioManager, library: library)
            }
        }
        // NEW: Attach the sheet to the ZStack
        .sheet(isPresented: $showInfoSheet) {
            if let song = audioManager.currentSong {
                MacSongInfoSheet(song: song)
            }
        }
    }
    
    func formatDuration(_ duration: TimeInterval) -> String { guard !duration.isNaN && !duration.isInfinite else { return "0:00" }; let m = Int(duration) / 60; let s = Int(duration) % 60; return String(format: "%d:%02d", m, s) }
}

struct MacLyricsView: View {
    let song: MacSong
    @ObservedObject var audioManager: MacAudioEngine
    @ObservedObject var library: MacLibrary
    
    @State private var playbackLineIndex: Int = -1
    
    var processedLyrics: [SyncedLyricLine]? {
        // FIX: Extract .lines from the new wrapper document
        guard let lines = library.syncedLyrics[song.id]?.lines else { return nil }
        var merged: [SyncedLyricLine] = []
        for line in lines {
            if line.text == "[Instrumental]" {
                if !merged.isEmpty, merged.last?.text == "[Instrumental]" {
                    if let newEnd = line.endTime { merged[merged.count - 1].endTime = newEnd }
                    continue
                }
            }
            merged.append(line)
        }
        return merged
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let lines = processedLyrics, !lines.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 20) {
                                ForEach(0..<lines.count, id: \.self) { i in
                                    let isCurrent = (i == playbackLineIndex)
                                    let isPast = (i < playbackLineIndex)
                                    let line = lines[i]
                                    
                                    if line.text == "[Instrumental]" {
                                        Text(isCurrent ? "..." : "•••").font(.largeTitle).foregroundColor(.white.opacity(0.4)).padding(.vertical, 10).id(i)
                                    } else {
                                        Text(line.text)
                                            .font(.system(size: 40, weight: .bold))
                                            .foregroundColor(isCurrent ? .pink : .white)
                                            .multilineTextAlignment(.leading)
                                            .scaleEffect(isCurrent ? 1.0 : 0.6, anchor: .leading)
                                            .opacity(isCurrent ? 1.0 : (isPast ? 0.3 : 0.6))
                                            .blur(radius: isCurrent ? 0 : 1.0)
                                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: playbackLineIndex)
                                            .id(i)
                                            .onTapGesture { audioManager.seek(to: line.startTime) }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 40).padding(.top, geo.size.height * 0.4).padding(.bottom, geo.size.height * 0.5)
                        }
                        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
                            let time = audioManager.currentTime + 0.4
                            var activeL = -1
                            
                            for (index, line) in lines.enumerated() {
                                let nextStartTime = (index + 1 < lines.count) ? lines[index + 1].startTime : .infinity
                                if time >= line.startTime && time < nextStartTime {
                                    activeL = index
                                    break
                                }
                            }
                            
                            if activeL != playbackLineIndex {
                                playbackLineIndex = activeL
                                if activeL >= 0 {
                                    withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { proxy.scrollTo(activeL, anchor: .center) }
                                }
                            }
                        }
                    }
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0.0), .init(color: .black, location: 0.15), .init(color: .black, location: 0.85), .init(color: .clear, location: 1.0)], startPoint: .top, endPoint: .bottom))
                } else if let rawText = song.lyrics, !rawText.isEmpty {
                    ScrollView { Text(rawText).font(.title).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center).padding(.vertical, 80) }
                } else {
                    VStack { Image(systemName: "music.mic").font(.system(size: 60)).foregroundColor(.white.opacity(0.5)); Text("No lyrics available.").foregroundColor(.white.opacity(0.7)) }
                }
            }
        }
    }
}


