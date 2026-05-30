//
//  MacSyncEditorSheet.swift
//  music
//
//  Created by Matthew Noren on 4/21/26.
//


//
//  MacSyncEditorSheet.swift
//  musicMac
//

import SwiftUI

struct MacSyncEditorSheet: View {
    let song: MacSong
    @ObservedObject var audioManager: MacAudioEngine
    @ObservedObject var library: MacLibrary
    @Environment(\.dismiss) var dismiss
    
    @State private var rawLines: [String] = []
    @State private var isSyncing = false
    @State private var countdown = -1
    @State private var syncLineIndex = 0
    @State private var isLineActive = false
    @State private var recordedLines: [SyncedLyricLine] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Lyric Sync Editor").font(.title.bold())
                Spacer()
                Button("Cancel") {
                    if audioManager.isPlaying { audioManager.togglePlayPause() }
                    dismiss()
                }.keyboardShortcut(.escape)
            }
            .padding().background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            ZStack {
                Color(NSColor.windowBackgroundColor).ignoresSafeArea()
                
                if rawLines.isEmpty {
                    VStack { Text("No lyrics found in file metadata.").foregroundColor(.secondary) }
                } else if !isSyncing {
                    VStack(spacing: 20) {
                        Text("Listen to the song and tap along to sync each line to the beat.").font(.headline)
                        Button("Start Syncing") { startInitialCountdown() }.buttonStyle(.borderedProminent).tint(.pink).controlSize(.large)
                        ScrollView { VStack(spacing: 10) { ForEach(rawLines, id: \.self) { line in Text(line).foregroundColor(.secondary) } }.padding() }
                    }.padding(.top, 40)
                } else {
                    VStack {
                        Spacer()
                        if syncLineIndex < rawLines.count {
                            Text(rawLines[syncLineIndex]).font(.system(size: 40, weight: .bold)).foregroundColor(isLineActive ? .pink : .primary).scaleEffect(isLineActive ? 1.0 : 0.8)
                            if syncLineIndex + 1 < rawLines.count { Text(rawLines[syncLineIndex + 1]).font(.system(size: 24)).foregroundColor(.secondary) }
                        } else {
                            Text("Sync Complete!").font(.largeTitle.bold()).foregroundColor(.green)
                            Button("Save & Close") { finishSyncing() }.buttonStyle(.borderedProminent).tint(.green).padding(.top)
                        }
                        Spacer()
                        
                        if syncLineIndex < rawLines.count {
                            HStack(spacing: 20) {
                                Button("Break") { recordBreak() }.buttonStyle(.bordered).controlSize(.large)
                                if !isLineActive {
                                    Button("Start Lyric") { startLyric() }.buttonStyle(.borderedProminent).tint(.pink).controlSize(.large).keyboardShortcut(.space, modifiers: [])
                                } else {
                                    Button("End Lyric") { endLyric() }.buttonStyle(.bordered).controlSize(.large)
                                    Button("Next Lyric") { nextLyric() }.buttonStyle(.borderedProminent).tint(.pink).controlSize(.large).keyboardShortcut(.space, modifiers: [])
                                }
                            }.padding(40).background(Color(NSColor.controlBackgroundColor).shadow(radius: 10))
                        }
                    }
                }
                
                if countdown > 0 {
                    ZStack { Color.black.opacity(0.8).ignoresSafeArea(); Text("\(countdown)").font(.system(size: 150, weight: .black)).foregroundColor(.white).transition(.scale) }
                }
            }
        }
        .frame(width: 800, height: 600)
        .onAppear { loadLyrics() }
    }
    
    func loadLyrics() {
        if let raw = song.lyrics, !raw.isEmpty {
            self.rawLines = raw.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        } else { self.rawLines = [] }
    }
    
    func startInitialCountdown() {
        countdown = 3
        if audioManager.isPlaying { audioManager.togglePlayPause() }
        audioManager.seek(to: 0)
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            withAnimation { countdown -= 1 }
            if countdown == 0 {
                timer.invalidate()
                isSyncing = true
                recordedLines.removeAll()
                syncLineIndex = 0
                isLineActive = false
                audioManager.seek(to: 0)
                if !audioManager.isPlaying { audioManager.togglePlayPause() }
            }
        }
    }
    
    func startLyric() {
        recordedLines.append(SyncedLyricLine(text: rawLines[syncLineIndex], startTime: audioManager.currentTime, endTime: nil))
        isLineActive = true
    }
    
    func endLyric() {
        recordedLines[recordedLines.count - 1].endTime = audioManager.currentTime
        syncLineIndex += 1
        isLineActive = false
        if syncLineIndex >= rawLines.count { finishSyncing() }
    }
    
    func nextLyric() {
        // Removed the line that sets the previous line's endTime
        syncLineIndex += 1
        if syncLineIndex < rawLines.count {
            recordedLines.append(SyncedLyricLine(text: rawLines[syncLineIndex], startTime: audioManager.currentTime, endTime: nil))
        } else {
            finishSyncing()
        }
    }
    
    func recordBreak() {
        let start = isLineActive ? audioManager.currentTime : (recordedLines.last?.endTime ?? audioManager.currentTime)
        if isLineActive {
            recordedLines[recordedLines.count - 1].endTime = start
            syncLineIndex += 1
            isLineActive = false
        }
        recordedLines.append(SyncedLyricLine(text: "[Instrumental]", startTime: start, endTime: nil))
        if syncLineIndex >= rawLines.count { finishSyncing() }
    }
    
    func finishSyncing() {
        library.saveSyncedLyrics(for: song, lines: recordedLines)
        dismiss()
    }
}
