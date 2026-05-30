import SwiftUI
import MediaPlayer
import Combine

struct WordSyncEditorSheet: View {
    var appleSong: MPMediaItem? = nil
    var localSong: LocalSong? = nil
    var remoteSong: RemoteSongDTO? = nil
    
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var library: LibraryManager
    @Environment(\.dismiss) var dismiss
    
    @State private var workingLines: [SyncedLyricLine] = []
    
    @State private var activeLineIndex: Int = -1
    @State private var activeWordIndex: Int = 0
    @State private var countdown = -1
    @State private var isSyncing = false
    
    var currentWords: [String] {
        guard activeLineIndex >= 0 && activeLineIndex < workingLines.count else { return [] }
        return workingLines[activeLineIndex].text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }
    
    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let mainFontSize: CGFloat = isLandscape ? 44 : 34
            
            NavigationView {
                ZStack {
                    Color(UIColor.systemBackground).ignoresSafeArea()
                    
                    if workingLines.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "music.mic.circle").font(.system(size: 60)).foregroundColor(.gray.opacity(0.5))
                            Text("No line-level sync found. Please do a standard sync first.").multilineTextAlignment(.center).foregroundColor(.gray).padding(.horizontal, 40)
                        }
                    } else if !isSyncing {
                        VStack(spacing: 30) {
                            Text("Word Sync Editor").font(.largeTitle.bold())
                            Text("The lines will advance automatically. Tap along to capture each word. The first word is automatically captured!").font(.headline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 40)
                            
                            Button(action: { startInitialCountdown() }) {
                                Text("Start Word Sync").font(.title2.bold()).foregroundColor(.white).padding(.horizontal, 40).padding(.vertical, 16).background(Color.pink).clipShape(Capsule()).shadow(color: .pink.opacity(0.4), radius: 10, x: 0, y: 5)
                            }
                        }.padding(.top, 40)
                    } else {
                        VStack(spacing: 0) {
                            VStack(spacing: 20) {
                                Spacer()
                                if activeLineIndex < workingLines.count && activeLineIndex >= 0 {
                                    renderActiveLine(fontSize: mainFontSize)
                                    
                                    if activeLineIndex + 1 < workingLines.count {
                                        Text(workingLines[activeLineIndex + 1].text).font(.system(size: mainFontSize, weight: .bold)).scaleEffect(0.6).foregroundColor(.gray.opacity(0.4)).multilineTextAlignment(.center).padding(.horizontal, 20)
                                    }
                                } else if activeLineIndex >= workingLines.count {
                                    Text("Word Sync Complete!").font(.system(size: mainFontSize, weight: .bold)).foregroundColor(.green)
                                    Button("Save & Close") { finishSyncing() }.font(.title2.bold()).foregroundColor(.white).padding(.horizontal, 30).padding(.vertical, 14).background(Color.green).clipShape(Capsule()).padding(.top, 20)
                                }
                                Spacer()
                            }
                            
                            if activeLineIndex < workingLines.count && activeLineIndex >= 0 {
                                VStack(spacing: 16) {
                                    // UPDATED: Added the 2-second Rewind Button
                                    HStack(spacing: 12) {
                                        Button(action: { rewindAndResume(by: 10) }) { Image(systemName: "gobackward.10").font(.title2).foregroundColor(.white).padding().frame(maxWidth: .infinity).background(Color.gray.opacity(0.4)).cornerRadius(12) }
                                        Button(action: { rewindAndResume(by: 5) }) { Image(systemName: "gobackward.5").font(.title2).foregroundColor(.white).padding().frame(maxWidth: .infinity).background(Color.gray.opacity(0.4)).cornerRadius(12) }
                                        Button(action: { rewindAndResume(by: 2) }) {
                                            ZStack {
                                                Image(systemName: "gobackward").font(.title2)
                                                Text("2").font(.system(size: 10, weight: .bold)).offset(y: 1.5)
                                            }
                                            .foregroundColor(.white).padding().frame(maxWidth: .infinity).background(Color.gray.opacity(0.4)).cornerRadius(12)
                                        }
                                    }.padding(.horizontal, 40)
                                    
                                    Button(action: { captureWord() }) {
                                        Text(activeWordIndex < currentWords.count ? "Next Word" : "Waiting...")
                                            .font(.title2.bold()).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 20).background(activeWordIndex < currentWords.count ? Color.pink : Color.pink.opacity(0.4)).cornerRadius(16)
                                    }.padding(.horizontal, 40)
                                }
                                .padding(.top, 20).padding(.bottom, geo.safeAreaInsets.bottom + 20).background(Color(UIColor.secondarySystemBackground).shadow(radius: 10))
                            }
                        }
                    }
                    
                    // UPDATED: Countdown Overlay
                    if countdown > 0 { ZStack { Color.black.opacity(0.8).ignoresSafeArea(); Text("\(countdown)").font(.system(size: 150, weight: .black)).foregroundColor(.white).transition(AnyTransition.scale.combined(with: AnyTransition.opacity)).id(countdown) } }
                }
                .navigationTitle(isLandscape ? "" : "Word Sync")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { if audioManager.isPlaying { audioManager.togglePlayPause() }; dismiss() } } }
                .onAppear { loadExistingSync() }
                .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
                    handleAutoLineAdvancement()
                }
            }.navigationViewStyle(.stack)
        }
    }
    
    // MARK: - Core Logic
    
    func loadExistingSync() {
        let songId = appleSong != nil ? String(appleSong!.persistentID) : (localSong?.id ?? remoteSong?.id ?? "")
        let title = appleSong?.title ?? localSong?.title ?? remoteSong?.title ?? ""
        let artist = appleSong?.artist ?? localSong?.artist ?? remoteSong?.artist ?? ""
        
        if let existingLines = library.getSyncedLyrics(id: songId, title: title, artist: artist), !existingLines.isEmpty {
            self.workingLines = existingLines.map {
                var cleanLine = $0
                cleanLine.wordTimings = []
                return cleanLine
            }
        } else {
            self.workingLines = []
        }
    }
    
    func startInitialCountdown() {
        countdown = 3
        if audioManager.isPlaying { audioManager.togglePlayPause() }
        audioManager.seek(to: 0)
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            withAnimation(.spring()) { countdown -= 1 }
            if countdown == 0 {
                countdown = -1
                timer.invalidate()
                isSyncing = true
                activeLineIndex = -1
                activeWordIndex = 0
                audioManager.seek(to: 0)
                if !audioManager.isPlaying { audioManager.togglePlayPause() }
            }
        }
    }
    
    func handleAutoLineAdvancement() {
        guard isSyncing, !workingLines.isEmpty, countdown <= 0 else { return }
        
        if activeLineIndex >= workingLines.count { return } // Already finished
        
        let time = audioManager.currentTime + 0.4 // Lookahead buffer
        
        // Check End of Song automatically
        if let lastLine = workingLines.last, let endTime = lastLine.endTime, time > endTime + 1.0 {
             if activeLineIndex != workingLines.count {
                 activeLineIndex = workingLines.count
                 UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
             }
             return
        }
        if audioManager.duration > 0 && audioManager.currentTime > audioManager.duration - 0.5 {
             if activeLineIndex != workingLines.count { activeLineIndex = workingLines.count }
             return
        }
        
        var newActiveLine = -1
        for (index, line) in workingLines.enumerated() {
            let nextStartTime = (index + 1 < workingLines.count) ? workingLines[index + 1].startTime : .infinity
            if time >= line.startTime && time < nextStartTime {
                newActiveLine = index
                break
            }
        }
        
        if newActiveLine != activeLineIndex && newActiveLine != -1 {
            activeLineIndex = newActiveLine
            
            // NEW: Auto-capture the first word!
            if activeLineIndex >= 0 && activeLineIndex < workingLines.count {
                let wordsForLine = workingLines[activeLineIndex].text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                
                if !wordsForLine.isEmpty && workingLines[activeLineIndex].text != "[Instrumental]" {
                    let firstWord = wordsForLine[0]
                    let timing = WordTiming(word: firstWord, startTime: workingLines[activeLineIndex].startTime)
                    workingLines[activeLineIndex].wordTimings = [timing]
                    activeWordIndex = 1
                } else {
                    activeWordIndex = 0
                }
            }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            
            // Check if completing the auto-capture finished the entire song
            if activeLineIndex == workingLines.count - 1 && activeWordIndex == currentWords.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    activeLineIndex = workingLines.count
                }
            }
        }
    }
    
    func captureWord() {
        guard activeLineIndex >= 0 && activeLineIndex < workingLines.count, countdown <= 0 else { return }
        
        if activeWordIndex < currentWords.count {
            let wordText = currentWords[activeWordIndex]
            let timing = WordTiming(word: wordText, startTime: audioManager.currentTime)
            
            if workingLines[activeLineIndex].wordTimings == nil {
                workingLines[activeLineIndex].wordTimings = []
            }
            workingLines[activeLineIndex].wordTimings?.append(timing)
            
            activeWordIndex += 1
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            
            // NEW: Automatically complete the sync if this was the very last word
            if activeLineIndex == workingLines.count - 1 && activeWordIndex == currentWords.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    activeLineIndex = workingLines.count
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                }
            }
            
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
    
    // UPDATED: Full Rewind Logic with Countdown Settings Check
    func rewindAndResume(by seconds: TimeInterval) {
        let syncResumeTime = max(0, audioManager.currentTime - seconds)
        
        // Clear word timings that happen *after* the rewind point
        for i in 0..<workingLines.count {
            workingLines[i].wordTimings?.removeAll(where: { $0.startTime >= syncResumeTime })
        }
        
        // Recalculate line
        var newActiveLine = -1
        for (index, line) in workingLines.enumerated() {
            let nextStartTime = (index + 1 < workingLines.count) ? workingLines[index + 1].startTime : .infinity
            if syncResumeTime >= line.startTime && syncResumeTime < nextStartTime {
                newActiveLine = index
                break
            }
        }
        
        activeLineIndex = newActiveLine
        if activeLineIndex >= 0 {
            activeWordIndex = workingLines[activeLineIndex].wordTimings?.count ?? 0
            
            // Ensure first word is recaptured if we rewound directly to the start of the line
            if activeWordIndex == 0 && workingLines[activeLineIndex].text != "[Instrumental]" {
                let wordsForLine = currentWords
                if !wordsForLine.isEmpty {
                    let firstWord = wordsForLine[0]
                    let timing = WordTiming(word: firstWord, startTime: workingLines[activeLineIndex].startTime)
                    workingLines[activeLineIndex].wordTimings = [timing]
                    activeWordIndex = 1
                }
            }
        } else {
            activeWordIndex = 0
        }
        
        let useCountdown = UserDefaults.standard.object(forKey: "rewindCountdown") as? Bool ?? true
        
        if useCountdown {
            countdown = 3
            if syncResumeTime >= 3.0 {
                let audioStartTime = syncResumeTime - 3.0
                audioManager.seek(to: audioStartTime)
                if !audioManager.isPlaying { audioManager.togglePlayPause() }
                
                Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                    withAnimation(.spring()) { countdown -= 1 }
                    if countdown == 0 {
                        countdown = -1
                        timer.invalidate()
                    }
                }
            } else {
                if audioManager.isPlaying { audioManager.togglePlayPause() }
                audioManager.seek(to: syncResumeTime)
                
                Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                    withAnimation(.spring()) { countdown -= 1 }
                    if countdown == 0 {
                        countdown = -1
                        timer.invalidate()
                        if !audioManager.isPlaying { audioManager.togglePlayPause() }
                    }
                }
            }
        } else {
            countdown = -1
            audioManager.seek(to: syncResumeTime)
            if !audioManager.isPlaying { audioManager.togglePlayPause() }
        }
    }
    
    func finishSyncing() {
        if let aSong = appleSong {
            library.saveSyncedLyrics(for: aSong, lines: workingLines)
        } else if let lSong = localSong {
            library.saveSyncedLyrics(id: lSong.id, title: lSong.title, artist: lSong.artist, lines: workingLines)
            if let index = DownloadsManager.shared.downloadedSongs.firstIndex(where: { $0.id == lSong.id }) {
                DownloadsManager.shared.downloadedSongs[index].syncedLyrics = workingLines
            }
            if audioManager.currentLocalSong?.id == lSong.id {
                audioManager.currentLocalSong?.syncedLyrics = workingLines
            }
        } else if let rSong = remoteSong {
            library.saveSyncedLyrics(id: rSong.id, title: rSong.title, artist: rSong.artist, lines: workingLines)
        }
        dismiss()
    }
    
    // MARK: - UI Helpers
    
    func renderActiveLine(fontSize: CGFloat) -> some View {
        var combinedText = Text("")
        let words = currentWords
        
        for (index, word) in words.enumerated() {
            let isCaptured = index < activeWordIndex
            let wordText = Text(word + (index == words.count - 1 ? "" : " "))
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(isCaptured ? .pink : .primary.opacity(0.7))
            
            combinedText = combinedText + wordText
        }
        
        return combinedText
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
    }
}
