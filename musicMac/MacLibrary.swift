//
//  MacLibrary.swift
//  musicMac
//

import Foundation
import AVFoundation
import SwiftUI
import Combine

struct SyncedLyricLine: Codable, Hashable {
    let text: String
    var startTime: TimeInterval
    var endTime: TimeInterval?
    var wordTimings: [WordTiming]?
    var isUnsynced: Bool? // NEW: Keeps JSON decoding from failing during peer sync
}

extension Array where Element == SyncedLyricLine {
    var isFullySynced: Bool {
        guard !isEmpty else { return false }
        return self.last?.isUnsynced != true
    }
}

struct WordTiming: Codable, Hashable {
    let word: String
    var startTime: TimeInterval
}

struct MacSong: Identifiable, Hashable, Codable {
    let id: String
    let url: URL
    var title: String
    var artist: String
    var album: String
    var genre: String
    var lyrics: String?
    var duration: TimeInterval
    var trackNumber: Int
    var discNumber: Int? // NEW
    
    // ... (keep the artwork var the same)
    
    // Dynamically load the artwork from the local folder when the UI asks for it
    var artwork: NSImage? {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let artworkDir = paths[0].appendingPathComponent("MacLibrary_Artwork")
        
        // Sanitize the album name so it's a valid filename
        let safeAlbumName = album.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let fileURL = artworkDir.appendingPathComponent("\(safeAlbumName).jpg")
        
        if let data = try? Data(contentsOf: fileURL) {
            return NSImage(data: data)
        }
        return nil
    }
}

struct MacPlaylist: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var songIDs: [String]
}

class MacLibrary: ObservableObject {
    static let shared = MacLibrary()
    
    @Published var songs: [MacSong] = []
    @Published var isImporting = false
    
    @Published var syncedLyrics: [String: SyncedLyricsDocument] = [:]
    @Published var playlists: [MacPlaylist] = []
    @Published var customAlbumColors: [String: [String: String]] = [:]
    @Published var customAlbumTransforms: [String: AlbumArtTransform] = [:]
    private let albumColorsKey = "MacAlbumColorsPersistenceKey"
    
    private let syncedLyricsKey = "MacSyncedLyricsPersistenceKey"
    private let playlistsKey = "MacPlaylistsPersistenceKey"
    private let songsKey = "MacSongsPersistenceKey"
    
    var albums: [String: [MacSong]] {
        Dictionary(grouping: songs, by: { $0.album })
    }
    
    init() {
        loadData()
        loadAlbumSettings()
    }
    
    // MARK: - Persistence
    func loadData() {
        // 1. Load Songs from the new JSON File
        if let data = try? Data(contentsOf: getLibraryFileURL()),
           let decoded = try? JSONDecoder().decode([MacSong].self, from: data) {
            self.songs = decoded
        }
        
        // 2. Load Playlists from UserDefaults
        if let data = UserDefaults.standard.data(forKey: playlistsKey),
           let decoded = try? JSONDecoder().decode([MacPlaylist].self, from: data) {
            self.playlists = decoded
        }
        
        // 3. Load Synced Lyrics from UserDefaults
        if let data = UserDefaults.standard.data(forKey: syncedLyricsKey),
           let decoded = try? JSONDecoder().decode([String: SyncedLyricsDocument].self, from: data) {
            self.syncedLyrics = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: albumColorsKey),
           let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            self.customAlbumColors = decoded
        }
        
        // 4. Run your existing lyrics patch
        var didPatch = false
        for (key, doc) in self.syncedLyrics {
            if doc.songTitle == "Unknown" || doc.artistName == "Unknown" {
                if let song = self.songs.first(where: { $0.id == key }) {
                    self.syncedLyrics[key] = SyncedLyricsDocument(
                        songTitle: song.title,
                        artistName: song.artist,
                        lines: doc.lines,
                        lastModified: doc.lastModified
                    )
                    didPatch = true
                }
            }
        }
        
        if didPatch {
            if let encoded = try? JSONEncoder().encode(self.syncedLyrics) {
                UserDefaults.standard.set(encoded, forKey: syncedLyricsKey)
            }
        }
    }
    
    func loadAlbumSettings() {
        if let data = UserDefaults.standard.data(forKey: "MacAlbumColors"),
           let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            self.customAlbumColors = decoded
        }
        if let data = UserDefaults.standard.data(forKey: "MacAlbumTransforms"),
           let decoded = try? JSONDecoder().decode([String: AlbumArtTransform].self, from: data) {
            self.customAlbumTransforms = decoded
        }
    }
    
    func saveSyncedLyrics(for song: MacSong, lines: [SyncedLyricLine]) {
        let doc = SyncedLyricsDocument(
            songTitle: song.title,
            artistName: song.artist,
            lines: lines,
            lastModified: Date()
        )
        syncedLyrics[song.id] = doc
        if let encoded = try? JSONEncoder().encode(syncedLyrics) {
            UserDefaults.standard.set(encoded, forKey: syncedLyricsKey)
        }
        
        // Push update to iPhone
        MultipeerManager.shared.syncLyricsDatabase(documents: syncedLyrics)
    }
    
    func merge(remoteLyrics: [String: SyncedLyricsDocument]) {
        var didUpdate = false
        for (songId, remoteDoc) in remoteLyrics {
            if let localDoc = syncedLyrics[songId] {
                if remoteDoc.lastModified > localDoc.lastModified {
                    syncedLyrics[songId] = remoteDoc
                    didUpdate = true
                }
            } else {
                syncedLyrics[songId] = remoteDoc
                didUpdate = true
            }
        }
        if didUpdate {
            if let encoded = try? JSONEncoder().encode(syncedLyrics) {
                UserDefaults.standard.set(encoded, forKey: syncedLyricsKey)
            }
        }
    }
    
    // MARK: - Playlist Management
    func createPlaylist(name: String) {
        playlists.append(MacPlaylist(name: name, songIDs: []))
        savePlaylists()
    }
    
    func addSongToPlaylist(_ song: MacSong, playlist: MacPlaylist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }), !playlists[index].songIDs.contains(song.id) {
            playlists[index].songIDs.append(song.id)
            savePlaylists()
        }
    }
    
    func addAlbumToPlaylist(_ albumSongs: [MacSong], playlist: MacPlaylist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            for song in albumSongs { if !playlists[index].songIDs.contains(song.id) { playlists[index].songIDs.append(song.id) } }
            savePlaylists()
        }
    }
    
    func deleteSong(_ song: MacSong) {
        // 1. Remove from the main library
        songs.removeAll { $0.id == song.id }
        saveSongs()
        
        // 2. Remove from any playlists to prevent dead links
        for i in 0..<playlists.count {
            playlists[i].songIDs.removeAll { $0 == song.id }
        }
        savePlaylists()
    }
    
    func clearAllFiles() {
        self.songs.removeAll()
        self.playlists.removeAll()
        saveSongs()
        savePlaylists()
    }
    
    func deleteAlbum(_ albumName: String) {
        // 1. Remove all matching songs
        songs.removeAll { $0.album == albumName }
        saveSongs()
        
        // 2. Clean up playlists to remove orphaned songs
        let validSongIDs = Set(songs.map { $0.id })
        for i in 0..<playlists.count {
            playlists[i].songIDs = playlists[i].songIDs.filter { validSongIDs.contains($0) }
        }
        savePlaylists()
    }
    
    func saveAlbumSettings(albumId: String, colors: [String: String]?, transform: AlbumArtTransform?) {
        if let colors = colors { customAlbumColors[albumId] = colors }
        if let transform = transform { customAlbumTransforms[albumId] = transform }
        
        if let encodedColors = try? JSONEncoder().encode(customAlbumColors) {
            UserDefaults.standard.set(encodedColors, forKey: "MacAlbumColors")
        }
        if let encodedTransforms = try? JSONEncoder().encode(customAlbumTransforms) {
            UserDefaults.standard.set(encodedTransforms, forKey: "MacAlbumTransforms")
        }
    }
    
    // MARK: - Persistence Helpers
    private func saveSongs() {
        DispatchQueue.global(qos: .background).async {
            if let encoded = try? JSONEncoder().encode(self.songs) {
                try? encoded.write(to: self.getLibraryFileURL(), options: .atomic)
            }
        }
    }
    
    private func savePlaylists() {
        if let encoded = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(encoded, forKey: playlistsKey)
        }
    }
    
    func getArtworkDirectoryURL() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("MacLibrary_Artwork")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    func hasSyncedLyrics(for song: MacSong) -> Bool {
        // 1. Direct ID match (Created on the Mac)
        if let lines = syncedLyrics[song.id]?.lines {
            return lines.isFullySynced
        }
        
        // 2. Fuzzy Match (Created on iPhone, synced to Mac with an Apple Music ID)
        let cleanTitle = song.title.lowercased().replacingOccurrences(of: " ", with: "")
        let cleanArtist = song.artist.lowercased().replacingOccurrences(of: " ", with: "")
        
        return syncedLyrics.values.first(where: { doc in
            let docTitle = doc.songTitle.lowercased().replacingOccurrences(of: " ", with: "")
            let docArtist = doc.artistName.lowercased().replacingOccurrences(of: " ", with: "")
            return docTitle == cleanTitle && docArtist == cleanArtist
        })?.lines.isFullySynced == true
    }
    
    // MARK: - File Importing
    func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true; panel.allowedContentTypes = [.audio]
        
        if panel.runModal() == .OK {
            isImporting = true
            
            // 1. Kick off a Task to handle the parsing concurrently
            Task {
                var newSongs: [MacSong] = []
                let fileManager = FileManager.default
                
                for url in panel.urls {
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
                        if isDir.boolValue {
                            if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                                for case let fileURL as URL in enumerator {
                                    if let song = await self.parseAudioFile(url: fileURL) { newSongs.append(song) }
                                }
                            }
                        } else {
                            if let song = await self.parseAudioFile(url: url) { newSongs.append(song) }
                        }
                    }
                }
                
                // 2. Hop back to the Main thread to update the UI
                await MainActor.run {
                    // NEW: Update existing songs with fresh metadata instead of ignoring them
                    for newSong in newSongs {
                        if let index = self.songs.firstIndex(where: { $0.url == newSong.url }) {
                            // The song exists, so replace it with the newly scanned version (grabbing the disc numbers!)
                            self.songs[index] = newSong
                        } else {
                            // It's a completely new song
                            self.songs.append(newSong)
                        }
                    }
                    
                    // Default Sort: Artist -> Album -> Track Number
                    self.songs.sort { ($0.artist, $0.album, $0.trackNumber) < ($1.artist, $1.album, $1.trackNumber) }
                    
                    self.saveSongs() // Save the updated library to disk
                    
                    self.isImporting = false
                }
            }
        }
    }
    
    private func getLibraryFileURL() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("MacLibrary_Songs.json")
    }
    
    // --- AGGRESSIVE METADATA PARSER ---
    private func parseAudioFile(url: URL) async -> MacSong? {
        let asset = AVAsset(url: url)
        
        // Wait for the asset to actually load before parsing
        guard let isPlayable = try? await asset.load(.isPlayable), isPlayable else { return nil }
        
        var title = url.deletingPathExtension().lastPathComponent
        var artist = "Unknown Artist"
        var album = "Unknown Album"
        var genre = "Unknown Genre"
        var artworkData: Data? = nil
        var lyrics: String?
        var trackNumber = 0
        var discNumber: Int? // NEW
        
        // Safely load duration
        let duration = (try? await asset.load(.duration).seconds) ?? 0.0
        
        // 1. Common Metadata
        if let commonMetadata = try? await asset.load(.commonMetadata) {
            for item in commonMetadata {
                switch item.commonKey?.rawValue {
                case "title": title = item.stringValue ?? title
                case "artist": artist = item.stringValue ?? artist
                case "albumName": album = item.stringValue ?? album
                case "type": genre = item.stringValue ?? genre
                case "artwork":
                    // SAVE THE ARTWORK TO THE FOLDER INSTEAD OF THE JSON
                    if let data = item.dataValue {
                        let safeAlbumName = album.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                        let fileURL = self.getArtworkDirectoryURL().appendingPathComponent("\(safeAlbumName).jpg")
                        
                        // Only write the file if we don't already have the cover for this album!
                        if !FileManager.default.fileExists(atPath: fileURL.path) {
                            var finalData = data
                            
                            // Compress the image down so it doesn't create huge files over Multipeer!
                            if let image = NSImage(data: data) {
                                let maxSize: CGFloat = 600.0
                                var newSize = image.size
                                if newSize.width > maxSize || newSize.height > maxSize {
                                    let ratio = min(maxSize / newSize.width, maxSize / newSize.height)
                                    newSize = NSSize(width: newSize.width * ratio, height: newSize.height * ratio)
                                }
                                
                                let resized = NSImage(size: newSize)
                                resized.lockFocus()
                                image.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
                                resized.unlockFocus()
                                
                                if let tiff = resized.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                                    if let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                                        finalData = jpeg
                                    }
                                }
                            }
                            
                            try? finalData.write(to: fileURL)
                        }
                    }
                default: break
                }
            }
        }
        
        // --- THE MAGIC FIX: Let Apple do the heavy lifting ---
        // AVAsset has dedicated native parsing for ID3 and MP4 lyrics that guarantees extraction
        if let nativeLyrics = try? await asset.load(.lyrics), !nativeLyrics.isEmpty {
            lyrics = nativeLyrics
        }
        
        // 2. Deep Dive (For Track Numbers, Disc Numbers, and Fallback Lyrics)
        if let formats = try? await asset.load(.availableMetadataFormats) {
            for format in formats {
                if let metadata = try? await asset.loadMetadata(for: format) {
                    for item in metadata {
                        let keyDesc = item.key?.description.lowercased() ?? ""
                        let commonKeyStr = item.commonKey?.rawValue.lowercased() ?? ""
                        let identifier = item.identifier?.rawValue.lowercased() ?? ""
                        
                        // 1. TRACK NUMBER
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
                        
                        // 2. DISC NUMBER (Now catches M4A 'disk' with a K)
                        if identifier.contains("disc") || identifier.contains("disk") || keyDesc.contains("tpos") {
                            if let str = item.stringValue {
                                let clean = str.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                if let d = Int(clean) { discNumber = d }
                            } else if let num = item.numberValue {
                                discNumber = num.intValue
                            } else if let data = item.dataValue, data.count >= 4 {
                                // M4A 'disk' tags use byte arrays just like track numbers
                                let disc = (Int(data[2]) << 8) | Int(data[3])
                                if disc > 0 { discNumber = disc }
                            }
                        }
                        
                        // 3. FALLBACK LYRICS
                        if lyrics == nil {
                            if keyDesc.contains("lyr") || keyDesc.contains("uslt") || keyDesc.contains("sylt") || keyDesc.contains("text") ||
                                commonKeyStr.contains("lyr") || identifier.contains("lyric") {
                                
                                if let str = item.stringValue, !str.isEmpty {
                                    lyrics = str
                                } else if let data = item.dataValue, let str = String(data: data, encoding: .utf8), !str.isEmpty {
                                    lyrics = str
                                }
                            }
                        }
                    }
                }
            }
        }
        let stableID = "\(title)-\(artist)".lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
        
        return MacSong(id: stableID, url: url, title: title, artist: artist, album: album, genre: genre, lyrics: lyrics, duration: duration, trackNumber: trackNumber, discNumber: discNumber)
    }
}
