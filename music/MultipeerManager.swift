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
    
    func cancelDownloads(for albumName: String) {
        DispatchQueue.main.async {
            let tasksToRemove = self.currentDownloads.values.filter { $0.metadata?.album == albumName }
            for task in tasksToRemove {
                self.cancelledDownloads.insert(task.id)
                self.currentDownloads.removeValue(forKey: task.id)
            }
        }
    }
    
    #if os(macOS)
    var onRequestLibrary: (() -> [RemoteSongDTO])?
    var onRequestAlbums: (() -> [RemoteAlbumSummary])?
    var onRequestArtists: (() -> [String])?
    var onRequestSongsForAlbum: ((String) -> [RemoteSongDTO])?
    var onRequestSongsForArtist: ((String) -> [RemoteSongDTO])?
    
    var onRequestArtwork: ((String) -> Void)?
    var onRequestLyrics: ((String) -> Void)?
    var onPlayRequestedSong: ((String) -> Void)?
    var onDownloadRequestedSong: ((String) -> Void)?
    var onStreamRequestedSong: ((String) -> Void)?
    var onReceiveLyricsSync: (([String: SyncedLyricsDocument]) -> Void)?
    var onPeerConnected: (() -> Void)?
    #endif

    func sendArtworkPayload(_ payload: ArtworkSyncPayload) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(payload)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("Failed to send artwork payload: \(error)")
        }
    }
    
    // MARK: - Unified Network Router
    func sendDataToPeers(_ data: Data, isBinary: Bool = false, isReliable: Bool = true) {
        // 1. Wi-Fi Route (Multipeer)
        if !session.connectedPeers.isEmpty {
            try? session.send(data, toPeers: session.connectedPeers, with: isReliable ? .reliable : .unreliable)
        }
        // 2. Cellular Route (WebRTC)
        // If Multipeer is empty, always pipe through WebRTC
        else {
            WebRTCManager.shared.sendToDataChannel(data, isBinary: isBinary)
        }
    }
    
    override init() {
        #if os(iOS)
        let defaultName = UIDevice.current.name
        #else
        let defaultName = Host.current().localizedName ?? "Mac"
        #endif
        
        // ⚠️ CRITICAL FIX 1: Persist the MCPeerID!
        // Generating a new one on every launch leaves "ghost" peers on the Mac server,
        // which completely blocks reconnection unless launched freshly from Xcode.
        if let data = UserDefaults.standard.data(forKey: "savedPeerID"),
           let savedPeerID = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data) {
            myPeerId = savedPeerID
        } else {
            myPeerId = MCPeerID(displayName: defaultName)
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: myPeerId, requiringSecureCoding: true) {
                UserDefaults.standard.set(data, forKey: "savedPeerID")
            }
        }
        
        super.init()
        setupSession()
        
        #if os(iOS)
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.disconnect() }
        // When coming back to the app, totally rebuild the session to clear dead background sockets
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in self?.rebuildSessionAndConnect() }
        DispatchQueue.main.async { self.startAutoConnect() }
        #endif
    }
    
    // NEW HELPER: Centralized Session Setup
    private func setupSession() {
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser.delegate = self
    }
    
    // NEW HELPER: Flushes out dead background connections
    func rebuildSessionAndConnect() {
        session?.disconnect()
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        
        setupSession()
        startAutoConnect()
    }
    
    func startAutoConnect() {
        guard connectionState != .connected else { return }
        connectionState = .connecting
        browser.startBrowsingForPeers()
    }
        
    func startBrowsing() {
        startAutoConnect()
    }
    
    func startAdvertising() { advertiser.startAdvertisingPeer() }
    
    func disconnect() {
        session.disconnect()
        DispatchQueue.main.async {
            self.connectionState = .disconnected
            self.connectedPeers = []
            self.isCastingToMac = false
            self.latestPayload?.isCasting = false
        }
    }
    
    func sendSyncPayload(_ payload: PlaybackSyncPayload) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            var finalPayload = payload
            finalPayload.isCasting = self.isCastingToMac
            let data = try JSONEncoder().encode(finalPayload)
            try session.send(data, toPeers: session.connectedPeers, with: .unreliable)
        } catch {}
    }
    
    func syncAlbumColors(colors: [String: String]) {
        guard !session.connectedPeers.isEmpty else { return }
        let payload = AlbumColorsSyncPayload(colors: colors)
        if let encoded = try? JSONEncoder().encode(payload) {
            try? session.send(encoded, toPeers: session.connectedPeers, with: .reliable)
        }
    }
    
    func sendCommand(_ command: String) {
        let syncCmd = SyncCommand(command: command)
        if let data = try? JSONEncoder().encode(syncCmd) {
            sendDataToPeers(data, isBinary: false)
        }
    }
    
    func sendStream(url: URL, streamName: String) {
        guard let peer = session.connectedPeers.first else { return }
        let hasAccess = url.startAccessingSecurityScopedResource()
        session.sendResource(at: url, withName: streamName, toPeer: peer) { [weak self] error in
            if hasAccess { url.stopAccessingSecurityScopedResource() }
            if let error = error {
                print("Stream transfer failed: \(error)")
                self?.sendCommand("DOWNLOAD_ERROR:Stream failed to load.")
            }
        }
    }
    
    func sendFile(url: URL) {
        guard let peer = session.connectedPeers.first else { return }
        let hasAccess = url.startAccessingSecurityScopedResource()
        session.sendResource(at: url, withName: url.lastPathComponent, toPeer: peer) { [weak self] error in
            if hasAccess { url.stopAccessingSecurityScopedResource() }
            if let error = error {
                print("File transfer failed: \(error)")
                self?.sendCommand("DOWNLOAD_ERROR:Failed to read file on Mac. Check macOS folder permissions.")
            }
        }
    }
    
    func syncLyricsDatabase(documents: [String: SyncedLyricsDocument]) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            let payload = LyricsSyncPayload(documents: documents)
            let data = try JSONEncoder().encode(payload)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("Failed to sync lyrics: \(error)")
        }
    }
}

extension MultipeerManager: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
            DispatchQueue.main.async {
                self.connectedPeers = session.connectedPeers
                if state == .connected {
                    self.connectionState = .connected
                    self.connectionTimer?.invalidate()
                    #if os(iOS)
                    self.syncLyricsDatabase(documents: LibraryManager.shared.syncedLyrics)
                    #elseif os(macOS)
                    DispatchQueue.main.async { self.onPeerConnected?() }
                    #endif
                } else if state == .notConnected {
                    self.connectionState = .disconnected
                    self.isCastingToMac = false
                    self.remoteLibrary = []
                    
                    #if os(macOS)
                    // THE FIX: Completely rebuild the Mac's session to purge "Ghost" peers
                    self.session?.disconnect()
                    self.advertiser?.stopAdvertisingPeer()
                    
                    self.setupSession() // Create a brand new, clean MCSession
                    self.advertiser.startAdvertisingPeer()
                    #elseif os(iOS)
                    self.startAutoConnect()
                    #endif
                }
            }
        }
    
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            var isHandled = false
            
            // 1. Check if it's a known string command
            if let text = String(data: data, encoding: .utf8) {
                isHandled = WebRTCManager.shared.handleCommand(text)
            }
            
            // 2. If it wasn't a command, check if it's a known JSON payload.
            // We check if it starts with 123 (the byte for '{') to avoid wasting CPU trying to JSON-decode raw audio
            if !isHandled, data.first == 123 {
                isHandled = self.processReceivedData(data)
            }
            
            // 3. THE FIX: If it wasn't a handled command AND wasn't valid JSON, it MUST be an audio chunk!
            if !isHandled {
                WebRTCManager.shared.downloadedData[WebRTCManager.shared.receivingSongId, default: Data()].append(data)
                WebRTCManager.shared.processPendingRequests()
            }
        }
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
                if let url = libraryPayload.streamServerURL { self.macServerURL = url }
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
        // CHANGED: Listens for unique masterLibrary variable
        else if let libraryPayload = try? JSONDecoder().decode(LibrarySyncPayload.self, from: data) {
            DispatchQueue.main.async {
                self.remoteLibrary = libraryPayload.masterLibrary
                // Add the server URL extraction here!
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
                    for i in self.remoteLibrary.indices {
                        if self.remoteLibrary[i].album == albumName { self.remoteLibrary[i].artworkData = artworkPayload.artworkData }
                    }
                    for i in self.remoteContextQueue.indices {
                        if self.remoteContextQueue[i].album == albumName { self.remoteContextQueue[i].artworkData = artworkPayload.artworkData }
                    }
                }
                
                // FIX: FORCE UI REFRESH. Inject the artwork directly into the active player so SwiftUI redraws!
                #if os(iOS)
                if AudioManager.shared.currentRemoteDTO?.id == artworkPayload.songId || AudioManager.shared.currentRemoteDTO?.album == albumName {
                    AudioManager.shared.currentRemoteDTO?.artworkData = artworkPayload.artworkData
                    AudioManager.shared.updateLockScreenInfo() // Update the Lock Screen too
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
            if self.currentDownloads[resourceName] == nil {
                self.currentDownloads[resourceName] = DownloadTask(id: resourceName)
            }
            self.currentDownloads[resourceName]?.attach(progress: progress)
        }
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {
        #if os(iOS)
        DispatchQueue.main.async {
            self.currentDownloads.removeValue(forKey: resourceName)
            
            if self.cancelledDownloads.contains(resourceName) {
                self.cancelledDownloads.remove(resourceName)
                if let tempURL = localURL { try? FileManager.default.removeItem(at: tempURL) }
                return
            }
            
            guard let tempURL = localURL, error == nil else {
                self.downloadMessage = "Transfer Interrupted: \(error?.localizedDescription ?? "Unknown Error")"
                self.showDownloadAlert = true
                return
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
