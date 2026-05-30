//
//  MacContentView.swift
//  musicMac
//

import SwiftUI
import LiveKitWebRTC
import Foundation

class MacPowerManager {
    static let shared = MacPowerManager()
    var activityInfo: NSObjectProtocol?
    
    func preventSleep() {
        // Keeps the network and processing alive even if the app is backgrounded
        activityInfo = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Serving music streams via WebRTC"
        )
    }
    
    func allowSleep() {
        if let activityInfo = activityInfo {
            ProcessInfo.processInfo.endActivity(activityInfo)
        }
    }
}

// MARK: - Main Content View
struct MacContentView: View {
    @StateObject var library = MacLibrary.shared
    @StateObject var audioManager = MacAudioEngine.shared
    @StateObject var webrtc = WebRTCManager.shared
    
    // Multipeer connectivity manager
    @StateObject var multipeer = MultipeerManager.shared
    
    @State private var selectedSidebarItem: String? = "Songs"
    @State private var navPath = NavigationPath()
    
    @State private var showFullPlayer = false
    @State private var showQueue = false
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var searchText = ""
    
    @State private var songForInfo: MacSong?
    
    // State to control the remote pop-up
    @State private var showRemotePlayer = false
    @State private var showSettings = false
    
    var filteredSongs: [MacSong] {
        if searchText.isEmpty { return library.songs }
        return library.songs.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.artist.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        ZStack {
            NavigationSplitView {
                // MARK: - Left Sidebar
                List(selection: $selectedSidebarItem) {
                    Section("Library") {
                        Label("Songs", systemImage: "music.note").tag("Songs")
                        Label("Albums", systemImage: "square.stack").tag("Albums")
                        Label("Genres", systemImage: "guitars").tag("Genres")
                    }
                    
                    Section("Playlists") {
                        ForEach(library.playlists) { playlist in
                            Label(playlist.name, systemImage: "music.note.list").tag(playlist.id.uuidString)
                        }
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle("Music")
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Button(action: { showNewPlaylistAlert = true }) { Label("New Playlist", systemImage: "plus.circle") }.buttonStyle(.plain).padding()
                        Spacer()
                    }
                }
                
            } detail: {
                // MARK: - Center Content
                NavigationStack(path: $navPath) {
                    ZStack(alignment: .bottom) {
                        Color(NSColor.windowBackgroundColor).ignoresSafeArea()
                        
                        VStack(spacing: 0) {
                            // Custom Search Bar (Confined strictly to Center Content)
                            if selectedSidebarItem == "Songs" || selectedSidebarItem == "Albums" || selectedSidebarItem == "Genres" {
                                HStack {
                                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                                    TextField("Search \(selectedSidebarItem?.lowercased() ?? "library")...", text: $searchText)
                                        .textFieldStyle(.plain)
                                    if !searchText.isEmpty {
                                        Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.buttonStyle(.plain)
                                    }
                                }
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                                .padding(.horizontal).padding(.top, 16).padding(.bottom, 8)
                            }
                            
                            if library.isImporting {
                                ProgressView("Scanning metadata...").frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if library.songs.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "music.note").font(.system(size: 60)).foregroundColor(.gray.opacity(0.5))
                                    Text("No Music Found").font(.title3).foregroundColor(.secondary)
                                    Button("Import Local Files") { library.importFolder() }.buttonStyle(.borderedProminent).tint(.pink)
                                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                if selectedSidebarItem == "Albums" {
                                    MacAlbumGridView(library: library, audioManager: audioManager, songForInfo: $songForInfo, navPath: $navPath, searchText: searchText)
                                } else if selectedSidebarItem == "Genres" {
                                    MacGenreListView(library: library, audioManager: audioManager, songForInfo: $songForInfo, searchText: searchText)
                                } else if let idString = selectedSidebarItem, let uuid = UUID(uuidString: idString), let playlist = library.playlists.first(where: { $0.id == uuid }) {
                                    MacPlaylistDetailView(playlist: playlist, library: library, audioManager: audioManager, songForInfo: $songForInfo)
                                } else {
                                    List(filteredSongs) { song in
                                        MacSongRow(song: song, isPlaying: audioManager.currentSong?.id == song.id)
                                            .contentShape(Rectangle())
                                            .onTapGesture(count: 2) { audioManager.play(song: song, queue: library.songs) }
                                            .contextMenu { SongContextMenu(song: song, library: library, audioManager: audioManager, songForInfo: $songForInfo) }
                                    }
                                    .listStyle(.inset)
                                }
                            }
                        }
                        .padding(.bottom, audioManager.currentSong != nil ? 80 : 0)
                        
                        // Bottom Mini Player
                        if let currentSong = audioManager.currentSong {
                            MacMiniPlayer(audioManager: audioManager, song: currentSong, onExpand: { showFullPlayer.toggle() }, onInfo: { songForInfo = currentSong })
                                .frame(height: 80).background(Material.bar).overlay(Divider(), alignment: .top).transition(.move(edge: .bottom))
                        }
                    }
                    .navigationTitle(getDisplayTitle())
                    .toolbar {
                        // Standard macOS Toolbar Setup
                        ToolbarItem(placement: .primaryAction) {
                            Button(action: { showQueue.toggle() }) {
                                Image(systemName: "sidebar.right")
                            }
                            .help("Toggle Up Next")
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button(action: { library.importFolder() }) {
                                Image(systemName: "arrow.down.doc")
                            }
                            .help("Import Files")
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button(action: { showSettings = true }) {
                                Image(systemName: "gearshape")
                            }
                            .help("Settings")
                        }
                    }
                    .navigationDestination(for: String.self) { albumName in
                        MacAlbumDetailView(albumName: albumName, library: library, audioManager: audioManager, songForInfo: $songForInfo)
                    }
                }
            }
            .onChange(of: selectedSidebarItem) { _ in navPath = NavigationPath(); searchText = "" }
            
            // MARK: - Native Right Sidebar
            .inspector(isPresented: $showQueue) {
                MacQueueView(audioManager: audioManager)
                    .inspectorColumnWidth(min: 250, ideal: 300, max: 450)
            }
            .sheet(isPresented: $showFullPlayer) { MacFullPlayerView(audioManager: audioManager, library: library, showFullPlayer: $showFullPlayer) }
            .sheet(item: $songForInfo) { song in MacSongInfoSheet(song: song) }
            .sheet(isPresented: $showSettings) { MacSettingsView(library: library, showSettings: $showSettings) }
            .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
                TextField("Playlist Name", text: $newPlaylistName)
                Button("Create", action: { if !newPlaylistName.isEmpty { library.createPlaylist(name: newPlaylistName); newPlaylistName = "" } })
                Button("Cancel", role: .cancel, action: { newPlaylistName = "" })
            }
            // MARK: - Multipeer Modifiers
            .onAppear {
                multipeer.startAdvertising()
                
                // ADD THIS: Force the Mac to sit in the Render lobby and listen for the iPhone
                // (Replace "connect()" with whatever your connection function is named in WebRTCManager, e.g., setupWebSocket(), startSignaling(), etc.)
                webrtc.connect()
                
                multipeer.onRequestAlbums = {
                    let grouped = Dictionary(grouping: library.songs, by: { $0.album })
                    return grouped.map { RemoteAlbumSummary(name: $0.key, artist: $0.value.first?.artist ?? "Unknown") }.sorted { $0.name < $1.name }
                }
                
                multipeer.onRequestArtists = {
                    return Array(Set(library.songs.map { $0.artist })).sorted()
                }
                
                // FIXED: Sanitized duration and zeroed out lyrics flags for a minimal payload
                multipeer.onRequestSongsForAlbum = { albumName in
                    return library.songs.filter { $0.album == albumName }.map { song in
                        let safeDuration = (song.duration.isNaN || song.duration.isInfinite) ? 0 : song.duration
                        
                        return RemoteSongDTO(
                            id: song.id,
                            title: song.title,
                            artist: song.artist,
                            album: song.album,
                            artworkData: nil,
                            duration: safeDuration, // Safe duration to prevent JSON crashing
                            genre: song.genre,
                            trackNumber: song.trackNumber,
                            discNumber: song.discNumber,
                            hasRawLyrics: false,    // Stripped for speed
                            hasLyrics: song.lyrics != nil && !song.lyrics!.isEmpty,
                            hasSyncedLyrics: MacLibrary.shared.hasSyncedLyrics(for: song)
                        )
                    }.sorted { ($0.discNumber ?? 1, $0.trackNumber) < ($1.discNumber ?? 1, $1.trackNumber) }
                }
                
                // FIXED: Sanitized duration and zeroed out lyrics flags for a minimal payload
                multipeer.onRequestSongsForArtist = { artistName in
                    return library.songs.filter { $0.artist == artistName }.map { song in
                        let safeDuration = (song.duration.isNaN || song.duration.isInfinite) ? 0 : song.duration
                        
                        return RemoteSongDTO(
                            id: song.id,
                            title: song.title,
                            artist: song.artist,
                            album: song.album,
                            artworkData: nil,
                            duration: safeDuration,
                            genre: "",
                            trackNumber: song.trackNumber,
                            discNumber: song.discNumber,
                            hasRawLyrics: false,
                            hasLyrics: song.lyrics != nil && !song.lyrics!.isEmpty,
                            hasSyncedLyrics: MacLibrary.shared.hasSyncedLyrics(for: song)
                        )
                    }.sorted { $0.title < $1.title }
                }
                
                multipeer.onPeerConnected = {
                    multipeer.syncLyricsDatabase(documents: library.syncedLyrics)
                }
                
                // 1. Send the library text data instantly
                multipeer.onRequestLibrary = {
                    return library.songs.map { song in
                        return RemoteSongDTO(
                            id: song.id,
                            title: song.title,
                            artist: song.artist,
                            album: song.album,
                            artworkData: nil,
                            duration: 0,
                            genre: "",
                            trackNumber: 0,
                            discNumber: nil,
                            hasRawLyrics: false,
                            hasLyrics: song.lyrics != nil && !song.lyrics!.isEmpty,
                            hasSyncedLyrics: MacLibrary.shared.hasSyncedLyrics(for: song)
                        )
                    }
                }
                
                // 2. Send the specific album cover when the iPhone taps on an album
                multipeer.onRequestArtwork = { songId in
                    guard let song = library.songs.first(where: { $0.id == songId }) else { return }
                    
                    let safeAlbumName = song.album.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                    
                    // FIX: Create the path directly
                    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
                    let fileURL = paths[0].appendingPathComponent("MacLibrary_Artwork").appendingPathComponent("\(safeAlbumName).jpg")
                    
                    // Read the image from the hard drive and beam it to the iPhone
                    if let data = try? Data(contentsOf: fileURL) {
                        let payload = ArtworkSyncPayload(songId: songId, artworkData: data)
                        multipeer.sendArtworkPayload(payload)
                    }
                }
                
                // Tell the MultiPeer manager how to play a requested song
                multipeer.onPlayRequestedSong = { songId in
                    if let songToPlay = library.songs.first(where: { $0.id == songId }) {
                        audioManager.play(song: songToPlay, queue: library.songs)
                    }
                }
                
                multipeer.onReceiveLyricsSync = { incomingDocs in
                    library.merge(remoteLyrics: incomingDocs)
                }
                
                multipeer.onDownloadRequestedSong = { songId in
                    if let songToDownload = library.songs.first(where: { $0.id == songId }) {
                        let meta = DownloadMetadataPayload(
                            fileName: songToDownload.url.lastPathComponent,
                            title: songToDownload.title,
                            artist: songToDownload.artist,
                            album: songToDownload.album,
                            lyrics: songToDownload.lyrics,
                            syncedLyrics: library.syncedLyrics[songToDownload.id]?.lines,
                            trackNumber: songToDownload.trackNumber,
                            discNumber: songToDownload.discNumber // NEW: Beam the disc number!
                        )
                        
                        // 2. Send the metadata JSON first
                        if let encoded = try? JSONEncoder().encode(meta),
                           let jsonStr = String(data: encoded, encoding: .utf8) {
                            multipeer.sendCommand("DOWNLOAD_METADATA:\(jsonStr)")
                        }
                        
                        // 3. Send the raw audio file right after
                        multipeer.sendFile(url: songToDownload.url)
                    }
                }
                
                // NEW: Add the Stream Request Handler
                multipeer.onStreamRequestedSong = { songId in
                    if let songToStream = library.songs.first(where: { $0.id == songId }) {
                        let meta = DownloadMetadataPayload(
                            fileName: songToStream.url.lastPathComponent, // Changed
                            title: songToStream.title,                    // Changed
                            artist: songToStream.artist,                  // Changed
                            album: songToStream.album,                    // Changed
                            lyrics: songToStream.lyrics,                  // Changed
                            syncedLyrics: library.syncedLyrics[songToStream.id]?.lines, // Changed
                            trackNumber: songToStream.trackNumber,        // Changed
                            discNumber: songToStream.discNumber           // Changed
                        )
                        if let encoded = try? JSONEncoder().encode(meta),
                           let jsonStr = String(data: encoded, encoding: .utf8) {
                            multipeer.sendCommand("STREAM_METADATA:\(jsonStr)")
                        }
                        
                        // Prefix the resource name so iOS knows not to save it permanently!
                        let streamName = "STREAM_" + songToStream.url.lastPathComponent
                        let hasAccess = songToStream.url.startAccessingSecurityScopedResource()
                        
                        multipeer.sendStream(url: songToStream.url, streamName: streamName)
                        if hasAccess { songToStream.url.stopAccessingSecurityScopedResource() }
                    }
                }
                
                webrtc.onReceiveWebRTCCommand = { command in
                    if command == "REQUEST_LIBRARY" {
                        // Build the library payload
                        let remoteSongs = library.songs.map { song in
                            RemoteSongDTO(
                                id: song.id,
                                title: song.title,
                                artist: song.artist,
                                album: song.album,
                                artworkData: nil, // Send artwork separately on demand to save bandwidth
                                duration: (song.duration.isNaN || song.duration.isInfinite) ? 0 : song.duration,
                                genre: song.genre,
                                trackNumber: song.trackNumber,
                                discNumber: song.discNumber,
                                hasRawLyrics: false,
                                hasLyrics: song.lyrics != nil && !song.lyrics!.isEmpty,
                                hasSyncedLyrics: MacLibrary.shared.hasSyncedLyrics(for: song)
                            )
                        }
                        
                        // Send it back over WebRTC
                        if let encoded = try? JSONEncoder().encode(remoteSongs),
                           let jsonString = String(data: encoded, encoding: .utf8) {
                            webrtc.sendCommandOverWebRTC("LIBRARY_RESPONSE:\(jsonString)")
                        }
                    }
                    
                    if command.starts(with: "PLAY_SONG:") {
                        let songId = String(command.dropFirst(10))
                        if let songToPlay = library.songs.first(where: { $0.id == songId }) {
                            audioManager.play(song: songToPlay, queue: library.songs)
                        }
                    }
                }
            }
            // 1. REPLACED: Listen for the AirPlay casting flag instead of the song title changing
            .onChange(of: multipeer.latestPayload?.isCasting) { isCasting in
                if isCasting == true && !showRemotePlayer {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showRemotePlayer = true
                    }
                } else if isCasting == false && showRemotePlayer {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showRemotePlayer = false
                    }
                }
            }
            .onChange(of: showRemotePlayer) { isShowing in
                if let window = NSApplication.shared.windows.first {
                    let isFullScreen = window.styleMask.contains(.fullScreen)
                    
                    window.toolbar?.isVisible = !isShowing
                    
                    if isShowing && !isFullScreen {
                        window.toggleFullScreen(nil)
                    } else if !isShowing && isFullScreen {
                        window.toggleFullScreen(nil)
                    }
                }
                
                // 2. Tell iOS we stopped casting if the user manually closes the Mac window
                if !isShowing {
                    multipeer.sendCommand("STOP_CASTING")
                }
            }
            
            // MARK: - Full Screen Remote Overlay
            if showRemotePlayer {
                MacRemotePlayerView(multipeer: multipeer, showRemotePlayer: $showRemotePlayer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    func getDisplayTitle() -> String {
        if selectedSidebarItem == "Albums" { return "Albums" }
        if selectedSidebarItem == "Songs" { return "Songs" }
        if selectedSidebarItem == "Genres" { return "Genres" }
        if let idString = selectedSidebarItem, let uuid = UUID(uuidString: idString), let pl = library.playlists.first(where: { $0.id == uuid }) { return pl.name }
        return "Library"
    }
}
// NEW: Helper to safely compress artwork for bulk network transfer
extension NSImage {
    func thumbnailData(size: CGSize = CGSize(width: 60, height: 60)) -> Data? {
        let targetFrame = NSRect(origin: .zero, size: size)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        self.draw(in: targetFrame, from: NSRect(origin: .zero, size: self.size), operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        
        // Compress heavily (0.2) to ensure the payload stays small
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.2])
    }
}

// MARK: - Mac Settings View
struct MacSettingsView: View {
    @ObservedObject var library: MacLibrary
    @Binding var showSettings: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Standard macOS Sheet Header
            HStack {
                Text("Settings").font(.headline)
                Spacer()
                Button("Done") { showSettings = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            
            Divider()
            
            NavigationStack {
                Form {
                    Section(header: Text("Data & Storage").font(.subheadline.bold()).foregroundColor(.secondary)) {
                        NavigationLink("Manage Synced Lyrics") {
                            MacSyncedLyricsStorageView()
                        }
                    }
                }
                .formStyle(.grouped) // Matches the native macOS system settings look
            }
        }
        .frame(width: 500, height: 450)
    }
}

// MARK: - Mac Genre Views
struct MacGenreListView: View {
    @ObservedObject var library: MacLibrary
    @ObservedObject var audioManager: MacAudioEngine
    @Binding var songForInfo: MacSong?
    var searchText: String
    
    var activeGenres: [String] {
        var genres = Set<String>()
        library.songs.forEach { if !$0.genre.isEmpty { genres.insert($0.genre) } }
        var sorted = Array(genres).sorted()
        if !searchText.isEmpty { sorted = sorted.filter { $0.localizedCaseInsensitiveContains(searchText) } }
        return sorted
    }
    
    var body: some View {
        List(activeGenres, id: \.self) { genre in
            NavigationLink(destination: MacGenreDetailView(genre: genre, library: library, audioManager: audioManager, songForInfo: $songForInfo)) {
                HStack {
                    Image(systemName: "guitars").foregroundColor(.pink)
                    Text(genre).font(.body)
                }
                .padding(.vertical, 8)
            }
        }
        .listStyle(.inset)
    }
}

struct MacGenreDetailView: View {
    let genre: String
    @ObservedObject var library: MacLibrary
    @ObservedObject var audioManager: MacAudioEngine
    @Binding var songForInfo: MacSong?
    
    var songs: [MacSong] {
        library.songs.filter { $0.genre == genre }.sorted { $0.title < $1.title }
    }
    
    var body: some View {
        List(songs) { song in
            MacSongRow(song: song, isPlaying: audioManager.currentSong?.id == song.id)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { audioManager.play(song: song, queue: songs) }
                .contextMenu { SongContextMenu(song: song, library: library, audioManager: audioManager, songForInfo: $songForInfo) }
        }
        .listStyle(.inset)
        .navigationTitle(genre)
    }
}

// MARK: - Mac Synced Lyrics Storage View
struct MacSyncedLyricsStorageView: View {
    @ObservedObject var library = MacLibrary.shared
    
    var totalStorageString: String {
        guard let data = try? JSONEncoder().encode(library.syncedLyrics) else { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(data.count))
    }
    
    var sortedKeys: [String] {
        library.syncedLyrics.keys.sorted {
            let date1 = library.syncedLyrics[$0]?.lastModified ?? Date.distantPast
            let date2 = library.syncedLyrics[$1]?.lastModified ?? Date.distantPast
            return date1 > date2
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                Section(header: Text("Storage Info").font(.subheadline.bold()).foregroundColor(.secondary)) {
                    HStack {
                        Text("Total Space Used")
                        Spacer()
                        Text(totalStorageString).foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Synced Songs (\(library.syncedLyrics.count))").font(.subheadline.bold()).foregroundColor(.secondary)) {
                    if library.syncedLyrics.isEmpty {
                        Text("No synced lyrics found.").foregroundColor(.secondary)
                    } else {
                        ForEach(sortedKeys, id: \.self) { key in
                            if let doc = library.syncedLyrics[key] {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(doc.songTitle).font(.headline)
                                        Text(doc.artistName).font(.subheadline).foregroundColor(.secondary)
                                        Text("Last synced: \(doc.lastModified, style: .date)").font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        deleteLyrics(key: key)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.red)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset) // Clean native mac list styling
        }
        .navigationTitle("Synced Lyrics")
    }
    
    private func deleteLyrics(key: String) {
        // 1. Delete from Mac's live memory
        library.syncedLyrics.removeValue(forKey: key)
        
        // 2. Save the wiped state to the Mac's hard drive
        if let encoded = try? JSONEncoder().encode(library.syncedLyrics) {
            UserDefaults.standard.set(encoded, forKey: "MacSyncedLyricsPersistenceKey") // Using your specific Mac key
        }
        
        // 3. Immediately beam the deletion over to the iPhone so the databases stay synchronized
        MultipeerManager.shared.syncLyricsDatabase(documents: library.syncedLyrics)
    }
}

// MARK: - Album Grid View
struct MacAlbumGridView: View {
    @ObservedObject var library: MacLibrary
    @ObservedObject var audioManager: MacAudioEngine
    @Binding var songForInfo: MacSong?
    @Binding var navPath: NavigationPath
    var searchText: String
    
    let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 30) {
                let sortedAlbums = library.albums.keys.sorted()
                ForEach(sortedAlbums.filter { searchText.isEmpty || $0.localizedCaseInsensitiveContains(searchText) }, id: \.self) { albumName in
                    let albumSongs = library.albums[albumName] ?? []
                    if let representative = albumSongs.first {
                        NavigationLink(value: albumName) {
                            VStack(alignment: .leading) {
                                if let img = representative.artwork {
                                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).cornerRadius(10).shadow(radius: 5)
                                } else {
                                    Rectangle().fill(Color.gray.opacity(0.3)).aspectRatio(1.0, contentMode: .fit).cornerRadius(10).overlay(Image(systemName: "music.note").font(.largeTitle))
                                }
                                
                                Text(albumName).font(.headline).lineLimit(1).foregroundColor(.primary)
                                Text(representative.artist).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu { AlbumContextMenu(albumSongs: albumSongs, albumName: albumName, library: library, audioManager: audioManager) }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Album Detail View (Full Page Scrolling & Ordered Tracks)
struct MacAlbumDetailView: View {
    let albumName: String
    @ObservedObject var library: MacLibrary
    @ObservedObject var audioManager: MacAudioEngine
    @Binding var songForInfo: MacSong?
    
    // Auto-sorts tracks by Disc Number, then Track Number exactly as imported
    var albumSongs: [MacSong] {
        (library.albums[albumName] ?? []).sorted(by: {
            let d0 = $0.discNumber ?? 1
            let d1 = $1.discNumber ?? 1
            if d0 == d1 {
                return $0.trackNumber < $1.trackNumber
            }
            return d0 < d1
        })
    }
    
    var totalRunTime: TimeInterval {
        albumSongs.reduce(0) { $0 + $1.duration }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()
            
            // Unified ScrollView makes the entire page scroll as one seamless unit
            ScrollView {
                VStack(spacing: 0) {
                    if let first = albumSongs.first {
                        HStack(spacing: 30) {
                            if let img = first.artwork {
                                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(width: 200, height: 200).cornerRadius(12).shadow(radius: 10)
                            } else {
                                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 200, height: 200).cornerRadius(12).overlay(Image(systemName: "music.note").font(.largeTitle))
                            }
                            
                            VStack(alignment: .leading, spacing: 10) {
                                Text(albumName).font(.system(size: 36, weight: .bold))
                                Text(first.artist).font(.title2).foregroundColor(.pink)
                                
                                Text("\(albumSongs.count) Songs · \(formatRuntime(totalRunTime)) · \(first.genre)")
                                    .font(.headline).foregroundColor(.secondary)
                                
                                HStack {
                                    Button(action: { audioManager.play(song: first, queue: albumSongs) }) {
                                        Label("Play", systemImage: "play.fill")
                                    }.buttonStyle(.borderedProminent).tint(.pink).controlSize(.large)
                                    
                                    Button(action: { audioManager.playNext(songs: albumSongs) }) {
                                        Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                                    }.buttonStyle(.bordered).controlSize(.large)
                                }.padding(.top, 10)
                            }
                            Spacer()
                        }.padding(30)
                    }
                    
                    Divider()
                    
                    // LazyVStack prevents performance drops on huge albums without breaking the unified scroll
                    LazyVStack(spacing: 0) {
                        let groupedByDisc = Dictionary(grouping: albumSongs, by: { $0.discNumber ?? 1 })
                        let sortedDiscs = groupedByDisc.keys.sorted()
                        let showHeaders = sortedDiscs.count > 1 || (sortedDiscs.first ?? 1) > 1
                        
                        ForEach(sortedDiscs, id: \.self) { disc in
                            if showHeaders {
                                HStack {
                                    Text("Disc \(disc)")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .padding(.bottom, 8)
                                
                                Divider().padding(.leading, 20)
                            }
                            
                            if let discSongs = groupedByDisc[disc] {
                                ForEach(discSongs) { song in
                                    MacSongRow(song: song, isPlaying: audioManager.currentSong?.id == song.id)
                                        .padding(.horizontal, 20)
                                        .contentShape(Rectangle())
                                        .onTapGesture(count: 2) { audioManager.play(song: song, queue: albumSongs) }
                                        .contextMenu { SongContextMenu(song: song, library: library, audioManager: audioManager, songForInfo: $songForInfo) }
                                    Divider().padding(.leading, 70)
                                }
                            }
                        }
                    }
                    .padding(.top, 10)
                }
                .padding(.bottom, audioManager.currentSong != nil ? 100 : 20)
            }
        }
        .navigationTitle(albumName)
    }
    
    func formatRuntime(_ duration: TimeInterval) -> String {
        let h = Int(duration) / 3600
        let m = (Int(duration) % 3600) / 60
        if h > 0 { return "\(h) hr \(m) min" }
        return "\(m) min"
    }
}

// MARK: - Playlist Detail View
struct MacPlaylistDetailView: View {
    let playlist: MacPlaylist
    @ObservedObject var library: MacLibrary
    @ObservedObject var audioManager: MacAudioEngine
    @Binding var songForInfo: MacSong?
    
    var playlistSongs: [MacSong] { playlist.songIDs.compactMap { id in library.songs.first(where: { $0.id == id }) } }
    
    var body: some View {
        if playlistSongs.isEmpty {
            VStack {
                Image(systemName: "music.note.list").font(.system(size: 60)).foregroundColor(.gray.opacity(0.5))
                Text("Playlist is empty.").font(.title3).foregroundColor(.secondary).padding(.top)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(playlistSongs) { song in
                MacSongRow(song: song, isPlaying: audioManager.currentSong?.id == song.id)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { audioManager.play(song: song, queue: playlistSongs) }
                    .contextMenu { SongContextMenu(song: song, library: library, audioManager: audioManager, songForInfo: $songForInfo) }
            }.listStyle(.inset)
        }
    }
}

// MARK: - Native Right Sidebar Queue View
struct MacQueueView: View {
    @ObservedObject var audioManager: MacAudioEngine
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if audioManager.queue.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "list.bullet").font(.largeTitle).foregroundColor(.secondary)
                    Text("Queue is empty").foregroundColor(.secondary).padding(.top, 5)
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(Array(audioManager.queue.enumerated()), id: \.offset) { index, song in
                        let isCurrent = (audioManager.currentSong?.id == song.id) && (index == audioManager.queue.firstIndex(of: audioManager.currentSong!) ?? -1)
                        
                        HStack {
                            if isCurrent {
                                Image(systemName: "speaker.wave.2.fill").foregroundColor(.pink).font(.caption)
                            } else {
                                Text("\(index + 1)").font(.caption).foregroundColor(.secondary).frame(width: 15)
                            }
                            
                            VStack(alignment: .leading) {
                                Text(song.title).font(.body).foregroundColor(isCurrent ? .pink : .primary).lineLimit(1)
                                Text(song.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { audioManager.play(song: song, queue: audioManager.queue) }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("Up Next")
    }
}

// MARK: - Context Menus
struct SongContextMenu: View {
    let song: MacSong
    @ObservedObject var library: MacLibrary
    @ObservedObject var audioManager: MacAudioEngine
    @Binding var songForInfo: MacSong?
    var body: some View {
        Button("Play Next") { audioManager.playNext(song: song) }
        Button("Play Later") { audioManager.playLater(song: song) }
        Divider()
        Menu("Add to Playlist") {
            if library.playlists.isEmpty { Text("No Playlists Available").foregroundColor(.secondary) }
            ForEach(library.playlists) { playlist in Button(playlist.name) { library.addSongToPlaylist(song, playlist: playlist) } }
        }
        Divider()
        Button("Get Info") { songForInfo = song }
        Button(role: .destructive) {
            withAnimation { library.deleteSong(song) }
        } label: {
            Label("Delete from Library", systemImage: "trash")
        }
    }
}

struct AlbumContextMenu: View {
    let albumSongs: [MacSong]
    let albumName: String
    @ObservedObject var library: MacLibrary
    @ObservedObject var audioManager: MacAudioEngine
    var body: some View {
        Button("Play Album") { if let first = albumSongs.first { audioManager.play(song: first, queue: albumSongs) } }
        Button("Play Next") { audioManager.playNext(songs: albumSongs) }
        Button("Play Later") { audioManager.playLater(songs: albumSongs) }
        Divider()
        Menu("Add to Playlist") {
            if library.playlists.isEmpty { Text("No Playlists Available").foregroundColor(.secondary) }
            ForEach(library.playlists) { playlist in Button(playlist.name) { library.addAlbumToPlaylist(albumSongs, playlist: playlist) } }
        }
        Button(role: .destructive) {
            withAnimation { library.deleteAlbum(albumName) }
        } label: {
            Label("Delete Album", systemImage: "trash")
        }
    }
}

// MARK: - Mac Song Info Sheet
struct MacSongInfoSheet: View {
    var song: MacSong
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Song Info").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 20) {
                        if let artwork = song.artwork {
                            Image(nsImage: artwork)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 120, height: 120)
                                .cornerRadius(8)
                                .shadow(radius: 4)
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 120, height: 120)
                                .cornerRadius(8)
                                .overlay(Image(systemName: "music.note").font(.largeTitle).foregroundColor(.gray))
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            InfoRow(title: "Title", value: song.title)
                            InfoRow(title: "Artist", value: song.artist)
                            InfoRow(title: "Album", value: song.album)
                            InfoRow(title: "Genre", value: song.genre)
                        }
                    }
                    
                    HStack(spacing: 40) {
                        InfoRow(title: "Track", value: "\(song.trackNumber)")
                        if let disc = song.discNumber {
                            InfoRow(title: "Disc", value: "\(disc)")
                        }
                        InfoRow(title: "Duration", value: formatTime(song.duration))
                    }
                    
                    Divider()
                    
                    Text("Lyrics").font(.headline)
                    if let lyrics = song.lyrics, !lyrics.isEmpty {
                        Text(lyrics)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled) // Allows you to copy/paste lyrics
                    } else {
                        Text("No lyrics available.")
                            .italic()
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct InfoRow: View {
    var title: String
    var value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.body).bold()
        }
    }
}

struct MacSongRow: View {
    let song: MacSong
    let isPlaying: Bool
    
    // Add the library so the row updates when lyrics are synced
    @ObservedObject var library = MacLibrary.shared
    
    var hasSynced: Bool {
        library.hasSyncedLyrics(for: song)
    }
    
    var hasRaw: Bool {
        song.lyrics != nil && !song.lyrics!.isEmpty
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // NEW: Lyric Speech Bubble
            if hasSynced {
                Image(systemName: "quote.bubble.fill").font(.caption).foregroundColor(.pink).frame(width: 16)
            } else if hasRaw {
                Image(systemName: "quote.bubble").font(.caption).foregroundColor(.secondary).frame(width: 16)
            } else {
                Color.clear.frame(width: 16) // Preserves alignment
            }
            
            if song.trackNumber > 0 { Text("\(song.trackNumber)").font(.caption).foregroundColor(.secondary).frame(width: 20, alignment: .trailing) }
            if let img = song.artwork { Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 40, height: 40).cornerRadius(6) }
            else { Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 40, height: 40).cornerRadius(6).overlay(Image(systemName: "music.note").foregroundColor(.gray)) }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.body).fontWeight(isPlaying ? .bold : .regular).foregroundColor(isPlaying ? .pink : .primary)
                Text("\(song.artist) · \(song.album)").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(formatDuration(song.duration)).font(.caption.monospacedDigit()).foregroundColor(.secondary)
        }.padding(.vertical, 4)
    }
    func formatDuration(_ duration: TimeInterval) -> String { let m = Int(duration) / 60; let s = Int(duration) % 60; return String(format: "%d:%02d", m, s) }
}

struct MacMiniPlayer: View {
    @ObservedObject var audioManager: MacAudioEngine
    let song: MacSong
    var onExpand: () -> Void
    var onInfo: () -> Void
    
    var body: some View {
        HStack(spacing: 20) {
            HStack(spacing: 12) {
                if let img = song.artwork { Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 50, height: 50).cornerRadius(6).shadow(radius: 3) }
                VStack(alignment: .leading, spacing: 2) { Text(song.title).font(.headline).lineLimit(1); Text(song.artist).font(.subheadline).foregroundColor(.secondary).lineLimit(1) }
            }.frame(width: 250, alignment: .leading).contentShape(Rectangle()).onTapGesture { onExpand() }
            
            Spacer()
            
            HStack(spacing: 30) {
                Button(action: { audioManager.seek(to: 0) }) { Image(systemName: "backward.fill").font(.title2) }.buttonStyle(.plain)
                Button(action: { audioManager.togglePlayPause() }) { Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 40)) }.buttonStyle(.plain)
                Button(action: { audioManager.seek(to: song.duration) }) { Image(systemName: "forward.fill").font(.title2) }.buttonStyle(.plain)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                // NEW: Info Button on the Mini Player
                Button(action: { onInfo() }) {
                    Image(systemName: "info.circle").font(.title3).foregroundColor(.secondary)
                }.buttonStyle(.plain)
                
                HStack(spacing: 8) {
                    Text(formatDuration(audioManager.currentTime)).font(.caption.monospacedDigit())
                    Slider(value: Binding(get: { audioManager.currentTime }, set: { newValue in audioManager.seek(to: newValue) }), in: 0...max(1, song.duration)).tint(.pink).frame(width: 150)
                    Text(formatDuration(song.duration)).font(.caption.monospacedDigit())
                }
            }.padding(.trailing, 20)
        }.padding(.horizontal)
    }
    
    func formatDuration(_ duration: TimeInterval) -> String { guard !duration.isNaN else { return "0:00" }; let m = Int(duration) / 60; let s = Int(duration) % 60; return String(format: "%d:%02d", m, s) }
}

// MARK: - Lyric Line View
struct MacLyricLineView: View {
    let lineData: SyncedLyricLine
    let isCurrentLine: Bool
    let isPast: Bool
    let isPlaying: Bool
    let mainFontSize: CGFloat
    @ObservedObject var audioEngine: MacAudioEngine // Removed the settings dependency

    var isInstrumental: Bool { lineData.text == "[Instrumental]" }
    
    var body: some View {
        Group {
            // Unsynced lines render as inactive
            if lineData.isUnsynced == true {
                Text(lineData.text)
                    .font(.system(size: mainFontSize, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .scaleEffect(0.6, anchor: .center)
            } else if isInstrumental {
                if isCurrentLine {
                    PulsingDots(isPlaying: isPlaying).padding(.vertical, 10) // Fixed reference
                } else {
                    Text("•••").font(.title).foregroundColor(.white.opacity(0.4)).padding(.vertical, 10)
                }
            } else {
                if let timings = lineData.wordTimings, !timings.isEmpty {
                    renderWordSyncLine(lineData: lineData, timings: timings, fontSize: mainFontSize, isCurrentLine: isCurrentLine, isPast: isPast)
                        .scaleEffect(isCurrentLine ? 1.0 : 0.5, anchor: .center)
                        .opacity(isCurrentLine ? 1.0 : (isPast ? 0.5 : 0.7))
                        .blur(radius: isCurrentLine ? 0 : 0.8)
                } else {
                    Text(lineData.text)
                        .font(.system(size: mainFontSize, weight: .bold))
                        .foregroundColor(isCurrentLine ? .pink : .white) // Replaced settings color with .pink
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .scaleEffect(isCurrentLine ? 1.0 : 0.5, anchor: .center)
                        .opacity(isCurrentLine ? 1.0 : (isPast ? 0.5 : 0.7))
                        .blur(radius: isCurrentLine ? 0 : 0.8)
                }
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isCurrentLine)
    }
    
    func renderWordSyncLine(lineData: SyncedLyricLine, timings: [WordTiming], fontSize: CGFloat, isCurrentLine: Bool, isPast: Bool) -> some View {
        let words = lineData.text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        return MacCenterFlowLayout {
            ForEach(Array(words.enumerated()), id: \.offset) { item in
                let wIndex = item.offset
                let wordText = item.element
                let wordWithSpace = wordText + (wIndex == words.count - 1 ? "" : " ")
                let startTime = (wIndex < timings.count) ? timings[wIndex].startTime : .infinity
                let endTime = (wIndex + 1 < timings.count) ? timings[wIndex + 1].startTime : (lineData.endTime ?? (startTime + 1.5))
                
                MacProgressiveWordView(
                    word: wordWithSpace,
                    startTime: startTime,
                    endTime: endTime,
                    currentTime: audioEngine.currentTime,
                    fontSize: fontSize,
                    activeColor: .pink,
                    isCurrentLine: isCurrentLine,
                    isPast: isPast
                )
            }
        }
    }
}

// MARK: - Mac Progressive Word View
struct MacProgressiveWordView: View {
    let word: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let currentTime: TimeInterval
    let fontSize: CGFloat
    let activeColor: Color
    let isCurrentLine: Bool
    let isPast: Bool
    
    var progress: CGFloat {
        guard isCurrentLine else { return isPast ? 1.0 : 0.0 }
        if currentTime < startTime { return 0 }
        if currentTime >= endTime { return 1 }
        let total = endTime - startTime
        let current = currentTime - startTime
        return CGFloat(current / total)
    }
    
    var body: some View {
        Text(word)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundColor(isPast ? activeColor : .white.opacity(0.4))
            .overlay(
                Text(word)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundColor(activeColor)
                    .mask(
                        GeometryReader { geo in
                            Rectangle().frame(width: geo.size.width * progress)
                        }
                    )
            )
    }
}

// MARK: - Mac Center Flow Layout
@available(macOS 13.0, *)
struct MacCenterFlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 1000, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for row in result.rows {
            let rowXOffset = (bounds.width - row.width) / 2.0 // Centered
            for item in row.items {
                let x = bounds.minX + rowXOffset + item.x
                let y = bounds.minY + item.y
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            }
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var rows: [Row] = []
        
        struct Row { var items: [Item] = []; var width: CGFloat = 0; var height: CGFloat = 0 }
        struct Item { var index: Int; var x: CGFloat; var y: CGFloat; var size: CGSize }
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentRow = Row()
            var currentY: CGFloat = 0
            
            for (index, subview) in subviews.enumerated() {
                let size = subview.sizeThatFits(.unspecified)
                if currentRow.width + size.width > maxWidth, !currentRow.items.isEmpty {
                    rows.append(currentRow)
                    currentY += currentRow.height + spacing
                    currentRow = Row()
                }
                
                let item = Item(index: index, x: currentRow.width, y: currentY, size: size)
                currentRow.items.append(item)
                currentRow.width += size.width + (currentRow.items.count > 1 ? spacing : 0)
                currentRow.height = max(currentRow.height, size.height)
                self.size.width = max(self.size.width, currentRow.width)
            }
            if !currentRow.items.isEmpty {
                rows.append(currentRow)
                self.size.height = currentY + currentRow.height
            }
        }
    }
}
