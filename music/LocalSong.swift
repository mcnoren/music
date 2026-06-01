//
//  LocalSong.swift
//  music
//

import SwiftUI
import AVFoundation
import Combine

// MARK: - Models
struct LocalSong: Identifiable, Codable, Hashable {
    let id: String
    var url: URL // CHANGED TO VAR: We must update this on launch because iOS Sandbox paths change dynamically!
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var artworkData: Data?
    var trackNumber: Int
    var discNumber: Int?
    var genre: String = "Album"
    
    // Metadata support
    var lyrics: String?
    var syncedLyrics: [SyncedLyricLine]?
}

// MARK: - Downloads Manager
class DownloadsManager: ObservableObject {
    static let shared = DownloadsManager()
    @Published var downloadedSongs: [LocalSong] = []
    @Published var isImporting: Bool = false
    
    private let metadataKey = "LocalDownloadsMetadataKey"
    
    // NEW: The location of our Instant Cache file
    private var cacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("DownloadsFastCache.json")
    }

    init() {
        loadFastCache() // 1. INSTANTLY load the UI from the JSON cache
        loadDownloads() // 2. Check the file system in the background for new files
        NotificationCenter.default.addObserver(self, selector: #selector(loadDownloads), name: NSNotification.Name("NewDownloadComplete"), object: nil)
    }
    
    // MARK: - Fast Caching Logic
    private func saveCache(songs: [LocalSong]) {
        // Run on a background thread so massive artwork data doesn't freeze the UI while encoding
        Task.detached {
            if let data = try? JSONEncoder().encode(songs) {
                try? data.write(to: self.cacheURL)
            }
        }
    }
    
    private func loadFastCache() {
        if let data = try? Data(contentsOf: cacheURL),
           var cachedSongs = try? JSONDecoder().decode([LocalSong].self, from: data) {
            
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            
            // VITAL: Reconstruct the URLs because the iOS App Sandbox UUID changes every time you launch the app!
            for i in 0..<cachedSongs.count {
                let fileName = cachedSongs[i].url.lastPathComponent
                cachedSongs[i].url = docsDir.appendingPathComponent(fileName)
            }
            
            DispatchQueue.main.async {
                self.downloadedSongs = cachedSongs
                LibraryManager.shared.loadPinnedAlbums()
            }
        }
    }
    
    // MARK: - Metadata
    func saveMetadata(_ payload: DownloadMetadataPayload) {
        var allMeta = getSavedMetadata()
        allMeta[payload.fileName] = payload
        if let encoded = try? JSONEncoder().encode(allMeta) {
            UserDefaults.standard.set(encoded, forKey: metadataKey)
        }
        
        DispatchQueue.main.async {
            if payload.albumColors != nil || payload.albumTransform != nil {
                LibraryManager.shared.saveAlbumSettings(
                    albumId: payload.album,
                    colors: payload.albumColors,
                    transform: payload.albumTransform
                )
            }
        }
    }
    
    func getSavedMetadata() -> [String: DownloadMetadataPayload] {
        if let data = UserDefaults.standard.data(forKey: metadataKey),
           let decoded = try? JSONDecoder().decode([String: DownloadMetadataPayload].self, from: data) {
            return decoded
        }
        return [:]
    }
    
    func saveSyncedLyrics(for songId: String, lines: [SyncedLyricLine]) {
        guard let song = downloadedSongs.first(where: { $0.id == songId }) else { return }
        
        LibraryManager.shared.saveSyncedLyrics(
            id: songId,
            title: song.title,
            artist: song.artist,
            lines: lines
        )
        
        DispatchQueue.main.async {
            if let index = self.downloadedSongs.firstIndex(where: { $0.id == songId }) {
                self.downloadedSongs[index].syncedLyrics = lines
            }
            if AudioManager.shared.currentLocalSong?.id == songId {
                AudioManager.shared.currentLocalSong?.syncedLyrics = lines
            }
            
            // Save the updated lyrics to the instant cache
            self.saveCache(songs: self.downloadedSongs)
            LibraryManager.shared.loadPinnedAlbums()
        }
    }

    // MARK: - Background File Scanner
    @objc func loadDownloads() {
        Task.detached { [weak self] in
            guard let self = self else { return }
            let fileManager = FileManager.default
            guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let savedMeta = self.getSavedMetadata()
            
            // Grab our currently loaded cache so we know what to skip
            let currentSongs = await MainActor.run { self.downloadedSongs }
            var existingSongsMap: [String: LocalSong] = [:]
            for song in currentSongs {
                existingSongsMap[song.url.lastPathComponent] = song
            }
            
            do {
                let files = try fileManager.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil)
                let audioFiles = files.filter { ["mp3", "m4a", "wav", "aac", "flac"].contains($0.pathExtension.lowercased()) }
                
                var newSongsList: [LocalSong] = []
                var cacheUpdated = false
                
                for url in audioFiles {
                    let fileName = url.lastPathComponent
                    try? fileManager.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: url.path)
                    
                    // IF WE ALREADY HAVE THIS FILE CACHED, SKIP THE HEAVY AVASSET PARSING!
                    if var existingSong = existingSongsMap[fileName] {
                        existingSong.url = url // Ensure URL is fresh for this launch
                        
                        // Just double check if new lyrics came in over the network
                        let synced = LibraryManager.shared.syncedLyrics[fileName]?.lines ?? savedMeta[fileName]?.syncedLyrics
                        if existingSong.syncedLyrics != synced {
                            existingSong.syncedLyrics = synced
                            cacheUpdated = true
                        }
                        
                        newSongsList.append(existingSong)
                        continue
                    }
                    
                    // IF WE DONT HAVE IT, RUN THE HEAVY PARSER (For brand new downloads)
                    cacheUpdated = true
                    let asset = AVAsset(url: url)
                    let meta = savedMeta[fileName]
                    
                    var title = meta?.title ?? url.deletingPathExtension().lastPathComponent
                    var artist = meta?.artist ?? "Unknown Artist"
                    var album = meta?.album ?? "Unknown Album"
                    var duration: TimeInterval = 0
                    var artworkData: Data? = nil
                    var lyrics = meta?.lyrics
                    var syncedLyrics = LibraryManager.shared.syncedLyrics[fileName]?.lines ?? meta?.syncedLyrics
                    var trackNumber = meta?.trackNumber ?? 0
                    var discNumber = meta?.discNumber
                    var genre = "Album"
                    
                    if let dur = try? await asset.load(.duration) { duration = dur.seconds }
                    
                    if let metadata = try? await asset.load(.commonMetadata) {
                        for item in metadata {
                            if meta == nil {
                                if item.commonKey?.rawValue == "title" { title = try await item.load(.stringValue) ?? title }
                                if item.commonKey?.rawValue == "artist" { artist = try await item.load(.stringValue) ?? artist }
                                if item.commonKey?.rawValue == "albumName" { album = try await item.load(.stringValue) ?? album }
                            }
                            if item.commonKey?.rawValue == "type" { genre = try await item.load(.stringValue) ?? genre }
                            if item.commonKey?.rawValue == "artwork" { artworkData = try await item.load(.dataValue) }
                        }
                    }

                    if let formats = try? await asset.load(.availableMetadataFormats) {
                        for format in formats {
                            if let metadata = try? await asset.loadMetadata(for: format) {
                                for item in metadata {
                                    let identifier = item.identifier?.rawValue.lowercased() ?? ""
                                    if identifier.contains("track") || identifier.contains("trkn") || identifier.contains("trck") {
                                        if let str = item.stringValue {
                                            let clean = str.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                            trackNumber = Int(clean) ?? trackNumber
                                        } else if let num = item.numberValue {
                                            trackNumber = num.intValue
                                        } else if let data = item.dataValue, data.count >= 4 {
                                            let track = (Int(data[2]) << 8) | Int(data[3])
                                            if track > 0 { trackNumber = track }
                                        }
                                    }
                                    
                                    if identifier.contains("disc") || identifier.contains("tpos") {
                                        if let str = item.stringValue {
                                            let clean = str.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                            discNumber = Int(clean) ?? discNumber
                                        } else if let num = item.numberValue {
                                            discNumber = num.intValue
                                        } else if let data = item.dataValue, data.count >= 4 {
                                            let disc = (Int(data[2]) << 8) | Int(data[3])
                                            if disc > 0 { discNumber = disc }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    newSongsList.append(LocalSong(id: fileName, url: url, title: title, artist: artist, album: album, duration: duration, artworkData: artworkData, trackNumber: trackNumber, discNumber: discNumber, genre: genre, lyrics: lyrics, syncedLyrics: syncedLyrics))
                }
                
                let sortedSongs = newSongsList.sorted { $0.title < $1.title }
                
                // Only write to memory and update UI if something actually changed/downloaded
                if cacheUpdated || sortedSongs.count != existingSongsMap.count {
                    self.saveCache(songs: sortedSongs)
                    DispatchQueue.main.async {
                        self.downloadedSongs = sortedSongs
                        LibraryManager.shared.loadPinnedAlbums()
                    }
                }
            } catch {
                print("Error loading downloads: \(error)")
            }
        }
    }
    
    // MARK: - Deletion Logic
    func deleteSong(_ song: LocalSong) {
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: song.url.path) {
                try fileManager.removeItem(at: song.url)
            }
            
            var allMeta = getSavedMetadata()
            allMeta.removeValue(forKey: song.id)
            if let encoded = try? JSONEncoder().encode(allMeta) {
                UserDefaults.standard.set(encoded, forKey: metadataKey)
            }
            
            DispatchQueue.main.async {
                self.downloadedSongs.removeAll { $0.id == song.id }
                self.saveCache(songs: self.downloadedSongs) // Update cache
                
                if AudioManager.shared.currentLocalSong?.id == song.id && AudioManager.shared.isPlaying {
                    AudioManager.shared.togglePlayPause()
                }
                LibraryManager.shared.loadPinnedAlbums()
            }
        } catch {
            print("Error deleting file: \(error)")
        }
    }
    
    func deleteAlbum(albumName: String) {
        let songsToDelete = downloadedSongs.filter { $0.album == albumName }
        for song in songsToDelete {
            deleteSong(song)
        }
    }
}

// MARK: - Navigation Wrappers

struct LocalSongSection: Identifiable {
    let id = UUID()
    let letter: String
    let songs: [LocalSong]
}

struct LocalArtistSection: Identifiable {
    let id = UUID()
    let letter: String
    let artists: [String]
}


// MARK: - Main Tab View
struct DownloadsView: View {
    @ObservedObject var downloads = DownloadsManager.shared
    @State private var navPath = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $navPath) {
            DownloadsHomeView()
                .navigationDestination(for: String.self) { destination in
                    switch destination {
                    case "Artists": DownloadsArtistListView()
                    case "Albums": DownloadsAlbumListView()
                    case "Songs": DownloadsSongListView()
                    default: EmptyView()
                    }
                }
                .navigationDestination(for: LocalAlbumWrapper.self) { wrapper in
                    UniversalAlbumDetailView(albumName: wrapper.name, collection: .downloads(wrapper.songs))
                }
                .navigationDestination(for: LocalArtistWrapper.self) { wrapper in
                    DownloadsArtistDetailView(artistName: wrapper.name, songs: wrapper.songs)
                }
        }
        .accentColor(.pink)
    }
}

// MARK: - Home View
struct DownloadsHomeView: View {
    @ObservedObject var downloads = DownloadsManager.shared
    let menuItems = ["Artists", "Albums", "Songs"]
    
    func icon(for item: String) -> String {
        switch item {
        case "Artists": return "music.mic"
        case "Albums": return "square.stack"
        case "Songs": return "music.note"
        default: return "circle"
        }
    }
    
    var body: some View {
        Group {
            if downloads.downloadedSongs.isEmpty {
                VStack {
                    Image(systemName: "arrow.down.circle").font(.system(size: 60)).foregroundColor(.gray.opacity(0.5))
                    Text("No Downloads Yet").font(.title3).foregroundColor(.secondary).padding()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(menuItems, id: \.self) { item in
                            VStack(spacing: 0) {
                                NavigationLink(value: item) {
                                    SimpleMenuRow(icon: icon(for: item), title: item, showChevron: true)
                                }
                                Divider().padding(.leading, 60)
                            }
                        }
                    }
                    .padding(.top, 16)
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("Downloads")
    }
}

// MARK: - Songs List
struct DownloadsSongListView: View {
    @ObservedObject var downloads = DownloadsManager.shared
    @State private var searchText = ""
    @State private var scrollTarget: String?
    
    var activeSections: [LocalSongSection] {
        var filtered = downloads.downloadedSongs
        if !searchText.isEmpty {
            filtered = filtered.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.artist.localizedCaseInsensitiveContains(searchText) }
        }
        let grouped = Dictionary(grouping: filtered) { song -> String in
            let prefix = song.title.prefix(1).uppercased()
            return prefix.rangeOfCharacter(from: .letters) != nil ? prefix : "#"
        }
        let sortedKeys = grouped.keys.sorted { lhs, rhs in
            if lhs == "#" { return false }
            if rhs == "#" { return true }
            return lhs < rhs
        }
        return sortedKeys.map { LocalSongSection(letter: $0, songs: grouped[$0] ?? []) }
    }
    
    var body: some View {
        let currentQueue = activeSections.flatMap { $0.songs }
        
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(activeSections) { section in
                            Section(header: Text(section.letter).font(.headline).foregroundColor(.pink).padding(.horizontal).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).background(Color(.systemBackground)).id(section.letter)) {
                                ForEach(section.songs) { song in
                                    DownloadsSongRow(song: song, queue: currentQueue)
                                    Divider().padding(.leading, 70)
                                }
                            }
                        }
                        Spacer().frame(height: 100)
                    }.padding(.trailing, 20)
                }.onChange(of: scrollTarget) { target in if let t = target { proxy.scrollTo(t, anchor: .top) } }
            }
            if searchText.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 0) {
                        ForEach(activeSections.map{$0.letter}, id:\.self) { l in
                            Text(l).font(.system(size: 11, weight: .semibold)).foregroundColor(.pink).frame(width: 20, height: 18)
                                .onTapGesture { scrollTarget = l }
                        }
                    }
                    .padding(.trailing, 2)
                }
            }
        }
        .navigationTitle("Downloaded Songs")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
    }
}

// MARK: - Albums List
struct DownloadsAlbumListView: View {
    @ObservedObject var downloads = DownloadsManager.shared
    @State private var searchText = ""
    let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    
    var groupedAlbums: [String: [LocalSong]] { Dictionary(grouping: downloads.downloadedSongs, by: { $0.album }) }
    
    var filteredAlbumNames: [String] {
        let names = groupedAlbums.keys.sorted()
        if searchText.isEmpty { return names }
        return names.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(filteredAlbumNames, id: \.self) { albumName in
                    let songs = groupedAlbums[albumName] ?? []
                    NavigationLink(value: LocalAlbumWrapper(name: albumName, songs: songs)) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let firstSong = songs.first, let data = firstSong.artworkData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fit).cornerRadius(12).shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            } else {
                                Rectangle().fill(Color.gray.opacity(0.3)).aspectRatio(1.0, contentMode: .fit).cornerRadius(12).overlay(Image(systemName: "music.note").font(.largeTitle).foregroundColor(.gray))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(albumName).font(.headline).foregroundColor(.primary).lineLimit(1)
                                Text(songs.first?.artist ?? "Unknown").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) { DownloadsManager.shared.deleteAlbum(albumName: albumName) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .padding()
            Spacer().frame(height: 100)
        }
        .navigationTitle("Downloaded Albums")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
    }
}

// MARK: - Artists List
struct DownloadsArtistListView: View {
    @ObservedObject var downloads = DownloadsManager.shared
    @State private var searchText = ""
    @State private var scrollTarget: String?
    
    var groupedArtists: [String: [LocalSong]] { Dictionary(grouping: downloads.downloadedSongs, by: { $0.artist }) }
    
    var activeSections: [LocalArtistSection] {
        var filtered = groupedArtists.keys.sorted()
        if !searchText.isEmpty { filtered = filtered.filter { $0.localizedCaseInsensitiveContains(searchText) } }
        let grouped = Dictionary(grouping: filtered) { artist -> String in
            let prefix = artist.prefix(1).uppercased()
            return prefix.rangeOfCharacter(from: .letters) != nil ? prefix : "#"
        }
        let sortedKeys = grouped.keys.sorted { lhs, rhs in
            if lhs == "#" { return false }; if rhs == "#" { return true }; return lhs < rhs
        }
        return sortedKeys.map { LocalArtistSection(letter: $0, artists: grouped[$0] ?? []) }
    }
    
    var body: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(activeSections) { section in
                            Section(header: Text(section.letter).font(.headline).foregroundColor(.pink).padding(.horizontal).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).background(Color(.systemBackground)).id(section.letter)) {
                                ForEach(section.artists, id: \.self) { artistName in
                                    let songs = groupedArtists[artistName] ?? []
                                    NavigationLink(value: LocalArtistWrapper(name: artistName, songs: songs)) {
                                        Text(artistName).font(.body).foregroundColor(.primary).padding(.horizontal).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    }
                                    Divider().padding(.leading)
                                }
                            }
                        }
                        Spacer().frame(height: 100)
                    }
                    .padding(.trailing, 20)
                }.onChange(of: scrollTarget) { target in if let t = target { proxy.scrollTo(t, anchor: .top) } }
            }
            if searchText.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 0) {
                        ForEach(activeSections.map{$0.letter}, id:\.self) { l in
                            Text(l).font(.system(size: 11, weight: .semibold)).foregroundColor(.pink).frame(width: 20, height: 18).onTapGesture { scrollTarget = l }
                        }
                    }
                    .padding(.trailing, 2)
                }
            }
        }
        .navigationTitle("Artists")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
    }
}

struct DownloadsArtistDetailView: View {
    let artistName: String
    let songs: [LocalSong]
    
    @ObservedObject var downloads = DownloadsManager.shared
    var activeSongs: [LocalSong] {
        downloads.downloadedSongs
            .filter { $0.artist == artistName }
            .sorted {
                if $0.album == $1.album {
                    if $0.trackNumber == $1.trackNumber { return $0.title < $1.title }
                    if $0.trackNumber == 0 { return false }
                    if $1.trackNumber == 0 { return true }
                    return $0.trackNumber < $1.trackNumber
                }
                return $0.album < $1.album
            }
    }
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(activeSongs) { song in
                    DownloadsSongRow(song: song, queue: activeSongs)
                    Divider().padding(.leading)
                }
                Spacer().frame(height: 100)
            }
        }
        .navigationTitle(artistName)
        .onChange(of: activeSongs) { newSongs in
            if newSongs.isEmpty {
                dismiss()
            }
        }
    }
}

// MARK: - Row View
@MainActor
struct DownloadsSongRow: View {
    let song: LocalSong
    var queue: [LocalSong] = []
    var showArtwork: Bool = true
    var showTrackNumber: Bool = false
    var customPrimaryColor: Color? = nil
    var customSecondaryColor: Color? = nil
    var showArtist: Bool = true
    
    // 1. REMOVE @ObservedObject here
    var audioManager = AudioManager.shared
    @ObservedObject var library = LibraryManager.shared
    
    // 2. Change isPlaying to State
    @State private var isPlaying: Bool = false
    
    var body: some View {
        let artworkImage = song.artworkData != nil ? UIImage(data: song.artworkData!) : nil
        let hasSynced = song.syncedLyrics?.isFullySynced == true || library.getSyncedLyrics(id: song.id, title: song.title, artist: song.artist)?.isFullySynced == true
        let hasCustomRaw = library.customRawLyrics[song.id] != nil && !library.customRawLyrics[song.id]!.isEmpty
        let hasNativeRaw = song.lyrics != nil && !song.lyrics!.isEmpty
        
        UniversalCustomSongRow(
            title: song.title,
            artist: song.artist,
            trackNumber: song.trackNumber,
            hasSynced: hasSynced,
            showUnfilledBubble: hasCustomRaw || hasNativeRaw,
            artwork: artworkImage,
            isPlaying: isPlaying,
            showArtwork: showArtwork,
            showTrackNumber: showTrackNumber,
            showArtist: showArtist,
            customPrimaryColor: customPrimaryColor,
            customSecondaryColor: customSecondaryColor,
            onTap: {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                audioManager.play(localSong: song, queue: queue.isEmpty ? [song] : queue)
            }
        ) {
            DownloadsSongMenuContent(song: song)
        }
        // 3. ONLY update when the current song actually changes
        .onReceive(audioManager.$currentLocalSong) { currentSong in
            isPlaying = (currentSong?.id == song.id)
        }
        .onAppear {
            isPlaying = (audioManager.currentLocalSong?.id == song.id)
        }
    }
}

struct DownloadsSongMenuContent: View {
    let song: LocalSong
    
    var body: some View {
        Section {
            Button { NotificationCenter.default.post(name: NSNotification.Name("ShowAddToPlaylist"), object: ["local_\(song.id)"]) } label: { Label("Add to Playlist...", systemImage: "text.badge.plus") }
        }
        Section {
            Button(role: .destructive) { DownloadsManager.shared.deleteSong(song) } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

import Foundation
import AVFoundation

extension DownloadsManager {
    
    func importExternalURL(_ url: URL) async {
        self.isImporting = true
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
            self.isImporting = false
        }
        
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        
        if isDirectory.boolValue {
            if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    await processAndCopyFile(at: fileURL)
                }
            }
        } else {
            await processAndCopyFile(at: url)
        }
    }
    
    private func processAndCopyFile(at sourceURL: URL) async {
        let fileManager = FileManager.default
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        
        let validExtensions = ["mp3", "m4a", "wav", "aac", "flac"]
        guard validExtensions.contains(sourceURL.pathExtension.lowercased()) else { return }
        
        let destinationURL = documentsDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            
            if let newSong = await parseLocalAudioFile(url: destinationURL) {
                DispatchQueue.main.async {
                    if let index = self.downloadedSongs.firstIndex(where: { $0.id == newSong.id }) {
                        self.downloadedSongs[index] = newSong
                    } else {
                        self.downloadedSongs.append(newSong)
                    }
                    self.saveCache(songs: self.downloadedSongs) // Update cache instantly
                    LibraryManager.shared.loadPinnedAlbums()
                }
            }
        } catch {
            print("Failed to copy imported file: \(error.localizedDescription)")
        }
    }
    
    private func parseLocalAudioFile(url: URL) async -> LocalSong? {
        let asset = AVAsset(url: url)
        guard let isPlayable = try? await asset.load(.isPlayable), isPlayable else { return nil }
        
        var title = url.deletingPathExtension().lastPathComponent
        var artist = "Unknown Artist"
        var album = "Unknown Album"
        var genre = "Unknown Genre"
        var artworkData: Data? = nil
        var trackNumber = 0
        var discNumber: Int?
        var lyrics: String?
        
        let duration = (try? await asset.load(.duration).seconds) ?? 0.0
        
        if let commonMetadata = try? await asset.load(.commonMetadata) {
            for item in commonMetadata {
                switch item.commonKey?.rawValue {
                case "title": title = item.stringValue ?? title
                case "artist": artist = item.stringValue ?? artist
                case "albumName": album = item.stringValue ?? album
                case "type": genre = item.stringValue ?? genre
                case "artwork": artworkData = item.dataValue
                default: break
                }
            }
        }
        
        if let nativeLyrics = try? await asset.load(.lyrics), !nativeLyrics.isEmpty { lyrics = nativeLyrics }
        
        if let formats = try? await asset.load(.availableMetadataFormats) {
            for format in formats {
                if let metadata = try? await asset.loadMetadata(for: format) {
                    for item in metadata {
                        let identifier = item.identifier?.rawValue.lowercased() ?? ""
                        if identifier.contains("track") || identifier.contains("trkn") || identifier.contains("trck") {
                            if let str = item.stringValue {
                                let clean = str.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                trackNumber = Int(clean) ?? trackNumber
                            } else if let num = item.numberValue {
                                trackNumber = num.intValue
                            } else if let data = item.dataValue, data.count >= 4 {
                                let track = (Int(data[2]) << 8) | Int(data[3])
                                if track > 0 { trackNumber = track }
                            }
                        }
                        
                        if identifier.contains("disc") || identifier.contains("disk") {
                            if let str = item.stringValue {
                                let clean = str.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                if let d = Int(clean) { discNumber = d }
                            } else if let num = item.numberValue {
                                discNumber = num.intValue
                            } else if let data = item.dataValue, data.count >= 4 {
                                let disc = (Int(data[2]) << 8) | Int(data[3])
                                if disc > 0 { discNumber = disc }
                            }
                        }
                    }
                }
            }
        }
        
        // FIX: Bound the ID strictly to the filename so deletion and updating map perfectly
        let stableID = url.lastPathComponent
        
        return LocalSong(id: stableID, url: url, title: title, artist: artist, album: album, duration: duration, artworkData: artworkData, trackNumber: trackNumber, discNumber: discNumber, genre: genre, lyrics: lyrics)
    }
}
