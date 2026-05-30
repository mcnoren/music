import SwiftUI
import MediaPlayer
import Combine

// Internal model
struct EditableLine: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval?
    var isUnsynced: Bool
}

enum EditorMode {
    case text
    case sync
}
// MARK: - Text Mode Row
struct LyricTextRow: View {
    @Binding var line: EditableLine
    @Binding var activeTextLineId: UUID?
    @FocusState private var isTextFieldFocused: Bool
    
    var isActive: Bool // <--- NEW: Receives playback state
    
    let onSplit: (String, String) -> Void
    let onDelete: () -> Void
    let onTapText: () -> Void
    
    var isEditing: Bool {
        activeTextLineId == line.id
    }
    
    var body: some View {
        HStack(spacing: 12) {
            
            // 1. LEFT: Trash Can
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onDelete()
            }) {
                Image(systemName: "trash.fill")
                    .font(.headline)
                    .foregroundColor(.red.opacity(0.8))
                    .frame(width: 60, height: 36)
                    .background(Color.red.opacity(0.15))
                    .cornerRadius(6)
            }
            .buttonStyle(BorderlessButtonStyle())
            
            // 2. MIDDLE: Text
            if isEditing {
                // ACTIVE EDIT MODE
                TextField("Empty line...", text: $line.text, axis: .vertical)
                    .font(.system(size: 18, weight: .semibold, design: .default))
                    .focused($isTextFieldFocused)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isTextFieldFocused = true
                        }
                    }
                    .onChange(of: line.text) { newValue in
                        if let newlineRange = newValue.range(of: "\n") {
                            let before = String(newValue[..<newlineRange.lowerBound])
                            let after = String(newValue[newlineRange.upperBound...])
                            onSplit(before, after)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // PASSIVE VIEW MODE
                Text(line.text.isEmpty ? "Empty line..." : line.text)
                    .font(.system(size: 18, weight: .semibold, design: .default))
                    .foregroundColor(line.text.isEmpty ? .gray.opacity(0.5) : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onTapText() }
            }
            
            // 3. RIGHT: Edit / Checkmark
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if isEditing {
                    activeTextLineId = nil // Stop Editing
                } else {
                    activeTextLineId = line.id // Start Editing
                }
            }) {
                if isEditing {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundColor(.green)
                        .frame(width: 60, height: 36)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(6)
                } else {
                    Image(systemName: "pencil")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(width: 60, height: 36)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(6)
                }
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(minHeight: 55)
        .background(isActive ? Color.pink.opacity(0.15) : Color.clear) // <--- NEW: Applies the highlight
    }
}
// MARK: - Sync Mode Row
struct LyricSyncRow: View {
    @Binding var line: EditableLine
    var audioManager: AudioManager
    var isActive: Bool
    
    var onTapText: () -> Void
    var onTimeChange: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            
            // 1. END TIME
            if !line.isUnsynced {
                if let eTime = line.endTime {
                    Text(formatTime(eTime))
                        .font(.caption.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundColor(.orange)
                        .frame(width: 60, height: 36) // REDUCED FROM 75
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(6)
                        .onTapGesture { setEndTime() }
                        .onLongPressGesture(minimumDuration: 0.5) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            line.endTime = nil
                            onTimeChange()
                        }
                } else {
                    Image(systemName: "stopwatch")
                        .font(.headline)
                        .foregroundColor(.gray.opacity(0.4))
                        .frame(width: 60, height: 36) // REDUCED FROM 75
                        .contentShape(Rectangle())
                        .onTapGesture { setEndTime() }
                }
            } else {
                Spacer().frame(width: 60) // REDUCED FROM 75
            }
            
            // 2. TEXT (Middle)
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: 18, weight: .semibold, design: .default))
                .foregroundColor(isActive ? .pink : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    onTapText()
                }
            
            // 3. START TIME
            if line.isUnsynced {
                Image(systemName: "stopwatch")
                    .font(.headline)
                    .foregroundColor(.pink)
                    .frame(width: 60, height: 36) // REDUCED FROM 75
                    .contentShape(Rectangle())
                    .onTapGesture { setStartTime() }
            } else {
                Text(formatTime(line.startTime))
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundColor(.green)
                    .frame(width: 60, height: 36) // REDUCED FROM 75
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(6)
                    .onTapGesture { setStartTime() }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        line.isUnsynced = true
                        line.endTime = nil
                        onTimeChange()
                    }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(minHeight: 55)
        .background(isActive ? Color.pink.opacity(0.15) : Color.clear)
    }
    
    // ... (Keep your existing setStartTime, setEndTime, and formatTime functions here) ...
    private func setStartTime() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        line.startTime = audioManager.currentTime
        line.isUnsynced = false
        onTimeChange()
    }
    
    private func setEndTime() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        line.endTime = audioManager.currentTime
        onTimeChange()
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let m = Int(time) / 60
        let s = Int(time) % 60
        let ms = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, ms)
    }
}
// MARK: - Main Editor Sheet
struct RawLyricsEditorSheet: View {
    @State var appleSong: MPMediaItem? = nil
    @State var localSong: LocalSong? = nil
    @State var remoteSong: RemoteSongDTO? = nil
    
    var audioManager: AudioManager
    var library: LibraryManager
    @Environment(\.dismiss) var dismiss
    
    @State private var editableLines: [EditableLine] = []
    @State private var activeTextLineId: UUID? = nil
    
    @State private var mode: EditorMode = .sync
    @State private var activeLineId: UUID? = nil
    @State private var isSeeking = false
    @State private var localIsPlaying = false
    @State private var countdownString: String = "-0:00"
    @State private var scrollTarget: UUID?
    
    // UPDATE THESE COMPUTED PROPERTIES:
    var songId: String { appleSong != nil ? String(appleSong!.persistentID) : (localSong?.id ?? remoteSong?.id ?? "") }
    var title: String { appleSong?.title ?? localSong?.title ?? remoteSong?.title ?? "" }
    var artist: String { appleSong?.artist ?? localSong?.artist ?? remoteSong?.artist ?? "" }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                
                VStack(spacing: 0) {
                    // MARK: - Top Picker & Paste Button
                    HStack {
                        Picker("Mode", selection: $mode) {
                            Text("Sync Lines").tag(EditorMode.sync)
                            Text("Edit Text").tag(EditorMode.text)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        
                        // Only show Paste button when in Text mode
                        if mode == .text {
                            Button(action: handlePaste) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.title2)
                                    .foregroundColor(.pink)
                                    .padding(.leading, 8)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .zIndex(1)
                    
                    // MARK: - Editor Views
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach($editableLines) { $line in
                                let index = editableLines.firstIndex(where: { $0.id == line.id }) ?? 0
                                
                                // NEW: Wrap the branch in a Group to stabilize the View Identity
                                Group {
                                    if mode == .text {
                                        LyricTextRow(
                                            line: $line,
                                            activeTextLineId: $activeTextLineId,
                                            isActive: activeLineId == line.id, // <--- NEW: Pass highlight state
                                            onSplit: { before, after in handleSplit(at: index, before: before, after: after) },
                                            onDelete: {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    editableLines.removeAll { $0.id == line.id }
                                                }
                                            },
                                            onTapText: {
                                                isSeeking = true
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isSeeking = false }
                                                
                                                var targetTime: TimeInterval = 0
                                                for i in stride(from: index, through: 0, by: -1) {
                                                    if !editableLines[i].isUnsynced {
                                                        targetTime = editableLines[i].startTime
                                                        break
                                                    }
                                                }
                                                
                                                audioManager.seek(to: targetTime)
                                                if !audioManager.isPlaying { audioManager.togglePlayPause() }
                                                updateCountdownString()
                                            }
                                        )
                                    } else {
                                        LyricSyncRow(
                                            line: $line,
                                            audioManager: audioManager,
                                            isActive: activeLineId == line.id,
                                            onTapText: {
                                                isSeeking = true
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isSeeking = false }
                                                
                                                var targetTime: TimeInterval = 0
                                                for i in stride(from: index, through: 0, by: -1) {
                                                    if !editableLines[i].isUnsynced {
                                                        targetTime = editableLines[i].startTime
                                                        break
                                                    }
                                                }
                                                
                                                audioManager.seek(to: targetTime)
                                                if !audioManager.isPlaying { audioManager.togglePlayPause() }
                                                updateCountdownString()
                                            },
                                            onTimeChange: {
                                                cleanupEndTimes()
                                            }
                                        )
                                    }
                                }
                                // The ID and alternating background MUST sit outside the if/else!
                                .background(index % 2 == 0 ? Color(.systemBackground) : Color(.secondarySystemBackground))
                                .id(line.id)
                            }
                        }
                        .padding(.bottom, 120)
                        .scrollTargetLayout()
                    }
                    .scrollPosition(id: $scrollTarget, anchor: .center)
                    .background(Color(.systemBackground))
                }
                
                // MARK: - Compact Liquid Glass Media Bar
                VStack(spacing: 12) {
                    HStack(spacing: 40) {
                        Button(action: {
                            audioManager.seek(to: max(0, audioManager.currentTime - 3))
                            isSeeking = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isSeeking = false }
                            updateCountdownString()
                        }) {
                            ZStack {
                                Image(systemName: "gobackward").font(.title3)
                                Text("3").font(.system(size: 8, weight: .bold)).offset(y: 1.5)
                            }
                            .frame(width: 44, height: 44)
                        }
                        
                        Button(action: {
                            localIsPlaying.toggle()
                            audioManager.togglePlayPause()
                            updateCountdownString()
                        }) {
                            Image(systemName: localIsPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 50))
                        }
                        
                        Button(action: { insertInstrumentalBlock() }) {
                            Image(systemName: "music.note.list").font(.title3)
                                .frame(width: 44, height: 44)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        GeometryReader { geo in
                            let duration = max(audioManager.duration, 1)
                            let progress = max(0, min(1, audioManager.currentTime / duration))
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.gray.opacity(0.3))
                                Capsule().fill(Color.pink).frame(width: geo.size.width * CGFloat(progress))
                            }
                        }
                        .frame(height: 4)
                        
                        Text(countdownString)
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.primary.opacity(0.6))
                    }
                    .padding(.horizontal, 30)
                }
                .foregroundColor(.pink)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
                .background(Material.ultraThin)
                .overlay(
                    Rectangle()
                        .frame(height: 1/UIScreen.main.scale)
                        .foregroundColor(Color.gray.opacity(0.3)),
                    alignment: .top
                )
            }
            .navigationTitle("Line Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.bold()
                }
            }
            .onAppear {
                loadExistingData()
                localIsPlaying = audioManager.isPlaying
                audioManager.preventAutoAdvance = true
                updateCountdownString()
                
                // NEW: Setup the scroll target synchronously before the screen renders
                updateActiveLine()
                if let id = activeLineId {
                    scrollTarget = id
                } else {
                    let time = audioManager.currentTime
                    var fallbackId: UUID? = nil
                    for line in editableLines.reversed() {
                        if !line.isUnsynced && line.startTime <= time {
                            fallbackId = line.id
                            break
                        }
                    }
                    scrollTarget = fallbackId ?? editableLines.first?.id
                }
            }
            .onDisappear {
                // MOVE SAVING HERE: Save only when the sheet is dismissed to fix the lag!
                saveLyrics()
                
                audioManager.preventAutoAdvance = false
                isSeeking = false
                
                if audioManager.duration > 0 && audioManager.currentTime >= (audioManager.duration - 1.0) {
                    audioManager.next()
                }
            }
            .onChange(of: audioManager.isPlaying) { newValue in
                localIsPlaying = newValue
                updateCountdownString()
            }
            .onChange(of: audioManager.currentSong) { newSong in
                if let _ = newSong { reloadLyricsFromCurrentSong() }
            }
            .onChange(of: audioManager.currentLocalSong) { newSong in
                if let _ = newSong { reloadLyricsFromCurrentSong() }
            }
            .onChange(of: audioManager.currentRemoteDTO) { newSong in
                if let _ = newSong { reloadLyricsFromCurrentSong() }
            }
            // REMOVE the `.onChange(of: editableLines) { _ in saveLyrics() }` block entirely!
            .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
                if localIsPlaying { updateCountdownString() }
            }
            // ... (Keep the other existing .onReceive timers)
            .onReceive(Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()) { _ in
                updateActiveLine()
                
                if audioManager.duration > 0 && audioManager.currentTime >= (audioManager.duration - 0.05) {
                    if audioManager.isPlaying {
                        audioManager.togglePlayPause()
                        localIsPlaying = false
                        updateCountdownString()
                    }
                }
            }
        }
    }
    
    private func reloadLyricsFromCurrentSong() {
        // 1. CRITICAL: Save the CURRENT edits before the song fully switches!
        saveLyrics()
        
        // 2. Update the tracking variables to the NEW song
        self.appleSong = audioManager.currentSong
        self.localSong = audioManager.currentLocalSong
        self.remoteSong = audioManager.currentRemoteDTO
        
        // 3. Load the new song's lyrics into the UI
        loadExistingData()
        
        // 4. Reset the scroll position
        updateActiveLine()
        if let id = activeLineId {
            scrollTarget = id
        } else {
            scrollTarget = editableLines.first?.id
        }
    }
    
    private func updateActiveLine() {
        guard mode == .sync, !isSeeking else { return } // 🛑 Stop Jitter while seeking
        let time = audioManager.currentTime
        var latestSyncedIndex: Int? = nil
        
        // Find the most recent line that is explicitly synced
        for (index, line) in editableLines.enumerated() {
            if !line.isUnsynced && line.startTime <= time {
                latestSyncedIndex = index
            }
        }
        
        if let idx = latestSyncedIndex {
            let activeLine = editableLines[idx]
            if let end = activeLine.endTime, time > end {
                if activeLineId != nil { activeLineId = nil }
            } else {
                if activeLineId != activeLine.id { activeLineId = activeLine.id }
            }
        } else {
            if activeLineId != nil { activeLineId = nil }
        }
    }
    
    private func cleanupEndTimes() {
        for i in 0..<(editableLines.count - 1) {
            if let eTime = editableLines[i].endTime, !editableLines[i+1].isUnsynced {
                // If end time is identical or within 50ms of the next start time, delete it
                if abs(eTime - editableLines[i+1].startTime) < 0.05 {
                    editableLines[i].endTime = nil
                }
            }
        }
    }
    
    private func loadExistingData() {
        if let existing = library.getSyncedLyrics(id: songId, title: title, artist: artist), !existing.isEmpty {
            editableLines = existing.map { EditableLine(text: $0.text, startTime: $0.startTime, endTime: $0.endTime, isUnsynced: $0.isUnsynced ?? false) }
        } else {
            let fallbackLyrics = appleSong?.lyrics ?? localSong?.lyrics ?? (remoteSong != nil ? library.customRawLyrics[remoteSong!.id] : nil)
            if let raw = library.getRawLyrics(id: songId, fallback: fallbackLyrics), !raw.isEmpty {
                let lines = raw.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                editableLines = lines.map { EditableLine(text: $0, startTime: 0, endTime: nil, isUnsynced: true) }
            } else {
                editableLines = [EditableLine(text: "", startTime: 0, endTime: nil, isUnsynced: true)]
            }
        }
    }
    
    private func handleSplit(at index: Int, before: String, after: String) {
        editableLines[index].text = before
        let inheritedTime = editableLines[index].startTime
        let newLine = EditableLine(text: after, startTime: inheritedTime, endTime: nil, isUnsynced: true)
        editableLines.insert(newLine, at: index + 1)
        
        // <--- UPDATE THIS LAST LINE --->
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { activeTextLineId = newLine.id }
    }
    
    private func handlePaste() {
        guard let pasteString = UIPasteboard.general.string else { return }
        
        // Use .newlines to safely handle both Mac (\n) and Windows (\r\n) formats
        let newLines = pasteString
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } // This safely deletes double-enters
            .map { EditableLine(text: $0, startTime: 0, endTime: nil, isUnsynced: true) }
        
        if !newLines.isEmpty {
            self.editableLines = newLines
        }
    }
    
    private func saveLyrics() {
        let finalLines = editableLines.map { line in
            SyncedLyricLine(text: line.text, startTime: line.startTime, endTime: line.endTime, wordTimings: nil, isUnsynced: line.isUnsynced ? true : nil)
        }
        if let aSong = appleSong {
            library.saveSyncedLyrics(for: aSong, lines: finalLines)
        } else if let lSong = localSong {
            library.saveSyncedLyrics(id: lSong.id, title: lSong.title, artist: lSong.artist, lines: finalLines)
            if let index = DownloadsManager.shared.downloadedSongs.firstIndex(where: { $0.id == lSong.id }) {
                DownloadsManager.shared.downloadedSongs[index].syncedLyrics = finalLines
            }
            if audioManager.currentLocalSong?.id == lSong.id { audioManager.currentLocalSong?.syncedLyrics = finalLines }
        } else if let rSong = remoteSong {
            // Save streamed lyrics directly into the local dictionary
            library.saveSyncedLyrics(id: rSong.id, title: rSong.title, artist: rSong.artist, lines: finalLines)
        }
        library.customRawLyrics.removeValue(forKey: songId)
    }
    
    private func insertInstrumentalBlock() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let time = audioManager.currentTime
        
        // Find the first synced line that comes AFTER our current playback time
        if let firstFutureSyncedIndex = editableLines.firstIndex(where: { !$0.isUnsynced && $0.startTime > time }) {
            
            // Check if there are any synced lines before this future one
            let hasPastSynced = editableLines[0..<firstFutureSyncedIndex].contains(where: { !$0.isUnsynced })
            
            if !hasPastSynced {
                // If we are before ALL synced timestamps, insert at the beginning and lock it to 0s
                let newBlock = EditableLine(text: "[Instrumental]", startTime: 0, endTime: nil, isUnsynced: false)
                editableLines.insert(newBlock, at: 0)
            } else {
                // Otherwise, insert it right before the future lyrics (so it falls in the correct chronological spot)
                let newBlock = EditableLine(text: "[Instrumental]", startTime: time, endTime: nil, isUnsynced: false)
                editableLines.insert(newBlock, at: firstFutureSyncedIndex)
            }
        } else {
            // If there are no future synced lines, find the last past synced line and insert it right after
            if let lastPastSyncedIndex = editableLines.lastIndex(where: { !$0.isUnsynced && $0.startTime <= time }) {
                let newBlock = EditableLine(text: "[Instrumental]", startTime: time, endTime: nil, isUnsynced: false)
                editableLines.insert(newBlock, at: lastPastSyncedIndex + 1)
            } else {
                // If the entire song is unsynced, just put it at the top
                let newBlock = EditableLine(text: "[Instrumental]", startTime: 0, endTime: nil, isUnsynced: false)
                editableLines.insert(newBlock, at: 0)
            }
        }
        
        cleanupEndTimes()
    }
    
    private func updateCountdownString() {
        let remaining = max(0, audioManager.duration - audioManager.currentTime)
        guard !remaining.isNaN && !remaining.isInfinite else {
            countdownString = "-0:00"
            return
        }
        let m = Int(remaining) / 60
        let s = Int(remaining) % 60
        countdownString = String(format: "-%d:%02d", m, s)
    }
}
