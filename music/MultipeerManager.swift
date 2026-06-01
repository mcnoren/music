import Foundation
import MultipeerConnectivity
import Combine
import LiveKitWebRTC
#if os(iOS)
import UIKit
#endif

// MARK: - Reactive Download Observer
class DownloadTask: ObservableObject, Identifiable {
    let id: String // fileName
    @Published var metadata: DownloadMetadataPayload?
    @Published var fractionCompleted: Double = 0
    private var observation: NSKeyValueObservation?
    
    init(id: String, metadata: DownloadMetadataPayload? = nil) {
        self.id = id
        self.metadata = metadata
    }
    
    func attach(progress: Progress) {
        observation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] p, _ in
            DispatchQueue.main.async { self?.fractionCompleted = p.fractionCompleted }
        }
    }
}

struct AlbumArtTransform: Codable, Equatable {
    var scale: CGFloat
    var offsetX: CGFloat
    var offsetY: CGFloat
}

// Command structure for two-way control
struct SyncCommand: Codable {
    let command: String
}

// CHANGED: Unique variable names to prevent JSONDecoder confusion
struct ContextSyncPayload: Codable {
    let contextQueue: [RemoteSongDTO]
    var streamServerURL: String?
}

// MultipeerManager.swift (Shared)
struct LibrarySyncPayload: Codable {
    let masterLibrary: [RemoteSongDTO]
    var streamServerURL: String? // Add this property
}

struct ArtworkSyncPayload: Codable {
    let songId: String
    let artworkData: Data
}

// ---> ADD THIS NEW STRUCT <---
struct StreamLyricsPayload: Codable {
    let songId: String
    let lyrics: String?
    let syncedLyrics: [SyncedLyricLine]?
}

struct AlbumColorsSyncPayload: Codable {
    let colors: [String: String]
}

struct RemoteAlbumSummary: Codable, Hashable, Identifiable {
    var id: String { name }
    let name: String
    let artist: String
}

struct AlbumsSyncPayload: Codable {
    let albums: [RemoteAlbumSummary]
}

struct ArtistsSyncPayload: Codable {
    let artists: [String]
}

struct AlbumSettingsSyncPayload: Codable {
    var command: String = "syncAlbumSettings"
    let albumId: String
    let colors: [String: String]?
    let transform: AlbumArtTransform?
}

struct RemoteSongDTO: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String
    var artworkData: Data? = nil
    var duration: TimeInterval = 0
    var genre: String = "Album"
    var trackNumber: Int = 0
    var discNumber: Int?
    var hasRawLyrics: Bool = false
    var hasLyrics: Bool = false
    var hasSyncedLyrics: Bool = false
}

struct DownloadMetadataPayload: Codable {
    let fileName: String
    let title: String
    let artist: String
    let album: String
    let lyrics: String?
    let syncedLyrics: [SyncedLyricLine]?
    var trackNumber: Int? = 0
    var discNumber: Int?
    var albumColors: [String: String]?
    var albumTransform: AlbumArtTransform?
}

struct SyncedLyricsDocument: Codable, Hashable {
    let songTitle: String
    let artistName: String
    let lines: [SyncedLyricLine]
    let lastModified: Date
}

struct LyricsSyncPayload: Codable {
    let documents: [String: SyncedLyricsDocument]
}

struct PlaybackSyncPayload: Codable {
    let title: String
    let artist: String
    let currentTime: TimeInterval
    let isPlaying: Bool
    let currentLyric: String?
    
    var artworkData: Data? = nil
    var fullSyncedLyrics: [SyncedLyricLine]? = nil
    var isMetadataUpdate: Bool = false
    var isCasting: Bool = false
}

struct DevicePairingPayload: Codable {
    let macID: String
    let authToken: String
    let endToEndEncryptionKey: Data
}

enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case failed
}

class MultipeerManager: NSObject, ObservableObject {
    static let shared = MultipeerManager()
    
    private let serviceType = "music-sync"
    private let myPeerId: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    
    @Published var connectedPeers: [MCPeerID] = []
    @Published var latestPayload: PlaybackSyncPayload?
    @Published var remoteArtworkData: Data?
    @Published var remoteSyncedLyrics: [SyncedLyricLine] = []
    @Published var remoteAlbums: [RemoteAlbumSummary] = []
    @Published var remoteArtists: [String] = []
    
    @Published var remoteLibrary: [RemoteSongDTO] = []
    @Published var remoteContextQueue: [RemoteSongDTO] = []
    
    @Published var connectionState: ConnectionState = .disconnected
    @Published var isCastingToMac: Bool = false
    private var connectionTimer: Timer?
    
    @Published var downloadMessage: String = ""
    @Published var showDownloadAlert: Bool = false
    
    @Published var currentDownloads: [String: DownloadTask] = [:]
    @Published var cancelledDownloads: Set<String> = []
    
    @Published var macServerURL: String?
    
    @Published var isSyncingLibrary: Bool = false
    @Published var librarySyncProgress: Double = 0.0
    private var librarySyncObservation: NSKeyValueObservation?
    
    @Published var requestedArtworkAlbums: Set<String> = []
        
    func requestArtworkLazily(for song: RemoteSongDTO) {
        #if os(iOS)
        let album = song.album
        guard !requestedArtworkAlbums.contains(album) else { return }
        
        // Prevent re-downloading if we already have it safely cached
        if LibraryManager.shared.getCachedRemoteArtwork(albumName: album) == nil {
            requestedArtworkAlbums.insert(album)
            sendCommand("REQUEST_ARTWORK:\(song.id)")
        }
        #endif
    }
    
    // Ensure this returns a Bool so the function above knows if it successfully parsed the JSON
    @discardableResult
    func processReceivedData(_ data: Data) -> Bool {
        if let payload = try? JSONDecoder().decode(PlaybackSyncPayload.self, from: data) {
            DispatchQueue.main.async { self.latestPayload = payload; if payload.isMetadataUpdate { self.remoteArtworkData = payload.artworkData; self.remoteSyncedLyrics = payload.fullSyncedLyrics ?? [] } }
            return true
        }
        else if let libraryPayload = try? JSONDecoder().decode(LibrarySyncPayload.self, from: data) {
            DispatchQueue.main.async {
                self.remoteLibrary = libraryPayload.masterLibrary
                
                #if os(iOS)
                LibraryManager.shared.saveCachedRemoteMetadata(libraryPayload.masterLibrary)
                #endif
                
                if let url = libraryPayload.streamServerURL {
                    self.macServerURL = url
                }
            }
            return true
        }
        else if let contextPayload = try? JSONDecoder().decode(ContextSyncPayload.self, from: data) {
            DispatchQueue.main.async {
                self.remoteContextQueue = contextPayload.contextQueue
                if let url = contextPayload.streamServerURL { self.macServerURL = url }
            }
            return true
        }
        else if let artworkPayload = try? JSONDecoder().decode(ArtworkSyncPayload.self, from: data) {
            DispatchQueue.main.async {
                var albumName = self.remoteLibrary.first(where: { $0.id == artworkPayload.songId })?.album
                if albumName == nil { albumName = self.remoteContextQueue.first(where: { $0.id == artworkPayload.songId })?.album }
                
                if let albumName = albumName {
                    #if os(iOS)
                    LibraryManager.shared.saveRemoteArtwork(data: artworkPayload.artworkData, albumName: albumName)
                    #endif
                    
                    for i in self.remoteLibrary.indices { if self.remoteLibrary[i].album == albumName { self.remoteLibrary[i].artworkData = artworkPayload.artworkData } }
                    for i in self.remoteContextQueue.indices { if self.remoteContextQueue[i].album == albumName { self.remoteContextQueue[i].artworkData = artworkPayload.artworkData } }
                }
                
                #if os(iOS)
                if AudioManager.shared.currentRemoteDTO?.id == artworkPayload.songId || AudioManager.shared.currentRemoteDTO?.album == albumName {
                    AudioManager.shared.currentRemoteDTO?.artworkData = artworkPayload.artworkData
                    AudioManager.shared.updateLockScreenInfo()
                }
                #endif
            }
            return true
        }
        else if let lyricsPayload = try? JSONDecoder().decode(StreamLyricsPayload.self, from: data) {
            DispatchQueue.main.async {
                #if os(iOS)
                if let raw = lyricsPayload.lyrics, !raw.isEmpty { LibraryManager.shared.customRawLyrics[lyricsPayload.songId] = raw }
                if let synced = lyricsPayload.syncedLyrics, !synced.isEmpty {
                    let song = self.remoteLibrary.first(where: { $0.id == lyricsPayload.songId }) ?? self.remoteContextQueue.first(where: { $0.id == lyricsPayload.songId })
                    if let s = song { LibraryManager.shared.saveSyncedLyrics(id: s.id, title: s.title, artist: s.artist, lines: synced) }
                }
                if AudioManager.shared.currentRemoteDTO?.id == lyricsPayload.songId {
                    let temp = AudioManager.shared.currentRemoteDTO
                    AudioManager.shared.currentRemoteDTO = nil
                    AudioManager.shared.currentRemoteDTO = temp
                }
                #endif
            }
            return true
        }
        else if let colorsPayload = try? JSONDecoder().decode(AlbumColorsSyncPayload.self, from: data) {
            DispatchQueue.main.async {
                #if os(macOS)
                var migratedColors: [String: [String: String]] = [:]
                for (albumId, hex) in colorsPayload.colors { migratedColors[albumId] = ["primary": hex] }
                MacLibrary.shared.customAlbumColors = migratedColors
                #else
                LibraryManager.shared.customAlbumColors = colorsPayload.colors
                #endif
            }
            return true
        }
        else if let albumsPayload = try? JSONDecoder().decode(AlbumsSyncPayload.self, from: data) {
            DispatchQueue.main.async { self.remoteAlbums = albumsPayload.albums }
            return true
        }
        else if let artistsPayload = try? JSONDecoder().decode(ArtistsSyncPayload.self, from: data) {
            DispatchQueue.main.async { self.remoteArtists = artistsPayload.artists }
            return true
        }
        else if let syncCmd = try? JSONDecoder().decode(SyncCommand.self, from: data) {
            DispatchQueue.main.async {
                #if os(iOS)
                if syncCmd.command == "STOP_CASTING" {
                    self.latestPayload?.isCasting = false
                } else if syncCmd.command.hasPrefix("DOWNLOAD_METADATA:") {
                    let jsonStr = syncCmd.command.replacingOccurrences(of: "DOWNLOAD_METADATA:", with: "")
                    if let metaData = jsonStr.data(using: .utf8), let meta = try? JSONDecoder().decode(DownloadMetadataPayload.self, from: metaData) {
                        self.currentDownloads[meta.fileName] = DownloadTask(id: meta.fileName, metadata: meta)
                        DownloadsManager.shared.saveMetadata(meta)
                    }
                } else if syncCmd.command.hasPrefix("STREAM_METADATA:") {
                    let jsonStr = syncCmd.command.replacingOccurrences(of: "STREAM_METADATA:", with: "")
                    if let metaData = jsonStr.data(using: .utf8), let meta = try? JSONDecoder().decode(DownloadMetadataPayload.self, from: metaData) {
                        AudioManager.shared.tempMetadataCache[meta.fileName] = meta
                    }
                } else if syncCmd.command.hasPrefix("DOWNLOAD_ERROR:") {
                    self.downloadMessage = syncCmd.command.replacingOccurrences(of: "DOWNLOAD_ERROR:", with: "")
                    self.showDownloadAlert = true
                }
                #elseif os(macOS)
                if syncCmd.command == "REQUEST_LIBRARY" {
                    if let libraryData = self.onRequestLibrary?() {
                        let serverURL = MacStreamServer.shared.start()
                        let payload = LibrarySyncPayload(masterLibrary: libraryData, streamServerURL: serverURL)
                        if let encoded = try? JSONEncoder().encode(payload) {
                            
                            // 👉 WRITE TO TEMP FILE AND SEND AS A RESOURCE FOR ACCURATE PROGRESS
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("LIBRARY_METADATA_SYNC.json")
                            do {
                                try encoded.write(to: tempURL)
                                for peer in self.session.connectedPeers {
                                    self.session.sendResource(at: tempURL, withName: "LIBRARY_METADATA_SYNC", toPeer: peer) { error in
                                        if let e = error { print("Failed to send library resource: \(e)") }
                                    }
                                }
                            } catch {
                                print("Failed to write library temp file: \(error)")
                            }
                        }
                    } else if syncCmd.command == "REQUEST_ALL_ALBUMS" {
                        if let albums = self.onRequestAlbums?() {
                            let payload = AlbumsSyncPayload(albums: albums)
                            if let encoded = try? JSONEncoder().encode(payload) { self.sendDataToPeers(encoded) }
                        }
                    }
                } else if syncCmd.command == "REQUEST_ALL_ARTISTS" {
                    if let artists = self.onRequestArtists?() {
                        let payload = ArtistsSyncPayload(artists: artists)
                        if let encoded = try? JSONEncoder().encode(payload) { self.sendDataToPeers(encoded) }
                    }
                } else if syncCmd.command.hasPrefix("REQUEST_ALBUM_SONGS:") {
                    let album = syncCmd.command.replacingOccurrences(of: "REQUEST_ALBUM_SONGS:", with: "")
                    if let songs = self.onRequestSongsForAlbum?(album) {
                        let serverURL = MacStreamServer.shared.start()
                        let payload = ContextSyncPayload(contextQueue: songs, streamServerURL: serverURL)
                        if let encoded = try? JSONEncoder().encode(payload) { self.sendDataToPeers(encoded) }
                    }
                } else if syncCmd.command.hasPrefix("REQUEST_ARTIST_SONGS:") {
                    let artist = syncCmd.command.replacingOccurrences(of: "REQUEST_ARTIST_SONGS:", with: "")
                    if let songs = self.onRequestSongsForArtist?(artist) {
                        let serverURL = MacStreamServer.shared.start()
                        let payload = ContextSyncPayload(contextQueue: songs, streamServerURL: serverURL)
                        if let encoded = try? JSONEncoder().encode(payload) { self.sendDataToPeers(encoded) }
                    }
                } else if syncCmd.command.hasPrefix("REQUEST_ARTWORK:") {
                    self.onRequestArtwork?(syncCmd.command.replacingOccurrences(of: "REQUEST_ARTWORK:", with: ""))
                } else if syncCmd.command.hasPrefix("REQUEST_LYRICS:") {
                    let songId = syncCmd.command.replacingOccurrences(of: "REQUEST_LYRICS:", with: "")
                    self.onRequestLyrics?(songId)
                    if let song = MacLibrary.shared.songs.first(where: { $0.id == songId }) {
                        let synced = MacLibrary.shared.syncedLyrics[songId]?.lines
                        let payload = StreamLyricsPayload(songId: songId, lyrics: song.lyrics, syncedLyrics: synced)
                        if let encoded = try? JSONEncoder().encode(payload) { self.sendDataToPeers(encoded) }
                    }
                } else if syncCmd.command.hasPrefix("PLAY_SONG:") {
                    self.onPlayRequestedSong?(syncCmd.command.replacingOccurrences(of: "PLAY_SONG:", with: ""))
                } else if syncCmd.command.hasPrefix("DOWNLOAD_SONG:") {
                    self.onDownloadRequestedSong?(syncCmd.command.replacingOccurrences(of: "DOWNLOAD_SONG:", with: ""))
                } else if syncCmd.command.hasPrefix("STREAM_SONG:") {
                    self.onStreamRequestedSong?(syncCmd.command.replacingOccurrences(of: "STREAM_SONG:", with: ""))
                }
                #endif
            }
            return true
        }
        else if let settingsPayload = try? JSONDecoder().decode(AlbumSettingsSyncPayload.self, from: data) {
            DispatchQueue.main.async {
                #if os(macOS)
                MacLibrary.shared.saveAlbumSettings(albumId: settingsPayload.albumId, colors: settingsPayload.colors, transform: settingsPayload.transform)
                #else
                LibraryManager.shared.saveAlbumSettings(albumId: settingsPayload.albumId, colors: settingsPayload.colors, transform: settingsPayload.transform)
                #endif
            }
            return true
        }
        
        return false // If it gets here, it was NOT a valid JSON payload
    }
    
    func processReceivedData(_ data: Data) {
        if let payload = try? JSONDecoder().decode(PlaybackSyncPayload.self, from: data) {
            DispatchQueue.main.async { self.latestPayload = payload; if payload.isMetadataUpdate { self.remoteArtworkData = payload.artworkData; self.remoteSyncedLyrics = payload.fullSyncedLyrics ?? [] } }
        }
        else if let libraryPayload = try? JSONDecoder().decode(LibrarySyncPayload.self, from: data) {
            DispatchQueue.main.async {
                self.remoteLibrary = libraryPayload.masterLibrary
                
                #if os(iOS)
                LibraryManager.shared.saveCachedRemoteMetadata(libraryPayload.masterLibrary)
                #endif
                
                if let url = libraryPayload.streamServerURL {
                    self.macServerURL = url
                }
            }
        }
        else if let contextPayload = try? JSONDecoder().decode(ContextSyncPayload.self, from: data) {
            DispatchQueue.main.async {
                self.remoteContextQueue = contextPayload.contextQueue
                if let url = contextPayload.streamServerURL {
                    self.macServerURL = url
                }
            }
        }
        else if let artworkPayload = try? JSONDecoder().decode(ArtworkSyncPayload.self, from: data) {
            DispatchQueue.main.async {
                var albumName = self.remoteLibrary.first(where: { $0.id == artworkPayload.songId })?.album
                if albumName == nil {
                    albumName = self.remoteContextQueue.first(where: { $0.id == artworkPayload.songId })?.album
                }
                
                if let albumName = albumName {
                    #if os(iOS)
                    LibraryManager.shared.saveRemoteArtwork(data: artworkPayload.artworkData, albumName: albumName)
                    #endif
                    
                    for i in self.remoteLibrary.indices {
                        if self.remoteLibrary[i].album == albumName { self.remoteLibrary[i].artworkData = artworkPayload.artworkData }
                    }
                    for i in self.remoteContextQueue.indices {
                        if self.remoteContextQueue[i].album == albumName { self.remoteContextQueue[i].artworkData = artworkPayload.artworkData }
                    }
                }
                
                #if os(iOS)
                if AudioManager.shared.currentRemoteDTO?.id == artworkPayload.songId || AudioManager.shared.currentRemoteDTO?.album == albumName {
                    AudioManager.shared.currentRemoteDTO?.artworkData = artworkPayload.artworkData
                    AudioManager.shared.updateLockScreenInfo()
                }
                #endif
            }
        }
        else if let lyricsPayload = try? JSONDecoder().decode(StreamLyricsPayload.self, from: data) {
            DispatchQueue.main.async {
                #if os(iOS)
                // 1. Save Raw Lyrics
                if let raw = lyricsPayload.lyrics, !raw.isEmpty {
                    LibraryManager.shared.customRawLyrics[lyricsPayload.songId] = raw
                }
                
                // 2. Save Synced Lyrics
                if let synced = lyricsPayload.syncedLyrics, !synced.isEmpty {
                    let song = self.remoteLibrary.first(where: { $0.id == lyricsPayload.songId }) ?? self.remoteContextQueue.first(where: { $0.id == lyricsPayload.songId })
                    if let s = song {
                        LibraryManager.shared.saveSyncedLyrics(id: s.id, title: s.title, artist: s.artist, lines: synced)
                    }
                }
                
                // 3. Force UI Update if this is the currently playing song
                if AudioManager.shared.currentRemoteDTO?.id == lyricsPayload.songId {
                    let temp = AudioManager.shared.currentRemoteDTO
                    AudioManager.shared.currentRemoteDTO = nil
                    AudioManager.shared.currentRemoteDTO = temp
                }
                #endif
            }
        }
        else if let colorsPayload = try? JSONDecoder().decode(AlbumColorsSyncPayload.self, from: data) {
            DispatchQueue.main.async {
                #if os(macOS)
                var migratedColors: [String: [String: String]] = [:]
                for (albumId, hex) in colorsPayload.colors {
                    migratedColors[albumId] = ["primary": hex]
                }
                MacLibrary.shared.customAlbumColors = migratedColors
                #else
                LibraryManager.shared.customAlbumColors = colorsPayload.colors
                #endif
            }
            return
        }
        else if let albumsPayload = try? JSONDecoder().decode(AlbumsSyncPayload.self, from: data) {
            DispatchQueue.main.async { self.remoteAlbums = albumsPayload.albums }
        }
        else if let artistsPayload = try? JSONDecoder().decode(ArtistsSyncPayload.self, from: data) {
            DispatchQueue.main.async { self.remoteArtists = artistsPayload.artists }
        }
        else if let syncCmd = try? JSONDecoder().decode(SyncCommand.self, from: data) {
            DispatchQueue.main.async {
                
                #if os(iOS)
                if syncCmd.command == "STOP_CASTING" {
                    self.latestPayload?.isCasting = false
                } else if syncCmd.command.hasPrefix("DOWNLOAD_METADATA:") {
                    let jsonStr = syncCmd.command.replacingOccurrences(of: "DOWNLOAD_METADATA:", with: "")
                    if let metaData = jsonStr.data(using: .utf8),
                       let meta = try? JSONDecoder().decode(DownloadMetadataPayload.self, from: metaData) {
                        self.currentDownloads[meta.fileName] = DownloadTask(id: meta.fileName, metadata: meta)
                        DownloadsManager.shared.saveMetadata(meta)
                    }
                } else if syncCmd.command.hasPrefix("STREAM_METADATA:") {
                    let jsonStr = syncCmd.command.replacingOccurrences(of: "STREAM_METADATA:", with: "")
                    if let metaData = jsonStr.data(using: .utf8),
                       let meta = try? JSONDecoder().decode(DownloadMetadataPayload.self, from: metaData) {
                        AudioManager.shared.tempMetadataCache[meta.fileName] = meta
                    }
                } else if syncCmd.command.hasPrefix("DOWNLOAD_ERROR:") {
                    self.downloadMessage = syncCmd.command.replacingOccurrences(of: "DOWNLOAD_ERROR:", with: "")
                    self.showDownloadAlert = true
                }
                
                #elseif os(macOS)
                if syncCmd.command == "REQUEST_LIBRARY" {
                    if let libraryData = self.onRequestLibrary?() {
                        let serverURL = MacStreamServer.shared.start()
                        let payload = LibrarySyncPayload(masterLibrary: libraryData, streamServerURL: serverURL)
                        if let encoded = try? JSONEncoder().encode(payload) { self.sendDataToPeers(encoded) }
                    }
                } else if syncCmd.command == "REQUEST_ALL_ALBUMS" {
                    if let albums = self.onRequestAlbums?() {
                        let payload = AlbumsSyncPayload(albums: albums)
                        if let encoded = try? JSONEncoder().encode(payload) { self.sendDataToPeers(encoded) }
                    }
                } else if syncCmd.command == "REQUEST_ALL_ARTISTS" {
                    if let artists = self.onRequestArtists?() {
                        let payload = ArtistsSyncPayload(artists: artists)
                        if let encoded = try? JSONEncoder().encode(payload) { self.sendDataToPeers(encoded) }
                    }
                } else if syncCmd.command.hasPrefix("REQUEST_ALBUM_SONGS:") {
                    let album = syncCmd.command.replacingOccurrences(of: "REQUEST_ALBUM_SONGS:", with: "")
                    if let songs = self.onRequestSongsForAlbum?(album) {
                        let serverURL = MacStreamServer.shared.start()
                        let payload = ContextSyncPayload(contextQueue: songs, streamServerURL: serverURL)
                        if let encoded = try? JSONEncoder().encode(payload) { self.sendDataToPeers(encoded) }
                    }
                } else if syncCmd.command.hasPrefix("REQUEST_ARTIST_SONGS:") {
                    let artist = syncCmd.command.replacingOccurrences(of: "REQUEST_ARTIST_SONGS:", with: "")
                    if let songs = self.onRequestSongsForArtist?(artist) {
                        let serverURL = MacStreamServer.shared.start()
                        let payload = ContextSyncPayload(contextQueue: songs, streamServerURL: serverURL)
                        if let encoded = try? JSONEncoder().encode(payload) { self.sendDataToPeers(encoded) }
                    }
                } else if syncCmd.command.hasPrefix("REQUEST_ARTWORK:") {
                    self.onRequestArtwork?(syncCmd.command.replacingOccurrences(of: "REQUEST_ARTWORK:", with: ""))
                } else if syncCmd.command.hasPrefix("REQUEST_LYRICS:") {
                    let songId = syncCmd.command.replacingOccurrences(of: "REQUEST_LYRICS:", with: "")
                    self.onRequestLyrics?(songId)
                    
                    // Instantly process and send it back to the iPhone
                    if let song = MacLibrary.shared.songs.first(where: { $0.id == songId }) {
                        let synced = MacLibrary.shared.syncedLyrics[songId]?.lines
                        let payload = StreamLyricsPayload(songId: songId, lyrics: song.lyrics, syncedLyrics: synced)
                        if let encoded = try? JSONEncoder().encode(payload) {
                            self.sendDataToPeers(encoded)
                        }
                    }
                } else if syncCmd.command.hasPrefix("PLAY_SONG:") {
                    self.onPlayRequestedSong?(syncCmd.command.replacingOccurrences(of: "PLAY_SONG:", with: ""))
                } else if syncCmd.command.hasPrefix("DOWNLOAD_SONG:") {
                    self.onDownloadRequestedSong?(syncCmd.command.replacingOccurrences(of: "DOWNLOAD_SONG:", with: ""))
                } else if syncCmd.command.hasPrefix("STREAM_SONG:") {
                    self.onStreamRequestedSong?(syncCmd.command.replacingOccurrences(of: "STREAM_SONG:", with: ""))
                }
                #endif
            }
        }
        if let settingsPayload = try? JSONDecoder().decode(AlbumSettingsSyncPayload.self, from: data) {
            DispatchQueue.main.async {
                #if os(macOS)
                // Save to Mac's local storage
                MacLibrary.shared.saveAlbumSettings(
                    albumId: settingsPayload.albumId,
                    colors: settingsPayload.colors,
                    transform: settingsPayload.transform
                )
                #else
                // Save to iPhone's local storage
                LibraryManager.shared.saveAlbumSettings(
                    albumId: settingsPayload.albumId,
                    colors: settingsPayload.colors,
                    transform: settingsPayload.transform
                )
                #endif
            }
            return
        }
    }
    
    func processReceivedData(_ data: Data) {
        if let payload = try? JSONDecoder().decode(PlaybackSyncPayload.self, from: data) {
            DispatchQueue.main.async { self.latestPayload = payload; if payload.isMetadataUpdate { self.remoteArtworkData = payload.artworkData; self.remoteSyncedLyrics = payload.fullSyncedLyrics ?? [] } }
        }
        // CHANGED: Listens for unique masterLibrary variable
        else if let libraryPayload = try? JSONDecoder().decode(LibrarySyncPayload.self, from: data) {
            DispatchQueue.main.async {
                self.remoteLibrary = libraryPayload.masterLibrary
                
                // 👉 Wrap the iOS-only save function
                #if os(iOS)
                LibraryManager.shared.saveCachedRemoteMetadata(libraryPayload.masterLibrary)
                
                // 👉 ADDED FIX: Request missing artwork for all cached remote albums
                let grouped = Dictionary(grouping: libraryPayload.masterLibrary, by: { $0.album })
                for (albumName, songs) in grouped {
                    if LibraryManager.shared.getCachedRemoteArtwork(albumName: albumName) == nil {
                        if let firstSong = songs.first {
                            self.sendCommand("REQUEST_ARTWORK:\(firstSong.id)")
                        }
                    }
                }
                #endif
                
                if let url = libraryPayload.streamServerURL {
                    self.macServerURL = url
                }
            }
        }
        // CHANGED: Listens for unique contextQueue variable
        else if let contextPayload = try? JSONDecoder().decode(ContextSyncPayload.self, from: data) {
            DispatchQueue.main.async {
                self.remoteContextQueue = contextPayload.contextQueue
                if let url = contextPayload.streamServerURL {
                    self.macServerURL = url
                }
            }
        }
        else if let artworkPayload = try? JSONDecoder().decode(ArtworkSyncPayload.self, from: data) {
            DispatchQueue.main.async {
                var albumName = self.remoteLibrary.first(where: { $0.id == artworkPayload.songId })?.album
                if albumName == nil {
                    albumName = self.remoteContextQueue.first(where: { $0.id == artworkPayload.songId })?.album
                }
                
                if let albumName = albumName {
                    
                    // 👉 Wrap the iOS-only save function
                    #if os(iOS)
                    LibraryManager.shared.saveRemoteArtwork(data: artworkPayload.artworkData, albumName: albumName)
                    #endif
                    
                    for i in self.remoteLibrary.indices {
                        if self.remoteLibrary[i].album == albumName { self.remoteLibrary[i].artworkData = artworkPayload.artworkData }
                    }
                    for i in self.remoteContextQueue.indices {
                        if self.remoteContextQueue[i].album == albumName { self.remoteContextQueue[i].artworkData = artworkPayload.artworkData }
                    }
                }
                
                #if os(iOS)
                if AudioManager.shared.currentRemoteDTO?.id == artworkPayload.songId || AudioManager.shared.currentRemoteDTO?.album == albumName {
                    AudioManager.shared.currentRemoteDTO?.artworkData = artworkPayload.artworkData
                    AudioManager.shared.updateLockScreenInfo()
                }
                #endif
            }
        }
        else if let lyricsPayload = try? JSONDecoder().decode(StreamLyricsPayload.self, from: data) {
            DispatchQueue.main.async {
                #if os(iOS)
                // 1. Save Raw Lyrics
                if let raw = lyricsPayload.lyrics, !raw.isEmpty {
                    LibraryManager.shared.customRawLyrics[lyricsPayload.songId] = raw
                }
                
                // 2. Save Synced Lyrics
                if let synced = lyricsPayload.syncedLyrics, !synced.isEmpty {
                    let song = self.remoteLibrary.first(where: { $0.id == lyricsPayload.songId }) ?? self.remoteContextQueue.first(where: { $0.id == lyricsPayload.songId })
                    if let s = song {
                        LibraryManager.shared.saveSyncedLyrics(id: s.id, title: s.title, artist: s.artist, lines: synced)
                    }
                }
                
                // 3. Force UI Update if this is the currently playing song
                if AudioManager.shared.currentRemoteDTO?.id == lyricsPayload.songId {
                    let temp = AudioManager.shared.currentRemoteDTO
                    AudioManager.shared.currentRemoteDTO = nil
                    AudioManager.shared.currentRemoteDTO = temp
                }
                #endif
            }
        }
        else if let colorsPayload = try? JSONDecoder().decode(AlbumColorsSyncPayload.self, from: data) {
            DispatchQueue.main.async {
                #if os(macOS)
                // Migrate the iPhone's flat dictionary into the Mac's nested dictionary
                var migratedColors: [String: [String: String]] = [:]
                for (albumId, hex) in colorsPayload.colors {
                    migratedColors[albumId] = ["primary": hex]
                }
                MacLibrary.shared.customAlbumColors = migratedColors
                #else
                LibraryManager.shared.customAlbumColors = colorsPayload.colors
                #endif
            }
            return
        }
        else if let albumsPayload = try? JSONDecoder().decode(AlbumsSyncPayload.self, from: data) {
            DispatchQueue.main.async { self.remoteAlbums = albumsPayload.albums }
        }
        else if let artistsPayload = try? JSONDecoder().decode(ArtistsSyncPayload.self, from: data) {
            DispatchQueue.main.async { self.remoteArtists = artistsPayload.artists }
        }
        else if let syncCmd = try? JSONDecoder().decode(SyncCommand.self, from: data) {
            DispatchQueue.main.async {
                
                #if os(iOS)
                if syncCmd.command == "STOP_CASTING" {
                    self.latestPayload?.isCasting = false
                } else if syncCmd.command.hasPrefix("DOWNLOAD_METADATA:") {
                    let jsonStr = syncCmd.command.replacingOccurrences(of: "DOWNLOAD_METADATA:", with: "")
                    if let metaData = jsonStr.data(using: .utf8),
                       let meta = try? JSONDecoder().decode(DownloadMetadataPayload.self, from: metaData) {
                        self.currentDownloads[meta.fileName] = DownloadTask(id: meta.fileName, metadata: meta)
                        DownloadsManager.shared.saveMetadata(meta)
                    }
                } else if syncCmd.command.hasPrefix("STREAM_METADATA:") {
                    let jsonStr = syncCmd.command.replacingOccurrences(of: "STREAM_METADATA:", with: "")
                    if let metaData = jsonStr.data(using: .utf8),
                       let meta = try? JSONDecoder().decode(DownloadMetadataPayload.self, from: metaData) {
                        AudioManager.shared.tempMetadataCache[meta.fileName] = meta
                    }
                } else if syncCmd.command.hasPrefix("DOWNLOAD_ERROR:") {
                    self.downloadMessage = syncCmd.command.replacingOccurrences(of: "DOWNLOAD_ERROR:", with: "")
                    self.showDownloadAlert = true
                }
                
                #elseif os(macOS)
                if syncCmd.command == "REQUEST_LIBRARY" {
                    if let libraryData = self.onRequestLibrary?() {
                        let serverURL = MacStreamServer.shared.start()
                        let payload = LibrarySyncPayload(masterLibrary: libraryData, streamServerURL: serverURL)
                        if let encoded = try? JSONEncoder().encode(payload) { self.sendDataToPeers(encoded) }
                    }
                } else if syncCmd.command == "REQUEST_ALL_ALBUMS" {
                    if let albums = self.onRequestAlbums?() {
                        let payload = AlbumsSyncPayload(albums: albums)
                        if let encoded = try? JSONEncoder().encode(payload) { self.sendDataToPeers(encoded) }
                    }
                } else if syncCmd.command == "REQUEST_ALL_ARTISTS" {
                    if let artists = self.onRequestArtists?() {
                        let payload = ArtistsSyncPayload(artists: artists)
                        if let encoded = try? JSONEncoder().encode(payload) { self.sendDataToPeers(encoded) }
                    }
                } else if syncCmd.command.hasPrefix("REQUEST_ALBUM_SONGS:") {
                    let album = syncCmd.command.replacingOccurrences(of: "REQUEST_ALBUM_SONGS:", with: "")
                    if let songs = self.onRequestSongsForAlbum?(album) {
                        let serverURL = MacStreamServer.shared.start()
                        let payload = ContextSyncPayload(contextQueue: songs, streamServerURL: serverURL)
                        if let encoded = try? JSONEncoder().encode(payload) { self.sendDataToPeers(encoded) }
                    }
                } else if syncCmd.command.hasPrefix("REQUEST_ARTIST_SONGS:") {
                    let artist = syncCmd.command.replacingOccurrences(of: "REQUEST_ARTIST_SONGS:", with: "")
                    if let songs = self.onRequestSongsForArtist?(artist) {
                        let serverURL = MacStreamServer.shared.start()
                        let payload = ContextSyncPayload(contextQueue: songs, streamServerURL: serverURL)
                        if let encoded = try? JSONEncoder().encode(payload) { self.sendDataToPeers(encoded) }
                    }
                } else if syncCmd.command.hasPrefix("REQUEST_ARTWORK:") {
                    self.onRequestArtwork?(syncCmd.command.replacingOccurrences(of: "REQUEST_ARTWORK:", with: ""))
                } else if syncCmd.command.hasPrefix("REQUEST_LYRICS:") {
                    let songId = syncCmd.command.replacingOccurrences(of: "REQUEST_LYRICS:", with: "")
                    self.onRequestLyrics?(songId)
                    
                    // Instantly process and send it back to the iPhone
                    if let song = MacLibrary.shared.songs.first(where: { $0.id == songId }) {
                        let synced = MacLibrary.shared.syncedLyrics[songId]?.lines
                        let payload = StreamLyricsPayload(songId: songId, lyrics: song.lyrics, syncedLyrics: synced)
                        if let encoded = try? JSONEncoder().encode(payload) {
                            self.sendDataToPeers(encoded)
                        }
                    }
                } else if syncCmd.command.hasPrefix("PLAY_SONG:") {
                    self.onPlayRequestedSong?(syncCmd.command.replacingOccurrences(of: "PLAY_SONG:", with: ""))
                } else if syncCmd.command.hasPrefix("DOWNLOAD_SONG:") {
                    self.onDownloadRequestedSong?(syncCmd.command.replacingOccurrences(of: "DOWNLOAD_SONG:", with: ""))
                } else if syncCmd.command.hasPrefix("STREAM_SONG:") {
                    self.onStreamRequestedSong?(syncCmd.command.replacingOccurrences(of: "STREAM_SONG:", with: ""))
                }
                #endif
            }
        }
        if let settingsPayload = try? JSONDecoder().decode(AlbumSettingsSyncPayload.self, from: data) {
            DispatchQueue.main.async {
                #if os(macOS)
                // Save to Mac's local storage
                MacLibrary.shared.saveAlbumSettings(
                    albumId: settingsPayload.albumId,
                    colors: settingsPayload.colors,
                    transform: settingsPayload.transform
                )
                #else
                // Save to iPhone's local storage (Assuming you have a save function in LibraryManager)
                LibraryManager.shared.saveAlbumSettings(
                    albumId: settingsPayload.albumId,
                    colors: settingsPayload.colors,
                    transform: settingsPayload.transform
                )
                #endif
            }
            return
        }
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        DispatchQueue.main.async {
            // 👉 INTERCEPT THE LIBRARY SYNC TO POWER THE PROGRESS BAR
            if resourceName == "LIBRARY_METADATA_SYNC" {
                self.isSyncingLibrary = true
                self.librarySyncProgress = 0.0
                self.librarySyncObservation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] p, _ in
                    DispatchQueue.main.async {
                        self?.librarySyncProgress = p.fractionCompleted
                    }
                }
                return // Stop here so it doesn't show up in the Download Queue sheet
            }
            
            if self.currentDownloads[resourceName] == nil {
                self.currentDownloads[resourceName] = DownloadTask(id: resourceName)
            }
            self.currentDownloads[resourceName]?.attach(progress: progress)
        }
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {
            
        // 1. 👉 Unwrap the URL at the very top so ALL your code below can see it
        guard let tempURL = localURL else { return }
        
        #if os(iOS)
        DispatchQueue.main.async {
            
            // 2. Intercept the Library Sync
            if resourceName == "LIBRARY_METADATA_SYNC" {
                self.isSyncingLibrary = false
                self.librarySyncObservation?.invalidate()
                self.librarySyncObservation = nil
                
                if error == nil {
                    if let data = try? Data(contentsOf: tempURL) {
                        
                        // 3. 👉 Fix the ambiguity by explicitly forcing Swift to use the Void function
                        let processVoidVersion: (Data) -> Void = self.processReceivedData
                        processVoidVersion(data)
                        
                    }
                }
                
                // Clean up the temp metadata file
                try? FileManager.default.removeItem(at: tempURL)
                return // Stop here so it doesn't go into your actual song download queue below
            }
            
            let fileManager = FileManager.default
            if resourceName.hasPrefix("STREAM_") {
                let actualFileName = resourceName.replacingOccurrences(of: "STREAM_", with: "")
                let destinationURL = fileManager.temporaryDirectory.appendingPathComponent(actualFileName)
                
                do {
                    if fileManager.fileExists(atPath: destinationURL.path) { try fileManager.removeItem(at: destinationURL) }
                    try fileManager.moveItem(at: tempURL, to: destinationURL)
                    try fileManager.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: destinationURL.path)
                    
                    AudioManager.shared.handleStreamFileReady(fileName: actualFileName, url: destinationURL)
                } catch {
                    print("Stream save error: \(error)")
                }
            } else {
                guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
                let destinationURL = documents.appendingPathComponent(resourceName)
                
                do {
                    if fileManager.fileExists(atPath: destinationURL.path) { try fileManager.removeItem(at: destinationURL) }
                    try fileManager.moveItem(at: tempURL, to: destinationURL)
                    try fileManager.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: destinationURL.path)
                    
                    NotificationCenter.default.post(name: NSNotification.Name("NewDownloadComplete"), object: nil)
                    
                    self.downloadMessage = "Successfully downloaded \(resourceName)!"
                    self.showDownloadAlert = true
                    
                } catch {
                    self.downloadMessage = "Failed to save file: \(error.localizedDescription)"
                    self.showDownloadAlert = true
                }
            }
        }
        #endif
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) { browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10) }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) { invitationHandler(true, session) }
}
