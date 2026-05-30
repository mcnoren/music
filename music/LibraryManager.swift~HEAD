//
//  LibraryManager.swift
//  music
//
//  Created by Matthew Noren on 12/10/25.
//

import Combine
import MediaPlayer
import SwiftUI

// MARK: - Lyric Syncing Data Structures
struct SyncedLyricLine: Codable, Hashable {
    let text: String
    var startTime: TimeInterval
    var endTime: TimeInterval?
    var wordTimings: [WordTiming]?
    var isUnsynced: Bool? // NEW: Allows inline text additions without breaking existing syncs
}

extension Array where Element == SyncedLyricLine {
    var isFullySynced: Bool {
        guard !isEmpty else { return false }
        return self.last?.isUnsynced != true
    }
}


struct SongSection: Identifiable {
    let id = UUID()
    let letter: String
    let songs: [MPMediaItem]
}

struct ArtistSection: Identifiable {
    let id = UUID()
    let letter: String
    let artists: [String]
}

struct WordTiming: Codable, Hashable {
    let word: String
    var startTime: TimeInterval
}

struct PinnedAlbumCache: Codable, Equatable {
    let title: String
    let artist: String
    let applePersistentID: String?
}

class LibraryManager: ObservableObject {
    static let shared = LibraryManager()
    @Published var songs: [MPMediaItem] = []
    @Published var albums: [MPMediaItemCollection] = []
    @Published var playlists: [MPMediaItemCollection] = []
    @Published var sections: [SongSection] = []
    @Published var artistSections: [ArtistSection] = []
    @Published var customRawLyrics: [String: String] = [:]
    @Published var customAlbumDescriptions: [String: String] = [:]
    @Published var albumEdgeToEdgePrefs: [String: Bool] = [:]
    @Published var albumArtTransforms: [String: AlbumArtTransform] = [:]
    @Published var albumShowTitlePrefs: [String: Bool] = [:]
    @Published var albumShowArtistPrefs: [String: Bool] = [:]
    @Published var albumTextColorPrefs: [String: String] = [:]
    @Published var songTextColorPrefs: [String: String] = [:]
    @Published var pinnedAlbumCache: [String: PinnedAlbumCache] = [:]
    private let pinnedAlbumCacheKey = "PinnedAlbumCachePersistenceKey"
    private let albumArtTransformsKey = "AlbumArtTransformsPersistenceKey"
    private let albumEdgeToEdgeKey = "AlbumEdgeToEdgePersistenceKey"
    private let albumDescriptionsKey = "AlbumDescriptionsPersistenceKey"
    private let customRawLyricsKey = "CustomRawLyricsPersistenceKey"
    private let showTitleKey = "AlbumShowTitlePrefsKey"
    private let showArtistKey = "AlbumShowArtistPrefsKey"
    private let albumTextColKey = "AlbumTextColorPrefsKey"
    private let songTextColKey = "SongTextColorPrefsKey"
    
    
    // Filtered lists for Favorites
    @Published var favoriteAlbums: [MPMediaItemCollection] = []
    
    // Pinned Albums (User Selected)
    @Published var pinnedAlbums: [MPMediaItemCollection] = []
    @Published var pinnedUnifiedAlbums: [UnifiedAlbumItem] = []
    
    @Published var albumVideoArt: [String: URL] = [:]
    private let albumVideoArtKey = "AlbumVideoArtPersistenceKey"
    
    // Menu Order
    @Published var menuItems: [String] = []
    
    // Local Favorites persistence
    @Published var localFavoriteIDs: Set<String> = []
    
    // Persistent Synced Lyrics Storage
    @Published var syncedLyrics: [String: SyncedLyricsDocument] = [:]
    
    private var favoriteSongIDs: Set<MPMediaEntityPersistentID> = []
    private let pinnedAlbumsKey = "PinnedAlbumsPersistenceKey"
    private let menuOrderKey = "LibraryMenuOrderKey"
    private let localFavoritesKey = "LocalFavoritesPersistenceKey"
    private let syncedLyricsKey = "SyncedLyricsPersistenceKey"
    
    @Published var isAuthorized = false
    
    @Published var customAlbumSecondaryColors: [String: String] = [:]
    
    @Published var albumArtCrops: [String: AlbumArtCrop] = [:]
    private let albumArtCropsKey = "AlbumArtCropsPersistenceKey"
    
    init() {
        // Load menu order or default, migrating to include Mac and Genres if they don't exist yet
        var savedMenu = UserDefaults.standard.stringArray(forKey: menuOrderKey) ?? ["Playlists", "Artists", "Genres", "Albums", "Songs", "Mac"]
        
        var menuNeedsUpdate = false
        if !savedMenu.contains("Mac") {
            savedMenu.append("Mac")
            menuNeedsUpdate = true
        }
        if !savedMenu.contains("Genres") {
            // Insert Genres after Artists or at the end
            if let index = savedMenu.firstIndex(of: "Artists") {
                savedMenu.insert("Genres", at: index + 1)
            } else {
                savedMenu.append("Genres")
            }
            menuNeedsUpdate = true
        }
        if menuNeedsUpdate {
            UserDefaults.standard.set(savedMenu, forKey: menuOrderKey)
        }
        // Load Edge-to-Edge Preferences
        if let data = UserDefaults.standard.data(forKey: albumEdgeToEdgeKey),
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            self.albumEdgeToEdgePrefs = decoded
        }
        // Load Synced Lyrics
        if let data = UserDefaults.standard.data(forKey: syncedLyricsKey) {
            if let decoded = try? JSONDecoder().decode([String: SyncedLyricsDocument].self, from: data) {
                self.syncedLyrics = decoded
            } else if let oldDecoded = try? JSONDecoder().decode([String: [SyncedLyricLine]].self, from: data) {
                // Migrate old data to new format
                var newDict: [String: SyncedLyricsDocument] = [:]
                for (key, lines) in oldDecoded {
                    newDict[key] = SyncedLyricsDocument(songTitle: "Unknown", artistName: "Unknown", lines: lines, lastModified: Date())
                }
                self.syncedLyrics = newDict
            }
            
            // --- NEW: Scrub duplicate timestamps on load ---
            var didScrub = false
            for (key, doc) in self.syncedLyrics {
                var modifiedLines = doc.lines
                var docChanged = false
                
                if modifiedLines.count > 1 {
                    for i in 0..<(modifiedLines.count - 1) {
                        if let eTime = modifiedLines[i].endTime, !(modifiedLines[i+1].isUnsynced ?? false) {
                            // If the end time is within 50ms of the next start time, delete it
                            if abs(eTime - modifiedLines[i+1].startTime) < 0.05 {
                                modifiedLines[i].endTime = nil
                                docChanged = true
                            }
                        }
                    }
                }
                
                if docChanged {
                    self.syncedLyrics[key] = SyncedLyricsDocument(
                        songTitle: doc.songTitle,
                        artistName: doc.artistName,
                        lines: modifiedLines,
                        lastModified: doc.lastModified
                    )
                    didScrub = true
                }
            }
            
            // Re-save if we cleaned anything up
            if didScrub {
                if let encoded = try? JSONEncoder().encode(self.syncedLyrics) {
                    UserDefaults.standard.set(encoded, forKey: syncedLyricsKey)
                }
            }
            
            // Load the Instant-Render Cache
            if let data = UserDefaults.standard.data(forKey: pinnedAlbumCacheKey),
               let decoded = try? JSONDecoder().decode([String: PinnedAlbumCache].self, from: data) {
                self.pinnedAlbumCache = decoded
            }
            // -----------------------------------------------
        }
        self.menuItems = savedMenu
        
        loadPinnedAlbums()
        loadAlbumColors()
        
        // Load local favorites
        let savedFavorites = UserDefaults.standard.stringArray(forKey: localFavoritesKey) ?? []
        self.localFavoriteIDs = Set(savedFavorites)
        
        // ---> ADD THESE 4 LINES HERE <---
        // Load Custom Raw Lyrics
        if let data = UserDefaults.standard.data(forKey: customRawLyricsKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.customRawLyrics = decoded
        }
        // ---------------------------------
        
        // Load Synced Lyrics
        if let data = UserDefaults.standard.data(forKey: syncedLyricsKey) {
            if let decoded = try? JSONDecoder().decode([String: SyncedLyricsDocument].self, from: data) {
                self.syncedLyrics = decoded
            } else if let oldDecoded = try? JSONDecoder().decode([String: [SyncedLyricLine]].self, from: data) {
                // Migrate old data to new format
                var newDict: [String: SyncedLyricsDocument] = [:]
                for (key, lines) in oldDecoded {
                    newDict[key] = SyncedLyricsDocument(songTitle: "Unknown", artistName: "Unknown", lines: lines, lastModified: Date())
                }
                self.syncedLyrics = newDict
            }
        }
        
        if let data = UserDefaults.standard.dictionary(forKey: showTitleKey) as? [String: Bool] { self.albumShowTitlePrefs = data }
        if let data = UserDefaults.standard.dictionary(forKey: showArtistKey) as? [String: Bool] { self.albumShowArtistPrefs = data }
        if let data = UserDefaults.standard.dictionary(forKey: albumTextColKey) as? [String: String] { self.albumTextColorPrefs = data }
        if let data = UserDefaults.standard.dictionary(forKey: songTextColKey) as? [String: String] { self.songTextColorPrefs = data }
        
        // Load Custom Album Descriptions
        if let data = UserDefaults.standard.data(forKey: albumDescriptionsKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.customAlbumDescriptions = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: albumArtTransformsKey),
           let decoded = try? JSONDecoder().decode([String: AlbumArtTransform].self, from: data) {
            self.albumArtTransforms = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: albumArtCropsKey),
           let decoded = try? JSONDecoder().decode([String: AlbumArtCrop].self, from: data) {
            self.albumArtCrops = decoded
        }
        
        // Load Album Video Art
        if let savedVideos = UserDefaults.standard.dictionary(forKey: albumVideoArtKey) as? [String: String] {
            for (id, filename) in savedVideos {
                let url = URL.documentsDirectory.appending(path: filename)
                if FileManager.default.fileExists(atPath: url.path) {
                    self.albumVideoArt[id] = url
                }
            }
        }
    }
    
    // MARK: - Album Colors Storage
    @Published var customAlbumColors: [String: String] = [:]
    private let albumColorsKey = "AlbumColorsPersistenceKey"
    
    func loadAlbumColors() {
        if let data = UserDefaults.standard.data(forKey: albumColorsKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            customAlbumColors = decoded
        }
    }
    
    func setAlbumVideo(id: String, url: URL?) {
        albumVideoArt[id] = url
        
        // Persist the mapping of ID to filename
        var savedVideos = UserDefaults.standard.dictionary(forKey: albumVideoArtKey) as? [String: String] ?? [:]
        if let url = url {
            savedVideos[id] = url.lastPathComponent
        } else {
            savedVideos.removeValue(forKey: id)
        }
        UserDefaults.standard.set(savedVideos, forKey: albumVideoArtKey)
        
        objectWillChange.send()
    }
    
    func isEdgeToEdgeEnabled(for albumId: String) -> Bool {
        // If the user hasn't explicitly set it, default to true
        return albumEdgeToEdgePrefs[albumId] ?? true
    }
    
    func saveAlbumColor(id: String, hex: String?) {
        if let hex = hex {
            customAlbumColors[id] = hex
        } else {
            customAlbumColors.removeValue(forKey: id)
        }
        
        if let encoded = try? JSONEncoder().encode(customAlbumColors) {
            UserDefaults.standard.set(encoded, forKey: albumColorsKey)
        }
        // Tell the Mac to save it too
        MultipeerManager.shared.syncAlbumColors(colors: customAlbumColors)
    }
    
    func saveAlbumArtCrop(id: String, crop: AlbumArtCrop?) {
        if let crop = crop {
            albumArtCrops[id] = crop
        } else {
            albumArtCrops.removeValue(forKey: id)
        }
        
        if let encoded = try? JSONEncoder().encode(albumArtCrops) {
            UserDefaults.standard.set(encoded, forKey: albumArtCropsKey)
        }
    }
    
    func saveAlbumArtTransform(id: String, transform: AlbumArtTransform?) {
        if let transform = transform {
            albumArtTransforms[id] = transform
        } else {
            albumArtTransforms.removeValue(forKey: id)
        }
        
        if let encoded = try? JSONEncoder().encode(albumArtTransforms) {
            UserDefaults.standard.set(encoded, forKey: albumArtTransformsKey)
        }
    }
    
    // MARK: - Cross-Platform Sync Helper
    func saveAlbumSettings(albumId: String, colors: [String: String]?, transform: AlbumArtTransform?) {
        // Unpack the Mac's color dictionary into the iPhone's separate properties
        if let colors = colors {
            if let primary = colors["primary"] {
                saveAlbumColor(id: albumId, hex: primary)
            }
            if let secondary = colors["secondary"] {
                saveAlbumSecondaryColor(id: albumId, hex: secondary)
            }
        }
        
        if let transform = transform {
            saveAlbumArtTransform(id: albumId, transform: transform)
        }
    }
    
    func saveAlbumSecondaryColor(id: String, hex: String?) {
        if let hex = hex {
            customAlbumSecondaryColors[id] = hex
        } else {
            customAlbumSecondaryColors.removeValue(forKey: id)
        }
        // Save to UserDefaults
        if let encoded = try? JSONEncoder().encode(customAlbumSecondaryColors) {
            UserDefaults.standard.set(encoded, forKey: "CustomAlbumSecondaryColorsKey")
        }
    }
    
    // 2. Add these functions anywhere in the LibraryManager class:
    func saveCustomRawLyrics(id: String, lyrics: String) {
        customRawLyrics[id] = lyrics
        
        // REQUIREMENT: Wipe previous synced lyrics when raw lyrics are edited
        syncedLyrics.removeValue(forKey: id)
        
        // Save Custom Lyrics to Disk
        if let encoded = try? JSONEncoder().encode(customRawLyrics) {
            UserDefaults.standard.set(encoded, forKey: customRawLyricsKey)
        }
        // Save Wiped Sync Database to Disk
        if let encodedSync = try? JSONEncoder().encode(syncedLyrics) {
            UserDefaults.standard.set(encodedSync, forKey: syncedLyricsKey)
        }
        
        // Push the wiped sync state to the Mac instantly
        MultipeerManager.shared.syncLyricsDatabase(documents: syncedLyrics)
        objectWillChange.send()
    }
    
    func saveAlbumDescription(id: String, text: String?) {
        if let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            customAlbumDescriptions[id] = text
        } else {
            customAlbumDescriptions.removeValue(forKey: id)
        }
        
        if let encoded = try? JSONEncoder().encode(customAlbumDescriptions) {
            UserDefaults.standard.set(encoded, forKey: albumDescriptionsKey)
        }
    }
    
    func setEdgeToEdge(id: String, isEnabled: Bool) {
        albumEdgeToEdgePrefs[id] = isEnabled
        if let encoded = try? JSONEncoder().encode(albumEdgeToEdgePrefs) {
            UserDefaults.standard.set(encoded, forKey: albumEdgeToEdgeKey)
        }
    }
    
    // Universal getter that prioritizes your edits over the file's metadata
    func getRawLyrics(id: String, fallback: String?) -> String? {
        return customRawLyrics[id] ?? fallback
    }
    
    // Update BOTH saveSyncedLyrics functions in LibraryManager to include this scrubber:

    func saveSyncedLyrics(for song: MPMediaItem, lines: [SyncedLyricLine]) {
        // 1. Scrub the lines for NaN or Infinity
        let cleanLines = lines.map { line -> SyncedLyricLine in
            var cleanLine = line
            if cleanLine.startTime.isNaN || cleanLine.startTime.isInfinite { cleanLine.startTime = 0.0 }
            if let end = cleanLine.endTime, (end.isNaN || end.isInfinite) { cleanLine.endTime = nil }
            return cleanLine
        }
        
        // 2. Use cleanLines in the document
        let doc = SyncedLyricsDocument(
            songTitle: song.title ?? "Unknown",
            artistName: song.artist ?? "Unknown",
            lines: cleanLines,
            lastModified: Date()
        )
        
        syncedLyrics[String(song.persistentID)] = doc
        
        if let encoded = try? JSONEncoder().encode(syncedLyrics) {
            UserDefaults.standard.set(encoded, forKey: syncedLyricsKey)
        }
        
        MultipeerManager.shared.syncLyricsDatabase(documents: syncedLyrics)
    }
    
    // MARK: - Save Helpers
    func setShowTitle(id: String, show: Bool) {
        albumShowTitlePrefs[id] = show
        UserDefaults.standard.set(albumShowTitlePrefs, forKey: showTitleKey)
    }
    
    func setShowArtist(id: String, show: Bool) {
        albumShowArtistPrefs[id] = show
        UserDefaults.standard.set(albumShowArtistPrefs, forKey: showArtistKey)
    }
    
    func setAlbumTextColor(id: String, hex: String?) {
        albumTextColorPrefs[id] = hex
        UserDefaults.standard.set(albumTextColorPrefs, forKey: albumTextColKey)
    }
    
    func setSongTextColor(id: String, hex: String?) {
        songTextColorPrefs[id] = hex
        UserDefaults.standard.set(songTextColorPrefs, forKey: songTextColKey)
    }
    
    // NEW: Universal save for Downloads and Streams
        func saveSyncedLyrics(id: String, title: String, artist: String, lines: [SyncedLyricLine]) {
            // 1. Scrub the lines for NaN or Infinity
            let cleanLines = lines.map { line -> SyncedLyricLine in
                var cleanLine = line
                if cleanLine.startTime.isNaN || cleanLine.startTime.isInfinite { cleanLine.startTime = 0.0 }
                if let end = cleanLine.endTime, (end.isNaN || end.isInfinite) { cleanLine.endTime = nil }
                return cleanLine
            }
            
            // 2. Use cleanLines in the document
            let doc = SyncedLyricsDocument(
                songTitle: title,
                artistName: artist,
                lines: cleanLines,
                lastModified: Date()
            )
            
            // Use the passed-in ID, not song.persistentID
            syncedLyrics[id] = doc
            
            if let encoded = try? JSONEncoder().encode(syncedLyrics) {
                UserDefaults.standard.set(encoded, forKey: syncedLyricsKey)
            }
            
            MultipeerManager.shared.syncLyricsDatabase(documents: syncedLyrics)
        }
    
    // MARK: - Robust Lyrics Lookup
    func getSyncedLyrics(id: String, title: String, artist: String) -> [SyncedLyricLine]? {
        // 1. Try exact ID match first (Fastest)
        if let match = syncedLyrics[id]?.lines, !match.isEmpty {
            return match
        }
        
        // 2. Fallback: Fuzzy match by Title and Artist (Fixes cross-platform ID mismatches)
        let cleanTitle = title.lowercased().replacingOccurrences(of: " ", with: "")
        let cleanArtist = artist.lowercased().replacingOccurrences(of: " ", with: "")
        
        for (_, doc) in syncedLyrics {
            let docTitle = doc.songTitle.lowercased().replacingOccurrences(of: " ", with: "")
            let docArtist = doc.artistName.lowercased().replacingOccurrences(of: " ", with: "")
            
            if docTitle == cleanTitle && docArtist == cleanArtist {
                return doc.lines
            }
        }
        
        return nil
    }
    
    func merge(remoteLyrics: [String: SyncedLyricsDocument]) {
        var didUpdate = false
        
        for (songId, remoteDoc) in remoteLyrics {
            if let localDoc = syncedLyrics[songId] {
                // Compare timestamps; only overwrite if the remote is newer
                if remoteDoc.lastModified > localDoc.lastModified {
                    syncedLyrics[songId] = remoteDoc
                    didUpdate = true
                }
            } else {
                // We don't have this one, add it
                syncedLyrics[songId] = remoteDoc
                didUpdate = true
            }
        }
        
        if didUpdate {
            if let encoded = try? JSONEncoder().encode(syncedLyrics) {
                UserDefaults.standard.set(encoded, forKey: syncedLyricsKey)
            }
            // Optional: Bounce back the merged library so both are perfectly identical
            MultipeerManager.shared.syncLyricsDatabase(documents: syncedLyrics)
        }
    }
    
    func requestPermissionAndFetch() {
        MPMediaLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                if status == .authorized {
                    self.isAuthorized = true
                    self.fetchAll()
                } else {
                    self.isAuthorized = false
                }
            }
        }
    }
    
    private func fetchAll() {
        Task.detached(priority: .userInitiated) {
            // Stage 1: Fast Album Fetch (For Pinned Art)
            // MPMediaQuery.albums() is much faster than .songs() because it returns collections
            let albums = MPMediaQuery.albums().collections ?? []
            
            await MainActor.run {
                self.albums = albums
                self.loadPinnedAlbums() // Now has real album objects, will show artwork
            }
            
            // Stage 2: Fetch Playlists & Favorite IDs
            let playlists = MPMediaQuery.playlists().collections ?? []
            let favPlaylist = playlists.first(where: {
                let name = $0.value(forProperty: MPMediaPlaylistPropertyName) as? String ?? ""
                return name == "Favorite Songs" || name == "Favorites"
            })
            let favoriteSongIDs = Set(favPlaylist?.items.map { $0.persistentID } ?? [])
            let favoriteAlbums = albums.filter { self.isSystemFavorite(album: $0) }

            await MainActor.run {
                self.playlists = playlists
                self.favoriteSongIDs = favoriteSongIDs
                self.favoriteAlbums = favoriteAlbums
            }

            // Stage 3: The Heavy Lifter (Full Song Fetch)
            let songs = MPMediaQuery.songs().items ?? []
            
            // Grouping Songs (O(N))
            let groupedSongs = Dictionary(grouping: songs) { song in
                let prefix = song.title?.prefix(1).uppercased() ?? "#"
                return "ABCDEFGHIJKLMNOPQRSTUVWXYZ".contains(prefix) ? prefix : "#"
            }
            let sortedSongKeys = groupedSongs.keys.sorted { lhs, rhs in
                if lhs == "#" { return false }
                if rhs == "#" { return true }
                return lhs < rhs
            }
            let songSections = sortedSongKeys.map { SongSection(letter: $0, songs: groupedSongs[$0] ?? []) }
            
            // Grouping Artists (O(N))
            let allArtists = Set(songs.compactMap { $0.artist })
            let groupedArtists = Dictionary(grouping: allArtists) { artist in
                let prefix = artist.prefix(1).uppercased()
                return "ABCDEFGHIJKLMNOPQRSTUVWXYZ".contains(prefix) ? String(prefix) : "#"
            }
            let sortedArtistKeys = groupedArtists.keys.sorted { lhs, rhs in
                if lhs == "#" { return false }
                if rhs == "#" { return true }
                return lhs < rhs
            }
            let artistSections = sortedArtistKeys.map { ArtistSection(letter: $0, artists: groupedArtists[$0]?.sorted() ?? []) }

            await MainActor.run {
                self.songs = songs
                self.sections = songSections
                self.artistSections = artistSections
                // Update pinned albums again in case new metadata is available
                self.loadPinnedAlbums()
            }
            
            // Stage 4: Background Repair
            await self.repairUnknownMetadata(allSongs: songs)
        }
    }
    
    private func repairUnknownMetadata(allSongs: [MPMediaItem]) async {
        var didPatch = false
        let songDict = Dictionary(uniqueKeysWithValues: allSongs.map { ($0.persistentID, $0) })
        
        var patchedLyrics = self.syncedLyrics
        
        for (key, doc) in patchedLyrics {
            if doc.songTitle == "Unknown" || doc.artistName == "Unknown" {
                if let persistentID = MPMediaEntityPersistentID(key), let song = songDict[persistentID] {
                    patchedLyrics[key] = SyncedLyricsDocument(
                        songTitle: song.title ?? "Unknown",
                        artistName: song.artist ?? "Unknown",
                        lines: doc.lines,
                        lastModified: doc.lastModified
                    )
                    didPatch = true
                }
            }
        }
        
        if didPatch {
            await MainActor.run {
                self.syncedLyrics = patchedLyrics
                if let encoded = try? JSONEncoder().encode(self.syncedLyrics) {
                    UserDefaults.standard.set(encoded, forKey: syncedLyricsKey)
                }
                MultipeerManager.shared.syncLyricsDatabase(documents: self.syncedLyrics)
            }
        }
    }
    
    private func createSections() {
        let grouped = Dictionary(grouping: songs) { song in
            let prefix = song.title?.prefix(1).uppercased() ?? "#"
            return "ABCDEFGHIJKLMNOPQRSTUVWXYZ".contains(prefix) ? prefix : "#"
        }
        let sortedKeys = grouped.keys.sorted {
            if $0 == "#" { return false }
            if $1 == "#" { return true }
            return $0 < $1
        }
        self.sections = sortedKeys.map { SongSection(letter: $0, songs: grouped[$0] ?? []) }
    }
    
    private func createArtistSections() {
        let allArtists = Set(songs.compactMap { $0.artist })
        let grouped = Dictionary(grouping: allArtists) { artist in
            let prefix = artist.prefix(1).uppercased()
            return "ABCDEFGHIJKLMNOPQRSTUVWXYZ".contains(prefix) ? String(prefix) : "#"
        }
        let sortedKeys = grouped.keys.sorted {
            if $0 == "#" { return false }
            if $1 == "#" { return true }
            return $0 < $1
        }
        self.artistSections = sortedKeys.map { ArtistSection(letter: $0, artists: grouped[$0]?.sorted() ?? []) }
    }
    
    func hasSyncedLyrics(song: MPMediaItem) -> Bool {
        return getSyncedLyrics(id: String(song.persistentID), title: song.title ?? "", artist: song.artist ?? "")?.isFullySynced == true
    }
    
    // MARK: - Smart Search Logic
    private func sanitize(_ text: String) -> String { return text.lowercased().folding(options: .diacriticInsensitive, locale: .current) }
    
    func smartFilterSongs(in source: [MPMediaItem], for query: String) -> [MPMediaItem] {
        let cleanQuery = sanitize(query)
        let tokens = cleanQuery.split(separator: " ")
        if tokens.isEmpty { return source }
        return source.filter { song in
            let t = sanitize(song.title ?? "")
            let a = sanitize(song.artist ?? "")
            let al = sanitize(song.albumTitle ?? "")
            return tokens.allSatisfy { token in t.contains(token) || a.contains(token) || al.contains(token) }
        }
    }
    
    func smartFilterAlbums(in source: [MPMediaItemCollection], for query: String) -> [MPMediaItemCollection] {
        let cleanQuery = sanitize(query)
        let tokens = cleanQuery.split(separator: " ")
        if tokens.isEmpty { return source }
        return source.filter { album in
            let t = sanitize(album.representativeItem?.albumTitle ?? "")
            let a = sanitize(album.representativeItem?.artist ?? "")
            return tokens.allSatisfy { token in t.contains(token) || a.contains(token) }
        }
    }
    
    func smartFilterArtists(in source: [String], for query: String) -> [String] {
        let cleanQuery = sanitize(query)
        let tokens = cleanQuery.split(separator: " ")
        if tokens.isEmpty { return source }
        return source.filter { artist in
            let t = sanitize(artist)
            return tokens.allSatisfy { token in t.contains(token) }
        }
    }
    
    func smartFilterPlaylists(in source: [MPMediaItemCollection], for query: String) -> [MPMediaItemCollection] {
        let cleanQuery = sanitize(query)
        let tokens = cleanQuery.split(separator: " ")
        if tokens.isEmpty { return source }
        return source.filter { playlist in
            let t = sanitize(playlist.value(forProperty: MPMediaPlaylistPropertyName) as? String ?? "")
            return tokens.allSatisfy { token in t.contains(token) }
        }
    }

    // MARK: - Pins Logic
    @Published var pinnedAlbumIDs: [String] = [] // Unified array storing both "apple_ID" and "local_Name"
    
    // FIX: Change to internal/public so the UI can unpin ghost states
    func togglePin(id: String) {
        var currentPins = UserDefaults.standard.stringArray(forKey: pinnedAlbumsKey) ?? []
        currentPins = currentPins.map { $0.contains("_") ? $0 : "apple_\($0)" } // Migrate legacy pins
        
        if currentPins.contains(id) {
            currentPins.removeAll { $0 == id }
        } else {
            currentPins.append(id)
        }
        UserDefaults.standard.set(currentPins, forKey: pinnedAlbumsKey)
        loadPinnedAlbums()
    }

    func togglePin(album: MPMediaItemCollection) {
        let id = "apple_\(album.persistentID)"
        if pinnedAlbumCache[id] != nil {
            pinnedAlbumCache.removeValue(forKey: id)
        } else {
            pinnedAlbumCache[id] = PinnedAlbumCache(title: album.representativeItem?.albumTitle ?? "Unknown", artist: album.representativeItem?.artist ?? "Unknown", applePersistentID: String(album.persistentID))
        }
        if let encoded = try? JSONEncoder().encode(pinnedAlbumCache) { UserDefaults.standard.set(encoded, forKey: pinnedAlbumCacheKey) }
        
        togglePin(id: id)
    }
    
    func togglePin(localAlbumName: String) {
        let id = "local_\(localAlbumName)"
        let artist = DownloadsManager.shared.downloadedSongs.first { $0.album == localAlbumName }?.artist ?? "Unknown"
        
        if pinnedAlbumCache[id] != nil {
            pinnedAlbumCache.removeValue(forKey: id)
        } else {
            pinnedAlbumCache[id] = PinnedAlbumCache(title: localAlbumName, artist: artist, applePersistentID: nil)
        }
        if let encoded = try? JSONEncoder().encode(pinnedAlbumCache) { UserDefaults.standard.set(encoded, forKey: pinnedAlbumCacheKey) }
        
        togglePin(id: id)
    }
    
    func isPinned(album: MPMediaItemCollection) -> Bool {
        return pinnedAlbumIDs.contains("apple_\(album.persistentID)")
    }
    
    func isPinned(localAlbumName: String) -> Bool {
        return pinnedAlbumIDs.contains("local_\(localAlbumName)")
    }
    
    // MARK: - Artwork Helpers
    func getArtwork(for albumPersistentID: UInt64, size: CGSize) -> UIImage? {
        let query = MPMediaQuery.albums()
        let predicate = MPMediaPropertyPredicate(value: albumPersistentID, forProperty: MPMediaEntityPropertyPersistentID)
        query.addFilterPredicate(predicate)
        
        return query.collections?.first?.representativeItem?.artwork?.image(at: size)
    }
    
    func loadPinnedAlbums() {
        let currentPins = UserDefaults.standard.stringArray(forKey: pinnedAlbumsKey) ?? []
        let sanitizedPins = currentPins.map { $0.contains("_") ? $0 : "apple_\($0)" }
        self.pinnedAlbumIDs = sanitizedPins
        
        // 1. Create a lookup dictionary for currently loaded albums (O(N))
        let appleAlbumDict = Dictionary(self.albums.map { (String($0.persistentID), $0) }, uniquingKeysWith: { first, _ in first })
        
        // 2. Pre-calculate the Unified list for the Home View
        var unified: [UnifiedAlbumItem] = []
        var didUpdateCache = false
        
        for idString in sanitizedPins {
            if idString.hasPrefix("apple_") {
                let appleID = String(idString.dropFirst(6))
                if let album = appleAlbumDict[appleID] {
                    unified.append(UnifiedAlbumItem(id: idString, title: album.representativeItem?.albumTitle ?? "Unknown", artist: album.representativeItem?.artist ?? "Unknown", sortTitle: "", appleAlbum: album, localWrapper: nil))
                    
                    // Update cache if missing
                    if pinnedAlbumCache[idString] == nil {
                        pinnedAlbumCache[idString] = PinnedAlbumCache(title: album.representativeItem?.albumTitle ?? "Unknown", artist: album.representativeItem?.artist ?? "Unknown", applePersistentID: String(album.persistentID))
                        didUpdateCache = true
                    }
                } else if let cached = pinnedAlbumCache[idString] {
                    // Show cached text immediately while album object loads
                    unified.append(UnifiedAlbumItem(id: idString, title: cached.title, artist: cached.artist, sortTitle: "", appleAlbum: nil, localWrapper: nil))
                }
            } else if idString.hasPrefix("local_") {
                let localName = String(idString.dropFirst(6))
                let songs = DownloadsManager.shared.downloadedSongs.filter { $0.album == localName }
                if !songs.isEmpty {
                    unified.append(UnifiedAlbumItem(id: idString, title: localName, artist: songs.first?.artist ?? "Unknown", sortTitle: "", appleAlbum: nil, localWrapper: LocalAlbumWrapper(name: localName, songs: songs)))
                    
                    if pinnedAlbumCache[idString] == nil {
                        pinnedAlbumCache[idString] = PinnedAlbumCache(title: localName, artist: songs.first?.artist ?? "Unknown", applePersistentID: nil)
                        didUpdateCache = true
                    }
                } else if let cached = pinnedAlbumCache[idString] {
                    unified.append(UnifiedAlbumItem(id: idString, title: cached.title, artist: cached.artist, sortTitle: "", appleAlbum: nil, localWrapper: nil))
                }
            }
        }
        
        self.pinnedUnifiedAlbums = unified
        
        // Update compatibility list
        self.pinnedAlbums = unified.compactMap { $0.appleAlbum }
        
        if didUpdateCache, let encoded = try? JSONEncoder().encode(pinnedAlbumCache) {
            UserDefaults.standard.set(encoded, forKey: pinnedAlbumCacheKey)
        }
    }
    
    func movePinnedAlbum(from source: IndexSet, to destination: Int) {
        pinnedAlbumIDs.move(fromOffsets: source, toOffset: destination)
        UserDefaults.standard.set(pinnedAlbumIDs, forKey: pinnedAlbumsKey)
        loadPinnedAlbums()
    }
    
    func deletePinnedAlbum(at offsets: IndexSet) {
        pinnedAlbumIDs.remove(atOffsets: offsets)
        UserDefaults.standard.set(pinnedAlbumIDs, forKey: pinnedAlbumsKey)
        loadPinnedAlbums()
    }
    
    // MARK: - Reordering Logic
    func moveMenuItem(from source: IndexSet, to destination: Int) {
        menuItems.move(fromOffsets: source, toOffset: destination)
        UserDefaults.standard.set(menuItems, forKey: menuOrderKey)
    }
    
    // MARK: - Favorites Logic
    func toggleFavorite(song: MPMediaItem) {
        let id = String(song.persistentID)
        if localFavoriteIDs.contains(id) { localFavoriteIDs.remove(id) } else { localFavoriteIDs.insert(id) }
        UserDefaults.standard.set(Array(localFavoriteIDs), forKey: localFavoritesKey)
        objectWillChange.send()
        
        if AudioManager.shared.currentSong?.persistentID == song.persistentID {
            AudioManager.shared.isLiked = isSystemFavorite(song: song)
        }
    }
    
    func isSystemFavorite(song: MPMediaItem) -> Bool {
        if localFavoriteIDs.contains(String(song.persistentID)) { return true }
        if favoriteSongIDs.contains(song.persistentID) { return true }
        if song.rating >= 5 { return true }
        return false
    }
    func isSystemFavorite(album: MPMediaItemCollection) -> Bool {
        if let rep = album.representativeItem, rep.rating >= 5 { return true }
        return false
    }
}

struct AlbumArtCrop: Codable, Equatable {
    var top: CGFloat
    var bottom: CGFloat
    var leading: CGFloat
    var trailing: CGFloat
}

extension UIImage {
    func cropped(to normalizedRect: CGRect) -> UIImage? {
        // Redraw to normalize orientation before cropping
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let cgImage = normalizedImage?.cgImage else { return nil }
        
        let cropRect = CGRect(
            x: normalizedRect.origin.x * size.width * scale,
            y: normalizedRect.origin.y * size.height * scale,
            width: normalizedRect.size.width * size.width * scale,
            height: normalizedRect.size.height * size.height * scale
        )
        
        guard let croppedCG = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: croppedCG, scale: scale, orientation: .up)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue:  Double(b) / 255, opacity: Double(a) / 255)
    }

    func toHex() -> String? {
        let uic = UIColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return nil
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)
        
        if components.count >= 4 {
            a = Float(components[3])
        }
        
        if a != Float(1.0) {
            return String(format: "%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }
}

extension Array where Element == SyncedLyricLine {
    func activeIndex(for time: TimeInterval) -> Int? {
        var activeIdx: Int? = nil
        
        for (index, line) in self.enumerated() {
            if line.isUnsynced == true { continue } // Completely skip unsynced lines in the timeline
            
            if time >= line.startTime {
                activeIdx = index // Keep updating to the most recent passed timestamp
            } else {
                break // We've hit a future timestamp, stop searching
            }
        }
        
        // If the active line has a hard stop (endTime), check it
        if let idx = activeIdx, let endTime = self[idx].endTime {
            if time > endTime { return nil }
        }
        
        return activeIdx
    }
}
