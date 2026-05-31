//
//  ContentView.swift
//  music
//

import SwiftUI
import MediaPlayer
import Combine
import AVKit
import PhotosUI
import LiveKitWebRTC
import PhotosUI
import CoreTransferable

// MARK: - Album Sorting & Filtering Enums
enum AlbumSortType: String, CaseIterable {
    case titleAZ = "Title (A-Z)"
    case titleZA = "Title (Z-A)"
    case artistAZ = "Artist (A-Z)"
    case trackCount = "Track Count"
}

enum AlbumFilterType: String, CaseIterable {
    case all = "All Albums"
    case full = "Full Albums (4+ Songs)"
}

// MARK: - Shared UI State (Preserves Layout Across Orientation)
class PlayerUIState: ObservableObject {
    @Published var isPlayerExpanded = false
    @Published var showLyrics = false
    @Published var isLyricsFullScreen = false
}

struct UnifiedArtworkView: View {
    let item: UnifiedAlbumItem
    let size: CGSize
    @ObservedObject var library = LibraryManager.shared
    
    var body: some View {
        Group {
            if let apple = item.appleAlbum, let artwork = apple.representativeItem?.artwork?.image(at: size) {
                Image(uiImage: artwork).resizable()
            } else if item.id.hasPrefix("apple_"), let appleID = UInt64(item.id.dropFirst(6)), let artwork = library.getArtwork(for: appleID, size: size) {
                Image(uiImage: artwork).resizable()
            } else if let local = item.localWrapper, let firstSong = local.songs.first, let data = firstSong.artworkData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable()
            } else {
                Rectangle().fill(Color.gray.opacity(0.3))
                    .overlay(Image(systemName: "music.note").font(.system(size: min(size.width, size.height) * 0.4)).foregroundColor(.gray))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .cornerRadius(size.width < 50 ? 4 : 12)
    }
}

struct SongIDsWrapper: Identifiable {
    let id = UUID()
    let ids: [String]
}

// MARK: - Navigation & Scroll State Manager
class NavigationStateManager: ObservableObject {
    @Published var navigationPath = NavigationPath()
    @Published var scrollID: String?
    @Published var currentAlbumID: String? = nil // <-- Add this
}

// MARK: - External Display Manager (For Apple TV / Screen Mirroring)
class ExternalDisplayManager: ObservableObject {
    var additionalWindows: [UIWindow] = []
    
    func setupObserver(audioManager: AudioManager, library: LibraryManager, uiState: PlayerUIState, settings: AppSettings) {
        handleConnectedScreens(audioManager: audioManager, library: library, uiState: uiState, settings: settings)
        NotificationCenter.default.addObserver(forName: UIScreen.didConnectNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.handleConnectedScreens(audioManager: audioManager, library: library, uiState: uiState, settings: settings) }
        }
        NotificationCenter.default.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.handleConnectedScreens(audioManager: audioManager, library: library, uiState: uiState, settings: settings) }
        }
        NotificationCenter.default.addObserver(forName: UIScreen.didDisconnectNotification, object: nil, queue: .main) { [weak self] notification in
            guard let screen = notification.object as? UIScreen else { return }
            self?.tearDownWindow(for: screen)
        }
    }
    
    private func handleConnectedScreens(audioManager: AudioManager, library: LibraryManager, uiState: PlayerUIState, settings: AppSettings) {
        for screen in UIScreen.screens where screen != UIScreen.main {
            if additionalWindows.contains(where: { $0.screen == screen }) { continue }
            let tvView = TVDisplayView(audioManager: audioManager, library: library, uiState: uiState, settings: settings)
            let hostingController = UIHostingController(rootView: tvView)
            
            let matchingScene = UIApplication.shared.connectedScenes.first { scene in (scene as? UIWindowScene)?.screen == screen } as? UIWindowScene
            let window: UIWindow
            if let windowScene = matchingScene { window = UIWindow(windowScene: windowScene) } else { window = UIWindow(frame: screen.bounds); window.screen = screen }
            
            window.rootViewController = hostingController
            window.isHidden = false
            additionalWindows.append(window)
        }
    }
    private func tearDownWindow(for screen: UIScreen) {
        if let index = additionalWindows.firstIndex(where: { $0.screen == screen }) {
            additionalWindows[index].isHidden = true
            additionalWindows.remove(at: index)
        }
    }
}

// MARK: - App Settings
class AppSettings: ObservableObject {
    @Published var landscapeMode: LandscapeMode { didSet { UserDefaults.standard.set(landscapeMode.rawValue, forKey: "landscapeMode") } }
    @Published var showListArtwork: Bool { didSet { UserDefaults.standard.set(showListArtwork, forKey: "showListArtwork") } }
    @Published var globalStartOffset: Double { didSet { UserDefaults.standard.set(globalStartOffset, forKey: "globalStartOffset") } }
    @Published var globalEndOffset: Double { didSet { UserDefaults.standard.set(globalEndOffset, forKey: "globalEndOffset") } }
    @Published var lyricColorName: LyricColorName { didSet { UserDefaults.standard.set(lyricColorName.rawValue, forKey: "lyricColorName") } }
    @Published var showMacTab: Bool = true { didSet { UserDefaults.standard.set(showMacTab, forKey: "showMacTab") } }
    @Published var rewindCountdown: Bool { didSet { UserDefaults.standard.set(rewindCountdown, forKey: "rewindCountdown") } }
    
    init() {
        self.landscapeMode = LandscapeMode(rawValue: UserDefaults.standard.string(forKey: "landscapeMode") ?? "") ?? .coverFlow
        self.showListArtwork = (UserDefaults.standard.object(forKey: "showListArtwork") as? Bool) ?? true
        self.globalStartOffset = UserDefaults.standard.double(forKey: "globalStartOffset")
        self.globalEndOffset = UserDefaults.standard.double(forKey: "globalEndOffset")
        self.lyricColorName = LyricColorName(rawValue: UserDefaults.standard.string(forKey: "lyricColorName") ?? "") ?? .red
        
        if UserDefaults.standard.object(forKey: "showMacTab") == nil {
            self.showMacTab = true
        } else {
            self.showMacTab = UserDefaults.standard.bool(forKey: "showMacTab")
        }
        
        if UserDefaults.standard.object(forKey: "rewindCountdown") == nil {
            self.rewindCountdown = true
        } else {
            self.rewindCountdown = UserDefaults.standard.bool(forKey: "rewindCountdown")
        }
    }
    
    enum LandscapeMode: String, CaseIterable, Identifiable { case coverFlow = "Cover Flow", fullPlayer = "Full Player", off = "Off"; var id: String { self.rawValue } }
    enum LyricColorName: String, CaseIterable, Identifiable {
        case red = "Red", pink = "Pink", blue = "Blue", green = "Green", yellow = "Yellow", orange = "Orange", purple = "Purple", white = "White"
        var id: String { self.rawValue }
        var color: Color { switch self { case .red: return .red; case .pink: return .pink; case .blue: return .blue; case .green: return .green; case .yellow: return .yellow; case .orange: return .orange; case .purple: return .purple; case .white: return .white } }
    }
}

// MARK: - Improved Color Extraction
extension UIImage {
    var dominantColor: Color {
        let size = CGSize(width: 20, height: 20); let width = Int(size.width); let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB(); var rawData = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &rawData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 4 * width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue), let cgImage = self.cgImage else { return .gray }
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        var totalR: Int = 0, totalG: Int = 0, totalB: Int = 0
        for y in 0..<height { for x in 0..<width { let i = (y * 4 * width) + (x * 4); totalR += Int(rawData[i]); totalG += Int(rawData[i + 1]); totalB += Int(rawData[i + 2]) } }
        let count = width * height
        return Color(red: Double(totalR) / Double(count) / 255.0, green: Double(totalG) / Double(count) / 255.0, blue: Double(totalB) / Double(count) / 255.0)
    }
}

func collectionStats(collection: MPMediaItemCollection) -> String {
    let count = collection.count
    let totalSeconds = collection.items.reduce(0) { $0 + $1.playbackDuration }
    let hours = Int(totalSeconds) / 3600
    let minutes = (Int(totalSeconds) % 3600) / 60
    return hours > 0 ? "\(count) Songs · \(hours) hr \(minutes) min" : "\(count) Songs · \(minutes) min"
}

func localCollectionStats(songs: [LocalSong]) -> String {
    let count = songs.count
    let totalSeconds = songs.reduce(0) { $0 + $1.duration }
    let hours = Int(totalSeconds) / 3600
    let minutes = (Int(totalSeconds) % 3600) / 60
    return hours > 0 ? "\(count) Songs · \(hours) hr \(minutes) min" : "\(count) Songs · \(minutes) min"
}

// MARK: - App Content View
struct ContentView: View {
    @StateObject var library = LibraryManager.shared
    @StateObject var audioManager = AudioManager.shared
    @StateObject var settings = AppSettings()
    @StateObject var navState = NavigationStateManager()
    @StateObject var uiState = PlayerUIState()
    @StateObject var externalDisplayManager = ExternalDisplayManager()
    @StateObject var multipeer = MultipeerManager.shared
    @StateObject var webrtc = WebRTCManager.shared
    
    @State private var showSearchSheet = false
    @State private var songIdToPlaylist: StringIdentifiable? = nil
    @State private var songIDsToPlaylist: SongIDsWrapper? = nil
    
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            if isLandscape && settings.landscapeMode != .off {
                LandscapeLayout(library: library, audioManager: audioManager, settings: settings, uiState: uiState)
            } else {
                ZStack(alignment: .bottom) {
                    PortraitLayout(library: library, audioManager: audioManager, settings: settings, navState: navState, uiState: uiState)
                    
                    VStack {
                        Spacer()
                        HStack(alignment: .center, spacing: 12) {
                            MiniPlayerCapsule(
                                audioManager: audioManager,
                                onExpand: {
                                    if audioManager.currentSong != nil || audioManager.currentLocalSong != nil || audioManager.currentRemoteDTO != nil {
                                        uiState.isPlayerExpanded = true
                                    }
                                }
                            )
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            
                            Button(action: { showSearchSheet = true }) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                    .frame(width: 50, height: 50)
                                    .background(.regularMaterial)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 4)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 8 : 16)
                    }
                }
                .fullScreenCover(isPresented: $uiState.isPlayerExpanded) {
                    FullPlayerView(audioManager: audioManager, library: library, uiState: uiState, settings: settings).presentationBackground(.clear)
                }
                .sheet(isPresented: $showSearchSheet) {
                    NavigationView {
                        GlobalSearchView(library: library, audioManager: audioManager, showSearchSheet: $showSearchSheet, navState: navState)
                            .navigationBarItems(trailing: Button("Done") { showSearchSheet = false })
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowAddToPlaylist"))) { notif in
                    if let id = notif.object as? String {
                        songIdToPlaylist = StringIdentifiable(value: id)
                    }
                }
                .sheet(item: $songIdToPlaylist) { item in
                    AddToPlaylistSheet(songId: item.value)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowAddToPlaylist"))) { notif in
                    if let ids = notif.object as? [String] {
                        songIDsToPlaylist = SongIDsWrapper(ids: ids)
                    }
                }
                .sheet(item: $songIDsToPlaylist) { wrapper in
                    AddToPlaylistSheet(songIDs: wrapper.ids)
                }
            }
        }
        .onAppear {
            let _ = DownloadsManager.shared // Force background init
            library.requestPermissionAndFetch()
            audioManager.onToggleFavorite = {
                if let song = audioManager.currentSong { DispatchQueue.main.async { library.toggleFavorite(song: song) } }
            }
            externalDisplayManager.setupObserver(audioManager: audioManager, library: library, uiState: uiState, settings: settings)
        }
        .onChange(of: audioManager.currentSong?.persistentID) { _ in checkAndShowLyrics() }
        .onChange(of: audioManager.currentLocalSong?.id) { _ in checkAndShowLyrics() }
        .onChange(of: audioManager.currentRemoteDTO?.id) { _ in checkAndShowLyrics() }
    }
    
    private func checkAndShowLyrics() {
        if let song = audioManager.currentSong {
            let hasSynced = library.getSyncedLyrics(id: String(song.persistentID), title: song.title ?? "", artist: song.artist ?? "")?.isFullySynced == true
            if hasSynced { uiState.showLyrics = true }
        } else if let localSong = audioManager.currentLocalSong {
            let hasSynced = (localSong.syncedLyrics ?? library.getSyncedLyrics(id: localSong.id, title: localSong.title, artist: localSong.artist))?.isFullySynced == true
            if hasSynced { uiState.showLyrics = true }
        } else if let remoteSong = audioManager.currentRemoteDTO {
            let hasSynced = library.getSyncedLyrics(id: remoteSong.id, title: remoteSong.title, artist: remoteSong.artist)?.isFullySynced == true
            if hasSynced { uiState.showLyrics = true }
        }
    }
}

// MARK: - Custom Playlist Views
struct StringIdentifiable: Identifiable {
    let id = UUID()
    let value: String
}

struct AddToPlaylistSheet: View {
    let songIDs: [String]
    @ObservedObject var library = LibraryManager.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                if library.customPlaylists.isEmpty {
                    Text("No custom playlists yet. Create one in the Playlists tab!")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(library.customPlaylists) { playlist in
                        Button(action: {
                            library.addSongsToPlaylist(songIDs: songIDs, playlistId: playlist.id)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            dismiss()
                        }) {
                            HStack {
                                if let data = playlist.artworkData, let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage).resizable().frame(width: 40, height: 40).cornerRadius(4)
                                } else {
                                    Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 40, height: 40).cornerRadius(4)
                                        .overlay(Image(systemName: "music.note.list").foregroundColor(.white))
                                }
                                Text(playlist.title).foregroundColor(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct AppPlaylistDetailView: View {
    let playlist: AppPlaylist
    @ObservedObject var library = LibraryManager.shared
    @ObservedObject var audioManager = AudioManager.shared
    @State private var selectedPhoto: PhotosPickerItem? = nil
    
    var currentPlaylist: AppPlaylist? {
        library.customPlaylists.first { $0.id == playlist.id }
    }
    
    var unifiedSongs: [UnifiedSongItem] {
        guard let pl = currentPlaylist else { return [] }
        return pl.songIDs.compactMap { idStr in
            if idStr.hasPrefix("apple_"), let appleID = UInt64(idStr.dropFirst(6)) {
                if let song = library.songs.first(where: { $0.persistentID == appleID }) {
                    return UnifiedSongItem(id: idStr, title: song.title ?? "", artist: song.artist ?? "", sortTitle: "", appleSong: song, localSong: nil)
                }
            } else if idStr.hasPrefix("local_") {
                let localId = String(idStr.dropFirst(6))
                if let song = DownloadsManager.shared.downloadedSongs.first(where: { $0.id == localId }) {
                    return UnifiedSongItem(id: idStr, title: song.title, artist: song.artist, sortTitle: "", appleSong: nil, localSong: song)
                }
            }
            return nil
        }
    }
    
    var body: some View {
        VStack {
            if let pl = currentPlaylist {
                List {
                    Section {
                        HStack(spacing: 16) {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                if let data = pl.artworkData, let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage).resizable().scaledToFill().frame(width: 120, height: 120).cornerRadius(8)
                                } else {
                                    Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 120, height: 120).cornerRadius(8)
                                        .overlay(
                                            VStack {
                                                Image(systemName: "photo.badge.plus").font(.title)
                                                Text("Add Cover").font(.caption).padding(.top, 4)
                                            }.foregroundColor(.white)
                                        )
                                }
                            }
                            Text(pl.title).font(.title).bold()
                        }.padding(.vertical, 8)
                    }
                    
                    Section(header: Text("Songs")) {
                        if unifiedSongs.isEmpty {
                            Text("No songs added yet. Long press a song anywhere in your library to add it here.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(unifiedSongs) { item in
                                if let apple = item.appleSong {
                                    SongRow(song: apple, audioManager: audioManager, library: library, showArtwork: true, showTrackNumber: false)
                                        .onTapGesture {
                                            audioManager.play(song: apple, queue: unifiedSongs.compactMap { $0.appleSong }) // Quick fallback for playing
                                        }
                                } else if let local = item.localSong {
                                    DownloadsSongRow(song: local, queue: unifiedSongs.compactMap { $0.localSong }, showArtwork: true, showTrackNumber: false, audioManager: audioManager)
                                }
                            }
                            .onMove { source, dest in
                                library.moveSongsInPlaylist(playlistId: pl.id, from: source, to: dest)
                            }
                            .onDelete { offsets in
                                library.deleteSongFromPlaylist(playlistId: pl.id, at: offsets)
                            }
                        }
                    }
                }
                .listStyle(.grouped)
            }
        }
        .navigationTitle(currentPlaylist?.title ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onChange(of: selectedPhoto) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    DispatchQueue.main.async { library.updatePlaylistArtwork(id: playlist.id, data: data) }
                }
            }
        }
    }
}

// MARK: - Portrait Layout Routing
struct PortraitLayout: View {
    @ObservedObject var library: LibraryManager
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var settings: AppSettings
    @ObservedObject var navState: NavigationStateManager
    @ObservedObject var uiState: PlayerUIState
    
    @State private var showSettings = false
    
    var body: some View {
        NavigationStack(path: $navState.navigationPath) {
            LibraryHomeView(library: library, audioManager: audioManager, settings: settings, showSettings: $showSettings, navState: navState)
                .navigationDestination(for: String.self) { destination in
                    switch destination {
                    case "Playlists": PlaylistListView(library: library, audioManager: audioManager, isSearching: .constant(false), showSettings: $showSettings)
                    case "Artists": ArtistListView(library: library, audioManager: audioManager)
                    case "Albums": AlbumListView(library: library, audioManager: audioManager, isSearching: .constant(false), showSettings: $showSettings)
                    case "Songs": SongListView(library: library, audioManager: audioManager, isSearching: .constant(false), showArtwork: settings.showListArtwork, showSettings: $showSettings)
                    case "Mac": RemoteLibraryWrapperView()
                    case "RemoteArtists": RemoteArtistListView(multipeer: MultipeerManager.shared)
                    case "RemoteAlbums": RemoteAlbumListView(multipeer: MultipeerManager.shared)
                    case "RemoteSongs": RemoteSongListView(multipeer: MultipeerManager.shared)
                    case "Genres":
                        GenreListView(library: library, audioManager: audioManager)
                    case "RemoteGenres":
                        RemoteGenreListView(multipeer: MultipeerManager.shared)
                    default: Text("Unknown Destination")
                    }
                }
                .navigationDestination(for: MPMediaItemCollection.self) { collection in
                    if let rep = collection.representativeItem, rep.albumTitle != nil {
                        AlbumDetailView(album: collection, audioManager: audioManager, library: library)
                            .onAppear { navState.currentAlbumID = String(collection.persistentID) }
                            .onDisappear { if navState.currentAlbumID == String(collection.persistentID) { navState.currentAlbumID = nil } }
                    }
                    else { PlaylistDetailView(playlist: collection, audioManager: audioManager, library: library) }
                }
                .navigationDestination(for: UnifiedAlbumItem.self) { item in
                    DynamicAlbumWrapper(item: item, library: library, audioManager: audioManager)
                        .onAppear { navState.currentAlbumID = item.id }
                        .onDisappear { if navState.currentAlbumID == item.id { navState.currentAlbumID = nil } }
                }
                .navigationDestination(for: UnifiedArtistItem.self) { item in
                    UnifiedArtistDetailView(item: item, library: library, audioManager: audioManager)
                }
                .navigationDestination(for: RemoteAlbumWrapper.self) { wrapper in
                    UniversalAlbumDetailView(albumName: wrapper.name, collection: .remote(wrapper.songs))
                        .onAppear { navState.currentAlbumID = "remote_\(wrapper.name)" }
                        .onDisappear { if navState.currentAlbumID == "remote_\(wrapper.name)" { navState.currentAlbumID = nil } }
                }
                .navigationDestination(for: RemoteArtistWrapper.self) { wrapper in
                    RemoteArtistDetailView(artistName: wrapper.name, multipeer: MultipeerManager.shared)
                }
                .navigationDestination(for: StringWrapper.self) { wrapper in
                    ArtistDetailView(artist: wrapper.value, library: library, audioManager: audioManager)
                }
                .navigationDestination(for: AppPlaylist.self) { playlist in
                    AppPlaylistDetailView(playlist: playlist)
                }
                .navigationDestination(for: UnifiedPlaylistItem.self) { item in
                    UnifiedPlaylistDetailView(item: item, library: library, audioManager: audioManager)
                }
        }
        .accentColor(.pink)
        .sheet(isPresented: $showSettings) { SettingsView(settings: settings) }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToAlbum"))) { notification in
            guard let songId = notification.object as? String else { return }
            
            // 1. Check if it's an Apple Music Song
            if let song = library.songs.first(where: { String($0.persistentID) == songId }),
               let album = library.albums.first(where: { $0.persistentID == song.albumPersistentID }) {
                
                let targetAlbumID = String(album.persistentID)
                if navState.currentAlbumID == targetAlbumID { return } // Already on page!
                
                let item = UnifiedAlbumItem(
                    id: targetAlbumID,
                    title: album.representativeItem?.albumTitle ?? "Unknown",
                    artist: album.representativeItem?.artist ?? "Unknown",
                    sortTitle: album.representativeItem?.albumTitle ?? "Unknown",
                    appleAlbum: album,
                    localWrapper: nil
                )
                
                // Clear the stack and push safely
                var newPath = NavigationPath()
                newPath.append(item)
                navState.navigationPath = newPath
                
            // 2. Check if it's a Local Downloaded Song
            } else if let localSong = DownloadsManager.shared.downloadedSongs.first(where: { $0.id == songId }) {
                let albumName = localSong.album
                let targetAlbumID = "local_\(albumName)"
                if navState.currentAlbumID == targetAlbumID { return } // Already on page!
                
                let songs = DownloadsManager.shared.downloadedSongs.filter { $0.album == albumName }
                let item = UnifiedAlbumItem(
                    id: targetAlbumID,
                    title: albumName,
                    artist: localSong.artist,
                    sortTitle: albumName,
                    appleAlbum: nil,
                    localWrapper: LocalAlbumWrapper(name: albumName, songs: songs)
                )
                
                // Clear the stack and push safely
                var newPath = NavigationPath()
                newPath.append(item)
                navState.navigationPath = newPath
                
            // 3. Check if it's a Remote Mac Stream
            } else if let remoteSong = audioManager.currentRemoteDTO, remoteSong.id == songId {
                let targetAlbumID = "remote_\(remoteSong.album)"
                if navState.currentAlbumID == targetAlbumID { return } // Already on page!
                
                let item = RemoteAlbumWrapper(name: remoteSong.album, songs: [])
                
                // Clear the stack and push safely
                var newPath = NavigationPath()
                newPath.append(item)
                navState.navigationPath = newPath
            }
        }
    }
}

struct StringWrapper: Hashable { let value: String }

struct ExpandableDescriptionView: View {
    let text: String
    let albumTitle: String
    var backgroundColor: Color = Color(.systemBackground)
    var textColor: Color = .primary // Defaults to primary if not provided
    
    @State private var showFull = false
    
    var isLongText: Bool {
        text.count > 80 || text.contains("\n")
    }
    
    var body: some View {
        Button(action: {
            if isLongText {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showFull = true
            }
        }) {
            ZStack(alignment: .bottomTrailing) {
                // 1. Update the preview text color
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(textColor.opacity(0.8)) // Slightly dimmed for the preview
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if isLongText {
                    HStack(spacing: 0) {
                        LinearGradient(
                            gradient: Gradient(colors: [backgroundColor.opacity(0), backgroundColor]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 40, height: 20)
                        
                        Text("MORE")
                            .font(.caption.bold())
                            .foregroundColor(textColor) // Match the text color rather than forced pink
                            .padding(.leading, 2)
                            .background(backgroundColor)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isLongText)
        .sheet(isPresented: $showFull) {
            NavigationView {
                ZStack {
                    // 2. Set the background of the entire expanded sheet
                    backgroundColor.ignoresSafeArea()
                    
                    ScrollView {
                        // 3. Update the full text color
                        Text(text)
                            .font(.body)
                            .foregroundColor(textColor)
                            .padding(24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .navigationTitle(albumTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showFull = false }
                            .font(.headline)
                            .foregroundColor(textColor) // Match the done button to the text color
                    }
                }
                // Ensure the navigation bar reflects the background color
                .toolbarBackground(backgroundColor, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(textColor.luminance < 0.5 ? .light : .dark, for: .navigationBar)
            }
        }
    }
}

// MARK: - Mini Player Capsule
struct MiniPlayerCapsule: View {
    @ObservedObject var audioManager: AudioManager
    var onExpand: () -> Void
    
    @State private var currentDragTime: TimeInterval? = nil
    @State private var dragStartTranslationX: CGFloat = 0
    @State private var dragInitialTime: TimeInterval = 0
    
    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let currentTime = currentDragTime ?? audioManager.currentTime
            let duration = audioManager.duration > 0 ? audioManager.duration : 1
            let progress = currentTime / duration
            let safeProgress = progress.isNaN ? 0 : progress
            
            ZStack(alignment: .leading) {
                Capsule().fill(Material.ultraThin).shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                Rectangle().fill(Color.primary.opacity(0.1)).frame(width: totalWidth * CGFloat(max(0, min(1, safeProgress)))).animation(currentDragTime != nil ? nil : .linear(duration: 0.1), value: safeProgress)
                
                HStack(spacing: 10) {
                    if let artwork = audioManager.displayArtwork(size: CGSize(width: 40, height: 40)) {
                        Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fill).frame(width: 36, height: 36).cornerRadius(5).shadow(radius: 2)
                    } else {
                        Rectangle().fill(Color.gray.opacity(0.5)).frame(width: 36, height: 36).cornerRadius(5).overlay(Image(systemName: "music.note").foregroundColor(.white).font(.caption))
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(audioManager.displayTitle).font(.caption).bold().foregroundColor(.primary).lineLimit(1)
                        Text(audioManager.displayArtist).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                    Spacer()
                    let hasSong = audioManager.currentSong != nil || audioManager.currentLocalSong != nil || audioManager.currentRemoteDTO != nil
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3).foregroundColor(!hasSong ? .secondary : .primary).frame(width: 44, height: 44).contentShape(Rectangle())
                        .onTapGesture { if hasSong { audioManager.togglePlayPause() } }
                }
                .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 8)
            }
            .clipShape(Capsule()).contentShape(ContentShapeKinds.interaction, Capsule())
            .onTapGesture {
                let hasSong = audioManager.currentSong != nil || audioManager.currentLocalSong != nil || audioManager.currentRemoteDTO != nil
                if hasSong { onExpand() }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        let hasSong = audioManager.currentSong != nil || audioManager.currentLocalSong != nil || audioManager.currentRemoteDTO != nil
                        guard hasSong else { return }
                        if value.translation.height < -20 && abs(value.translation.height) > abs(value.translation.width) { onExpand(); return }
                        if currentDragTime == nil { dragInitialTime = audioManager.currentTime; dragStartTranslationX = value.translation.width }
                        let delta = value.translation.width - dragStartTranslationX
                        let timeDelta = (delta / totalWidth) * audioManager.duration
                        currentDragTime = max(0, min(audioManager.duration, dragInitialTime + timeDelta))
                    }
                    .onEnded { value in
                        let hasSong = audioManager.currentSong != nil || audioManager.currentLocalSong != nil || audioManager.currentRemoteDTO != nil
                        guard hasSong else { return }
                        if value.translation.height < -20 && abs(value.translation.height) > abs(value.translation.width) { onExpand() } else if let finalTime = currentDragTime { audioManager.seek(to: finalTime) }
                        currentDragTime = nil; dragStartTranslationX = 0
                    }
            )
        }
    }
}

struct SongRow: View {
    let song: MPMediaItem
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var library: LibraryManager
    var showArtwork: Bool
    var showTrackNumber: Bool
    @State private var showInfo = false
    @State private var dominantColor: Color = .clear
    
    var customPrimaryColor: Color? = nil
    var customSecondaryColor: Color? = nil
    
    var isPlaying: Bool { audioManager.currentSong?.persistentID == song.persistentID }
    
    var hasCustomRaw: Bool {
        let id = String(song.persistentID)
        return library.customRawLyrics[id] != nil && !library.customRawLyrics[id]!.isEmpty
    }
    var hasNativeRaw: Bool { return song.lyrics != nil && !song.lyrics!.isEmpty }
    var showUnfilledBubble: Bool { return hasCustomRaw || hasNativeRaw }
    
    var body: some View {
        ZStack {
            if isPlaying {
                Rectangle().fill(dominantColor.opacity(0.3)).mask(Rectangle()).onAppear { updateColor() }.onChange(of: isPlaying) { playing in if playing { updateColor() } }
            }
            
            HStack(spacing: 6) {
                if library.isSystemFavorite(song: song) { Image(systemName: "star.fill").font(.caption2).foregroundColor(customSecondaryColor ?? .yellow).frame(width: 12) } else { Color.clear.frame(width: 12) }
                
                if library.hasSyncedLyrics(song: song) {
                    Image(systemName: "quote.bubble.fill").font(.caption2).foregroundColor(customSecondaryColor ?? .pink).frame(width: 12)
                } else if showUnfilledBubble {
                    Image(systemName: "quote.bubble").font(.caption2).foregroundColor(customSecondaryColor ?? .gray).frame(width: 12)
                } else {
                    Color.clear.frame(width: 12)
                }
                
                if showTrackNumber {
                    if song.albumTrackNumber > 0 { Text("\(song.albumTrackNumber)").font(.caption).monospacedDigit().foregroundColor(customSecondaryColor ?? .gray).frame(width: 20, alignment: .trailing) } else { Color.clear.frame(width: 20) }
                }
                
                if showArtwork {
                    if let artwork = song.artwork?.image(at: CGSize(width: 50, height: 50)) { Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fit).frame(width: 40, height: 40).cornerRadius(5) } else { Color.gray.opacity(0.3).frame(width: 40, height: 40).cornerRadius(5).overlay(Image(systemName: "music.note").foregroundColor(.white.opacity(0.6)).font(.caption)) }
                }
                Spacer().frame(width: 4)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title ?? "Unknown")
                        .font(.subheadline)
                        .fontWeight(isPlaying ? .bold : .regular)
                        .lineLimit(1)
                        .foregroundColor(isPlaying ? .pink : (customPrimaryColor ?? .primary))
                    
                    let albumID = "apple_\(song.albumPersistentID)"
                    if library.albumShowArtistPrefs[albumID] ?? true {
                        Text(song.artist ?? "Unknown")
                            .font(.caption)
                            .foregroundColor(customSecondaryColor ?? .secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                
                Menu { SongMenuContent(song: song, library: library, audioManager: audioManager, showInfo: $showInfo) } label: { Image(systemName: "ellipsis").font(.title3).foregroundColor(customSecondaryColor ?? .pink).frame(width: 30, height: 30).contentShape(Rectangle()) }.highPriorityGesture(TapGesture())
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .contentShape(Rectangle())
        .contextMenu { SongMenuContent(song: song, library: library, audioManager: audioManager, showInfo: $showInfo) }
        .sheet(isPresented: $showInfo) { SongInfoSheet(appleSong: song) }
    }
    
    private func updateColor() {
        if let artwork = song.artwork?.image(at: CGSize(width: 50, height: 50)) { dominantColor = artwork.dominantColor } else { dominantColor = .gray }
    }
}

struct SongMenuContent: View {
    let song: MPMediaItem
    @ObservedObject var library: LibraryManager
    @ObservedObject var audioManager: AudioManager
    @Binding var showInfo: Bool
    
    var body: some View {
        Section {
            Button(action: { audioManager.play(song: song) }) { HStack { Text(song.title ?? "Unknown").font(.headline).multilineTextAlignment(.leading).lineLimit(nil); Spacer(); if let artwork = song.artwork?.image(at: CGSize(width: 100, height: 100)) { Image(uiImage: artwork) } else { Image(systemName: "music.note") } } }
        }
        Section {
            Button { audioManager.play(song: song) } label: { Label("Play", systemImage: "play") }
            Button { library.toggleFavorite(song: song) } label: { Label(library.isSystemFavorite(song: song) ? "Unfavorite" : "Favorite", systemImage: library.isSystemFavorite(song: song) ? "star.fill" : "star") }
            Button {
                NotificationCenter.default.post(name: NSNotification.Name("ShowAddToPlaylist"), object: ["apple_\(song.persistentID)"])
            } label: { Label("Add to Playlist...", systemImage: "text.badge.plus") }
            Button { showInfo = true } label: { Label("Song Info", systemImage: "info.circle") }
        }
    }
}

// MARK: - Download Queue Overlay
struct DownloadQueueSheet: View {
    @ObservedObject var multipeer = MultipeerManager.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                let tasks = Array(multipeer.currentDownloads.values).sorted(by: { ($0.metadata?.title ?? "") < ($1.metadata?.title ?? "") })
                
                if tasks.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 60)).foregroundColor(.green)
                        Text("All downloads complete").font(.headline).foregroundColor(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(tasks) { task in
                                HStack(spacing: 16) {
                                    ZStack {
                                        Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 50, height: 50).cornerRadius(8)
                                        Image(systemName: "arrow.down.doc.fill").foregroundColor(.pink)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(task.metadata?.title ?? task.id).font(.headline).lineLimit(1)
                                        Text(task.metadata?.artist ?? "Downloading...").font(.caption).foregroundColor(.secondary).lineLimit(1)
                                        
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                Capsule().fill(Color.gray.opacity(0.2)).frame(height: 6)
                                                Capsule().fill(Color.pink).frame(width: geo.size.width * CGFloat(task.fractionCompleted), height: 6)
                                                    .animation(.linear(duration: 0.2), value: task.fractionCompleted)
                                            }
                                        }.frame(height: 6)
                                    }
                                    
                                    Text("\(Int(task.fractionCompleted * 100))%")
                                        .font(.caption.monospacedDigit().bold())
                                        .foregroundColor(.pink)
                                        .frame(width: 40, alignment: .trailing)
                                }
                                .padding(12)
                                .background(Material.ultraThin)
                                .cornerRadius(16)
                                .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Download Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Main Library View
struct LibraryHomeView: View {
    @ObservedObject var library: LibraryManager
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var settings: AppSettings
    @Binding var showSettings: Bool
    @ObservedObject var navState: NavigationStateManager
    @ObservedObject var multipeer = MultipeerManager.shared
    @State private var showDownloadQueue = false
    @ObservedObject var downloads = DownloadsManager.shared
    
    @Environment(\.editMode) private var editMode
    let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    
    func icon(for item: String) -> String {
        switch item {
        case "Playlists": return "music.note.list"
        case "Artists": return "music.mic"
        case "Genres": return "guitars"
        case "Albums": return "square.stack"
        case "Songs": return "music.note"
        case "Mac": return "macwindow"
        default: return "circle"
        }
    }
    
    var body: some View {
        Group {
            if editMode?.wrappedValue == .active {
                List {
                    ForEach(library.menuItems, id: \.self) { item in
                        if item == "Mac" && !settings.showMacTab {
                            SimpleMenuRow(icon: icon(for: item), title: "Mac (Hidden)", showChevron: false)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.visible)
                        } else {
                            SimpleMenuRow(icon: icon(for: item), title: item, showChevron: false)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.visible)
                        }
                    }.onMove(perform: library.moveMenuItem)
                    
                    Section(header: Text("Pinned Albums")) {
                        ForEach(library.pinnedUnifiedAlbums, id: \.id) { unifiedAlbum in
                            HStack(spacing: 16) {
                                UnifiedArtworkView(item: unifiedAlbum, size: CGSize(width: 30, height: 30))
                                Text(unifiedAlbum.title).font(.body)
                                Spacer()
                            }.padding(.horizontal, 20).padding(.vertical, 12).listRowInsets(EdgeInsets())
                        }.onMove(perform: library.movePinnedAlbum).onDelete(perform: library.deletePinnedAlbum)
                    }
                }.listStyle(.plain)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        HStack { Text("Library").font(.largeTitle).bold(); Spacer() }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 16)
                        
                        ForEach(library.menuItems, id: \.self) { item in
                            if item == "Mac" && !settings.showMacTab {
                                EmptyView()
                            } else {
                                VStack(spacing: 0) {
                                    NavigationLink(value: item) { SimpleMenuRow(icon: icon(for: item), title: item, showChevron: true) }
                                    Divider().padding(.leading, 60)
                                }
                            }
                        }.id("LibraryTop")
                        
                        if !library.pinnedUnifiedAlbums.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Pinned Albums").font(.headline).padding(.horizontal, 20).padding(.top, 20)
                                LazyVGrid(columns: columns, spacing: 20) {
                                    ForEach(library.pinnedUnifiedAlbums, id: \.id) { item in
                                        NavigationLink(value: item) {
                                            VStack(alignment: .leading, spacing: 8) {
                                                UnifiedArtworkView(item: item, size: CGSize(width: 250, height: 250))
                                                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                                
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(item.title).font(.headline).bold().lineLimit(1).foregroundColor(.primary)
                                                    Text(item.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                                    
                                                    if let apple = item.appleAlbum { Text(collectionStats(collection: apple)).font(.caption2).foregroundColor(.gray).lineLimit(1) }
                                                    else if let local = item.localWrapper { Text(localCollectionStats(songs: local.songs)).font(.caption2).foregroundColor(.gray).lineLimit(1) }
                                                    else { Text("Loading...").font(.caption2).foregroundColor(.gray).lineLimit(1) }
                                                }
                                            }
                                        }
                                        .contextMenu {
                                            if let apple = item.appleAlbum {
                                                Button { audioManager.play(song: apple.items.first!, queue: apple.items) } label: { Label("Play", systemImage: "play") }
                                                Button {
                                                    let ids: [String]
                                                    if let apple = item.appleAlbum {
                                                        ids = apple.items.map { "apple_\($0.persistentID)" }
                                                    } else if let local = item.localWrapper {
                                                        ids = local.songs.map { "local_\($0.id)" }
                                                    } else { ids = [] }
                                                    NotificationCenter.default.post(name: NSNotification.Name("ShowAddToPlaylist"), object: ids)
                                                } label: { Label("Add to Playlist...", systemImage: "text.badge.plus") }
                                                Button { library.togglePin(album: apple) } label: { Label(library.isPinned(album: apple) ? "Unpin" : "Pin to Library", systemImage: "pin") }
                                            } else if let local = item.localWrapper {
                                                Button { audioManager.play(localSong: local.songs.first!, queue: local.songs) } label: { Label("Play", systemImage: "play") }
                                                Button {
                                                    let ids: [String]
                                                    if let apple = item.appleAlbum {
                                                        ids = apple.items.map { "apple_\($0.persistentID)" }
                                                    } else if let local = item.localWrapper {
                                                        ids = local.songs.map { "local_\($0.id)" }
                                                    } else { ids = [] }
                                                    NotificationCenter.default.post(name: NSNotification.Name("ShowAddToPlaylist"), object: ids)
                                                } label: { Label("Add to Playlist...", systemImage: "text.badge.plus") }
                                                Button { library.togglePin(localAlbumName: local.name) } label: { Label(library.isPinned(localAlbumName: local.name) ? "Unpin" : "Pin to Library", systemImage: "pin") }
                                                Button(role: .destructive) { DownloadsManager.shared.deleteAlbum(albumName: local.name) } label: { Label("Delete", systemImage: "trash") }
                                            } else {
                                                Button { library.togglePin(id: item.id) } label: { Label("Unpin", systemImage: "pin.slash") }
                                            }
                                        }
                                    }
                                }.padding(.horizontal, 20).padding(.bottom, 20)
                            }
                        }
                        Spacer().frame(height: 100)
                    }.scrollTargetLayout()
                }
            }
        }.scrollPosition(id: $navState.scrollID)
            .background(Color(.systemBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { EditButton().foregroundColor(.pink) }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !MultipeerManager.shared.currentDownloads.isEmpty {
                        Button(action: { showDownloadQueue = true }) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.pink)
                                .symbolEffect(.pulse, options: .repeating)
                        }
                    }
                    Button(action: { showSettings = true }) { Image(systemName: "gearshape.fill").foregroundColor(.pink) }
                }
            }
            .sheet(isPresented: $showDownloadQueue) {
                DownloadQueueSheet()
            }
    }
}

struct SimpleMenuRow: View {
    let icon: String
    let title: String
    var showChevron: Bool
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.title2).foregroundColor(.pink).frame(width: 30)
            Text(title).font(.body).foregroundColor(.primary)
            Spacer()
            if showChevron { Image(systemName: "chevron.right").font(.caption).foregroundColor(.gray.opacity(0.5)) }
        }.padding(.horizontal, 20).padding(.vertical, 12).contentShape(Rectangle())
    }
}

// MARK: - iOS Genre Views
struct GenreListView: View {
    @ObservedObject var library: LibraryManager
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var downloads = DownloadsManager.shared
    @State private var searchText = ""
    
    var activeGenres: [String] {
        var genres = Set<String>()
        library.songs.forEach { if let g = $0.genre, !g.isEmpty { genres.insert(g) } }
        downloads.downloadedSongs.forEach { if !$0.genre.isEmpty { genres.insert($0.genre) } }
        var sorted = Array(genres).sorted()
        if !searchText.isEmpty { sorted = sorted.filter { $0.localizedCaseInsensitiveContains(searchText) } }
        return sorted
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(activeGenres, id: \.self) { genre in
                    NavigationLink(destination: UnifiedGenreDetailView(genre: genre, library: library, audioManager: audioManager)) {
                        Text(genre)
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    Divider().padding(.leading)
                }
                Spacer().frame(height: 100)
            }
        }
        .navigationTitle("Genres")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
    }
}

struct UnifiedPlaylistDetailView: View {
    let item: UnifiedPlaylistItem
    @ObservedObject var library: LibraryManager
    @ObservedObject var audioManager: AudioManager
    @State private var selectedPhoto: PhotosPickerItem? = nil
    
    var customPlaylist: AppPlaylist? { library.customPlaylists.first { $0.id == item.id } }
    
    var unifiedSongs: [UnifiedSongItem] {
        if let apple = item.applePlaylist {
            return apple.items.map { UnifiedSongItem(id: "apple_\($0.persistentID)", title: $0.title ?? "", artist: $0.artist ?? "", sortTitle: "", appleSong: $0, localSong: nil) }
        } else if let custom = customPlaylist {
            return custom.songIDs.compactMap { idStr in
                if idStr.hasPrefix("apple_"), let appleID = UInt64(idStr.dropFirst(6)), let song = library.songs.first(where: { $0.persistentID == appleID }) {
                    return UnifiedSongItem(id: idStr, title: song.title ?? "", artist: song.artist ?? "", sortTitle: "", appleSong: song, localSong: nil)
                } else if idStr.hasPrefix("local_"), let song = DownloadsManager.shared.downloadedSongs.first(where: { $0.id == String(idStr.dropFirst(6)) }) {
                    return UnifiedSongItem(id: idStr, title: song.title, artist: song.artist, sortTitle: "", appleSong: nil, localSong: song)
                }
                return nil
            }
        }
        return []
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Header mimicking Album Detail View
                    VStack(spacing: 16) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            if let custom = customPlaylist, let data = custom.artworkData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fill).frame(width: 250, height: 250).cornerRadius(12).shadow(radius: 10)
                            } else {
                                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 250, height: 250).cornerRadius(12)
                                    .overlay(
                                        VStack {
                                            Image(systemName: item.customPlaylist != nil ? "photo.badge.plus" : "music.note.list").font(.largeTitle)
                                            if item.customPlaylist != nil { Text("Add Cover").font(.caption).padding(.top, 4) }
                                        }.foregroundColor(.gray)
                                    )
                            }
                        }
                        .disabled(item.customPlaylist == nil) // Only allow editing custom playlists
                        
                        VStack(spacing: 4) {
                            Text(item.title).font(.title2).bold().multilineTextAlignment(.center)
                            Text("Playlist").font(.title3).foregroundColor(.secondary)
                            Text("\(unifiedSongs.count) Songs").font(.caption).foregroundColor(.gray).padding(.top, 2)
                        }
                        .padding(.horizontal, 20)
                        
                        HStack(spacing: 20) {
                            Button(action: {
                                if let first = unifiedSongs.first {
                                    if let apple = first.appleSong { audioManager.play(song: apple, queue: unifiedSongs.compactMap { $0.appleSong }) }
                                    else if let local = first.localSong { audioManager.play(localSong: local, queue: unifiedSongs.compactMap { $0.localSong }) }
                                }
                            }) {
                                HStack { Image(systemName: "play.fill"); Text("Play") }.font(.headline).foregroundColor(.pink).frame(width: 160, height: 54).background(Color.gray.opacity(0.1)).clipShape(Capsule())
                            }
                            Button(action: {
                                audioManager.isShuffled = true
                                if let random = unifiedSongs.randomElement() {
                                    if let apple = random.appleSong { audioManager.play(song: apple, queue: unifiedSongs.compactMap { $0.appleSong }) }
                                    else if let local = random.localSong { audioManager.play(localSong: local, queue: unifiedSongs.compactMap { $0.localSong }) }
                                }
                            }) {
                                HStack { Image(systemName: "shuffle"); Text("Shuffle") }.font(.headline).foregroundColor(.pink).frame(width: 160, height: 54).background(Color.gray.opacity(0.1)).clipShape(Capsule())
                            }
                        }.padding(.top, 8)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 20)
                    
                    // Song List
                    if unifiedSongs.isEmpty {
                        Text("No songs added yet. Long press a song to add it here.")
                            .foregroundColor(.secondary)
                            .padding(.top, 40)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(unifiedSongs.enumerated()), id: \.element.id) { index, songItem in
                                if let apple = songItem.appleSong {
                                    SongRow(song: apple, audioManager: audioManager, library: library, showArtwork: true, showTrackNumber: false)
                                        .onTapGesture { audioManager.play(song: apple, queue: unifiedSongs.compactMap { $0.appleSong }) }
                                } else if let local = songItem.localSong {
                                    DownloadsSongRow(song: local, queue: unifiedSongs.compactMap { $0.localSong }, showArtwork: true, showTrackNumber: false, audioManager: audioManager)
                                }
                                Divider().padding(.leading)
                            }
                        }
                    }
                    Spacer().frame(height: 100)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if item.customPlaylist != nil { EditButton() }
        }
        .onChange(of: selectedPhoto) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    DispatchQueue.main.async { library.updatePlaylistArtwork(id: item.id, data: data) }
                }
            }
        }
    }
}

struct UnifiedGenreDetailView: View {
    let genre: String
    @ObservedObject var library: LibraryManager
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var downloads = DownloadsManager.shared
    
    var appleSongs: [MPMediaItem] { library.songs.filter { $0.genre == genre } }
    var localSongs: [LocalSong] { downloads.downloadedSongs.filter { $0.genre == genre } }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !appleSongs.isEmpty {
                    Section(header: Text("Apple Music").font(.headline).foregroundColor(.pink).padding(.horizontal).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).background(Color(.systemGroupedBackground))) {
                        ForEach(appleSongs, id: \.persistentID) { song in
                            SongRow(song: song, audioManager: audioManager, library: library, showArtwork: true, showTrackNumber: false)
                                .onTapGesture { audioManager.play(song: song, queue: appleSongs) }
                            Divider().padding(.leading)
                        }
                    }
                }
                
                if !localSongs.isEmpty {
                    Section(header: Text("Downloads").font(.headline).foregroundColor(.pink).padding(.horizontal).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).background(Color(.systemGroupedBackground))) {
                        ForEach(localSongs) { song in
                            DownloadsSongRow(song: song, queue: localSongs, showArtwork: true, showTrackNumber: false, audioManager: audioManager)
                            Divider().padding(.leading)
                        }
                    }
                }
                Spacer().frame(height: 100)
            }
        }
        .navigationTitle(genre)
    }
}

// MARK: - Connect To Mac Logic
struct ConnectToMacButton: View {
    @ObservedObject var multipeer: MultipeerManager
    @ObservedObject var audioManager: AudioManager
    
    var body: some View {
        Button(action: {
            if multipeer.connectionState == .disconnected || multipeer.connectionState == .failed {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                multipeer.startBrowsing()
                
                if audioManager.currentSong != nil { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { audioManager.forceSyncToMac() } }
            } else if multipeer.connectionState == .connected {
                let impact = UIImpactFeedbackGenerator(style: .rigid)
                impact.impactOccurred()
                multipeer.disconnect()
            }
        }) {
            HStack(spacing: 8) {
                switch multipeer.connectionState {
                case .disconnected: Image(systemName: "macwindow"); Text("Connect to Mac")
                case .connecting: ProgressView().tint(.white); Text("Connecting...")
                case .connected: Image(systemName: "macwindow.badge.checkmark"); Text("Connected to Mac")
                case .failed: Image(systemName: "exclamationmark.triangle.fill"); Text("Connection Failed")
                }
            }
            .font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 14).background(backgroundColor).cornerRadius(12).shadow(color: backgroundColor.opacity(0.3), radius: 8, x: 0, y: 4).contentTransition(.symbolEffect(.replace))
        }.padding(.horizontal, 20).disabled(multipeer.connectionState == .connecting).animation(.easeInOut(duration: 0.2), value: multipeer.connectionState)
    }
    private var backgroundColor: Color {
        switch multipeer.connectionState { case .disconnected: return Color.pink; case .connecting: return Color.gray; case .connected: return Color.green; case .failed: return Color.red }
    }
}

// MARK: - Global Search View
struct GlobalSearchView: View {
    @ObservedObject var library: LibraryManager
    @ObservedObject var audioManager: AudioManager
    @Binding var showSearchSheet: Bool
    @ObservedObject var navState: NavigationStateManager
    @State private var searchText = ""
    @FocusState private var isFocused: Bool
    
    var songs: [MPMediaItem] { searchText.isEmpty ? [] : library.smartFilterSongs(in: library.songs, for: searchText) }
    var albums: [MPMediaItemCollection] { searchText.isEmpty ? [] : library.smartFilterAlbums(in: library.albums, for: searchText) }
    
    func navigateTo<T: Hashable>(destination: T) {
        showSearchSheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { navState.navigationPath.append(destination) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundColor(.gray).font(.title3)
                TextField("Search library...", text: $searchText).focused($isFocused).font(.body).textFieldStyle(.plain).submitLabel(.search)
                if !searchText.isEmpty { Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundColor(.gray).font(.title3) } }
            }.padding(.horizontal, 16).padding(.vertical, 10).background(Color(.systemGray6)).cornerRadius(12).padding(16)
            
            List {
                if !songs.isEmpty {
                    Section(header: Text("Songs")) {
                        ForEach(songs.prefix(5), id: \.persistentID) { song in
                            SongRow(song: song, audioManager: audioManager, library: library, showArtwork: true, showTrackNumber: false)
                                .onTapGesture { audioManager.play(song: song); showSearchSheet = false }
                                .listRowInsets(EdgeInsets())
                        }
                    }
                }
                if !albums.isEmpty {
                    Section(header: Text("Albums")) {
                        ForEach(albums.prefix(5), id: \.persistentID) { album in
                            HStack {
                                if let artwork = album.representativeItem?.artwork?.image(at: CGSize(width: 50, height: 50)) { Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fit).frame(width: 40, height: 40).cornerRadius(4) } else { Color.gray.opacity(0.3).frame(width: 40, height: 40).cornerRadius(4) }
                                Text(album.representativeItem?.albumTitle ?? "Unknown").foregroundColor(.primary)
                            }.contentShape(Rectangle()).onTapGesture { navigateTo(destination: UnifiedAlbumItem(id: String(album.persistentID), title: "", artist: "", sortTitle: "", appleAlbum: album, localWrapper: nil)) }
                        }
                    }
                }
                Section { Spacer().frame(height: 100).listRowSeparator(.hidden) }
            }.listStyle(.plain)
        }.navigationTitle("Search").navigationBarTitleDisplayMode(.inline).onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFocused = true } }
    }
}

// MARK: - Playlists
struct PlaylistListView: View {
    @ObservedObject var library: LibraryManager
    @ObservedObject var audioManager: AudioManager
    @Binding var isSearching: Bool
    @Binding var showSettings: Bool
    @State private var searchText = ""
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistTitle = ""
    
    var unifiedPlaylists: [UnifiedPlaylistItem] {
        var items: [UnifiedPlaylistItem] = []
        
        // Add Apple Playlists
        items.append(contentsOf: library.playlists.map {
            UnifiedPlaylistItem(id: "apple_\($0.persistentID)", title: $0.value(forProperty: MPMediaPlaylistPropertyName) as? String ?? "Untitled", applePlaylist: $0, customPlaylist: nil)
        })
        
        // Add Custom Playlists
        items.append(contentsOf: library.customPlaylists.map {
            UnifiedPlaylistItem(id: $0.id, title: $0.title, applePlaylist: nil, customPlaylist: $0)
        })
        
        // Filter and Sort
        var sorted = items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        if !searchText.isEmpty {
            sorted = sorted.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        return sorted
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if unifiedPlaylists.isEmpty {
                    Text("No playlists found.").foregroundColor(.gray).padding()
                } else {
                    ForEach(unifiedPlaylists) { item in
                        NavigationLink(value: item) {
                            HStack(spacing: 16) {
                                // Artwork
                                if let custom = item.customPlaylist, let data = custom.artworkData, let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage).resizable().frame(width: 40, height: 40).cornerRadius(8)
                                } else {
                                    Image(systemName: "music.note.list").font(.title2).frame(width: 40, height: 40).background(Color.pink.opacity(0.1)).foregroundColor(.pink).cornerRadius(8)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.body).foregroundColor(.primary)
                                    if let apple = item.applePlaylist {
                                        Text(collectionStats(collection: apple)).font(.caption).foregroundColor(.secondary)
                                    } else if let custom = item.customPlaylist {
                                        Text("\(custom.songIDs.count) Songs").font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundColor(.gray.opacity(0.5))
                            }.padding(.horizontal, 20).padding(.vertical, 8).contentShape(Rectangle())
                        }
                        Divider().padding(.leading, 76)
                    }
                }
                Spacer().frame(height: 100)
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("Playlists")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showNewPlaylistAlert = true }) { Image(systemName: "plus") }
            }
        }
        .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
            TextField("Playlist Name", text: $newPlaylistTitle)
            Button("Cancel", role: .cancel) { newPlaylistTitle = "" }
            Button("Create") {
                if !newPlaylistTitle.isEmpty {
                    library.createPlaylist(title: newPlaylistTitle)
                    newPlaylistTitle = ""
                }
            }
        }
    }
}

// MARK: - UNIFIED Artists List
struct ArtistListView: View {
    @ObservedObject var library: LibraryManager
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var downloads = DownloadsManager.shared
    
    @State private var searchText = ""
    @State private var isScrubbing = false
    @State private var scrubLetter = ""
    
    var activeSections: [UnifiedArtistSection] {
        var allApple = library.artistSections.flatMap { $0.artists }
        var allLocal = Dictionary(grouping: downloads.downloadedSongs, by: { $0.artist }).keys.map { $0 }
        
        if !searchText.isEmpty {
            allApple = library.smartFilterArtists(in: allApple, for: searchText)
            allLocal = allLocal.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
        
        var unified: [UnifiedArtistItem] = []
        unified.append(contentsOf: allApple.map { UnifiedArtistItem(id: "apple_\($0)", name: $0, sortName: $0, appleArtist: $0, localWrapper: nil) })
        unified.append(contentsOf: allLocal.map { artist in
            let songs = downloads.downloadedSongs.filter { s in s.artist == artist }
            return UnifiedArtistItem(id: "local_\(artist)", name: artist, sortName: artist, appleArtist: nil, localWrapper: LocalArtistWrapper(name: artist, songs: songs))
        })
        
        let groupedByName = Dictionary(grouping: unified, by: { $0.name.lowercased() })
        var mergedUnified: [UnifiedArtistItem] = []
        for (_, items) in groupedByName {
            if items.count == 1 { mergedUnified.append(items[0]) } else {
                let apple = items.first(where: { $0.appleArtist != nil })?.appleArtist
                let localWrap = items.first(where: { $0.localWrapper != nil })?.localWrapper
                mergedUnified.append(UnifiedArtistItem(id: "merged_\(items[0].name)", name: items[0].name, sortName: items[0].sortName, appleArtist: apple, localWrapper: localWrap))
            }
        }
        
        let grouped = Dictionary(grouping: mergedUnified) { item -> String in
            let prefix = item.sortName.prefix(1).uppercased()
            return prefix.rangeOfCharacter(from: .letters) != nil ? prefix : "#"
        }
        
        let sortedKeys = grouped.keys.sorted { lhs, rhs in if lhs == "#" { return false }; if rhs == "#" { return true }; return lhs < rhs }
        return sortedKeys.map { letter in let sortedArtists = (grouped[letter] ?? []).sorted { $0.sortName < $1.sortName }; return UnifiedArtistSection(letter: letter, artists: sortedArtists) }
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(activeSections) { section in
                            Section(header: Text(section.letter).font(.headline).foregroundColor(.pink).padding(.horizontal).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).background(Color(.systemBackground)).id(section.letter)) {
                                ForEach(section.artists) { item in
                                    NavigationLink(value: item) {
                                        Text(item.name).font(.body).foregroundColor(.primary).padding(.horizontal).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    }
                                    Divider().padding(.leading)
                                }
                            }
                        }
                        Spacer().frame(height: 100)
                    }.padding(.trailing, 20)
                }
                
                if isScrubbing {
                    VStack {
                        Text(scrubLetter).font(.system(size: 60, weight: .bold)).foregroundColor(.white).frame(width: 100, height: 100).background(Color.black.opacity(0.6).cornerRadius(16))
                    }.zIndex(100)
                }
                
                if searchText.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 0) {
                            ForEach(activeSections.map{$0.letter}, id:\.self) { l in Text(l).font(.system(size: 11, weight: .semibold)).foregroundColor(.pink).frame(width: 20, height: 18) }
                        }
                        .padding(.trailing, 2)
                        .background(Color.white.opacity(0.001))
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            let letters = activeSections.map { $0.letter }; guard !letters.isEmpty else { return }
                            let index = max(0, min(letters.count - 1, Int(value.location.y / 18)))
                            let targetLetter = letters[index]
                            if scrubLetter != targetLetter { UIImpactFeedbackGenerator(style: .light).impactOccurred(); scrubLetter = targetLetter }
                            isScrubbing = true
                        }.onEnded { value in
                            let letters = activeSections.map { $0.letter }; guard !letters.isEmpty else { return }
                            let index = max(0, min(letters.count - 1, Int(value.location.y / 18)))
                            proxy.scrollTo(letters[index], anchor: .top)
                            withAnimation(.easeInOut(duration: 0.2)) { isScrubbing = false }
                        })
                    }
                }
            }
        }
        .navigationTitle("Artists")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
    }
}

// MARK: - UNIFIED Artist Detail View
struct UnifiedArtistDetailView: View {
    let item: UnifiedArtistItem
    @ObservedObject var library: LibraryManager
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var downloads = DownloadsManager.shared
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Button(action: {
                    audioManager.isShuffled = true
                    if let apple = item.appleArtist {
                        let appleSongs = library.songs.filter { $0.artist == apple }
                        if !appleSongs.isEmpty { audioManager.play(song: appleSongs.randomElement()!, queue: appleSongs) }
                    } else if let localWrap = item.localWrapper {
                        let localSongs = localWrap.songs
                        if !localSongs.isEmpty { audioManager.play(localSong: localSongs.randomElement()!, queue: localSongs) }
                    }
                }) {
                    HStack { Image(systemName: "shuffle"); Text("Shuffle Artist") }.font(.headline).foregroundColor(.pink).padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(.systemBackground))
                }
                
                if let appleName = item.appleArtist {
                    let appleSongs = library.songs.filter { $0.artist == appleName }
                    if !appleSongs.isEmpty {
                        Section(header: Text("Apple Music").font(.headline).foregroundColor(.pink).padding(.horizontal).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).background(Color(.systemGroupedBackground))) {
                            ForEach(appleSongs, id: \.persistentID) { song in
                                SongRow(song: song, audioManager: audioManager, library: library, showArtwork: true, showTrackNumber: false).contentShape(Rectangle()).onTapGesture { audioManager.play(song: song, queue: appleSongs) }
                                Divider().padding(.leading)
                            }
                        }
                    }
                }
                
                if let localWrap = item.localWrapper {
                    let localSongs = localWrap.songs
                    if !localSongs.isEmpty {
                        Section(header: Text("Downloads").font(.headline).foregroundColor(.pink).padding(.horizontal).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).background(Color(.systemGroupedBackground))) {
                            ForEach(localSongs) { song in
                                DownloadsSongRow(song: song, queue: localSongs, showArtwork: true, audioManager: audioManager)
                                Divider().padding(.leading)
                            }
                        }
                    }
                }
                Spacer().frame(height: 100)
            }
        }.navigationTitle(item.name)
    }
}

// MARK: - UNIFIED Albums List
struct AlbumListView: View {
    @ObservedObject var library: LibraryManager
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var downloads = DownloadsManager.shared
    
    @Binding var isSearching: Bool
    @Binding var showSettings: Bool
    @State private var searchText = ""
    @State private var showFavoritesOnly = false
    
    // NEW: Filter & Sort State
    @State private var sortType: AlbumSortType = .titleAZ
    @State private var filterType: AlbumFilterType = .all
    @State private var selectedGenre: String = "All Genres"
    
    @State private var isScrubbing = false
    @State private var scrubLetter = ""
    
    let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    
    // Dynamically calculate available genres in the local library
    var availableGenres: [String] {
        var genres = Set<String>()
        for album in library.albums {
            if let genre = album.representativeItem?.genre, !genre.isEmpty { genres.insert(genre) }
        }
        for song in downloads.downloadedSongs {
            if !song.genre.isEmpty { genres.insert(song.genre) }
        }
        return ["All Genres"] + genres.sorted()
    }
    
    var activeSections: [UnifiedAlbumSection] {
        var appleAlbums = showFavoritesOnly ? library.favoriteAlbums : library.albums
        if !searchText.isEmpty { appleAlbums = library.smartFilterAlbums(in: appleAlbums, for: searchText) }
        
        // APPLY FILTERS: Apple Music
        if filterType == .full { appleAlbums = appleAlbums.filter { $0.count >= 4 } }
        if selectedGenre != "All Genres" { appleAlbums = appleAlbums.filter { $0.representativeItem?.genre == selectedGenre } }
        
        var allLocalSongs = downloads.downloadedSongs
        let pendingTasks = MultipeerManager.shared.currentDownloads.values
        for task in pendingTasks {
            if let meta = task.metadata, !allLocalSongs.contains(where: { $0.id == meta.fileName }) {
                let tempSong = LocalSong(id: meta.fileName, url: URL(fileURLWithPath: ""), title: meta.title, artist: meta.artist, album: meta.album, duration: 0, artworkData: nil, trackNumber: meta.trackNumber ?? 0, discNumber: meta.discNumber)
                allLocalSongs.append(tempSong)
            }
        }
        
        var localAlbums = allLocalSongs
        if showFavoritesOnly { localAlbums = [] }
        let groupedLocal = Dictionary(grouping: localAlbums, by: { $0.album })
        var filteredLocalNames = groupedLocal.keys.sorted()
        if !searchText.isEmpty { filteredLocalNames = filteredLocalNames.filter { $0.localizedCaseInsensitiveContains(searchText) } }
        
        // APPLY FILTERS: Local Downloads
        if filterType == .full {
            filteredLocalNames = filteredLocalNames.filter { (groupedLocal[$0]?.count ?? 0) >= 4 }
        }
        if selectedGenre != "All Genres" {
            filteredLocalNames = filteredLocalNames.filter { (groupedLocal[$0]?.first?.genre ?? "Album") == selectedGenre }
        }
        
        var unified: [UnifiedAlbumItem] = []
        unified.append(contentsOf: appleAlbums.map {
            UnifiedAlbumItem(id: String($0.persistentID), title: $0.representativeItem?.albumTitle ?? "Unknown", artist: $0.representativeItem?.artist ?? "Unknown", sortTitle: $0.representativeItem?.albumTitle ?? "Unknown", appleAlbum: $0, localWrapper: nil)
        })
        unified.append(contentsOf: filteredLocalNames.map { name in
            let songs = groupedLocal[name] ?? []
            let artist = songs.first?.artist ?? "Unknown"
            return UnifiedAlbumItem(id: "local_\(name)", title: name, artist: artist, sortTitle: name, appleAlbum: nil, localWrapper: LocalAlbumWrapper(name: name, songs: songs))
        })
        
        // APPLY SORT: Grouping
        let grouped = Dictionary(grouping: unified) { item -> String in
            if sortType == .trackCount { return "#" } // Consolidate into a single visual list for Track Count
            let sortString = sortType == .artistAZ ? item.artist : item.sortTitle
            let prefix = sortString.prefix(1).uppercased()
            return prefix.rangeOfCharacter(from: .letters) != nil ? prefix : "#"
        }
        
        let sortedKeys = grouped.keys.sorted { lhs, rhs in
            if lhs == "#" { return false }
            if rhs == "#" { return true }
            return sortType == .titleZA ? lhs > rhs : lhs < rhs
        }
        
        return sortedKeys.map { letter in
            let sortedAlbums = (grouped[letter] ?? []).sorted {
                switch sortType {
                case .titleAZ: return $0.sortTitle < $1.sortTitle
                case .titleZA: return $0.sortTitle > $1.sortTitle
                case .artistAZ:
                    if $0.artist == $1.artist { return $0.sortTitle < $1.sortTitle }
                    return $0.artist < $1.artist
                case .trackCount:
                    let count0 = $0.appleAlbum?.count ?? $0.localWrapper?.songs.count ?? 0
                    let count1 = $1.appleAlbum?.count ?? $1.localWrapper?.songs.count ?? 0
                    if count0 == count1 { return $0.sortTitle < $1.sortTitle }
                    return count0 > count1 // Highest track count goes first!
                }
            }
            return UnifiedAlbumSection(letter: letter, albums: sortedAlbums)
        }
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(activeSections) { section in
                            // Hide the literal "#" header if we are sorting by Track Count
                            if sortType != .trackCount {
                                Section(header: Text(section.letter).font(.title3).bold().foregroundColor(.pink).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8).id(section.letter)) {
                                    EmptyView()
                                }
                            }
                            
                            ForEach(section.albums) { item in
                                NavigationLink(value: item) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if let apple = item.appleAlbum {
                                            if let artwork = apple.representativeItem?.artwork?.image(at: CGSize(width: 250, height: 250)) { Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fit).cornerRadius(12).shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2) } else { Rectangle().fill(Color.gray.opacity(0.3)).aspectRatio(1.0, contentMode: .fit).cornerRadius(12) }
                                        } else if let local = item.localWrapper {
                                            ZStack(alignment: .bottom) {
                                                if let firstSongWithArtwork = local.songs.first(where: { $0.artworkData != nil }), let data = firstSongWithArtwork.artworkData, let uiImage = UIImage(data: data) {
                                                    Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fit)
                                                } else {
                                                    Rectangle().fill(Color.gray.opacity(0.3)).aspectRatio(1.0, contentMode: .fit).overlay(Image(systemName: "music.note").font(.largeTitle).foregroundColor(.gray))
                                                }
                                                let albumTasks = MultipeerManager.shared.currentDownloads.values.filter { $0.metadata?.album == local.name }
                                                if !albumTasks.isEmpty {
                                                    let totalProgress = albumTasks.reduce(0) { $0 + $1.fractionCompleted } / Double(albumTasks.count)
                                                    ZStack(alignment: .leading) {
                                                        Rectangle().fill(Material.ultraThin).frame(height: 30)
                                                        GeometryReader { geo in Rectangle().fill(Color.pink.opacity(0.6)).frame(width: geo.size.width * CGFloat(totalProgress)).animation(.linear(duration: 0.2), value: totalProgress) }
                                                        Text("Downloading...").font(.caption2.bold()).foregroundColor(.white).padding(.leading, 8)
                                                    }.frame(height: 30)
                                                }
                                            }.cornerRadius(12).shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 2) {
                                                if let apple = item.appleAlbum, library.isSystemFavorite(album: apple) { Image(systemName: "star.fill").font(.caption2).foregroundColor(.yellow) }
                                                Text(item.title).font(.headline).foregroundColor(.primary).lineLimit(1)
                                            }
                                            Text(item.artist).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                                            if let apple = item.appleAlbum { Text(collectionStats(collection: apple)).font(.caption2).foregroundColor(.gray).lineLimit(1) }
                                            else if let local = item.localWrapper { Text(localCollectionStats(songs: local.songs.filter { $0.duration > 0 })).font(.caption2).foregroundColor(.gray).lineLimit(1) }
                                        }
                                    }
                                }
                                .contextMenu {
                                    if let apple = item.appleAlbum {
                                        Button { audioManager.play(song: apple.items.first!, queue: apple.items) } label: { Label("Play", systemImage: "play") }
                                        Button { library.togglePin(album: apple) } label: { Label(library.isPinned(album: apple) ? "Unpin" : "Pin to Library", systemImage: "pin") }
                                    } else if let local = item.localWrapper {
                                        let validSongs = local.songs.filter { $0.duration > 0 }
                                        if !validSongs.isEmpty { Button { audioManager.play(localSong: validSongs.first!, queue: validSongs) } label: { Label("Play", systemImage: "play") } }
                                        Button {
                                            let ids: [String]
                                            if let apple = item.appleAlbum {
                                                ids = apple.items.map { "apple_\($0.persistentID)" }
                                            } else if let local = item.localWrapper {
                                                ids = local.songs.map { "local_\($0.id)" }
                                            } else { ids = [] }
                                            NotificationCenter.default.post(name: NSNotification.Name("ShowAddToPlaylist"), object: ids)
                                        } label: { Label("Add to Playlist...", systemImage: "text.badge.plus") }
                                        Button { library.togglePin(localAlbumName: local.name) } label: { Label(library.isPinned(localAlbumName: local.name) ? "Unpin" : "Pin to Library", systemImage: "pin") }
                                        Button(role: .destructive) { DownloadsManager.shared.deleteAlbum(albumName: local.name) } label: { Label("Delete", systemImage: "trash") }
                                    }
                                }
                            }
                        }
                    }.padding()
                    Spacer().frame(height: 100)
                }
                
                if isScrubbing {
                    VStack { Text(scrubLetter).font(.system(size: 60, weight: .bold)).foregroundColor(.white).frame(width: 100, height: 100).background(Color.black.opacity(0.6).cornerRadius(16)) }.zIndex(100)
                }
                
                // Hide scrubber if sorting by track count (since everything is in one group)
                if searchText.isEmpty && sortType != .trackCount {
                    HStack {
                        Spacer()
                        VStack(spacing: 0) {
                            ForEach(activeSections.map{$0.letter}, id:\.self) { l in Text(l).font(.system(size: 11, weight: .semibold)).foregroundColor(.pink).frame(width: 20, height: 18) }
                        }
                        .padding(.trailing, 2).background(Color.white.opacity(0.001))
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            let letters = activeSections.map { $0.letter }; guard !letters.isEmpty else { return }
                            let index = max(0, min(letters.count - 1, Int(value.location.y / 18)))
                            let targetLetter = letters[index]
                            if scrubLetter != targetLetter { UIImpactFeedbackGenerator(style: .light).impactOccurred(); scrubLetter = targetLetter; proxy.scrollTo(targetLetter, anchor: .top) }
                            isScrubbing = true
                        }.onEnded { value in
                            let letters = activeSections.map { $0.letter }; guard !letters.isEmpty else { return }
                            let index = max(0, min(letters.count - 1, Int(value.location.y / 18)))
                            proxy.scrollTo(letters[index], anchor: .top)
                            withAnimation(.easeInOut(duration: 0.2)) { isScrubbing = false }
                        })
                    }
                }
            }
        }
        .navigationTitle("Albums")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Section(header: Text("Genre")) {
                        Picker("Genre", selection: $selectedGenre) {
                            ForEach(availableGenres, id: \.self) { genre in
                                Text(genre).tag(genre)
                            }
                        }
                    }
                    Section(header: Text("Filter")) {
                        Picker("Filter", selection: $filterType) {
                            ForEach(AlbumFilterType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                    }
                    Section(header: Text("Sort")) {
                        Picker("Sort By", selection: $sortType) {
                            ForEach(AlbumSortType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                    }
                    Section {
                        Button(action: { showFavoritesOnly.toggle() }) {
                            Label(showFavoritesOnly ? "Show All Albums" : "Favorites Only", systemImage: showFavoritesOnly ? "star.fill" : "star")
                        }
                    }
                } label: {
                    let isFiltered = filterType != .all || sortType != .titleAZ || showFavoritesOnly || selectedGenre != "All Genres"
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(isFiltered ? .pink : .primary)
                }
            }
        }
    }
}
// MARK: - Album Detail View (Apple Music only)
struct AlbumDetailView: View {
    let album: MPMediaItemCollection
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var library: LibraryManager
    
    @State private var showAlbumSettings = false
    
    var albumID: String { "apple_\(album.persistentID)" }
    
    var groupedByDisc: [Int: [MPMediaItem]] {
        var groups: [Int: [MPMediaItem]] = [:]
        var currentDisc = 1
        var lastTrack = -1
        
        for item in album.items {
            if item.discNumber > 0 {
                currentDisc = item.discNumber
            } else {
                if item.albumTrackNumber > 0 && item.albumTrackNumber <= lastTrack {
                    currentDisc += 1
                }
            }
            groups[currentDisc, default: []].append(item)
            lastTrack = item.albumTrackNumber > 0 ? item.albumTrackNumber : lastTrack + 1
        }
        return groups
    }
    var sortedDiscs: [Int] { groupedByDisc.keys.sorted() }
    var showDiscHeaders: Bool { sortedDiscs.count > 1 || (sortedDiscs.first ?? 1) > 1 }
    
    var customBgColor: Color? {
        if let hex = library.customAlbumColors[albumID] { return Color(hex: hex) }
        return nil
    }
    
    var albumTextColor: Color {
        if let hex = library.albumTextColorPrefs[albumID] { return Color(hex: hex) }
        return customBgColor?.adaptivePrimary ?? .primary
    }

    var songTextColor: Color {
        if let hex = library.songTextColorPrefs[albumID] { return Color(hex: hex) }
        return customBgColor?.adaptiveSecondary ?? .primary
    }
    
    var dividerColor: Color {
        customBgColor != nil ? .white.opacity(0.3) : Color.gray.opacity(0.3)
    }
    
    var body: some View {
        let isCurrentAlbum = audioManager.currentSong.map { album.items.contains($0) } == true
        let isPlayingThisAlbum = audioManager.isPlaying && isCurrentAlbum
        
        ZStack {
            if let bgColor = customBgColor { bgColor.ignoresSafeArea() }
            else { Color(.systemBackground).ignoresSafeArea() }
            
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        let isEdgeToEdge = library.isEdgeToEdgeEnabled(for: albumID) == true
                        
                        if isEdgeToEdge {
                            VStack(spacing: 0) {
                                let originalArtwork = album.representativeItem?.artwork?.image(at: CGSize(width: 800, height: 800))
                                
                                let aspect: CGFloat = {
                                    guard let img = originalArtwork else { return 1.0 }
                                    let w = img.size.width
                                    let h = max(img.size.height, 1)
                                    if let crop = library.albumArtCrops[albumID] {
                                        let croppedW = w * (crop.trailing - crop.leading)
                                        let croppedH = h * (crop.bottom - crop.top)
                                        return croppedW / max(croppedH, 1)
                                    }
                                    return w / h
                                }()

                                ZStack(alignment: .bottom) {
                                    GeometryReader { geo in
                                        let minY = geo.frame(in: .named("albumScroll")).minY
                                        let overscroll = max(0, minY)
                                        let scrollUpOffset = minY < 0 ? -minY : 0

                                        // 1. CHECK FOR VIDEO ART FIRST
                                        if let videoURL = library.albumVideoArt[albumID] {
                                            AnimatedVideoArtView(videoURL: videoURL, crop: library.albumArtCrops[albumID])
                                                .frame(width: geo.size.width, height: geo.size.height + overscroll, alignment: .bottom)
                                                .clipped()
                                                .offset(y: scrollUpOffset)
                                                // Apply your existing bottom gradient fade
                                                .mask(
                                                    VStack(spacing: 0) {
                                                        Color.black
                                                        LinearGradient(
                                                            stops: [.init(color: .black, location: 0.0), .init(color: .clear, location: 1.0)],
                                                            startPoint: .top, endPoint: .bottom
                                                        ).frame(height: geo.size.height * 0.15)
                                                    }
                                                )
                                                .offset(y: -overscroll)
                                                
                                        // 2. FALLBACK TO ORIGINAL IMAGE LOGIC
                                        } else if let img = originalArtwork {
                                            let finalArtwork: UIImage = {
                                                if let cropData = library.albumArtCrops[albumID] {
                                                    let rect = CGRect(x: cropData.leading, y: cropData.top, width: cropData.trailing - cropData.leading, height: cropData.bottom - cropData.top)
                                                    return img.cropped(to: rect) ?? img
                                                }
                                                return img
                                            }()

                                            Image(uiImage: finalArtwork)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: geo.size.width, height: geo.size.height + overscroll, alignment: .bottom)
                                                .clipped()
                                                .offset(y: scrollUpOffset)
                                                .mask(
                                                    VStack(spacing: 0) {
                                                        Color.black
                                                        LinearGradient(
                                                            stops: [
                                                                .init(color: .black, location: 0.0),
                                                                .init(color: .clear, location: 1.0)
                                                            ],
                                                            startPoint: .top,
                                                            endPoint: .bottom
                                                        )
                                                        .frame(height: geo.size.height * 0.15)
                                                    }
                                                )
                                                .offset(y: -overscroll)
                                        } else {
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(width: geo.size.width, height: geo.size.height + overscroll, alignment: .bottom)
                                                .clipped()
                                                .offset(y: scrollUpOffset)
                                                .mask(
                                                    VStack(spacing: 0) {
                                                        Color.black
                                                        LinearGradient(
                                                            stops: [
                                                                .init(color: .black, location: 0.0),
                                                                .init(color: .clear, location: 1.0)
                                                            ],
                                                            startPoint: .top,
                                                            endPoint: .bottom
                                                        )
                                                        .frame(height: geo.size.height * 0.15)
                                                    }
                                                    .padding(.bottom, scrollUpOffset)
                                                )
                                                .offset(y: -overscroll)
                                        }
                                    }
                                    .aspectRatio(aspect, contentMode: .fit)

                                    HStack(spacing: 20) {
                                        Button(action: {
                                            if isCurrentAlbum {
                                                audioManager.togglePlayPause()
                                            } else {
                                                audioManager.isShuffled = false
                                                audioManager.play(song: album.items.first!, queue: album.items)
                                            }
                                        }) {
                                            HStack { Image(systemName: isPlayingThisAlbum ? "pause.fill" : "play.fill"); Text(isPlayingThisAlbum ? "Pause" : "Play") }
                                                .font(.headline)
                                                .foregroundColor(.pink)
                                                .frame(width: 160, height: 54)
                                                .background(Color(.systemBackground).opacity(0.85))
                                                .background(Material.ultraThin)
                                                .clipShape(Capsule())
                                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                                        }
                                        Button(action: { audioManager.isShuffled = true; audioManager.play(song: album.items.randomElement()!, queue: album.items) }) {
                                            HStack { Image(systemName: "shuffle"); Text("Shuffle") }
                                                .font(.headline)
                                                .foregroundColor(.pink)
                                                .frame(width: 160, height: 54)
                                                .background(Color(.systemBackground).opacity(0.85))
                                                .background(Material.ultraThin)
                                                .clipShape(Capsule())
                                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                                        }
                                    }
                                    .offset(y: 24)
                                }
                                .padding(.bottom, 36)

                                VStack(spacing: 4) {
                                    if library.albumShowTitlePrefs[albumID] ?? true {
                                        HStack(alignment: .center, spacing: 6) {
                                            Text(album.representativeItem?.albumTitle ?? "Unknown Album").font(.title2).bold().multilineTextAlignment(.center).foregroundColor(albumTextColor)
                                            if library.isSystemFavorite(album: album) { Image(systemName: "star.fill").foregroundColor(albumTextColor.opacity(0.8)).font(.headline) }
                                        }
                                    }
                                    NavigationLink(value: StringWrapper(value: album.representativeItem?.artist ?? "")) {
                                        Text(album.representativeItem?.artist ?? "Unknown Artist")
                                            .font(.title3)
                                            .foregroundColor(albumTextColor.opacity(0.8))
                                            .multilineTextAlignment(.center)
                                            .lineLimit(2)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                    
                                    if let year = album.representativeItem?.releaseDate { Text("\(album.representativeItem?.genre ?? "Pop") · \(String(Calendar.current.component(.year, from: year))) · \(collectionStats(collection: album))").font(.caption).foregroundColor(albumTextColor.opacity(0.6)).padding(.top, 2) }
                                    else { Text("\(album.representativeItem?.genre ?? "Pop") · \(collectionStats(collection: album))").font(.caption).foregroundColor(albumTextColor.opacity(0.6)).padding(.top, 2) }
                                }
                                .padding(.horizontal, 20)
                                
                                if let desc = library.customAlbumDescriptions[albumID], !desc.isEmpty {
                                    let currentBgColor = library.customAlbumColors[albumID] != nil ? Color(hex: library.customAlbumColors[albumID]!) : Color(.systemBackground)
                                    
                                    ExpandableDescriptionView(
                                        text: desc,
                                        albumTitle: album.representativeItem?.albumTitle ?? "Album",
                                        backgroundColor: currentBgColor,
                                        textColor: songTextColor // <-- Pass the adaptive color
                                    )
                                    .padding(.horizontal, 24)
                                    .padding(.top, 12)
                                }
                                Spacer().frame(height: 20)
                            }
                        } else {
                            VStack(spacing: 16) {
                                // Add the video check here for the standard layout
                                if let videoURL = library.albumVideoArt[albumID] {
                                    AnimatedVideoArtView(videoURL: videoURL, crop: library.albumArtCrops[albumID])
                                        .frame(width: 250, height: 250)
                                        .cornerRadius(12)
                                        .shadow(radius: 10)
                                } else if let artwork = album.representativeItem?.artwork?.image(at: CGSize(width: 300, height: 300)) {
                                    Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fit).frame(width: 250, height: 250).cornerRadius(12).shadow(radius: 10)
                                } else {
                                    Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 250, height: 250).cornerRadius(12)
                                }
                                
                                VStack(spacing: 4) {
                                    if library.albumShowTitlePrefs[albumID] ?? true {
                                        HStack(alignment: .center, spacing: 6) {
                                            Text(album.representativeItem?.albumTitle ?? "Unknown Album").font(.title2).bold().multilineTextAlignment(.center).foregroundColor(albumTextColor)
                                            if library.isSystemFavorite(album: album) { Image(systemName: "star.fill").foregroundColor(albumTextColor.opacity(0.8)).font(.headline) }
                                        }
                                    }
                                    NavigationLink(value: StringWrapper(value: album.representativeItem?.artist ?? "")) {
                                        Text(album.representativeItem?.artist ?? "Unknown Artist")
                                            .font(.title3)
                                            .foregroundColor(albumTextColor.opacity(0.8))
                                            .multilineTextAlignment(.center)
                                            .lineLimit(2)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                    
                                    if let year = album.representativeItem?.releaseDate { Text("\(album.representativeItem?.genre ?? "Pop") · \(String(Calendar.current.component(.year, from: year))) · \(collectionStats(collection: album))").font(.caption).foregroundColor(albumTextColor.opacity(0.6)).padding(.top, 2) }
                                    else { Text("\(album.representativeItem?.genre ?? "Pop") · \(collectionStats(collection: album))").font(.caption).foregroundColor(albumTextColor.opacity(0.6)).padding(.top, 2) }
                                }
                                .padding(.horizontal, 20)
                                
                                HStack(spacing: 20) {
                                    Button(action: {
                                        if isCurrentAlbum {
                                            audioManager.togglePlayPause()
                                        } else {
                                            audioManager.isShuffled = false
                                            audioManager.play(song: album.items.first!, queue: album.items)
                                        }
                                    }) { HStack { Image(systemName: isPlayingThisAlbum ? "pause.fill" : "play.fill"); Text(isPlayingThisAlbum ? "Pause" : "Play") }.font(.headline).foregroundColor(.pink).frame(width: 160, height: 54).background(Color.gray.opacity(0.1)).clipShape(Capsule()) }
                                    Button(action: { audioManager.isShuffled = true; audioManager.play(song: album.items.randomElement()!, queue: album.items) }) { HStack { Image(systemName: "shuffle"); Text("Shuffle") }.font(.headline).foregroundColor(.pink).frame(width: 160, height: 54).background(Color.gray.opacity(0.1)).clipShape(Capsule()) }
                                }.padding(.top, 8)
                                
                                if let desc = library.customAlbumDescriptions[albumID], !desc.isEmpty {
                                    let currentBgColor = library.customAlbumColors[albumID] != nil ? Color(hex: library.customAlbumColors[albumID]!) : Color(.systemBackground)
                                    ExpandableDescriptionView(
                                        text: desc,
                                        albumTitle: album.representativeItem?.albumTitle ?? "Album",
                                        backgroundColor: currentBgColor
                                    )
                                    .padding(.horizontal, 24)
                                    .padding(.top, 8)
                                }
                            }
                            .padding(.top, 20)
                            .padding(.bottom, 20)
                        }
                    }
                    .padding(.top, library.isEdgeToEdgeEnabled(for: albumID) == true ? 0 : 20)
                    
                    ForEach(sortedDiscs, id: \.self) { disc in
                        if showDiscHeaders {
                            HStack {
                                Text("Disc \(disc)")
                                    .font(.headline)
                                    .foregroundColor(albumTextColor.opacity(0.8))
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.top, 16)
                            
                            Divider().background(dividerColor).padding(.leading)
                        }
                        
                        if let discSongs = groupedByDisc[disc] {
                            ForEach(discSongs, id: \.persistentID) { song in
                                SongRow(
                                    song: song,
                                    audioManager: audioManager,
                                    library: library,
                                    showArtwork: false,
                                    showTrackNumber: true,
                                    customPrimaryColor: songTextColor,
                                    customSecondaryColor: songTextColor.opacity(0.6)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    audioManager.play(song: song, queue: album.items)
                                }
                                
                                Divider().background(dividerColor).padding(.leading)
                            }
                        }
                    }
                    Spacer().frame(height: 100)
                }
            }
        }
        .coordinateSpace(name: "albumScroll")
        .ignoresSafeArea(edges: library.isEdgeToEdgeEnabled(for: albumID) == true ? .top : [])
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(library.isEdgeToEdgeEnabled(for: albumID) == true ? .hidden : .automatic, for: .navigationBar)
        .sheet(isPresented: $showAlbumSettings) {
            let art = album.representativeItem?.artwork?.image(at: CGSize(width: 800, height: 800))
            AlbumSettingsSheet(albumID: albumID, artworkImage: art)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showAlbumSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(.pink)
                    }
                    
                    Menu {
                        Button { audioManager.play(song: album.items.first!, queue: album.items) } label: { Label("Play", systemImage: "play") }
                        Button { library.togglePin(album: album) } label: { Label(library.isPinned(album: album) ? "Unpin" : "Pin to Library", systemImage: "pin") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.pink)
                    }
                }
            }
        }
    }
}

// MARK: - UNIFIED Songs List
struct SongListView: View {
    @ObservedObject var library: LibraryManager
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var downloads = DownloadsManager.shared
    
    @Binding var isSearching: Bool
    var showArtwork: Bool
    @Binding var showSettings: Bool
    @State private var searchText = ""
    @State private var showFavoritesOnly = false
    
    @State private var isScrubbing = false
    @State private var scrubLetter = ""
    
    var activeSections: [UnifiedSongSection] {
        var appleSongs = library.songs
        if showFavoritesOnly { appleSongs = appleSongs.filter { library.isSystemFavorite(song: $0) } }
        if !searchText.isEmpty { appleSongs = library.smartFilterSongs(in: appleSongs, for: searchText) }
        
        var localSongs = downloads.downloadedSongs
        if showFavoritesOnly { localSongs = [] }
        if !searchText.isEmpty { localSongs = localSongs.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.artist.localizedCaseInsensitiveContains(searchText) } }
        
        var unified: [UnifiedSongItem] = []
        unified.append(contentsOf: appleSongs.map {
            UnifiedSongItem(id: String($0.persistentID), title: $0.title ?? "Unknown", artist: $0.artist ?? "Unknown", sortTitle: $0.title ?? "Unknown", appleSong: $0, localSong: nil)
        })
        unified.append(contentsOf: localSongs.map {
            UnifiedSongItem(id: $0.id, title: $0.title, artist: $0.artist, sortTitle: $0.title, appleSong: nil, localSong: $0)
        })
        
        let grouped = Dictionary(grouping: unified) { item -> String in
            let prefix = item.sortTitle.prefix(1).uppercased()
            return prefix.rangeOfCharacter(from: .letters) != nil ? prefix : "#"
        }
        
        let sortedKeys = grouped.keys.sorted { lhs, rhs in if lhs == "#" { return false }; if rhs == "#" { return true }; return lhs < rhs }
        return sortedKeys.map { letter in let sortedSongs = (grouped[letter] ?? []).sorted { $0.sortTitle < $1.sortTitle }; return UnifiedSongSection(letter: letter, songs: sortedSongs) }
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                ScrollView {
                    let allUnified = activeSections.flatMap { $0.songs }
                    let appleQueue = allUnified.compactMap { $0.appleSong }
                    let localQueue = allUnified.compactMap { $0.localSong }
                    
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Button(action: {
                            audioManager.isShuffled = true
                            if let randomItem = allUnified.randomElement() {
                                if let apple = randomItem.appleSong { audioManager.play(song: apple, queue: appleQueue) }
                                else if let local = randomItem.localSong { audioManager.play(localSong: local, queue: localQueue) }
                            }
                        }) {
                            HStack { Image(systemName: "shuffle"); Text("Shuffle Songs") }.font(.headline).foregroundColor(.pink).padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(.systemBackground))
                        }
                        
                        ForEach(activeSections) { section in
                            Section(header: Text(section.letter).font(.headline).foregroundColor(.pink).padding(.horizontal).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).background(Color(.systemBackground)).id(section.letter)) {
                                ForEach(section.songs) { item in
                                    if let apple = item.appleSong {
                                        SongRow(song: apple, audioManager: audioManager, library: library, showArtwork: showArtwork, showTrackNumber: false)
                                            .contentShape(Rectangle())
                                            .onTapGesture { audioManager.play(song: apple, queue: appleQueue) }
                                    } else if let local = item.localSong {
                                        DownloadsSongRow(song: local, queue: localQueue, showArtwork: showArtwork, showTrackNumber: false, audioManager: audioManager)
                                    }
                                    Divider().padding(.leading)
                                }
                            }
                        }
                        Spacer().frame(height: 100)
                    }.padding(.trailing, 20)
                }
                
                if isScrubbing {
                    VStack {
                        Text(scrubLetter)
                            .font(.system(size: 60, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 100, height: 100)
                            .background(Color.black.opacity(0.6).cornerRadius(16))
                    }.zIndex(100)
                }
                
                if searchText.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 0) {
                            ForEach(activeSections.map{$0.letter}, id:\.self) { l in Text(l).font(.system(size: 11, weight: .semibold)).foregroundColor(.pink).frame(width: 20, height: 18) }
                        }
                        .padding(.trailing, 2)
                        .background(Color.white.opacity(0.001))
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            let letters = activeSections.map { $0.letter }; guard !letters.isEmpty else { return }
                            let index = max(0, min(letters.count - 1, Int(value.location.y / 18)))
                            let targetLetter = letters[index]
                            if scrubLetter != targetLetter { UIImpactFeedbackGenerator(style: .light).impactOccurred(); scrubLetter = targetLetter }
                            isScrubbing = true
                        }.onEnded { value in
                            let letters = activeSections.map { $0.letter }; guard !letters.isEmpty else { return }
                            let index = max(0, min(letters.count - 1, Int(value.location.y / 18)))
                            proxy.scrollTo(letters[index], anchor: .top)
                            withAnimation(.easeInOut(duration: 0.2)) { isScrubbing = false }
                        })
                    }
                }
            }
        }
        .navigationTitle("Songs")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: { showFavoritesOnly.toggle() }) { Image(systemName: showFavoritesOnly ? "star.fill" : "star").foregroundColor(showFavoritesOnly ? .yellow : .pink) }
            }
        }
    }
}

struct AlbumArtEditorSheet: View {
    let albumID: String
    let artworkImage: UIImage?
    
    @ObservedObject var library = LibraryManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var top: CGFloat = 0.0
    @State private var bottom: CGFloat = 1.0
    @State private var leading: CGFloat = 0.0
    @State private var trailing: CGFloat = 1.0
    
    @State private var startTop: CGFloat? = nil
    @State private var startBottom: CGFloat? = nil
    @State private var startLeading: CGFloat? = nil
    @State private var startTrailing: CGFloat? = nil

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                
                VStack {
                    Text("Drag the edges to crop. The selected area will scale to fill the edge-to-edge header.")
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center).padding()
                    
                    GeometryReader { geo in
                        if let img = artworkImage {
                            let imgRect = calculateImageRect(in: geo.size, imageSize: img.size)
                            
                            ZStack(alignment: .topLeading) {
                                Image(uiImage: img)
                                    .resizable().scaledToFit()
                                    .frame(width: geo.size.width, height: geo.size.height)
                                
                                let cropScreenRect = CGRect(
                                    x: imgRect.minX + leading * imgRect.width,
                                    y: imgRect.minY + top * imgRect.height,
                                    width: (trailing - leading) * imgRect.width,
                                    height: (bottom - top) * imgRect.height
                                )
                                
                                Path { path in
                                    path.addRect(CGRect(origin: .zero, size: geo.size))
                                    path.addRect(cropScreenRect)
                                }
                                .fill(style: FillStyle(eoFill: true))
                                .foregroundColor(Color.black.opacity(0.6))
                                
                                Rectangle()
                                    .stroke(Color.white, lineWidth: 2)
                                    .frame(width: cropScreenRect.width, height: cropScreenRect.height)
                                    .position(x: cropScreenRect.midX, y: cropScreenRect.midY)
                                
                                dragHandle(width: 40, height: 24)
                                    .position(x: cropScreenRect.midX, y: cropScreenRect.minY)
                                    .gesture(DragGesture()
                                        .onChanged { val in
                                            if startTop == nil { startTop = top }
                                            let delta = val.translation.height / imgRect.height
                                            top = max(0.0, min(startTop! + delta, bottom - 0.1))
                                        }
                                        .onEnded { _ in startTop = nil }
                                    )
                                
                                dragHandle(width: 40, height: 24)
                                    .position(x: cropScreenRect.midX, y: cropScreenRect.maxY)
                                    .gesture(DragGesture()
                                        .onChanged { val in
                                            if startBottom == nil { startBottom = bottom }
                                            let delta = val.translation.height / imgRect.height
                                            bottom = min(1.0, max(startBottom! + delta, top + 0.1))
                                        }
                                        .onEnded { _ in startBottom = nil }
                                    )
                                
                                dragHandle(width: 24, height: 40)
                                    .position(x: cropScreenRect.minX, y: cropScreenRect.midY)
                                    .gesture(DragGesture()
                                        .onChanged { val in
                                            if startLeading == nil { startLeading = leading }
                                            let delta = val.translation.width / imgRect.width
                                            leading = max(0.0, min(startLeading! + delta, trailing - 0.1))
                                        }
                                        .onEnded { _ in startLeading = nil }
                                    )
                                
                                dragHandle(width: 24, height: 40)
                                    .position(x: cropScreenRect.maxX, y: cropScreenRect.midY)
                                    .gesture(DragGesture()
                                        .onChanged { val in
                                            if startTrailing == nil { startTrailing = trailing }
                                            let delta = val.translation.width / imgRect.width
                                            trailing = min(1.0, max(startTrailing! + delta, leading + 0.1))
                                        }
                                        .onEnded { _ in startTrailing = nil }
                                    )
                            }
                        }
                    }
                    .padding()
                    
                    Button(role: .destructive) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        library.saveAlbumArtCrop(id: albumID, crop: nil)
                        dismiss()
                    } label: { Text("Reset to Default") }.padding(.bottom, 20)
                }
            }
            .navigationTitle("Crop Artwork")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let crop = AlbumArtCrop(top: top, bottom: bottom, leading: leading, trailing: trailing)
                        library.saveAlbumArtCrop(id: albumID, crop: crop)
                        dismiss()
                    }.bold()
                }
            }
            .onAppear {
                if let saved = library.albumArtCrops[albumID] {
                    top = saved.top; bottom = saved.bottom
                    leading = saved.leading; trailing = saved.trailing
                }
            }
        }
    }
    
    private func calculateImageRect(in geoSize: CGSize, imageSize: CGSize) -> CGRect {
        let widthRatio = geoSize.width / imageSize.width
        let heightRatio = geoSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (geoSize.width - w) / 2, y: (geoSize.height - h) / 2, width: w, height: h)
    }
    
    private func dragHandle(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.white.opacity(0.01)
                .frame(width: max(width, 44), height: max(height, 44))
            Capsule()
                .fill(Color.white)
                .shadow(radius: 2)
                .frame(width: width > 24 ? 30 : 6, height: height > 24 ? 30 : 6)
        }
    }
}

// MARK: - Legacy Apple Playlist Details
struct PlaylistDetailView: View {
    let playlist: MPMediaItemCollection
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var library: LibraryManager
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Button(action: { audioManager.isShuffled = true; audioManager.play(song: playlist.items.randomElement()!, queue: playlist.items) }) { HStack { Image(systemName: "shuffle"); Text("Shuffle Playlist") }.font(.headline).foregroundColor(.pink).padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(.systemBackground)) }
                ForEach(playlist.items, id: \.persistentID) { song in SongRow(song: song, audioManager: audioManager, library: library, showArtwork: true, showTrackNumber: false).contentShape(Rectangle()).onTapGesture { audioManager.play(song: song, queue: playlist.items) }; Divider().padding(.leading) }
                Spacer().frame(height: 100)
            }
        }.background(Color(.systemBackground)).navigationTitle(playlist.value(forProperty: MPMediaPlaylistPropertyName) as? String ?? "Playlist")
    }
}

// MARK: - Legacy Artist Search Fallback
struct ArtistDetailView: View {
    let artist: String
    @ObservedObject var library: LibraryManager
    @ObservedObject var audioManager: AudioManager
    var songs: [MPMediaItem] { library.songs.filter { $0.artist == artist } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Button(action: { audioManager.isShuffled = true; audioManager.play(song: songs.randomElement()!, queue: songs) }) { HStack { Image(systemName: "shuffle"); Text("Shuffle Artist") }.font(.headline).foregroundColor(.pink).padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(.systemBackground)) }
                ForEach(songs, id: \.persistentID) { song in SongRow(song: song, audioManager: audioManager, library: library, showArtwork: true, showTrackNumber: false).contentShape(Rectangle()).onTapGesture { audioManager.play(song: song, queue: songs) }; Divider().padding(.leading) }
                Spacer().frame(height: 100)
            }
        }.navigationTitle(artist)
    }
}

// MARK: - Landscape Layouts
struct LandscapeLayout: View {
    @ObservedObject var library: LibraryManager
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var settings: AppSettings
    @ObservedObject var uiState: PlayerUIState
    
    var body: some View {
        Group {
            if settings.landscapeMode == .fullPlayer { LandscapePlayerView(audioManager: audioManager, library: library, settings: settings, uiState: uiState, dismissAction: nil) }
            else { if uiState.isPlayerExpanded { LandscapePlayerView(audioManager: audioManager, library: library, settings: settings, uiState: uiState, dismissAction: { withAnimation { uiState.isPlayerExpanded = false } }) } else { CoverFlowContainer(library: library, audioManager: audioManager, showPlayer: $uiState.isPlayerExpanded) } }
        }.background(Color.black).edgesIgnoringSafeArea(.all).statusBar(hidden: true)
    }
}

struct LandscapePlayerView: View {
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var library: LibraryManager
    @ObservedObject var settings: AppSettings
    @ObservedObject var uiState: PlayerUIState
    var dismissAction: (() -> Void)?
    
    @State private var isDraggingSlider = false
    @State private var sliderValue: Double = 0
    @State private var isFlipped = false
    @State private var backViewScrollOffset: CGFloat = 0
    @State private var showSongInfo = false
    @State private var showSyncSheet = false
    @State private var showRawLyricsEditor = false
    
    let playbackSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    
    var body: some View {
        GeometryReader { geo in
            let safeArea = geo.safeAreaInsets; let isiPad = geo.size.height > 600
            ZStack {
                Group { if let artwork = audioManager.displayArtwork(size: CGSize(width: 800, height: 800)) { Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fill).blur(radius: 60).overlay(Color.black.opacity(0.5)) } else { Rectangle().fill(Color(UIColor.systemGray6)).overlay(Color.black.opacity(0.8)) } }.frame(width: geo.size.width, height: geo.size.height).ignoresSafeArea().onTapGesture { if isFlipped && !uiState.showLyrics { withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { isFlipped = false } } }
                
                HStack(spacing: 0) {
                    VStack {
                        Spacer()
                        GeometryReader { artGeo in
                            let size = min(artGeo.size.width, artGeo.size.height)
                            if uiState.showLyrics {
                                let hasSong = audioManager.currentSong != nil || audioManager.currentLocalSong != nil || audioManager.currentRemoteDTO != nil
                                if hasSong {
                                    InlineLyricsView(song: audioManager.currentSong, audioManager: audioManager, library: library, uiState: uiState, settings: settings, showRawLyricsEditor: $showRawLyricsEditor, showSyncSheet: $showSyncSheet, showFullScreenButton: true).frame(width: artGeo.size.width, height: artGeo.size.height).position(x: artGeo.size.width / 2, y: artGeo.size.height / 2).transition(AnyTransition.asymmetric(insertion: AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.95)), removal: AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.95))))
                                }
                            } else {
                                ZStack {
                                    if let artwork = audioManager.displayArtwork(size: CGSize(width: 600, height: 600)) { Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fit).cornerRadius(16).shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 15).opacity(isFlipped ? 0 : 1).rotation3DEffect(.degrees(isFlipped ? -180 : 0), axis: (x: 0, y: 1, z: 0)) } else { Image(systemName: "music.note").font(.system(size: 80)).foregroundColor(.white.opacity(0.2)).frame(width: size, height: size).background(Color.white.opacity(0.05)).cornerRadius(16).opacity(isFlipped ? 0 : 1).rotation3DEffect(.degrees(isFlipped ? -180 : 0), axis: (x: 0, y: 1, z: 0)) }
                                    if let song = audioManager.currentSong, let album = library.albums.first(where: { $0.persistentID == song.albumPersistentID }) { AlbumBackView(album: album, audioManager: audioManager, size: size, isReflection: false, externalScrollOffset: $backViewScrollOffset).cornerRadius(16).shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 15).rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0)).rotation3DEffect(.degrees(isFlipped ? -180 : 0), axis: (x: 0, y: 1, z: 0)).opacity(isFlipped ? 1 : 0) }
                                }
                                .frame(width: size, height: size).position(x: artGeo.size.width / 2, y: artGeo.size.height / 2).onTapGesture { if audioManager.currentSong != nil { withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { isFlipped.toggle() } } }.transition(AnyTransition.asymmetric(insertion: AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.95)), removal: AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.95))))
                            }
                        }
                        .frame(maxHeight: uiState.isLyricsFullScreen ? .infinity : geo.size.height * (isiPad ? 0.7 : 0.85))
                        // Shifted further right to avoid safe area, and trailing expanded out into the gap
                        .padding(.leading, uiState.isLyricsFullScreen ? safeArea.leading + 20 : safeArea.leading + 20)
                        .padding(.trailing, uiState.isLyricsFullScreen ? safeArea.trailing + 20 : -60)
                        Spacer()
                    }.frame(width: uiState.isLyricsFullScreen ? geo.size.width : geo.size.width * 0.55)
                    
                    if !uiState.isLyricsFullScreen {
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer()
                            VStack(alignment: .center, spacing: 8) {
                                HStack(alignment: .center, spacing: 6) {
                                    if let song = audioManager.currentSong { Button(action: { library.toggleFavorite(song: song); UIImpactFeedbackGenerator(style: .light).impactOccurred() }) { Image(systemName: library.isSystemFavorite(song: song) ? "star.fill" : "star").font(.title3).foregroundColor(library.isSystemFavorite(song: song) ? .yellow : .white.opacity(0.6)) } } else { Image(systemName: "star").font(.title3).opacity(0) }
                                    MarqueeText(text: audioManager.displayTitle, font: .system(size: isiPad ? 32 : 24, weight: .bold)).frame(height: 35).foregroundColor(.white)
                                    Image(systemName: "star").font(.title3).opacity(0)
                                }.padding(.horizontal, 30)
                                Text(audioManager.displayArtist).font(.system(size: isiPad ? 22 : 18, weight: .medium)).foregroundColor(.white.opacity(0.7)).lineLimit(1).multilineTextAlignment(.center).padding(.horizontal, 30)
                            }.padding(.bottom, 30)
                            
                            VStack(spacing: 8) {
                                Slider(value: $sliderValue, in: 0...max(audioManager.duration, 1), onEditingChanged: { editing in isDraggingSlider = editing; if !editing { audioManager.seek(to: sliderValue) } }).tint(.white).onChange(of: audioManager.currentTime, perform: { time in if !isDraggingSlider { let cleanTime = (time.isNaN || time.isInfinite || time < 0) ? 0 : time; sliderValue = min(max(0, cleanTime), max(1, audioManager.duration)) } })
                                HStack { Text(formatTime(isDraggingSlider ? sliderValue : audioManager.currentTime)); Spacer(); Text("-" + formatTime(max(0, audioManager.duration - audioManager.currentTime))) }.font(.caption.monospacedDigit().weight(.semibold)).foregroundColor(.white.opacity(0.6))
                            }.padding(.horizontal, 30).padding(.bottom, 20)
                            
                            HStack(spacing: 50) {
                                Button(action: { audioManager.previous() }) { Image(systemName: "backward.fill").font(.system(size: 30)).foregroundColor(.white) }
                                Button(action: { let impact = UIImpactFeedbackGenerator(style: .medium); impact.impactOccurred(); audioManager.togglePlayPause() }) { Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 70)).foregroundColor(.white).shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5) }
                                Button(action: { audioManager.next() }) { Image(systemName: "forward.fill").font(.system(size: 30)).foregroundColor(.white) }
                            }.frame(maxWidth: .infinity, alignment: .center).padding(.bottom, 30)
                            
                            HStack(spacing: 35) {
                                Button(action: { audioManager.toggleLoop() }) { Image(systemName: audioManager.isLooping ? "repeat.1" : "repeat").font(.title3).foregroundColor(audioManager.isLooping ? .pink : .white.opacity(0.4)) }
                                AirPlayView().frame(width: 44, height: 44)
                                Button(action: { uiState.showLyrics.toggle() }) { Image(systemName: "quote.bubble").font(.title3).foregroundColor(uiState.showLyrics ? .pink : .white.opacity(0.4)) }
                                Menu { ForEach(playbackSpeeds, id: \.self) { speed in Button { audioManager.setPlaybackSpeed(speed) } label: { HStack { Text("\(String(format: "%g", speed))x"); if audioManager.playbackRate == speed { Image(systemName: "checkmark") } } } } } label: { Text("\(String(format: "%g", audioManager.playbackRate))x").font(.title3).fontWeight(.bold).foregroundColor(audioManager.playbackRate == 1.0 ? .white.opacity(0.4) : .pink).frame(minWidth: 44) }
                                Button(action: { audioManager.toggleShuffle() }) { Image(systemName: "shuffle").font(.title3).foregroundColor(audioManager.isShuffled ? .pink : .white.opacity(0.4)) }
                            }.frame(maxWidth: .infinity, alignment: .center)
                            Spacer()
                        }.padding(.trailing, safeArea.trailing + 40).padding(.leading, 30).frame(width: geo.size.width * 0.45)
                    }
                }.padding(.top, safeArea.top).padding(.bottom, safeArea.bottom)
                
                VStack {
                    HStack {
                        Button(action: { if let dismiss = dismissAction { dismiss() } }) { HStack(spacing: 6) { Image(systemName: "chevron.down").font(.system(size: 18, weight: .bold)); Text("Library").font(.system(size: 16, weight: .semibold)) }.foregroundColor(.white.opacity(0.9)).padding(.vertical, 8).padding(.horizontal, 16).background(Material.ultraThin).clipShape(Capsule()) }.opacity(dismissAction == nil ? 0 : 1).padding(.leading, safeArea.leading + 20).padding(.top, safeArea.top + 20)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showSongInfo) {
            SongInfoSheet(appleSong: audioManager.currentSong, localSong: audioManager.currentLocalSong, remoteSong: audioManager.currentRemoteDTO)
        }
        .sheet(isPresented: $showRawLyricsEditor) {
            if let song = audioManager.currentSong {
                RawLyricsEditorSheet(appleSong: song, audioManager: audioManager, library: library)
            } else if let localSong = audioManager.currentLocalSong {
                RawLyricsEditorSheet(localSong: localSong, audioManager: audioManager, library: library)
            } else if let remoteSong = audioManager.currentRemoteDTO {
                RawLyricsEditorSheet(remoteSong: remoteSong, audioManager: audioManager, library: library)
            }
        }
        .sheet(isPresented: $showSyncSheet) {
            if let song = audioManager.currentSong {
                SyncEditorSheet(appleSong: song, audioManager: audioManager, library: library)
            } else if let localSong = audioManager.currentLocalSong {
                SyncEditorSheet(localSong: localSong, audioManager: audioManager, library: library)
            } else if let remoteSong = audioManager.currentRemoteDTO {
                SyncEditorSheet(remoteSong: remoteSong, audioManager: audioManager, library: library)
            }
        }
    }
    func formatTime(_ time: TimeInterval) -> String { guard !time.isNaN && !time.isInfinite else { return "0:00" }; let minutes = Int(time) / 60; let seconds = Int(time) % 60; return String(format: "%d:%02d", minutes, seconds) }
}

struct CoverFlowContainer: View {
    @ObservedObject var library: LibraryManager
    @ObservedObject var audioManager: AudioManager
    @Binding var showPlayer: Bool
    
    enum FilterState { case all, favorites, pinned }
    
    
    @State private var filterState: FilterState = .all
    @State private var selectedIndex: Double = 0
    @State private var dragOffset: CGFloat = 0
    @State private var flippedAlbumID: UInt64? = nil
    
    private let cardSize: CGFloat = 260; private let spacing: CGFloat = 180; private let sideCompression: CGFloat = 90; private let centerGap: CGFloat = 170
    
    var albums: [MPMediaItemCollection] { switch filterState { case .all: return library.albums; case .favorites: return library.favoriteAlbums; case .pinned: return library.pinnedAlbums } }
    var filterIcon: String { switch filterState { case .all: return "square.stack"; case .favorites: return "star.fill"; case .pinned: return "pin.fill" } }
    var filterLabel: String { switch filterState { case .all: return "All Albums"; case .favorites: return "Favorites"; case .pinned: return "Pinned" } }
    
    func syncToCurrentSong() { guard let current = audioManager.currentSong else { return }; if let index = albums.firstIndex(where: { $0.persistentID == current.albumPersistentID }) { withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { selectedIndex = Double(index) } } }
    
    var body: some View {
        GeometryReader { geo in
            let centerX = geo.size.width / 2; let centerY = geo.size.height / 2; let fitScale = (geo.size.height - 40) / cardSize
            let activeIndex = selectedIndex - (dragOffset / spacing); let centerInt = Int(round(activeIndex))
            
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all).contentShape(Rectangle()).onTapGesture { if flippedAlbumID != nil { withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { flippedAlbumID = nil } } }
                
                VStack {
                    HStack(alignment: .top) {
                        let hasSong = audioManager.currentSong != nil || audioManager.currentLocalSong != nil || audioManager.currentRemoteDTO != nil
                        if hasSong {
                            Button(action: { withAnimation { showPlayer = true } }) { HStack(spacing: 8) { if let artwork = audioManager.displayArtwork(size: CGSize(width: 40, height: 40)) { Image(uiImage: artwork).resizable().frame(width: 30, height: 30).cornerRadius(4) } else { Image(systemName: "music.note").frame(width: 30, height: 30).background(Color.gray).cornerRadius(4) }; VStack(alignment: .leading, spacing: 0) { Text(audioManager.displayTitle).font(.caption).bold().foregroundColor(.primary).lineLimit(1); Text(audioManager.displayArtist).font(.caption2).foregroundColor(.secondary).lineLimit(1) }; Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary) }.padding(8).background(.regularMaterial).cornerRadius(20).frame(maxWidth: 250, alignment: .leading) }.padding(.leading, 20).padding(.top, 20)
                        } else { Spacer() }
                        Spacer()
                        Menu { Button { withAnimation { filterState = .all; selectedIndex = 0 } } label: { Label("All Albums", systemImage: "square.stack") }; Button { withAnimation { filterState = .favorites; selectedIndex = 0 } } label: { Label("Favorites", systemImage: "star.fill") }; Button { withAnimation { filterState = .pinned; selectedIndex = 0 } } label: { Label("Pinned", systemImage: "pin.fill") } } label: { HStack(spacing: 6) { Image(systemName: filterIcon); Text(filterLabel) }.font(.system(size: 14, weight: .bold)).foregroundColor(.white).padding(.vertical, 8).padding(.horizontal, 16).background(Color.gray.opacity(0.3)).cornerRadius(20) }.padding(.top, 20).padding(.trailing, 20)
                    }
                    Spacer()
                }.zIndex(10000).allowsHitTesting(flippedAlbumID == nil)
                
                if albums.isEmpty { VStack { Image(systemName: filterIcon).font(.system(size: 60)).foregroundColor(.gray.opacity(0.5)); Text("No \(filterLabel)").font(.title3).foregroundColor(.gray) } } else {
                    let rangeStart = max(0, centerInt - 5); let rangeEnd = min(albums.count - 1, centerInt + 5)
                    ForEach(rangeStart...rangeEnd, id: \.self) { index in
                        let dist = CGFloat(index) - CGFloat(activeIndex); let isFlipped = (flippedAlbumID == albums[index].persistentID); let yPos = isFlipped ? centerY : (centerY - 30)
                        CoverFlowItem(album: albums[index], audioManager: audioManager, relativeIndex: dist, isFlipped: isFlipped, size: cardSize, sideCompression: sideCompression, centerGap: centerGap, zoomScale: fitScale, onTapBody: { if flippedAlbumID != nil { withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { flippedAlbumID = nil } } else { if index == centerInt { withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { flippedAlbumID = albums[index].persistentID } } else { withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { selectedIndex = Double(index) } } } }).position(x: centerX, y: yPos).zIndex(isFlipped ? 99999 : (1000 - abs(Double(dist)) * 10))
                    }
                    if centerInt >= 0 && centerInt < albums.count {
                        let currentAlbum = albums[centerInt]
                        VStack { Spacer(); HStack { if flippedAlbumID == nil { Button(action: { let impact = UIImpactFeedbackGenerator(style: .medium); impact.impactOccurred(); audioManager.play(song: currentAlbum.items.first!, queue: currentAlbum.items) }) { Image(systemName: "play.circle.fill").font(.system(size: 50)).foregroundColor(.white).shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4).padding(30) }.transition(AnyTransition.scale.combined(with: AnyTransition.opacity)) }; Spacer(); Button(action: { let impact = UIImpactFeedbackGenerator(style: .light); impact.impactOccurred(); withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { flippedAlbumID = (flippedAlbumID == currentAlbum.persistentID) ? nil : currentAlbum.persistentID } }) { Image(systemName: flippedAlbumID == currentAlbum.persistentID ? "arrow.uturn.backward.circle.fill" : "info.circle.fill").font(.system(size: 50)).foregroundColor(.white).shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4).padding(30) } } }
                    }
                }
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in guard flippedAlbumID == nil else { return }; let translation = value.translation.width; dragOffset = translation }.onEnded { value in guard flippedAlbumID == nil else { return }; let velocity = (value.predictedEndLocation.x - value.startLocation.x); let targetIndex: Double; if abs(velocity) < 300 { targetIndex = round(selectedIndex - (dragOffset / spacing)) } else { let inertia = velocity * 0.5; let projectedIndex = selectedIndex - (inertia / spacing); let jump = projectedIndex - selectedIndex; let maxJump: Double = 40; let clampedJump = max(-maxJump, min(maxJump, jump)); targetIndex = round(selectedIndex + clampedJump) }; let clampedTarget = max(0, min(Double(albums.count - 1), targetIndex)); withAnimation(.interpolatingSpring(mass: 1.0, stiffness: 100, damping: 20, initialVelocity: 0)) { selectedIndex = clampedTarget; dragOffset = 0 } })
        }.onAppear { syncToCurrentSong() }.onChange(of: showPlayer, perform: { isShowing in if !isShowing { syncToCurrentSong() } })
    }
}

struct CoverFlowItem: View {
    let album: MPMediaItemCollection; @ObservedObject var audioManager: AudioManager; let relativeIndex: CGFloat; let isFlipped: Bool; let size: CGFloat; let sideCompression: CGFloat; let centerGap: CGFloat; let zoomScale: CGFloat; let onTapBody: () -> Void; @State private var sharedScrollOffset: CGFloat = 0
    var body: some View {
        let absIndex = abs(relativeIndex); let isRight = relativeIndex > 0; let targetScale: CGFloat = isFlipped ? zoomScale : (1.0 - (min(1.0, absIndex) * 0.25)); let scrollRotation: Double = { let rotationLimit: Double = 65; let rotationFactor = min(1.0, absIndex); return (isRight ? -1 : 1) * (rotationLimit * rotationFactor) }(); let flipRotation: Double = isFlipped ? -180 : 0; let finalRotation = (isFlipped ? 0 : scrollRotation) + flipRotation; let xOffset: CGFloat = { if isFlipped { return 0 }; let stageProgress = min(1.0, absIndex); let stageOffset = stageProgress * centerGap; let stackIndex = max(0, absIndex - 1.0); let stackOffset = stackIndex * sideCompression; let total = stageOffset + stackOffset; return isRight ? total : -total }()
        return ZStack {
            Group { if let artwork = album.representativeItem?.artwork?.image(at: CGSize(width: 600, height: 600)) { Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fill).clipped() } else { Rectangle().fill(Color(UIColor.systemGray6)).overlay(Image(systemName: "music.note").font(.system(size: 80)).foregroundColor(.gray)) } }.frame(width: size, height: size).cornerRadius(8).opacity(isFlipped ? 0 : 1)
            AlbumBackView(album: album, audioManager: audioManager, size: size, isReflection: false, externalScrollOffset: $sharedScrollOffset).frame(width: size, height: size).cornerRadius(8).rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0)).opacity(isFlipped ? 1 : 0)
            if !isFlipped { ReflectionOverlay(album: album, size: size).offset(y: size).opacity(max(0, 0.6 - absIndex * 0.5)) }
            if isFlipped { AlbumBackView(album: album, audioManager: audioManager, size: size, isReflection: true, externalScrollOffset: $sharedScrollOffset).frame(width: size, height: size).cornerRadius(8).rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0)).scaleEffect(x: 1, y: -1, anchor: .bottom).mask(LinearGradient(gradient: Gradient(colors: [.white.opacity(0.35), .clear]), startPoint: .top, endPoint: .bottom)).offset(y: size).opacity(0.5) }
        }.scaleEffect(targetScale).rotation3DEffect(.degrees(finalRotation), axis: (x: 0, y: 1, z: 0), anchor: .center, perspective: 0.5).offset(x: xOffset).onTapGesture { onTapBody() }
    }
}

struct AlbumBackView: View {
    let album: MPMediaItemCollection; @ObservedObject var audioManager: AudioManager; let size: CGFloat; let isReflection: Bool; @Binding var externalScrollOffset: CGFloat; var onBackgroundTap: (() -> Void)? = nil
    var body: some View {
        ZStack {
            Color.black
            if let artwork = album.representativeItem?.artwork?.image(at: CGSize(width: 500, height: 500)) { Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fill).frame(width: size, height: size).scaleEffect(x: -1, y: 1).blur(radius: 20).overlay(Color.black.opacity(0.6)).clipped() }
            Color.clear.contentShape(Rectangle()).onTapGesture { onBackgroundTap?() }
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Button(action: { if !isReflection { audioManager.isShuffled = true; audioManager.play(song: album.items.randomElement()!, queue: album.items) } }) { HStack(spacing: 4) { Image(systemName: "shuffle"); Text("Shuffle") }.font(.system(size: 10, weight: .bold)).foregroundColor(.pink) }
                    Spacer()
                    Button(action: { if !isReflection { if let current = audioManager.currentSong, album.items.contains(current) { audioManager.togglePlayPause() } else { audioManager.play(song: album.items.first!, queue: album.items) } } }) { Image(systemName: (audioManager.isPlaying && (album.items.contains(audioManager.currentSong ?? album.items[0]))) ? "pause.fill" : "play.fill").font(.system(size: 14, weight: .bold)).foregroundColor(.pink) }
                }.padding(.horizontal, 12).frame(height: 36).background(Material.ultraThin)
                GeometryReader { geo in
                    let content = LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(album.items, id: \.persistentID) { song in
                            let isPlaying = audioManager.currentSong?.persistentID == song.persistentID
                            HStack(spacing: 8) { if isPlaying { Image(systemName: "speaker.wave.2.fill").font(.system(size: 10, weight: .bold)).foregroundColor(.pink).frame(width: 22, alignment: .trailing) } else { Text("\(song.albumTrackNumber)").font(.system(size: 11, weight: .bold)).monospacedDigit().foregroundColor(.white.opacity(0.7)).frame(width: 22, alignment: .trailing) }; Text(song.title ?? "Untitled").font(.system(size: 13, weight: isPlaying ? .bold : .medium)).foregroundColor(isPlaying ? .pink : .white).lineLimit(1).multilineTextAlignment(.leading); Spacer() }.padding(.vertical, 12).padding(.horizontal, 4).background(Color.clear).contentShape(Rectangle()).onTapGesture { if !isReflection { audioManager.play(song: song, queue: album.items) } }; Divider().background(Color.white.opacity(0.3))
                        }; Color.clear.frame(height: 40).contentShape(Rectangle()).onTapGesture { onBackgroundTap?() }
                    }
                    if isReflection { content.offset(y: -externalScrollOffset) } else { ScrollView(showsIndicators: true) { content.background(GeometryReader { innerGeo in Color.clear.preference(key: ScrollOffsetKey.self, value: innerGeo.frame(in: .named("scroll")).minY) }) }.coordinateSpace(name: "scroll").onPreferenceChange(ScrollOffsetKey.self) { value in self.externalScrollOffset = -value }.onTapGesture { onBackgroundTap?() } }
                }
            }
        }.frame(width: size, height: size).cornerRadius(8).clipped()
    }
}

struct AlbumSettingsSheet: View {
    let albumID: String
    var artworkImage: UIImage?
    @ObservedObject var library = LibraryManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var isEdgeToEdge: Bool = true
    @State private var showTitle: Bool = true
    @State private var showArtistOnSongs: Bool = true
    @State private var albumTextColor: Color = .primary
    @State private var songTextColor: Color = .primary
    @State private var showColorEditor = false
    @State private var showDescriptionEditor = false
    @State private var showArtEditor = false
    @State private var selectedVideoItem: PhotosPickerItem? = nil
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Layout")) {
                    Toggle("Edge-to-Edge Artwork", isOn: $isEdgeToEdge)
                        .onChange(of: isEdgeToEdge) { newValue in
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            library.setEdgeToEdge(id: albumID, isEnabled: newValue)
                        }
                    
                    if isEdgeToEdge {
                        Button { showArtEditor = true } label: {
                            Label("Crop Edge-to-Edge Artwork", systemImage: "crop")
                                .foregroundColor(.pink)
                        }
                    }
                    
                    Toggle("Show Album Title", isOn: $showTitle)
                        .onChange(of: showTitle) { newValue in
                            library.setShowTitle(id: albumID, show: newValue)
                        }
                    
                    Toggle("Show Artist Name on Songs", isOn: $showArtistOnSongs)
                        .onChange(of: showArtistOnSongs) { newValue in
                            library.setShowArtist(id: albumID, show: newValue)
                        }
                }
                
                // Inside your Form, add a new Section:
                Section(header: Text("Animated Art")) {
                    PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                        Label("Select Video Background", systemImage: "video.badge.plus")
                            .foregroundColor(.pink)
                    }
                    
                    if library.albumVideoArt[albumID] != nil {
                        Button(role: .destructive) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            library.setAlbumVideo(id: albumID, url: nil)
                        } label: {
                            Label("Remove Video Art", systemImage: "trash")
                        }
                    }
                }
                .onChange(of: selectedVideoItem) { newItem in
                    Task {
                        // Load the video file from the photo library
                        if let video = try? await newItem?.loadTransferable(type: VideoTransferable.self) {
                            DispatchQueue.main.async {
                                library.setAlbumVideo(id: albumID, url: video.url)
                            }
                        }
                    }
                }
                
                Section(header: Text("Typography & Colors")) {
                    ColorPicker("Album Text Color", selection: $albumTextColor)
                        .onChange(of: albumTextColor) { newValue in
                            library.setAlbumTextColor(id: albumID, hex: newValue.toHex())
                        }
                    
                    ColorPicker("Song Text Color", selection: $songTextColor)
                        .onChange(of: songTextColor) { newValue in
                            library.setSongTextColor(id: albumID, hex: newValue.toHex())
                        }
                    
                    // NEW: Restore Button
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        
                        // Clear the overrides
                        library.setAlbumTextColor(id: albumID, hex: nil)
                        library.setSongTextColor(id: albumID, hex: nil)
                        
                        // Update the local state so the UI ColorPickers reset immediately
                        if let hex = library.customAlbumColors[albumID] {
                            let bgColor = Color(hex: hex)
                            albumTextColor = bgColor.adaptivePrimary
                            songTextColor = bgColor.adaptiveSecondary
                        } else {
                            albumTextColor = .primary
                            songTextColor = .primary
                        }
                    }) {
                        Text("Restore Smart Text Coloring")
                            .foregroundColor(.pink)
                    }
                    
                    Button { showColorEditor = true } label: {
                        Label("Set Background Color", systemImage: "paintpalette")
                            .foregroundColor(.primary)
                    }
                    
                    Button { showDescriptionEditor = true } label: {
                        Label("Edit Description", systemImage: "text.quote")
                            .foregroundColor(.primary)
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        library.setShowTitle(id: albumID, show: true)
                        library.setShowArtist(id: albumID, show: true)
                        library.setAlbumTextColor(id: albumID, hex: nil)
                        library.setSongTextColor(id: albumID, hex: nil)
                        library.setAlbumVideo(id: albumID, url: nil)
                        dismiss()
                    } label: {
                        Text("Reset Defaults")
                    }
                }
            }
            .navigationTitle("Album Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.bold().foregroundColor(.pink)
                }
            }
            .onAppear {
                isEdgeToEdge = library.albumEdgeToEdgePrefs[albumID] ?? true
                showTitle = library.albumShowTitlePrefs[albumID] ?? true
                showArtistOnSongs = library.albumShowArtistPrefs[albumID] ?? true
                
                if let hex = library.albumTextColorPrefs[albumID] {
                    albumTextColor = Color(hex: hex)
                }
                if let hex = library.songTextColorPrefs[albumID] {
                    songTextColor = Color(hex: hex)
                }
            }
            .sheet(isPresented: $showColorEditor) { AlbumColorEditorSheet(albumID: albumID) }
            .sheet(isPresented: $showDescriptionEditor) { AlbumDescriptionEditorSheet(albumID: albumID) }
            .sheet(isPresented: $showArtEditor) {
                AlbumArtEditorSheet(albumID: albumID, artworkImage: artworkImage)
            }
        }
    }
}

struct ScrollOffsetKey: PreferenceKey { static var defaultValue: CGFloat = 0; static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() } }

struct ReflectionOverlay: View {
    let album: MPMediaItemCollection; let size: CGFloat
    var body: some View { Group { if let artwork = album.representativeItem?.artwork?.image(at: CGSize(width: 400, height: 400)) { Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fill) } else { Color.gray } }.frame(width: size, height: size).scaleEffect(y: -1).mask(LinearGradient(gradient: Gradient(colors: [.white.opacity(0.35), .clear]), startPoint: .top, endPoint: .bottom)).cornerRadius(8).clipped() }
}

struct ArtworkView: View {
    let song: MPMediaItem
    var body: some View {
        if let artwork = song.artwork?.image(at: CGSize(width: 400, height: 400)) { Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fit).cornerRadius(20).shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10) } else { Rectangle().fill(Color.gray.opacity(0.3)).aspectRatio(1.0, contentMode: .fit).cornerRadius(20) }
    }
}

// MARK: - Video Transfer Helper
struct VideoTransferable: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = URL.documentsDirectory.appending(path: received.file.lastPathComponent)
            if FileManager.default.fileExists(atPath: copy.path) {
                try FileManager.default.removeItem(at: copy)
            }
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self.init(url: copy)
        }
    }
}

// MARK: - iOS Song Info Sheet
struct SongInfoSheet: View {
    var appleSong: MPMediaItem?
    var localSong: LocalSong?
    var remoteSong: RemoteSongDTO?
    
    @Environment(\.dismiss) var dismiss
    
    var title: String { appleSong?.title ?? localSong?.title ?? remoteSong?.title ?? "Unknown Title" }
    var artist: String { appleSong?.artist ?? localSong?.artist ?? remoteSong?.artist ?? "Unknown Artist" }
    var album: String { appleSong?.albumTitle ?? localSong?.album ?? remoteSong?.album ?? "Unknown Album" }
    var genre: String { appleSong?.genre ?? localSong?.genre ?? remoteSong?.genre ?? "Unknown Genre" }
    var track: Int { appleSong?.albumTrackNumber ?? localSong?.trackNumber ?? remoteSong?.trackNumber ?? 0 }
    var disc: Int { appleSong?.discNumber ?? localSong?.discNumber ?? remoteSong?.discNumber ?? 0 }
    var duration: TimeInterval { appleSong?.playbackDuration ?? localSong?.duration ?? remoteSong?.duration ?? 0 }
    
    var lyrics: String? { appleSong?.lyrics ?? localSong?.lyrics ?? (remoteSong != nil ? LibraryManager.shared.customRawLyrics[remoteSong!.id] : nil) }
    
    var artwork: UIImage? {
        if let local = localSong, let data = local.artworkData { return UIImage(data: data) }
        if let remote = remoteSong, let data = remote.artworkData { return UIImage(data: data) }
        return appleSong?.artwork?.image(at: CGSize(width: 300, height: 300))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top, spacing: 20) {
                        if let img = artwork {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 120, height: 120)
                                .cornerRadius(12)
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 120, height: 120)
                                .cornerRadius(12)
                                .overlay(Image(systemName: "music.note").font(.largeTitle).foregroundColor(.gray))
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            InfoRow(title: "Title", value: title)
                            InfoRow(title: "Artist", value: artist)
                            InfoRow(title: "Album", value: album)
                            InfoRow(title: "Genre", value: genre)
                        }
                    }
                    .padding(.horizontal)
                    
                    HStack(spacing: 40) {
                        if track > 0 { InfoRow(title: "Track", value: "\(track)") }
                        if disc > 0 { InfoRow(title: "Disc", value: "\(disc)") }
                        InfoRow(title: "Duration", value: formatTime(duration))
                    }
                    .padding(.horizontal)
                    
                    Divider().padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Lyrics")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if let rawText = lyrics, !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(rawText)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        } else {
                            Text("No lyrics available.")
                                .italic()
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Song Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.bold()
                }
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN && !time.isInfinite else { return "0:00" }
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
            Text(value).font(.subheadline).bold()
        }
    }
}

struct MarqueeText: View {
    let text: String; let font: Font; @State private var offset: CGFloat = 0; @State private var textWidth: CGFloat = 0; @State private var isDragging = false; @State private var dragStartOffset: CGFloat = 0
    let timer = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect(); let speed: CGFloat = 0.5; let spacing: CGFloat = 40
    var body: some View {
        GeometryReader { geometry in
            let visibleWidth = geometry.size.width
            ZStack(alignment: .leading) {
                Text(text).font(font).fontWeight(.bold).fixedSize().background(GeometryReader { p in Color.clear.onAppear { textWidth = p.size.width } }).hidden()
                if textWidth > visibleWidth { HStack(spacing: spacing) { Text(text).font(font).fontWeight(.bold).foregroundColor(.white).fixedSize(); Text(text).font(font).fontWeight(.bold).foregroundColor(.white).fixedSize(); Text(text).font(font).fontWeight(.bold).foregroundColor(.white).fixedSize() }.offset(x: offset).gesture(DragGesture().onChanged { value in if !isDragging { isDragging = true; dragStartOffset = offset }; offset = dragStartOffset + value.translation.width }.onEnded { _ in isDragging = false }) } else { Text(text).font(font).fontWeight(.bold).foregroundColor(.white).frame(width: visibleWidth, alignment: .center) }
            }.onReceive(timer) { _ in guard !isDragging, textWidth > visibleWidth else { return }; offset -= speed; if offset <= -(textWidth + spacing) { offset += (textWidth + spacing) } }.onChange(of: text, perform: { _ in offset = 0 })
        }.clipped()
    }
}

struct AirPlayView: UIViewRepresentable { func makeUIView(context: Context) -> AVRoutePickerView { let r = AVRoutePickerView(); r.backgroundColor = .clear; r.activeTintColor = .systemPink; r.tintColor = .white; r.prioritizesVideoDevices = true; return r }; func updateUIView(_ uiView: AVRoutePickerView, context: Context) {} }

// MARK: - TV Display Views
struct TVDisplayView: View {
    @ObservedObject var audioManager: AudioManager; @ObservedObject var library: LibraryManager; @ObservedObject var uiState: PlayerUIState; @ObservedObject var settings: AppSettings
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Group { if let artwork = audioManager.displayArtwork(size: CGSize(width: 800, height: 800)) { Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fill).blur(radius: 80).overlay(Color.black.opacity(0.6)) } else { Color.black } }.frame(width: geo.size.width, height: geo.size.height).clipped()
                let hasSong = audioManager.currentSong != nil || audioManager.currentLocalSong != nil || audioManager.currentRemoteDTO != nil
                if hasSong {
                    if uiState.showLyrics {
                        HStack(spacing: 60) {
                            VStack { Spacer(); if let artwork = audioManager.displayArtwork(size: CGSize(width: 800, height: 800)) { Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fit).cornerRadius(24).shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 15) }; VStack(alignment: .leading, spacing: 12) { Text(audioManager.displayTitle).font(.system(size: 46, weight: .bold)).foregroundColor(.white).lineLimit(2); Text(audioManager.displayArtist).font(.system(size: 32, weight: .medium)).foregroundColor(.white.opacity(0.7)).lineLimit(1) }.padding(.top, 30).frame(maxWidth: .infinity, alignment: .leading); Spacer() }.frame(width: geo.size.width * 0.35)
                            TVLyricsView(song: audioManager.currentSong, audioManager: audioManager, library: library, uiState: uiState, settings: settings).frame(width: geo.size.width * 0.5)
                        }.padding(80)
                    } else {
                        VStack(spacing: 40) { if let artwork = audioManager.displayArtwork(size: CGSize(width: 800, height: 800)) { Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fit).frame(height: geo.size.height * 0.55).cornerRadius(32).shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 20) }; VStack(spacing: 16) { Text(audioManager.displayTitle).font(.system(size: 86, weight: .bold)).foregroundColor(.white).multilineTextAlignment(.center).lineLimit(2); Text(audioManager.displayArtist).font(.system(size: 56, weight: .medium)).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center).lineLimit(1) } }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else { Image(systemName: "music.note").font(.system(size: 150)).foregroundColor(.white.opacity(0.2)) }
            }
        }.ignoresSafeArea()
    }
}

struct TVLyricsView: View {
    let song: MPMediaItem?
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var library: LibraryManager
    @ObservedObject var uiState: PlayerUIState
    @ObservedObject var settings: AppSettings
    
    @State private var rawLines: [String] = []
    @State private var playbackLineIndex: Int = -1
    @State private var playbackGapIndex: Int = -1
    
    var processedLyrics: [SyncedLyricLine]? {
        let lines: [SyncedLyricLine]?
        if let local = audioManager.currentLocalSong {
            lines = local.syncedLyrics ?? library.getSyncedLyrics(id: local.id, title: local.title, artist: local.artist)
        } else if let remote = audioManager.currentRemoteDTO {
            lines = library.getSyncedLyrics(id: remote.id, title: remote.title, artist: remote.artist)
        } else if let s = song {
            lines = library.getSyncedLyrics(id: String(s.persistentID), title: s.title ?? "", artist: s.artist ?? "")
        } else {
            lines = nil
        }
        guard let validLines = lines else { return nil }
        
        var merged: [SyncedLyricLine] = []
        for line in validLines {
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
            let mainFontSize: CGFloat = 64
            
            ZStack {
                if let lines = processedLyrics {
                    ScrollViewReader { scrollProxy in
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 24) {
                                if !lines.isEmpty {
                                    ForEach(0...lines.count, id: \.self) { i in
                                        GapCapsule(isGap: playbackGapIndex == i, color: settings.lyricColorName.color, gapIndex: i, width: 120, height: 12, padding: 16)
                                        
                                        if i < lines.count {
                                            let lineData = lines[i]
                                            let isCurrentLine = (i == playbackLineIndex)
                                            let isPast = (i < playbackLineIndex)
                                            
                                            LyricLineView(lineData: lineData, isCurrentLine: isCurrentLine, isPast: isPast, isPlaying: audioManager.isPlaying, mainFontSize: mainFontSize, audioManager: audioManager, settings: settings)
                                                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 20)), removal: .opacity.combined(with: .scale(scale: 0.85)).combined(with: .offset(y: -40))))
                                                .id(i)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 40)
                            .padding(.top, geo.size.height * 0.4)
                            .padding(.bottom, geo.size.height * 0.5)
                        }
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0.0), .init(color: .black, location: 0.15), .init(color: .black, location: 0.85), .init(color: .clear, location: 1.0)], startPoint: .top, endPoint: .bottom))
                        .onChange(of: song?.persistentID) { _ in playbackLineIndex = -1; playbackGapIndex = -1 }
                        .onChange(of: audioManager.currentLocalSong?.id) { _ in playbackLineIndex = -1; playbackGapIndex = -1 }
                        .onChange(of: audioManager.currentRemoteDTO?.id) { _ in playbackLineIndex = -1; playbackGapIndex = -1 }
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                if playbackLineIndex >= 0 { scrollProxy.scrollTo(playbackLineIndex, anchor: UnitPoint(x: 0.5, y: 0.4)) }
                                else if playbackGapIndex >= 0 { scrollProxy.scrollTo("gap_\(playbackGapIndex)", anchor: UnitPoint(x: 0.5, y: 0.4)) }
                            }
                        }
                        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
                            let time = audioManager.currentTime + 0.4
                            var activeL = -1
                            var gapL = -1
                            
                            if lines.isEmpty { return }
                            
                            if time < lines[0].startTime {
                                gapL = 0
                            } else {
                                var lastPassedIndex = -1
                                for (index, line) in lines.enumerated() {
                                    if line.isUnsynced == true { continue }
                                    if time >= line.startTime { lastPassedIndex = index }
                                    else { break }
                                }
                                
                                if lastPassedIndex != -1 {
                                    let activeLine = lines[lastPassedIndex]
                                    if let end = activeLine.endTime, time > end { gapL = lastPassedIndex + 1 }
                                    else { activeL = lastPassedIndex }
                                }
                            }
                            
                            if activeL != playbackLineIndex || gapL != playbackGapIndex {
                                let isFirstSync = (playbackLineIndex == -1 && playbackGapIndex == -1)
                                playbackLineIndex = activeL
                                playbackGapIndex = gapL
                                
                                if isFirstSync {
                                    if activeL >= 0 { scrollProxy.scrollTo(activeL, anchor: UnitPoint(x: 0.5, y: 0.4)) }
                                    else if gapL >= 0 { scrollProxy.scrollTo("gap_\(gapL)", anchor: UnitPoint(x: 0.5, y: 0.4)) }
                                } else {
                                    withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                                        if activeL >= 0 { scrollProxy.scrollTo(activeL, anchor: UnitPoint(x: 0.5, y: 0.4)) }
                                        else if gapL >= 0 { scrollProxy.scrollTo("gap_\(gapL)", anchor: UnitPoint(x: 0.5, y: 0.4)) }
                                    }
                                }
                            }
                        }
                    }
                } else if !rawLines.isEmpty {
                    ScrollView(showsIndicators: false) {
                        ScrollViewReader { rawScrollProxy in
                            VStack(spacing: 16) {
                                Color.clear.frame(height: 0).id("TOP")
                                ForEach(rawLines, id: \.self) { line in Text(line).font(.system(size: 70)).foregroundColor(.white.opacity(0.6)).multilineTextAlignment(.center) }
                            }
                            .padding(.top, geo.size.height * 0.1)
                            .padding(.horizontal, 40)
                            .onChange(of: song?.persistentID) { _ in rawScrollProxy.scrollTo("TOP", anchor: .top) }
                            .onChange(of: audioManager.currentLocalSong?.id) { _ in rawScrollProxy.scrollTo("TOP", anchor: .top) }
                        }
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "music.mic").font(.system(size: 100)).foregroundColor(.white.opacity(0.5))
                        Text("No lyrics available.").font(.system(size: 60)).foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .onAppear { loadLyrics() }
            .onChange(of: song?.persistentID) { _ in loadLyrics() }
            .onChange(of: audioManager.currentLocalSong?.id) { _ in loadLyrics() }
            .onChange(of: audioManager.currentRemoteDTO?.id) { _ in loadLyrics() }
        }
    }
    
    func loadLyrics() {
        let rawText = audioManager.currentLocalSong?.lyrics ?? (audioManager.currentRemoteDTO != nil ? library.customRawLyrics[audioManager.currentRemoteDTO!.id] : nil) ?? song?.lyrics
        if let raw = rawText, !raw.isEmpty {
            self.rawLines = raw.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } else {
            self.rawLines = []
        }
    }
}

struct SyncedLyricsStorageView: View {
    @ObservedObject var library = LibraryManager.shared
    var totalStorageString: String { guard let data = try? JSONEncoder().encode(library.syncedLyrics) else { return "0 KB" }; let formatter = ByteCountFormatter(); formatter.allowedUnits = [.useKB, .useMB]; formatter.countStyle = .file; return formatter.string(fromByteCount: Int64(data.count)) }
    var sortedKeys: [String] { library.syncedLyrics.keys.sorted { let date1 = library.syncedLyrics[$0]?.lastModified ?? Date.distantPast; let date2 = library.syncedLyrics[$1]?.lastModified ?? Date.distantPast; return date1 > date2 } }
    var body: some View {
        List {
            Section(header: Text("Storage Info")) { HStack { Text("Total Space Used"); Spacer(); Text(totalStorageString).foregroundColor(.secondary) } }
            Section(header: Text("Synced Songs (\(library.syncedLyrics.count))")) {
                if library.syncedLyrics.isEmpty { Text("No synced lyrics found.").foregroundColor(.secondary) } else {
                    ForEach(sortedKeys, id: \.self) { key in if let doc = library.syncedLyrics[key] { VStack(alignment: .leading, spacing: 4) { Text(doc.songTitle).font(.headline); Text(doc.artistName).font(.subheadline).foregroundColor(.secondary); Text("Last synced: \(doc.lastModified, style: .date)").font(.caption).foregroundColor(.gray) }.padding(.vertical, 4) } }.onDelete(perform: deleteLyrics)
                }
            }
        }.navigationTitle("Synced Lyrics")
    }
    private func deleteLyrics(at offsets: IndexSet) { for index in offsets { let key = sortedKeys[index]; library.syncedLyrics.removeValue(forKey: key) }; if let encoded = try? JSONEncoder().encode(library.syncedLyrics) { UserDefaults.standard.set(encoded, forKey: "SyncedLyricsPersistenceKey") }; MultipeerManager.shared.syncLyricsDatabase(documents: library.syncedLyrics) }
}

// MARK: - Word Synced Lyrics Storage View
struct WordSyncedLyricsStorageView: View {
    @ObservedObject var library = LibraryManager.shared
    
    var sortedWordSyncKeys: [String] {
        library.syncedLyrics.keys.filter { key in
            guard let doc = library.syncedLyrics[key] else { return false }
            guard let lines = library.getSyncedLyrics(id: key, title: doc.songTitle, artist: doc.artistName) else { return false }
            return lines.contains { $0.wordTimings != nil && !$0.wordTimings!.isEmpty }
        }.sorted {
            let date1 = library.syncedLyrics[$0]?.lastModified ?? Date.distantPast
            let date2 = library.syncedLyrics[$1]?.lastModified ?? Date.distantPast
            return date1 > date2
        }
    }
    
    var body: some View {
        List {
            Section(header: Text("Word Synced Songs (\(sortedWordSyncKeys.count))"), footer: Text("Swiping to delete here will ONLY remove the word-level timings, keeping your standard line sync intact.")) {
                if sortedWordSyncKeys.isEmpty {
                    Text("No word-synced lyrics found.").foregroundColor(.secondary)
                } else {
                    ForEach(sortedWordSyncKeys, id: \.self) { key in
                        if let doc = library.syncedLyrics[key] {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(doc.songTitle).font(.headline)
                                Text(doc.artistName).font(.subheadline).foregroundColor(.secondary)
                                Text("Word Sync Active").font(.caption).foregroundColor(.pink)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: stripWordSync)
                }
            }
        }
        .navigationTitle("Word Sync Data")
    }
    
    private func stripWordSync(at offsets: IndexSet) {
        for index in offsets {
            let key = sortedWordSyncKeys[index]
            if let doc = library.syncedLyrics[key],
               let lines = library.getSyncedLyrics(id: key, title: doc.songTitle, artist: doc.artistName) {
                
                let strippedLines = lines.map { line -> SyncedLyricLine in
                    var cleanLine = line
                    cleanLine.wordTimings = []
                    return cleanLine
                }
                library.saveSyncedLyrics(id: key, title: doc.songTitle, artist: doc.artistName, lines: strippedLines)
            }
        }
    }
}

// MARK: - Local Music Storage View
struct AlbumStorageItem: Identifiable {
    let id = UUID()
    let name: String
    let size: Int64
    let formattedSize: String
    let songCount: Int
}

struct DownloadsStorageView: View {
    @ObservedObject var downloads = DownloadsManager.shared
    @State private var freeSpace: String = "Calculating..."
    
    var albumStorageItems: [AlbumStorageItem] {
        let grouped = Dictionary(grouping: downloads.downloadedSongs, by: { $0.album })
        var items: [AlbumStorageItem] = []
        
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        
        for (albumName, songs) in grouped {
            var totalSize: Int64 = 0
            for song in songs {
                if let attr = try? FileManager.default.attributesOfItem(atPath: song.url.path),
                   let size = attr[.size] as? Int64 {
                    totalSize += size
                }
            }
            items.append(AlbumStorageItem(
                name: albumName,
                size: totalSize,
                formattedSize: formatter.string(fromByteCount: totalSize),
                songCount: songs.count
            ))
        }
        return items.sorted { $0.size > $1.size }
    }
    
    var totalUsedSpace: String {
        let total = albumStorageItems.reduce(0) { $0 + $1.size }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: total)
    }
    
    var body: some View {
        List {
            Section(header: Text("Device Storage")) {
                HStack { Text("Free Space"); Spacer(); Text(freeSpace).foregroundColor(.secondary) }
                HStack { Text("Music Downloads"); Spacer(); Text(totalUsedSpace).foregroundColor(.secondary) }
            }
            
            Section(header: Text("Downloaded Albums (\(albumStorageItems.count))"), footer: Text("Swipe left to delete an album from your device.")) {
                if albumStorageItems.isEmpty {
                    Text("No downloaded music found.").foregroundColor(.secondary)
                } else {
                    ForEach(albumStorageItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.headline)
                            HStack {
                                Text("\(item.songCount) Songs").font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Text(item.formattedSize).font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: deleteAlbums)
                }
            }
        }
        .navigationTitle("Downloaded Music")
        .onAppear { calculateFreeSpace() }
    }
    
    private func deleteAlbums(at offsets: IndexSet) {
        let items = albumStorageItems
        for index in offsets {
            let albumName = items[index].name
            DownloadsManager.shared.deleteAlbum(albumName: albumName)
        }
    }
    
    private func calculateFreeSpace() {
        do {
            let fileURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useGB, .useMB]
                formatter.countStyle = .file
                freeSpace = formatter.string(fromByteCount: capacity)
            } else { freeSpace = "Unknown" }
        } catch { freeSpace = "Unknown" }
    }
}

// MARK: - Artwork Data Storage View
struct ArtworkDataStorageItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let type: String
    let size: Int64
    let formattedSize: String
}

struct ArtworkDataStorageView: View {
    @State private var items: [ArtworkDataStorageItem] = []
    
    var videoItems: [ArtworkDataStorageItem] { items.filter { $0.type == "Video" } }
    var imageItems: [ArtworkDataStorageItem] { items.filter { $0.type == "Image" } }
    
    var totalVideoSize: Int64 { videoItems.reduce(0) { $0 + $1.size } }
    var totalImageSize: Int64 { imageItems.reduce(0) { $0 + $1.size } }
    
    var formattedVideoSize: String { format(totalVideoSize) }
    var formattedImageSize: String { format(totalImageSize) }
    
    func format(_ size: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: size)
    }
    
    var body: some View {
        List {
            Section(header: Text("Storage Overview")) {
                HStack { Text("Video Artwork"); Spacer(); Text(formattedVideoSize).foregroundColor(.secondary) }
                HStack { Text("Image Artwork"); Spacer(); Text(formattedImageSize).foregroundColor(.secondary) }
            }
            
            Section(header: Text("Artwork Files (\(items.count))"), footer: Text("Swipe left to delete an artwork file from your device.")) {
                if items.isEmpty {
                    Text("No artwork found.").foregroundColor(.secondary)
                } else {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.headline).lineLimit(1)
                            HStack {
                                Text(item.type).font(.caption).foregroundColor(item.type == "Video" ? .blue : .green)
                                Spacer()
                                Text(item.formattedSize).font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: deleteItems)
                }
            }
        }
        .navigationTitle("Artwork Data")
        .onAppear { loadItems() }
    }
    
    func deleteItems(at offsets: IndexSet) {
        for i in offsets {
            let item = items[i]
            try? FileManager.default.removeItem(at: item.url)
            
            // Remove from LibraryManager video art dictionary if it exists
            if item.type == "Video" {
                if let key = LibraryManager.shared.albumVideoArt.first(where: { $0.value.lastPathComponent == item.url.lastPathComponent })?.key {
                    LibraryManager.shared.setAlbumVideo(id: key, url: nil)
                }
            }
        }
        loadItems()
    }
    
    func loadItems() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        
        var newItems: [ArtworkDataStorageItem] = []
        for file in files {
            let ext = file.pathExtension.lowercased()
            let isVideo = ["mp4", "mov", "m4v"].contains(ext)
            let isImage = ["jpg", "jpeg", "png", "heic"].contains(ext)
            
            if isVideo || isImage {
                let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
                let size = attrs?[.size] as? Int64 ?? 0
                newItems.append(ArtworkDataStorageItem(
                    url: file,
                    name: file.lastPathComponent,
                    type: isVideo ? "Video" : "Image",
                    size: size,
                    formattedSize: format(size)
                ))
            }
        }
        self.items = newItems.sorted { $0.size > $1.size }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) var dismiss
    private var decimalFormatter: NumberFormatter { let f = NumberFormatter(); f.numberStyle = .decimal; return f }
    @AppStorage("useSmartTextColoring") private var useSmartTextColoring: Bool = true
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Data & Storage")) {
                    NavigationLink("Manage Synced Lyrics") { SyncedLyricsStorageView() }
                    NavigationLink("Manage Word Sync Data") { WordSyncedLyricsStorageView() }
                    NavigationLink("Manage Downloaded Music") { DownloadsStorageView() }
                    NavigationLink("Manage Artwork Data") { ArtworkDataStorageView() }
                }
                
                Section(header: Text("Landscape")) { Picker("Mode", selection: $settings.landscapeMode) { ForEach(AppSettings.LandscapeMode.allCases) { Text($0.rawValue).tag($0) } } }
                
                Section(header: Text("Appearance")) {
                    Toggle("Show Mac Tab", isOn: $settings.showMacTab);
                    Toggle("Show Song Artwork", isOn: $settings.showListArtwork);
                    Picker("Lyric Highlight Color", selection: $settings.lyricColorName) { ForEach(AppSettings.LyricColorName.allCases) { color in Text(color.rawValue).tag(color) } }
                    Toggle("Smart Text Coloring", isOn: $useSmartTextColoring)
                        // Only show the restore button if the user has changed the default setting
                        if !useSmartTextColoring {
                            Button(action: {
                                withAnimation {
                                    useSmartTextColoring = true
                                }
                            }) {
                                Text("Restore Smart Text Coloring")
                                    .foregroundColor(.accentColor)
                            }
                        }
                }
                
                Section(header: Text("Playback Timing"), footer: Text("Automatically skip long intros or fade-outs.")) {
                    TimingTextField(title: "Start Song At", value: $settings.globalStartOffset)
                    TimingTextField(title: "End Song Early By", value: $settings.globalEndOffset)
                }
                
                Section(header: Text("Sync Editor")) {
                    Toggle("Countdown on Rewind", isOn: $settings.rewindCountdown)
                }
                
            }.navigationTitle("Settings").toolbar { Button("Done") { dismiss() } }
        }
    }
}

struct InlineLyricsView: View {
    let song: MPMediaItem?
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var library: LibraryManager
    @ObservedObject var uiState: PlayerUIState
    @ObservedObject var settings: AppSettings
    @Binding var showRawLyricsEditor: Bool
    @Binding var showSyncSheet: Bool
    var showFullScreenButton: Bool = true
    var dragOffset: Binding<CGSize>? = nil
    
    @State private var rawLines: [String] = []
    @State private var playbackLineIndex: Int = -1
    @State private var playbackGapIndex: Int = -1
    @State private var isUserScrolling = false
    @State private var currentScrollOffset: CGFloat = 0
    @State private var dragStartedAtTop = false
    @State private var dragSessionActive = false
    @State private var showWordSyncSheet = false
    @State private var lockedAppleSong: MPMediaItem? = nil
    @State private var lockedLocalSong: LocalSong? = nil
    @State private var lockedRemoteSong: RemoteSongDTO? = nil
    
    var activeRawLyrics: String? {
        let id = audioManager.currentLocalSong?.id ?? audioManager.currentRemoteDTO?.id ?? String(song?.persistentID ?? 0)
        if let custom = library.customRawLyrics[id], !custom.isEmpty { return custom }
        return audioManager.currentLocalSong?.lyrics ?? song?.lyrics
    }
    
    var processedLyrics: [SyncedLyricLine]? {
        let lines: [SyncedLyricLine]?
        if let local = audioManager.currentLocalSong {
            lines = local.syncedLyrics ?? library.getSyncedLyrics(id: local.id, title: local.title, artist: local.artist)
        } else if let remote = audioManager.currentRemoteDTO {
            lines = library.getSyncedLyrics(id: remote.id, title: remote.title, artist: remote.artist)
        } else if let s = song {
            lines = library.getSyncedLyrics(id: String(s.persistentID), title: s.title ?? "", artist: s.artist ?? "")
        } else {
            lines = nil
        }
        guard let validLines = lines else { return nil }
        var merged: [SyncedLyricLine] = []
        for line in validLines { if line.text == "[Instrumental]" { if !merged.isEmpty, merged.last?.text == "[Instrumental]" { if let newEnd = line.endTime { merged[merged.count - 1].endTime = newEnd }; continue } }; merged.append(line) }
        return merged
    }
    
    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let mainFontSize: CGFloat = isLandscape ? (uiState.isLyricsFullScreen ? 68 : 40) : (uiState.isLyricsFullScreen ? 44 : 34)
            
            // Expanded internal horizontal padding: Now set to 0 when in landscape compact mode
            let horizontalPadding: CGFloat = isLandscape ? (uiState.isLyricsFullScreen ? max(geo.safeAreaInsets.leading, geo.safeAreaInsets.trailing) + 40 : -50) : 20
            let scrollAnchor: UnitPoint = isLandscape
                ? (uiState.isLyricsFullScreen ? UnitPoint(x: 0.5, y: 0.1) : UnitPoint(x: 0.5, y: 0.25)) // Landscape: [Full Screen] vs [Compact]
                : (uiState.isLyricsFullScreen ? UnitPoint(x: 0.5, y: 0.30) : UnitPoint(x: 0.5, y: 0.35)) // Portrait: [Full Screen] vs [Compact]
            
            let halfHeight = geo.size.height * 0.5
            let topPadding = halfHeight
            let bottomPadding = halfHeight
            
            ZStack {
                if let lines = processedLyrics {
                    ScrollViewReader { scrollProxy in
                        ZStack(alignment: .top) {
                            ScrollView(showsIndicators: false) {
                                VStack(spacing: 0) {
                                    if !lines.isEmpty {
                                        ForEach(0...lines.count, id: \.self) { i in
                                            lyricRow(for: i, lines: lines, mainFontSize: mainFontSize)
                                        }                                    }
                                }
                                .padding(.leading, (isLandscape && !uiState.isLyricsFullScreen) ? 90 : 0)
                                .padding(.trailing, (isLandscape && !uiState.isLyricsFullScreen) ? 70 : 0)
                                .padding(.horizontal, horizontalPadding)
                                .padding(.top, topPadding)
                                .padding(.bottom, bottomPadding)
                                .background(GeometryReader { innerGeo in Color.clear.preference(key: ScrollOffsetKey.self, value: innerGeo.frame(in: .named("lyricsScroll")).minY) })
                            }
                            .coordinateSpace(name: "lyricsScroll")
                            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                                currentScrollOffset = offset; let baseTop = topPadding
                                if offset > baseTop {
                                    let overscroll = offset - baseTop
                                    if dragStartedAtTop && dragSessionActive {
                                        let estimatedFingerTranslation = overscroll * 2.8; dragOffset?.wrappedValue = CGSize(width: 0, height: estimatedFingerTranslation)
                                        if estimatedFingerTranslation > 100 { withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { uiState.isPlayerExpanded = false } }
                                    }
                                } else { dragOffset?.wrappedValue = .zero }
                            }
                            .offset(y: (dragStartedAtTop && (dragOffset?.wrappedValue.height ?? 0) > 0) ? -max(0, currentScrollOffset - topPadding) : 0)
                            .ignoresSafeArea(.all, edges: .vertical)
                            // Re-center perfectly on toggle
                            .onChange(of: uiState.isLyricsFullScreen) { isNowFullScreen in
                                let targetAnchor: UnitPoint = isLandscape
                                    ? (isNowFullScreen ? UnitPoint(x: 0.5, y: 0.5) : UnitPoint(x: 0.5, y: 0.3))
                                    : (isNowFullScreen ? UnitPoint(x: 0.5, y: 0.45) : UnitPoint(x: 0.5, y: 0.45))
                                
                                // 1. Initial push to get it moving in the general direction while the UI resizes
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                                    if playbackLineIndex >= 0 { scrollProxy.scrollTo(playbackLineIndex, anchor: targetAnchor) }
                                    else if playbackGapIndex >= 0 { scrollProxy.scrollTo("gap_\(playbackGapIndex)", anchor: targetAnchor) }
                                }
                                
                                // 2. The spring animation above takes ~0.6 seconds to finish.
                                // We MUST wait slightly longer (0.65s) so the font sizes and frames are 100% settled.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                                    // 3. Fire a final, fast correction snap. The proxy math will now be perfect.
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        if playbackLineIndex >= 0 { scrollProxy.scrollTo(playbackLineIndex, anchor: targetAnchor) }
                                        else if playbackGapIndex >= 0 { scrollProxy.scrollTo("gap_\(playbackGapIndex)", anchor: targetAnchor) }
                                    }
                                }
                            }
                            .onChange(of: song?.persistentID) { _ in isUserScrolling = false; playbackLineIndex = -1; playbackGapIndex = -1; loadLyrics() }
                            .onChange(of: audioManager.currentLocalSong?.id) { _ in isUserScrolling = false; playbackLineIndex = -1; playbackGapIndex = -1; loadLyrics() }
                            .onChange(of: audioManager.currentRemoteDTO?.id) { _ in isUserScrolling = false; playbackLineIndex = -1; playbackGapIndex = -1; loadLyrics() }
                            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if !isUserScrolling { if playbackLineIndex >= 0 { scrollProxy.scrollTo(playbackLineIndex, anchor: .center) } else if playbackGapIndex >= 0 { scrollProxy.scrollTo("gap_\(playbackGapIndex)", anchor: .center) } } } }
                            .mask(LinearGradient(stops: [.init(color: .clear, location: 0.0), .init(color: .black, location: 0.10), .init(color: .black, location: 0.90), .init(color: .clear, location: 1.0)], startPoint: .top, endPoint: .bottom))
                            .simultaneousGesture(DragGesture().onChanged { value in
                                if !isUserScrolling { withAnimation(.easeInOut(duration: 0.2)) { isUserScrolling = true } }
                                if !dragSessionActive { dragSessionActive = true; let baseTop = topPadding; dragStartedAtTop = currentScrollOffset >= (baseTop - 5) }
                                if dragStartedAtTop && value.translation.height > 0 { dragOffset?.wrappedValue = value.translation }
                            }.onEnded { value in
                                dragSessionActive = false
                                if dragStartedAtTop {
                                    dragStartedAtTop = false
                                    if value.translation.height > 100 { withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { uiState.isPlayerExpanded = false } }
                                    else { withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { dragOffset?.wrappedValue = .zero } }
                                }
                            })
                            .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
                                let time = audioManager.currentTime + 0.4
                                var activeL = -1
                                var gapL = -1
                                if lines.isEmpty { return }
                                
                                if time < lines[0].startTime {
                                    gapL = 0
                                } else {
                                    var lastPassedIndex = -1
                                    for (index, line) in lines.enumerated() {
                                        if line.isUnsynced == true { continue }
                                        if time >= line.startTime { lastPassedIndex = index } else { break }
                                    }
                                    if lastPassedIndex != -1 {
                                        let activeLine = lines[lastPassedIndex]
                                        if let end = activeLine.endTime, time > end { gapL = lastPassedIndex + 1 } else { activeL = lastPassedIndex }
                                    }
                                }
                                
                                if activeL != playbackLineIndex || gapL != playbackGapIndex {
                                    let isFirstSync = (playbackLineIndex == -1 && playbackGapIndex == -1)
                                    playbackLineIndex = activeL; playbackGapIndex = gapL
                                    if !isUserScrolling {
                                        if isFirstSync {
                                            if activeL >= 0 { scrollProxy.scrollTo(activeL, anchor: scrollAnchor) } else if gapL >= 0 { scrollProxy.scrollTo("gap_\(gapL)", anchor: scrollAnchor) } // <--- HERE
                                        } else {
                                            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                                                if activeL >= 0 { scrollProxy.scrollTo(activeL, anchor: scrollAnchor) } else if gapL >= 0 { scrollProxy.scrollTo("gap_\(gapL)", anchor: scrollAnchor) } // <--- HERE
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // NEW RESUME BUTTON LOCATION
                            if isUserScrolling {
                                Button(action: {
                                    isUserScrolling = false
                                    
                                    // 1. Wrap the scroll logic cleanly so we can call it multiple times
                                    let snapToCurrent = {
                                        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                                            if playbackLineIndex >= 0 { scrollProxy.scrollTo(playbackLineIndex, anchor: scrollAnchor) }
                                            else if playbackGapIndex >= 0 { scrollProxy.scrollTo("gap_\(playbackGapIndex)", anchor: scrollAnchor) }
                                            else { scrollProxy.scrollTo(0, anchor: scrollAnchor) }
                                        }
                                    }
                                    
                                    // 2. Fire immediately
                                    snapToCurrent()
                                    
                                    // 3. Fire repeatedly over a tiny window to aggressively kill any active scroll momentum
                                    for delay in [0.05, 0.15, 0.3] {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                            // Only snap if the user hasn't physically touched the screen again
                                            if !isUserScrolling {
                                                snapToCurrent()
                                            }
                                        }
                                    }
                                    
                                }) {
                                    HStack { Image(systemName: "arrow.down.forward.and.scroll.right"); Text("Resume") }
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 16)
                                        .background(Color.red)
                                        .clipShape(Capsule())
                                        .shadow(color: .red.opacity(0.4), radius: 5, x: 0, y: 3)
                                }
                                // Matches the toolbar padding perfectly!
                                .padding(.top, isLandscape ? max(geo.safeAreaInsets.top, 0) : max(geo.safeAreaInsets.top, 20) + 45)
                                .transition(.scale.combined(with: .opacity))
                                .zIndex(100)
                            }
                        }
                    }
                } else if let liveRawText = activeRawLyrics, !liveRawText.isEmpty {
                    VStack(spacing: 20) {
                        Text("Lyrics available, but not synced.").font(.subheadline).foregroundColor(.white.opacity(0.7)).padding(.top, 80)
                        if audioManager.currentSong != nil || audioManager.currentLocalSong != nil || audioManager.currentRemoteDTO != nil {
                            Button(action: { showSyncSheet = true }) {
                                HStack { Image(systemName: "arrow.triangle.2.circlepath"); Text("Sync Now") }
                                    .font(.headline.bold()).foregroundColor(.white).padding(.horizontal, 24).padding(.vertical, 12).background(Color.pink).clipShape(Capsule()).shadow(color: .pink.opacity(0.4), radius: 8, x: 0, y: 4)
                            }
                        }
                        
                        let lines = liveRawText.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        ScrollView(showsIndicators: false) {
                            ScrollViewReader { rawScrollProxy in
                                VStack(spacing: 12) {
                                    Color.clear.frame(height: 0).id("TOP")
                                    ForEach(lines, id: \.self) { line in Text(line).font(.subheadline).foregroundColor(.white.opacity(0.6)).multilineTextAlignment(.center) }
                                }.padding(.horizontal, horizontalPadding)
                                .onChange(of: song?.persistentID) { _ in rawScrollProxy.scrollTo("TOP", anchor: .top) }
                                .onChange(of: audioManager.currentLocalSong?.id) { _ in rawScrollProxy.scrollTo("TOP", anchor: .top) }
                                .onChange(of: audioManager.currentRemoteDTO?.id) { _ in rawScrollProxy.scrollTo("TOP", anchor: .top) }
                            }
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "music.mic").font(.system(size: 50)).foregroundColor(.white.opacity(0.5))
                        Text("No lyrics available.").font(.subheadline).multilineTextAlignment(.center).foregroundColor(.white.opacity(0.7)).padding(.horizontal, 20)
                    }
                }
                
                VStack {
                    HStack {
                        if showFullScreenButton {
                            Button(action: { withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { uiState.isLyricsFullScreen.toggle() } }) {
                                Image(systemName: uiState.isLyricsFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                    .font(.title3).foregroundColor(.white).padding(12).background(Circle().fill(Color.black.opacity(0.4))).shadow(radius: 5)
                            }
                        }
                        
                        Spacer() // <--- The Resume button has been removed from here
                        
                        if audioManager.currentSong != nil || audioManager.currentLocalSong != nil || audioManager.currentRemoteDTO != nil {
                            Button(action: { showRawLyricsEditor = true }) {
                                Image(systemName: "pencil").font(.title3).foregroundColor(.white).padding(12).background(Circle().fill(Color.black.opacity(0.4))).shadow(radius: 5)
                            }
                        }
                    }
                    .padding(.horizontal, max(geo.safeAreaInsets.leading, 16))
                    .padding(.top, isLandscape ? max(geo.safeAreaInsets.top, 0) : max(geo.safeAreaInsets.top, 20) + 16)
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { loadLyrics() }
        .sheet(isPresented: $showWordSyncSheet) {
            if let aSong = lockedAppleSong {
                WordSyncEditorSheet(appleSong: aSong, audioManager: audioManager, library: library)
            } else if let lSong = lockedLocalSong {
                WordSyncEditorSheet(localSong: lSong, audioManager: audioManager, library: library)
            } else if let rSong = lockedRemoteSong {
                WordSyncEditorSheet(remoteSong: rSong, audioManager: audioManager, library: library)
            }
        }
    }
    
    // Add these right before func loadLyrics()
    private var resyncLinesButton: some View {
        Button(action: { showSyncSheet = true }) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("Resync Lines")
            }
            .font(.caption.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.15))
            .clipShape(Capsule())
        }
    }
    
    private var wordSyncButton: some View {
        Button(action: {
            lockedAppleSong = song
            lockedLocalSong = audioManager.currentLocalSong
            lockedRemoteSong = audioManager.currentRemoteDTO
            showWordSyncSheet = true
        }) {
            HStack {
                Image(systemName: "text.word.spacing")
                Text("Word Sync")
            }
            .font(.caption.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.pink.opacity(0.8))
            .clipShape(Capsule())
        }
    }
    
    @ViewBuilder
    private func lyricRow(for index: Int, lines: [SyncedLyricLine], mainFontSize: CGFloat) -> some View {
        Group {
            GapCapsule(
                isGap: playbackGapIndex == index,
                color: settings.lyricColorName.color,
                gapIndex: index,
                width: 40,
                height: 4,
                padding: 8
            )
            
            if index < lines.count {
                let lineData = lines[index]
                
                LyricLineView(
                    lineData: lineData,
                    isCurrentLine: index == playbackLineIndex,
                    isPast: index < playbackLineIndex,
                    isPlaying: audioManager.isPlaying,
                    mainFontSize: mainFontSize,
                    audioManager: audioManager,
                    settings: settings
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 20)),
                    removal: .opacity.combined(with: .scale(scale: 0.85)).combined(with: .offset(y: -40))
                ))
                .id(index)
                .contentShape(Rectangle())
                .onTapGesture {
                    audioManager.seek(to: lineData.startTime)
                    isUserScrolling = false
                }
            }
        }
    }
    
    func loadLyrics() {
        let rawText = audioManager.currentLocalSong?.lyrics ?? (audioManager.currentRemoteDTO != nil ? library.customRawLyrics[audioManager.currentRemoteDTO!.id] : nil) ?? song?.lyrics
        if let raw = rawText, !raw.isEmpty {
            self.rawLines = raw.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } else {
            self.rawLines = []
        }
    }
    
    private func dynamicAnchor(for index: Int) -> UnitPoint {
        guard let lines = processedLyrics, index >= 0 && index < lines.count else { return .center }
        
        // Count the number of lines in the current lyric chunk
        let lineCount = CGFloat(lines[index].text.components(separatedBy: "\n").count)
        
        // Base center is exactly 0.5.
        // For every extra line, subtract 0.04 to shift the anchor slightly higher up the screen.
        // This perfectly centers large blocks and prevents them from looking "too low".
        let adjustedY = 0.5 - ((lineCount - 1) * 0.04)
        
        // Max limits it to 0.25 so massive chunks don't hit the absolute top edge
        return UnitPoint(x: 0.5, y: max(0.25, adjustedY))
    }
}

struct SyncEditorSheet: View {
    var appleSong: MPMediaItem? = nil; var localSong: LocalSong? = nil; var remoteSong: RemoteSongDTO? = nil; @ObservedObject var audioManager: AudioManager; @ObservedObject var library: LibraryManager; @Environment(\.dismiss) var dismiss
    @State private var rawLines: [String] = []; @State private var isSyncing = false; @State private var countdown = -1; @State private var syncLineIndex = 0; @State private var isLineActive = false; @State private var recordedLines: [SyncedLyricLine] = []
    
    private var safeTime: TimeInterval {
        let t = audioManager.currentTime
        return (t.isNaN || t.isInfinite) ? 0.0 : t
    }
    
    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height; let mainFontSize: CGFloat = isLandscape ? 44 : 34
            NavigationView {
                ZStack {
                    Color(UIColor.systemBackground).ignoresSafeArea()
                    if rawLines.isEmpty { VStack(spacing: 16) { Image(systemName: "music.mic").font(.system(size: 60)).foregroundColor(.gray.opacity(0.5)); Text("No lyrics available to sync.").multilineTextAlignment(.center).foregroundColor(.gray).padding(Edge.Set.horizontal, 40) } } else if !isSyncing { VStack(spacing: 30) { Text("Lyric Sync Editor").font(.largeTitle.bold()); Text("Listen to the song and tap along to sync each line to the beat.").font(.headline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(Edge.Set.horizontal, 40); Button(action: { startInitialCountdown() }) { Text("Start Syncing").font(.title2.bold()).foregroundColor(.white).padding(Edge.Set.horizontal, 40).padding(.vertical, 16).background(Color.pink).clipShape(Capsule()).shadow(color: .pink.opacity(0.4), radius: 10, x: 0, y: 5) }; ScrollView { VStack(spacing: 10) { ForEach(rawLines, id: \.self) { line in Text(line).font(.subheadline).foregroundColor(.gray.opacity(0.5)) } }.padding() } }.padding(.top, 40) } else {
                        VStack(spacing: 0) {
                            VStack(spacing: 20) {
                                Spacer()
                                if syncLineIndex < rawLines.count { Text(rawLines[syncLineIndex]).font(.system(size: mainFontSize, weight: .bold)).foregroundColor(isLineActive ? .pink : .primary.opacity(0.7)).scaleEffect(isLineActive ? 1.0 : 0.8).multilineTextAlignment(.center).lineLimit(nil).fixedSize(horizontal: false, vertical: true).padding(Edge.Set.horizontal, 20); if syncLineIndex + 1 < rawLines.count { Text(rawLines[syncLineIndex + 1]).font(.system(size: mainFontSize, weight: .bold)).scaleEffect(0.6).foregroundColor(.gray.opacity(0.4)).multilineTextAlignment(.center).padding(Edge.Set.horizontal, 20) } } else { Text("Sync Complete!").font(.system(size: mainFontSize, weight: .bold)).foregroundColor(.green); Button("Save & Close") { finishSyncing() }.font(.title2.bold()).foregroundColor(.white).padding(Edge.Set.horizontal, 30).padding(.vertical, 14).background(Color.green).clipShape(Capsule()).padding(.top, 20) }
                                Spacer()
                            }
                            if syncLineIndex < rawLines.count {
                                VStack(spacing: 16) {
                                    HStack(spacing: 12) {
                                        Button(action: { rewindAndResume(by: 10) }) {
                                            Image(systemName: "gobackward.10")
                                                .font(.title2)
                                                .foregroundColor(.white)
                                                .padding()
                                                .frame(maxWidth: .infinity)
                                                .background(Color.gray.opacity(0.4))
                                                .cornerRadius(12)
                                        }
                                        
                                        Button(action: { rewindAndResume(by: 5) }) {
                                            Image(systemName: "gobackward.5")
                                                .font(.title2)
                                                .foregroundColor(.white)
                                                .padding()
                                                .frame(maxWidth: .infinity)
                                                .background(Color.gray.opacity(0.4))
                                                .cornerRadius(12)
                                        }
                                        
                                        Button(action: { rewindAndResume(by: 2) }) {
                                            ZStack {
                                                Image(systemName: "gobackward").font(.title2)
                                                Text("2").font(.system(size: 10, weight: .bold)).offset(y: 1.5)
                                            }
                                            .foregroundColor(.white)
                                            .padding()
                                            .frame(maxWidth: .infinity)
                                            .background(Color.gray.opacity(0.4))
                                            .cornerRadius(12)
                                        }
                                    
                                        Button(action: { let breakStartTime: TimeInterval; if isLineActive { breakStartTime = safeTime; recordedLines[recordedLines.count - 1].endTime = breakStartTime; syncLineIndex += 1; isLineActive = false } else { if recordedLines.isEmpty { breakStartTime = 0.0 } else { breakStartTime = recordedLines.last?.endTime ?? safeTime } }; recordedLines.append(SyncedLyricLine(text: "[Instrumental]", startTime: breakStartTime, endTime: nil)); UIImpactFeedbackGenerator(style: .medium).impactOccurred(); if syncLineIndex >= rawLines.count { finishSyncing() } }) { HStack { Image(systemName: "music.note");  }.font(.headline).foregroundColor(.white).padding().frame(maxWidth: .infinity).background(Color.gray.opacity(0.4)).cornerRadius(12) }
                                    }.padding(Edge.Set.horizontal, 40)
                                    if !isLineActive { Button(action: { recordedLines.append(SyncedLyricLine(text: rawLines[syncLineIndex], startTime: safeTime, endTime: nil)); isLineActive = true; UIImpactFeedbackGenerator(style: .medium).impactOccurred() }) { Text("Start Lyric").font(.title2.bold()).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 20).background(Color.pink).cornerRadius(16) }.padding(Edge.Set.horizontal, 40) } else { HStack(spacing: 16) { Button(action: { recordedLines[recordedLines.count - 1].endTime = safeTime; syncLineIndex += 1; isLineActive = false; UIImpactFeedbackGenerator(style: .light).impactOccurred(); if syncLineIndex >= rawLines.count { finishSyncing() } }) { Text("End Lyric").font(.headline.bold()).foregroundColor(.pink).frame(maxWidth: .infinity).padding(.vertical, 20).background(Color.pink.opacity(0.15)).cornerRadius(16) }; Button(action: { recordedLines[recordedLines.count - 1].endTime = safeTime; syncLineIndex += 1; if syncLineIndex < rawLines.count { recordedLines.append(SyncedLyricLine(text: rawLines[syncLineIndex], startTime: safeTime, endTime: nil)) } else { finishSyncing() }; UIImpactFeedbackGenerator(style: .medium).impactOccurred() }) { Text("Next Lyric").font(.title2.bold()).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 20).background(Color.pink).cornerRadius(16) } }.padding(Edge.Set.horizontal, 40) }
                                }.padding(.top, 20).padding(.bottom, geo.safeAreaInsets.bottom + 20).background(Color(UIColor.secondarySystemBackground).shadow(radius: 10))
                            }
                        }
                    }
                    if countdown > 0 { ZStack { Color.black.opacity(0.8).ignoresSafeArea(); Text("\(countdown)").font(.system(size: 150, weight: .black)).foregroundColor(.white).transition(AnyTransition.scale.combined(with: AnyTransition.opacity)).id(countdown) } }
                }.navigationTitle(isLandscape ? "" : "Sync Editor").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { if audioManager.isPlaying { audioManager.togglePlayPause() }; dismiss() } } }.onAppear { loadLyrics() }
            }.navigationViewStyle(.stack)
        }
    }
    
    func loadLyrics() {
        let songId = appleSong != nil ? String(appleSong!.persistentID) : (localSong?.id ?? remoteSong?.id ?? "")
        let defaultLyrics = appleSong?.lyrics ?? localSong?.lyrics ?? (remoteSong != nil ? library.customRawLyrics[remoteSong!.id] : nil)
        
        if let raw = library.getRawLyrics(id: songId, fallback: defaultLyrics), !raw.isEmpty {
            self.rawLines = raw.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        } else {
            self.rawLines = []
        }
    }
    func startInitialCountdown() { countdown = 3; if audioManager.isPlaying { audioManager.togglePlayPause() }; audioManager.seek(to: 0); Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in withAnimation(Animation.spring()) { countdown -= 1 }; if countdown == 0 { timer.invalidate(); isSyncing = true; recordedLines.removeAll(); syncLineIndex = 0; isLineActive = false; audioManager.seek(to: 0); if !audioManager.isPlaying { audioManager.togglePlayPause() } } } }
    func rewindAndResume(by seconds: TimeInterval) {
        let syncResumeTime = max(0, audioManager.currentTime - seconds)
        recordedLines.removeAll { $0.startTime >= syncResumeTime }
        
        if let last = recordedLines.last {
            if last.text == "[Instrumental]" {
                isLineActive = false
                syncLineIndex = recordedLines.filter { $0.text != "[Instrumental]" }.count
            } else {
                if let end = last.endTime, end <= syncResumeTime {
                    isLineActive = false
                    syncLineIndex = recordedLines.filter { $0.text != "[Instrumental]" }.count
                } else {
                    recordedLines[recordedLines.count - 1].endTime = nil
                    isLineActive = true
                    syncLineIndex = recordedLines.filter { $0.text != "[Instrumental]" }.count - 1
                }
            }
        } else {
            isLineActive = false
            syncLineIndex = 0
        }
        
        let useCountdown = UserDefaults.standard.object(forKey: "rewindCountdown") as? Bool ?? true
        if useCountdown {
            countdown = 3
            if syncResumeTime >= 3.0 {
                let audioStartTime = syncResumeTime - 3.0
                audioManager.seek(to: audioStartTime)
                if !audioManager.isPlaying { audioManager.togglePlayPause() }
                Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                    withAnimation(Animation.spring()) { countdown -= 1 }
                    if countdown == 0 { timer.invalidate() }
                }
            } else {
                if audioManager.isPlaying { audioManager.togglePlayPause() }
                audioManager.seek(to: syncResumeTime)
                Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                    withAnimation(Animation.spring()) { countdown -= 1 }
                    if countdown == 0 {
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
            library.saveSyncedLyrics(for: aSong, lines: recordedLines)
        } else if let lSong = localSong {
            library.saveSyncedLyrics(id: lSong.id, title: lSong.title, artist: lSong.artist, lines: recordedLines)
            if let index = DownloadsManager.shared.downloadedSongs.firstIndex(where: { $0.id == lSong.id }) {
                DownloadsManager.shared.downloadedSongs[index].syncedLyrics = recordedLines
            }
            if audioManager.currentLocalSong?.id == lSong.id {
                audioManager.currentLocalSong?.syncedLyrics = recordedLines
            }
        } else if let rSong = remoteSong {
            library.saveSyncedLyrics(id: rSong.id, title: rSong.title, artist: rSong.artist, lines: recordedLines)
        }
        dismiss()
    }
}

extension Color {
    init(customHex: String) {
        let hexSanitized = customHex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var int: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&int) else { self.init(.clear); return }
        
        let a, r, g, b: UInt64
        switch hexSanitized.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue:  Double(b) / 255, opacity: Double(a) / 255)
    }

    func toCustomHex() -> String? {
        let uic = UIColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else { return nil }
        let r = Float(components[0]); let g = Float(components[1]); let b = Float(components[2]); var a = Float(1.0)
        if components.count >= 4 { a = Float(components[3]) }
        if a != Float(1.0) { return String(format: "%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255)) }
        else { return String(format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255)) }
    }
}

struct AlbumColorEditorSheet: View {
    let albumID: String
    @ObservedObject var library = LibraryManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var selectedBgColor: Color = .black
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Background Color")) {
                    ColorPicker("Set Color", selection: $selectedBgColor, supportsOpacity: false)
                }
                Section(header: Text("Extract from Photo"), footer: Text("Select a photo to display it here, then use the eyedropper tool in the Color Picker above to grab a specific color from it!")) {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label("Select Photo from Library", systemImage: "photo.on.rectangle")
                    }
                    if let image = selectedImage { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200).cornerRadius(8) }
                }
                Section {
                    Button("Apply Background Color") { library.saveAlbumColor(id: albumID, hex: selectedBgColor.toHex()); dismiss() }
                    Button("Remove Custom Background", role: .destructive) { library.saveAlbumColor(id: albumID, hex: nil); dismiss() }
                }
            }
            .navigationTitle("Page Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } } }
            .onChange(of: selectedItem) { newItem in Task { if let data = try? await newItem?.loadTransferable(type: Data.self), let uiImage = UIImage(data: data) { selectedImage = uiImage } } }
            .onAppear { if let hex = library.customAlbumColors[albumID] { selectedBgColor = Color(hex: hex) } }
        }
    }
}

struct PulsingDots: View {
    var isPlaying: Bool
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 24) {
            ForEach(0..<3) { i in
                Circle().fill(Color.pink).frame(width: 18, height: 18).scaleEffect(pulse && isPlaying ? 1.4 : 1.0).opacity(pulse && isPlaying ? 1.0 : 0.2)
                    .animation(isPlaying ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(Double(i) * 0.25) : .easeInOut(duration: 0.4), value: pulse)
            }
        }.onAppear { pulse = true }
    }
}

struct ProgressiveWordView: View {
    let word: String; let startTime: TimeInterval; let endTime: TimeInterval; let currentTime: TimeInterval; let fontSize: CGFloat; let activeColor: Color; let isCurrentLine: Bool; let isPast: Bool
    var progress: CGFloat {
        if isPast { return 1.0 }
        if !isCurrentLine { return 0.0 }
        guard currentTime >= startTime else { return 0.0 }
        guard currentTime < endTime else { return 1.0 }
        let duration = max(endTime - startTime, 0.01)
        return CGFloat((currentTime - startTime) / duration)
    }
    var body: some View {
        ZStack(alignment: .leading) {
            Text(word).font(.system(size: fontSize, weight: .bold)).foregroundColor(isPast ? .white : .white.opacity(0.5))
            Text(word).font(.system(size: fontSize, weight: .bold)).foregroundColor(activeColor).mask(GeometryReader { geo in Rectangle().frame(width: geo.size.width * progress, height: geo.size.height).animation(.linear(duration: 0.1), value: progress) })
        }.fixedSize(horizontal: true, vertical: true)
    }
}

struct GapCapsule: View {
    let isGap: Bool; let color: Color; let gapIndex: Int; let width: CGFloat; let height: CGFloat; let padding: CGFloat
    var body: some View { Capsule().fill(color).frame(width: width, height: height).padding(.vertical, isGap ? padding : CGFloat(0)).opacity(isGap ? 1.0 : 0.0).frame(height: isGap ? nil : CGFloat(0)).id("gap_\(gapIndex)").animation(.spring(), value: isGap) }
}

struct LyricLineView: View {
    let lineData: SyncedLyricLine; let isCurrentLine: Bool; let isPast: Bool; let isPlaying: Bool; let mainFontSize: CGFloat; @ObservedObject var audioManager: AudioManager; @ObservedObject var settings: AppSettings
    var isInstrumental: Bool { lineData.text == "[Instrumental]" }
    var body: some View {
        Group {
            if lineData.isUnsynced == true {
                Text(lineData.text).font(.system(size: mainFontSize, weight: .bold)).foregroundColor(.white.opacity(0.3)).multilineTextAlignment(.center).lineLimit(nil).fixedSize(horizontal: false, vertical: true).scaleEffect(0.6, anchor: .center)
            } else if isInstrumental {
                if isCurrentLine { PulsingDots(isPlaying: isPlaying).padding(.vertical, 10) } else { Text("•••").font(.title).foregroundColor(.white.opacity(0.4)).padding(.vertical, 10) }
            } else {
                if let timings = lineData.wordTimings, !timings.isEmpty {
                    renderWordSyncLine(lineData: lineData, timings: timings, fontSize: mainFontSize, isCurrentLine: isCurrentLine, isPast: isPast).scaleEffect(isCurrentLine ? 1.0 : 0.5, anchor: .center).opacity(isCurrentLine ? 1.0 : (isPast ? 0.5 : 0.7))
                    // REMOVED BLUR: blur(radius: isCurrentLine ? 0 : 0.8)
                } else {
                    Text(lineData.text).font(.system(size: mainFontSize, weight: .bold)).foregroundColor(isCurrentLine ? settings.lyricColorName.color : .white).multilineTextAlignment(.center).lineLimit(nil).fixedSize(horizontal: false, vertical: true).scaleEffect(isCurrentLine ? 1.0 : 0.5, anchor: .center).opacity(isCurrentLine ? 1.0 : (isPast ? 0.5 : 0.7))
                    // REMOVED BLUR: blur(radius: isCurrentLine ? 0 : 0.8)
                }
            }
        }.animation(.spring(response: 0.6, dampingFraction: 0.8), value: isCurrentLine)
    }
    
    func renderWordSyncLine(lineData: SyncedLyricLine, timings: [WordTiming], fontSize: CGFloat, isCurrentLine: Bool, isPast: Bool) -> some View {
        let words = lineData.text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return CenterFlowLayout {
            ForEach(Array(words.enumerated()), id: \.offset) { item in
                let wIndex = item.offset; let wordText = item.element; let wordWithSpace = wordText + (wIndex == words.count - 1 ? "" : " ")
                let startTime = (wIndex < timings.count) ? timings[wIndex].startTime : .infinity
                let endTime = (wIndex + 1 < timings.count) ? timings[wIndex + 1].startTime : (lineData.endTime ?? (startTime + 1.5))
                ProgressiveWordView(word: wordWithSpace, startTime: startTime, endTime: endTime, currentTime: audioManager.currentTime, fontSize: fontSize, activeColor: settings.lyricColorName.color, isCurrentLine: isCurrentLine, isPast: isPast)
            }
        }
    }
}

struct AlbumDescriptionEditorSheet: View {
    let albumID: String; @ObservedObject var library = LibraryManager.shared; @Environment(\.dismiss) var dismiss; @State private var descriptionText: String = ""
    var body: some View {
        NavigationView {
            Form { Section(header: Text("Album Description"), footer: Text("This will appear above the play controls on the album page.")) { TextEditor(text: $descriptionText).frame(minHeight: 150) } }
            .navigationTitle("Edit Description").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .navigationBarTrailing) { Button("Save") { library.saveAlbumDescription(id: albumID, text: descriptionText); dismiss() }.bold() } }
            .onAppear { descriptionText = library.customAlbumDescriptions[albumID] ?? "" }
        }
    }
}

struct CenterFlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { let result = FlowResult(in: proposal.width ?? 1000, subviews: subviews); return result.size }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let xOffset = bounds.minX + (bounds.width - result.rowWidths[result.rowIndex[index]]) / 2
            subview.place(at: CGPoint(x: xOffset + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: ProposedViewSize(result.frames[index].size))
        }
    }
    struct FlowResult {
        var frames: [CGRect] = []; var rowWidths: [CGFloat] = []; var rowIndex: [Int] = []; var size: CGSize = .zero
        init(in maxWidth: CGFloat, subviews: Subviews) {
            var currentX: CGFloat = 0; var currentY: CGFloat = 0; var lineHeight: CGFloat = 0; var currentRowIndex = 0
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if currentX + size.width > maxWidth && currentX > 0 { rowWidths.append(currentX); currentX = 0; currentY += lineHeight; lineHeight = 0; currentRowIndex += 1 }
                frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height)); rowIndex.append(currentRowIndex); currentX += size.width; lineHeight = max(lineHeight, size.height)
            }
            if currentX > 0 { rowWidths.append(currentX) }
            self.size = CGSize(width: rowWidths.max() ?? 0, height: currentY + lineHeight)
        }
    }
}

struct DynamicAlbumWrapper: View {
    let item: UnifiedAlbumItem; @ObservedObject var library: LibraryManager; @ObservedObject var audioManager: AudioManager
    // Actively observe local downloads so the view redraws when they populate
    @ObservedObject var downloads = DownloadsManager.shared
    
    var body: some View {
        // 1. If it was already loaded when tapped, just show it normally
        if let apple = item.appleAlbum {
            AlbumDetailView(album: apple, audioManager: audioManager, library: library)
        } else if let local = item.localWrapper {
            UniversalAlbumDetailView(albumName: local.name, collection: .downloads(local.songs))
        } else {
            // 2. GHOST STATE: Actively scan the live library arrays to see if it finished loading in the background
            let appleID = item.id.hasPrefix("apple_") ? String(item.id.dropFirst(6)) : nil
            let localName = item.id.hasPrefix("local_") ? String(item.id.dropFirst(6)) : nil
            
            if let aID = appleID, let liveApple = library.albums.first(where: { String($0.persistentID) == aID }) {
                AlbumDetailView(album: liveApple, audioManager: audioManager, library: library)
                
            } else if let lName = localName, !downloads.downloadedSongs.filter({ $0.album == lName }).isEmpty {
                let liveSongs = downloads.downloadedSongs.filter({ $0.album == lName })
                UniversalAlbumDetailView(albumName: lName, collection: .downloads(liveSongs))
                
            } else {
                // 3. Still waiting for Apple's media framework to finish querying...
                VStack {
                    ProgressView()
                    Text("Loading Album...")
                        .foregroundColor(.secondary)
                        .padding(.top)
                }
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

// MARK: - Safe Decimal Input for Settings
struct TimingTextField: View {
    let title: String
    @Binding var value: Double
    @State private var typedText: String = ""
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0.0", text: $typedText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)
                .onChange(of: typedText) { newValue in
                    // Safely allow the field to be empty without forcing a "0.0" on the screen
                    if newValue.isEmpty {
                        value = 0
                    } else if let doubleValue = Double(newValue) {
                        value = doubleValue
                    }
                }
                .onAppear {
                    // Initialize the text field with the current saved value
                    typedText = value > 0 ? String(value) : ""
                }
            
            Text("sec")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Dynamic Text Legibility
extension Color {
    // Helper to calculate perceived brightness
    var luminance: CGFloat {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        let components = [r, g, b].map { val -> CGFloat in
            return val <= 0.03928 ? val / 12.92 : pow((val + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * components[0] + 0.7152 * components[1] + 0.0722 * components[2]
    }
    
    var isDark: Bool {
        return luminance < 0.5
    }
    
    // Pure White or Pure Black for Titles
    var adaptivePrimary: Color {
        return isDark ? .white : .black
    }
    
    // Opacity blend naturally creates a "lighter/darker shade" of the background!
    var adaptiveSecondary: Color {
        return isDark ? .white.opacity(0.65) : .black.opacity(0.6)
    }
    
    // Faint blend for Dividers
    var adaptiveDivider: Color {
        return isDark ? .white.opacity(0.15) : .black.opacity(0.15)
    }
}

#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
#endif

extension Color {
    /// Returns black or white text color depending on the luminance of the background color.
    func smartTextColor() -> Color {
        let platformColor = PlatformColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        // Extract RGB values
        platformColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        // Calculate relative luminance
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        
        // If the background is light, use black text. Otherwise, use white text.
        return luminance > 0.5 ? .black : .white
    }
}


