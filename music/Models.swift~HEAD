
import Foundation
import MediaPlayer

// MARK: - Unified Content Models
struct UnifiedSongItem: Identifiable {
    let id: String
    let title: String
    let artist: String
    let sortTitle: String
    let appleSong: MPMediaItem?
    let localSong: LocalSong?
}

struct UnifiedSongSection: Identifiable {
    let id = UUID()
    let letter: String
    let songs: [UnifiedSongItem]
}

struct UnifiedAlbumItem: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let sortTitle: String
    let appleAlbum: MPMediaItemCollection?
    let localWrapper: LocalAlbumWrapper?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: UnifiedAlbumItem, rhs: UnifiedAlbumItem) -> Bool { lhs.id == rhs.id }
}

struct UnifiedAlbumSection: Identifiable {
    let id = UUID()
    let letter: String
    let albums: [UnifiedAlbumItem]
}

struct UnifiedArtistItem: Identifiable, Hashable {
    let id: String
    let name: String
    let sortName: String
    let appleArtist: String?
    let localWrapper: LocalArtistWrapper?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: UnifiedArtistItem, rhs: UnifiedArtistItem) -> Bool { lhs.id == rhs.id }
}

struct UnifiedArtistSection: Identifiable {
    let id = UUID()
    let letter: String
    let artists: [UnifiedArtistItem]
}

struct LocalAlbumWrapper: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let songs: [LocalSong]
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
    static func == (lhs: LocalAlbumWrapper, rhs: LocalAlbumWrapper) -> Bool { lhs.name == rhs.name }
}

struct LocalArtistWrapper: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let songs: [LocalSong]
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
    static func == (lhs: LocalArtistWrapper, rhs: LocalArtistWrapper) -> Bool { lhs.name == rhs.name }
}
