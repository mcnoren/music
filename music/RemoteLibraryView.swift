//
//  RemoteLibraryView.swift
//  music
//

#if os(iOS)
import SwiftUI
import Combine
import UIKit
import LiveKitWebRTC

// MARK: - Navigation Wrappers

struct RemoteSongSection: Identifiable {
    let id = UUID()
    let letter: String
    let songs: [RemoteSongDTO]
}

struct RemoteArtistSection: Identifiable {
    let id = UUID()
    let letter: String
    let artists: [String]
}

struct RemoteAlbumSection: Identifiable {
    let id = UUID()
    let letter: String
    let albums: [RemoteAlbumSummary]
}

// MARK: - Main Remote Wrapper View
struct RemoteLibraryWrapperView: View {
    @ObservedObject var multipeer = MultipeerManager.shared
    @ObservedObject var audioManager = AudioManager.shared
    @ObservedObject var webrtc = WebRTCManager.shared

    var body: some View {
        Group {
            if multipeer.connectionState == .connected ||
               webrtc.connectionState == .connected ||
               webrtc.connectionState == .completed {
                
                RemoteLibraryHomeView(multipeer: multipeer)
                
            } else if webrtc.connectionState == .failed || webrtc.connectionState == .disconnected {
                // MARK: - The New Disconnect / Timeout Screen
                VStack(spacing: 24) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 60))
                        .foregroundColor(.pink)
                    
                    Text("Connection Failed")
                        .font(.title2.bold())
                    
                    Text("The iPhone could not reach the Mac. Make sure the Mac app is open and connected to the internet.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button(action: {
                        // Trigger the hard reset function we built earlier
                        webrtc.connectionState = .new // Instantly flip UI back to loading
                        webrtc.performHardResetAndReconnect()
                    }) {
                        Text("Try Reconnecting")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 14)
                            .background(Color.pink)
                            .cornerRadius(12)
                    }
                    .padding(.top, 10)
                }
            } else {
                // MARK: - The Loading Screen
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Connecting to Mac...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Remote Genre Views
struct RemoteGenreListView: View {
    @ObservedObject var multipeer: MultipeerManager
    @State private var searchText = ""
    
    var activeGenres: [String] {
        var genres = Set<String>()
        multipeer.remoteLibrary.forEach { if !$0.genre.isEmpty { genres.insert($0.genre) } }
        var sorted = Array(genres).sorted()
        if !searchText.isEmpty { sorted = sorted.filter { $0.localizedCaseInsensitiveContains(searchText) } }
        return sorted
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(activeGenres, id: \.self) { genre in
                    NavigationLink(destination: RemoteGenreDetailView(genre: genre, multipeer: multipeer)) {
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
            }
        }
        .navigationTitle("Remote Genres")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
    }
}

struct RemoteGenreDetailView: View {
    let genre: String
    @ObservedObject var multipeer: MultipeerManager
    
    var songs: [RemoteSongDTO] {
        multipeer.remoteLibrary.filter { $0.genre == genre }.sorted { $0.title < $1.title }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(songs) { song in
                    RemoteSongRow(song: song, queue: songs, multipeer: multipeer)
                    Divider().padding(.leading)
                }
            }
        }
        .navigationTitle(genre)
    }
}

// MARK: - Remote Home View
struct RemoteLibraryHomeView: View {
    @ObservedObject var multipeer: MultipeerManager
    let menuItems = [
        ("Artists", "RemoteArtists", "music.mic"),
        ("Albums", "RemoteAlbums", "square.stack"),
        ("Genres", "RemoteGenres", "guitars"),
        ("Songs", "RemoteSongs", "music.note")
    ]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ConnectToMacButton(multipeer: multipeer, audioManager: AudioManager.shared)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                
                ForEach(menuItems, id: \.1) { item in
                    VStack(spacing: 0) {
                        NavigationLink(value: item.1) {
                            SimpleMenuRow(icon: item.2, title: item.0, showChevron: true)
                        }
                        Divider().padding(.leading, 60)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("Mac Library")
        // ADD THIS BLOCK: Pre-fetch the library to ensure we get the streamServerURL immediately
        .onAppear {
            if multipeer.remoteLibrary.isEmpty {
                multipeer.sendCommand("REQUEST_LIBRARY")
            }
        }
    }
}

// MARK: - Remote Songs List (A-Z Sectioned)
struct RemoteSongListView: View {
    @ObservedObject var multipeer: MultipeerManager
    @State private var searchText = ""
    @State private var isScrubbing = false
    @State private var scrubLetter = ""
    
    @State private var activeSections: [RemoteSongSection] = []
    // FIXED: Store the active queue once to prevent a massive CPU spike during scrolling
    @State private var activeQueue: [RemoteSongDTO] = []
    
    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(activeSections) { section in
                            // FIXED: Moved the .id() modifier to the outer Section for crash-free target tracking
                            Section(header: Text(section.letter).font(.headline).foregroundColor(.pink).padding(.horizontal).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).background(Color(.systemBackground))) {
                                
                                ForEach(section.songs) { song in
                                    // FIXED: Pass the pre-calculated activeQueue
                                    RemoteSongRow(song: song, queue: activeQueue, multipeer: multipeer, showArtwork: false)
                                    Divider().padding(.leading)
                                }
                            }
                            .id(section.letter)
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
                            
                            if scrubLetter != targetLetter {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                scrubLetter = targetLetter
                                // FIXED: Added live scrolling while your finger drags
                                proxy.scrollTo(targetLetter, anchor: .top)
                            }
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
        .onAppear {
            if multipeer.remoteLibrary.isEmpty { multipeer.sendCommand("REQUEST_LIBRARY") }
        }
        .task(id: searchText) { await calculateSections() }
        .task(id: multipeer.remoteLibrary) { await calculateSections() }
    }
    
    private func calculateSections() async {
        if !searchText.isEmpty { try? await Task.sleep(nanoseconds: 250_000_000); if Task.isCancelled { return } }
        
        let currentSearch = searchText
        let source = multipeer.remoteAlbums
        let currentSort = sortType
        let currentFilter = filterType
        let currentGenre = selectedGenre
        let fullLibrary = multipeer.remoteLibrary
        
        // Safely extract download state before the detached task
        let multipeer = MultipeerManager.shared
        let downloadedAlbums = Set(DownloadsManager.shared.downloadedSongs.map { $0.album })
        let downloadingAlbums = Set(multipeer.downloadQueue.map { $0.album })
        var activeAlbumName: String? = nil
        if let activeId = multipeer.activeDownloadId {
            activeAlbumName = multipeer.remoteLibrary.first(where: { $0.id == activeId })?.album ?? multipeer.remoteContextQueue.first(where: { $0.id == activeId })?.album
        }
        
        let results = await Task.detached { () -> ([RemoteAlbumSection], [String]) in
            var filtered = source
            
            // 0. Extract Available Genres dynamically
            let albumGenres = Dictionary(grouping: fullLibrary, by: { $0.album }).mapValues { $0.first?.genre ?? "Unknown" }
            let uniqueGenres = ["All Genres"] + Array(Set(albumGenres.values)).sorted()
            
            // 1. Filter Logic
            let albumCounts = Dictionary(grouping: fullLibrary, by: { $0.album }).mapValues { $0.count }
            if currentFilter == .full {
                filtered = filtered.filter { (albumCounts[$0.name] ?? 0) >= 4 }
            } else if currentFilter == .downloaded {
                // Keep albums with downloaded songs AND albums currently in the queue
                filtered = filtered.filter { album in
                    downloadedAlbums.contains(album.name) ||
                    downloadingAlbums.contains(album.name) ||
                    album.name == activeAlbumName
                }
            }
            
            // 2. Filter by Genre
            if currentGenre != "All Genres" {
                filtered = filtered.filter { (albumGenres[$0.name] ?? "Unknown") == currentGenre }
            }
            
            // 3. Search
            if !currentSearch.isEmpty {
                filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(currentSearch) || $0.artist.localizedCaseInsensitiveContains(currentSearch) }
            }
            
            // 4. Group by Title or Artist Initial
            let grouped = Dictionary(grouping: filtered) { summary -> String in
                if currentSort == .trackCount { return "#" }
                
                let sortString = currentSort == .artistAZ ? summary.artist : summary.name
                let prefix = sortString.prefix(1).uppercased()
                return prefix.rangeOfCharacter(from: .letters) != nil ? prefix : "#"
            }
            
            let sortedKeys = grouped.keys.sorted { lhs, rhs in
                if lhs == "#" { return false }
                if rhs == "#" { return true }
                return currentSort == .titleZA ? lhs > rhs : lhs < rhs
            }
            
            // 5. Sort within the groups
            let sections = sortedKeys.map { letter in
                let sortedAlbums = (grouped[letter] ?? []).sorted {
                    switch currentSort {
                    case .titleAZ: return $0.name < $1.name
                    case .titleZA: return $0.name > $1.name
                    case .artistAZ:
                        if $0.artist == $1.artist { return $0.name < $1.name }
                        return $0.artist < $1.artist
                    case .trackCount:
                        let count0 = albumCounts[$0.name] ?? 0
                        let count1 = albumCounts[$1.name] ?? 0
                        if count0 == count1 { return $0.name < $1.name }
                        return count0 > count1
                    }
                }
                return RemoteAlbumSection(letter: letter, albums: sortedAlbums)
            }
            
            return (sections, uniqueGenres)
        }.value
        
        if !Task.isCancelled {
            await MainActor.run {
                self.activeSections = results.0
                self.availableGenres = results.1
            }
        }
    }
}

// MARK: - Remote Albums List (Optimized Scrubber)
struct RemoteAlbumListView: View {
    @ObservedObject var multipeer: MultipeerManager
    @State private var searchText = ""
    @State private var isScrubbing = false
    @State private var scrubLetter = ""
    @State private var activeSections: [RemoteAlbumSection] = []
    
    // NEW: Filter & Sort State
    @State private var sortType: AlbumSortType = .titleAZ
    @State private var filterType: AlbumFilterType = .all
    @State private var selectedGenre: String = "All Genres"
    @State private var availableGenres: [String] = ["All Genres"]
    
    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(activeSections) { section in
                            // Hide the literal "#" header if we are sorting by Track Count
                            if sortType != .trackCount {
                                Section(header: Text(section.letter).font(.headline).foregroundColor(.pink).padding(.horizontal).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).background(Color(.systemBackground))) {
                                    EmptyView()
                                }
                            }
                            
                            ForEach(section.albums) { album in
                                NavigationLink(value: RemoteAlbumWrapper(name: album.name, songs: [])) {
                                    HStack(spacing: 16) {
                                        ZStack(alignment: .bottom) {
                                            if let cached = LibraryManager.shared.getCachedRemoteArtwork(albumName: album.name) {
                                                Image(uiImage: cached)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 50, height: 50)
                                                    .cornerRadius(6)
                                                    .clipped()
                                            } else {
                                                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 50, height: 50).cornerRadius(6).overlay(Image(systemName: "square.stack").foregroundColor(.gray))
                                                    .onAppear {
                                                        if let song = multipeer.remoteLibrary.first(where: { $0.album == album.name }) {
                                                            multipeer.requestArtworkLazily(for: song)
                                                        }
                                                    }
                                            }
                                            AlbumProgressOverlay(albumName: album.name)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(album.name).font(.body).foregroundColor(.primary).lineLimit(1)
                                            Text(album.artist).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundColor(.gray.opacity(0.5)).font(.caption)
                                    }
                                    .padding(.horizontal).padding(.vertical, 8).contentShape(Rectangle())
                                }
                                Divider().padding(.leading, 82)
                            }
                            .id(section.letter)
                        }
                        Spacer().frame(height: 100)
                    }.padding(.trailing, 20)
                }
                
                if isScrubbing {
                    VStack { Text(scrubLetter).font(.system(size: 60, weight: .bold)).foregroundColor(.white).frame(width: 100, height: 100).background(Color.black.opacity(0.6).cornerRadius(16)) }.zIndex(100)
                }
                
                // Hide scrubber if sorting by track count
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
                            
                            if scrubLetter != targetLetter {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                scrubLetter = targetLetter
                                proxy.scrollTo(targetLetter, anchor: .top)
                            }
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
        .onAppear { if multipeer.remoteAlbums.isEmpty { multipeer.sendCommand("REQUEST_ALL_ALBUMS") } }
        // NEW: Re-run calculations when filters change
        .task(id: searchText) { await calculateSections() }
        .task(id: multipeer.remoteAlbums) { await calculateSections() }
        .task(id: sortType) { await calculateSections() }
        .task(id: filterType) { await calculateSections() }
        .task(id: selectedGenre) { await calculateSections() }
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
                } label: {
                    let isFiltered = filterType != .all || sortType != .titleAZ || selectedGenre != "All Genres"
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(isFiltered ? .pink : .primary)
                }
            }
        }
    }
    
    private func calculateSections() async {
        if !searchText.isEmpty { try? await Task.sleep(nanoseconds: 250_000_000); if Task.isCancelled { return } }
        
        let currentSearch = searchText
        let source = multipeer.remoteAlbums
        let currentSort = sortType
        let currentFilter = filterType
        let currentGenre = selectedGenre
        let fullLibrary = multipeer.remoteLibrary
        
        let results = await Task.detached { () -> ([RemoteAlbumSection], [String]) in
            var filtered = source
            
            // 0. Extract Available Genres dynamically
            let albumGenres = Dictionary(grouping: fullLibrary, by: { $0.album }).mapValues { $0.first?.genre ?? "Unknown" }
            let uniqueGenres = ["All Genres"] + Array(Set(albumGenres.values)).sorted()
            
            // 1. Calculate and filter out small EPs/Singles
            let albumCounts = Dictionary(grouping: fullLibrary, by: { $0.album }).mapValues { $0.count }
            if currentFilter == .full {
                filtered = filtered.filter { (albumCounts[$0.name] ?? 0) >= 4 }
            }
            
            // 2. Filter by Genre
            if currentGenre != "All Genres" {
                filtered = filtered.filter { (albumGenres[$0.name] ?? "Unknown") == currentGenre }
            }
            
            // 3. Search
            if !currentSearch.isEmpty {
                filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(currentSearch) || $0.artist.localizedCaseInsensitiveContains(currentSearch) }
            }
            
            // 4. Group by Title or Artist Initial
            let grouped = Dictionary(grouping: filtered) { summary -> String in
                if currentSort == .trackCount { return "#" }
                
                let sortString = currentSort == .artistAZ ? summary.artist : summary.name
                let prefix = sortString.prefix(1).uppercased()
                return prefix.rangeOfCharacter(from: .letters) != nil ? prefix : "#"
            }
            
            let sortedKeys = grouped.keys.sorted { lhs, rhs in
                if lhs == "#" { return false }
                if rhs == "#" { return true }
                return currentSort == .titleZA ? lhs > rhs : lhs < rhs
            }
            
            // 5. Sort within the groups
            let sections = sortedKeys.map { letter in
                let sortedAlbums = (grouped[letter] ?? []).sorted {
                    switch currentSort {
                    case .titleAZ: return $0.name < $1.name
                    case .titleZA: return $0.name > $1.name
                    case .artistAZ:
                        if $0.artist == $1.artist { return $0.name < $1.name }
                        return $0.artist < $1.artist
                    case .trackCount:
                        let count0 = albumCounts[$0.name] ?? 0
                        let count1 = albumCounts[$1.name] ?? 0
                        if count0 == count1 { return $0.name < $1.name }
                        return count0 > count1
                    }
                }
                return RemoteAlbumSection(letter: letter, albums: sortedAlbums)
            }
            
            return (sections, uniqueGenres)
        }.value
        
        if !Task.isCancelled {
            await MainActor.run {
                self.activeSections = results.0
                self.availableGenres = results.1
            }
        }
    }
}

// MARK: - Remote Artists List (Optimized Scrubber)
struct RemoteArtistListView: View {
    @ObservedObject var multipeer: MultipeerManager
    @State private var searchText = ""
    @State private var isScrubbing = false
    @State private var scrubLetter = ""
    @State private var activeSections: [RemoteArtistSection] = []
    
    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(activeSections) { section in
                            Section(header: Text(section.letter).font(.headline).foregroundColor(.pink).padding(.horizontal).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).background(Color(.systemBackground))) {
                                ForEach(section.artists, id: \.self) { artistName in
                                    NavigationLink(value: RemoteArtistWrapper(name: artistName, songs: [])) {
                                        Text(artistName).font(.body).foregroundColor(.primary).padding(.horizontal).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    }
                                    Divider().padding(.leading)
                                }
                            }
                            .id(section.letter)
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
                        .padding(.trailing, 2).background(Color.white.opacity(0.001))
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            let letters = activeSections.map { $0.letter }; guard !letters.isEmpty else { return }
                            let index = max(0, min(letters.count - 1, Int(value.location.y / 18)))
                            let targetLetter = letters[index]
                            
                            if scrubLetter != targetLetter {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                scrubLetter = targetLetter
                                proxy.scrollTo(targetLetter, anchor: .top)
                            }
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
        .onAppear { if multipeer.remoteArtists.isEmpty { multipeer.sendCommand("REQUEST_ALL_ARTISTS") } }
        .task(id: searchText) { await calculateSections() }
        .task(id: multipeer.remoteArtists) { await calculateSections() }
    }
    
    private func calculateSections() async {
        let currentSearch = searchText
        let source = multipeer.remoteArtists
        let results = await Task.detached { () -> [RemoteArtistSection] in
            var filtered = source
            if !currentSearch.isEmpty { filtered = filtered.filter { $0.localizedCaseInsensitiveContains(currentSearch) } }
            let grouped = Dictionary(grouping: filtered) { artist -> String in
                let prefix = artist.prefix(1).uppercased()
                return prefix.rangeOfCharacter(from: .letters) != nil ? prefix : "#"
            }
            let sortedKeys = grouped.keys.sorted { lhs, rhs in if lhs == "#" { return false }; if rhs == "#" { return true }; return lhs < rhs }
            return sortedKeys.map { RemoteArtistSection(letter: $0, artists: grouped[$0]?.sorted() ?? []) }
        }.value
        if !Task.isCancelled { await MainActor.run { self.activeSections = results } }
    }
}

// When you tap an Artist, fetch ONLY their songs
struct RemoteArtistDetailView: View {
    let artistName: String
    @ObservedObject var multipeer: MultipeerManager
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(multipeer.remoteContextQueue) { song in
                    RemoteSongRow(song: song, queue: multipeer.remoteContextQueue, multipeer: multipeer, showArtwork: true)
                    Divider().padding(.leading)
                }
                Spacer().frame(height: 100)
            }
        }
        .navigationTitle(artistName)
        .onAppear {
            if !multipeer.remoteContextQueue.contains(where: { $0.artist == artistName }) {
                multipeer.remoteContextQueue = []
            }
            multipeer.sendCommand("REQUEST_ARTIST_SONGS:\(artistName)")
        }
    }
}

// MARK: - Shared UI Row (Remote Cast Row)
struct RemoteSongRow: View {
    let song: RemoteSongDTO
    var queue: [RemoteSongDTO]
    @ObservedObject var multipeer: MultipeerManager
    var showArtwork: Bool = false
    var showTrackNumber: Bool = false
    
    var customPrimaryColor: Color? = nil
    var customSecondaryColor: Color? = nil
    var showArtist: Bool = true
    
    @ObservedObject var library = LibraryManager.shared
    
    var isPlaying: Bool { AudioManager.shared.currentRemoteDTO?.id == song.id }
    
    var hasSynced: Bool {
        if let lines = library.getSyncedLyrics(id: song.id, title: song.title, artist: song.artist) {
            return lines.isFullySynced
        }
        return song.hasSyncedLyrics
    }
    
    var hasCustomRaw: Bool {
        return library.customRawLyrics[song.id] != nil && !library.customRawLyrics[song.id]!.isEmpty
    }
    
    var showUnfilledBubble: Bool {
        return hasCustomRaw || song.hasLyrics
    }
    
    var isDownloading: Bool { multipeer.activeDownloadId == song.id }
    var isQueued: Bool { multipeer.downloadQueue.contains { $0.id == song.id } }
    
    var body: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: 12)
            
            if hasSynced {
                Image(systemName: "quote.bubble.fill").font(.caption2).foregroundColor(customSecondaryColor ?? .pink).frame(width: 12)
            } else if showUnfilledBubble {
                Image(systemName: "quote.bubble").font(.caption2).foregroundColor(customSecondaryColor ?? .gray).frame(width: 12)
            } else {
                Color.clear.frame(width: 12)
            }
            
            if showTrackNumber {
                if song.trackNumber > 0 {
                    Text("\(song.trackNumber)").font(.caption).monospacedDigit().foregroundColor(customSecondaryColor ?? .gray).frame(width: 20, alignment: .trailing)
                } else {
                    Color.clear.frame(width: 20)
                }
            }
            
            if showArtwork {
                if let cached = library.getCachedRemoteArtwork(albumName: song.album) {
                    Image(uiImage: cached).resizable().frame(width: 40, height: 40).cornerRadius(6)
                } else if let data = song.artworkData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage).resizable().frame(width: 40, height: 40).cornerRadius(6)
                } else {
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 40, height: 40).cornerRadius(6).overlay(Image(systemName: "music.note").foregroundColor(.gray))
                        .onAppear { multipeer.requestArtworkLazily(for: song) }
                }
            }
            Spacer().frame(width: 4)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.subheadline)
                    .fontWeight(isPlaying ? .bold : .regular)
                    .foregroundColor(isPlaying ? .pink : (customPrimaryColor ?? .primary))
                    .lineLimit(1)
                
                if showArtist {
                    Text(song.artist)
                        .font(.caption)
                        .foregroundColor(customSecondaryColor ?? .secondary)
                        .lineLimit(1)
                }
            }
            .frame(minHeight: 36, alignment: .center)
            Spacer()
            
            Menu {
                if isDownloading {
                    Text("Downloading...")
                } else if isQueued {
                    Text("Queued...")
                } else {
                    Button { multipeer.enqueueDownloads(songs: [song]) } label: { Label("Download to iPhone", systemImage: "arrow.down.circle") }
                }
                Button { multipeer.sendCommand("PLAY_SONG:\(song.id)") } label: { Label("Play on Mac", systemImage: "macwindow") }
            } label: {
                if isDownloading, let task = multipeer.currentDownloads.values.first(where: { $0.metadata?.title == song.title && $0.metadata?.album == song.album }) {
                    ZStack {
                        Circle().stroke(Color.pink.opacity(0.3), lineWidth: 2)
                        Circle().trim(from: 0, to: task.fractionCompleted)
                            .stroke(Color.pink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.2), value: task.fractionCompleted)
                    }.frame(width: 20, height: 20).padding(5)
                } else if isDownloading {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .pink)).frame(width: 20, height: 20).padding(5)
                } else if isQueued {
                    Image(systemName: "arrow.down.circle.dotted").foregroundColor(.gray).font(.title3).frame(width: 30, height: 30)
                } else {
                    Image(systemName: "ellipsis").foregroundColor(.pink).font(.title3).frame(width: 30, height: 30).contentShape(Rectangle())
                }
            }
            .highPriorityGesture(TapGesture())
        }
        .frame(minHeight: 50)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            AudioManager.shared.playStream(remoteSong: song, queue: queue)
        }
    }
}

enum AlbumFilterType: String, CaseIterable {
    case all = "All Albums"
    case full = "Full Albums Only"
    case downloaded = "Downloaded"
}

// MARK: - Unified Album State
enum AlbumSongCollection {
    case downloads([LocalSong])
    case remote([RemoteSongDTO])
}

struct UniversalAlbumDetailView: View {
    let albumName: String
    let collection: AlbumSongCollection
    @Environment(\.dismiss) var dismiss
    
    @ObservedObject var downloads = DownloadsManager.shared
    @ObservedObject var multipeer = MultipeerManager.shared
    @ObservedObject var library = LibraryManager.shared
    @ObservedObject var audioManager = AudioManager.shared
    
    @State private var showAlbumSettings = false
    
    var albumID: String { "local_\(albumName)" }
    
    var customBgColor: Color? {
        if let hex = library.customAlbumColors[albumID] { return Color(customHex: hex) }
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
    
    var computedActiveSongs: AlbumSongCollection {
        // ALWAYS Prioritize the full remote tracklist if we are connected to the Mac!
        // This stops the view from "erasing" non-downloaded songs when the download finishes.
        if multipeer.connectionState == .connected, !multipeer.remoteContextQueue.isEmpty, multipeer.remoteContextQueue.first?.album == albumName {
            let current = multipeer.remoteContextQueue.sorted {
                let d0 = $0.discNumber ?? 1
                let d1 = $1.discNumber ?? 1
                if d0 == d1 {
                    if $0.trackNumber == $1.trackNumber { return $0.title < $1.title }
                    if $0.trackNumber == 0 { return false }
                    if $1.trackNumber == 0 { return true }
                    return $0.trackNumber < $1.trackNumber
                }
                return d0 < d1
            }
            return .remote(current)
        }
        
        // Fallback for Local/Offline Playback
        switch collection {
        case .downloads(_):
            let current = downloads.downloadedSongs
                .filter { $0.album == albumName }
                .sorted {
                    let d0 = $0.discNumber ?? 1
                    let d1 = $1.discNumber ?? 1
                    if d0 == d1 {
                        if $0.trackNumber == $1.trackNumber { return $0.title < $1.title }
                        if $0.trackNumber == 0 { return false }
                        if $1.trackNumber == 0 { return true }
                        return $0.trackNumber < $1.trackNumber
                    }
                    return d0 < d1
                }
            return .downloads(current)
            
        case .remote(let passedSongs):
            let source = multipeer.remoteContextQueue.isEmpty ? passedSongs : multipeer.remoteContextQueue
            let current = source.sorted { $0.trackNumber < $1.trackNumber }
            return .remote(current)
        }
    }
    
    var body: some View {
        let activeSongs = computedActiveSongs
        
        let isDisconnectedRemote = {
            if case .remote(_) = activeSongs {
                return multipeer.connectionState != .connected
            }
            return false
        }()
        
        let isCurrentAlbum: Bool = {
            switch activeSongs {
            case .downloads(let localSongs):
                return localSongs.contains(where: { $0.id == audioManager.currentLocalSong?.id })
            case .remote(let remoteSongs):
                return remoteSongs.contains(where: { $0.id == audioManager.currentRemoteDTO?.id })
            }
        }()
        let isPlayingThisAlbum = audioManager.isPlaying && isCurrentAlbum
        
        let artistName: String = { switch activeSongs { case .downloads(let songs): return songs.first?.artist ?? "Unknown Artist"; case .remote(let songs): return songs.first?.artist ?? "Unknown Artist" } }()
        let songCount: Int = { switch activeSongs { case .downloads(let songs): return songs.count; case .remote(let songs): return songs.count } }()
        let totalDuration: TimeInterval = { switch activeSongs { case .downloads(let songs): return songs.reduce(0) { $0 + $1.duration }; case .remote(let songs): return songs.reduce(0) { $0 + $1.duration } } }()
        let albumGenre: String = { switch activeSongs { case .downloads(let songs): return songs.first?.genre ?? "Album"; case .remote(let songs): return songs.first?.genre ?? "Album" } }()
        
        let isDownloading = multipeer.downloadQueue.contains(where: { $0.album == albumName }) ||
                            (multipeer.activeDownloadId != nil && (multipeer.remoteLibrary.first(where: { $0.id == multipeer.activeDownloadId })?.album == albumName || multipeer.remoteContextQueue.first(where: { $0.id == multipeer.activeDownloadId })?.album == albumName)) ||
                            !multipeer.currentDownloads.values.filter { $0.metadata?.album == albumName }.isEmpty
                            
        let isEdgeToEdge = library.isEdgeToEdgeEnabled(for: albumID) == true
        
        let originalArtwork: UIImage? = {
            switch activeSongs {
            case .downloads(let songs):
                if let data = songs.first?.artworkData { return UIImage(data: data) }
            case .remote(let songs):
                if let cached = library.getCachedRemoteArtwork(albumName: albumName) { return cached }
                if let data = songs.first?.artworkData { return UIImage(data: data) }
            }
            return nil
        }()
        
        ZStack {
            if let hex = library.customAlbumColors[albumID] { Color(customHex: hex).ignoresSafeArea() }
            else { Color(.systemBackground).ignoresSafeArea() }
            
            ScrollView {
                VStack(spacing: 0) {
                    
                    if isEdgeToEdge {
                        VStack(spacing: 0) {
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
                                    
                                    if let videoURL = library.albumVideoArt[albumID] {
                                        AnimatedVideoArtView(videoURL: videoURL, crop: library.albumArtCrops[albumID])
                                            .frame(width: geo.size.width, height: geo.size.height + overscroll, alignment: .bottom)
                                            .clipped()
                                            .offset(y: scrollUpOffset)
                                            .mask(
                                                LinearGradient(
                                                    stops: [
                                                        .init(color: .black, location: 0.0),
                                                        .init(color: .black, location: 0.85),
                                                        .init(color: .clear, location: 1.0)
                                                    ],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                )
                                                .ignoresSafeArea()
                                                .offset(y: -scrollUpOffset)
                                            )
                                            .offset(y: -overscroll)
                                            
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
                                                LinearGradient(
                                                    stops: [
                                                        .init(color: .black, location: 0.0),
                                                        .init(color: .black, location: 0.85),
                                                        .init(color: .clear, location: 1.0)
                                                    ],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                )
                                                .ignoresSafeArea()
                                                .offset(y: -scrollUpOffset)
                                            )
                                            .offset(y: -overscroll)
                                    } else {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: geo.size.width, height: geo.size.height + overscroll, alignment: .bottom)
                                            .clipped()
                                            .offset(y: scrollUpOffset)
                                            .mask(
                                                LinearGradient(
                                                    stops: [
                                                        .init(color: .black, location: 0.0),
                                                        .init(color: .black, location: 0.85),
                                                        .init(color: .clear, location: 1.0)
                                                    ],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                )
                                                .ignoresSafeArea()
                                                .offset(y: -scrollUpOffset)
                                            )
                                            .offset(y: -overscroll)
                                    }
                                }
                                .aspectRatio(aspect, contentMode: .fit)

                                HStack(spacing: 24) {
                                    Button(action: { shuffleAlbum(songs: activeSongs) }) {
                                        Image(systemName: "shuffle")
                                            .font(.title3.bold())
                                            .foregroundColor(albumTextColor)
                                            .frame(width: 50, height: 50)
                                            .background(albumTextColor.opacity(0.1))
                                            .background(Material.ultraThin)
                                            .clipShape(Circle())
                                            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                                    }
                                    
                                    Button(action: {
                                        if isCurrentAlbum {
                                            audioManager.togglePlayPause()
                                        } else {
                                            playAlbum(songs: activeSongs)
                                        }
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: isPlayingThisAlbum ? "pause.fill" : "play.fill")
                                            Text(isPlayingThisAlbum ? "Pause" : "Play")
                                        }
                                        .font(.title3.bold())
                                        .foregroundColor(customBgColor != nil ? customBgColor : Color(.systemBackground))
                                        .frame(width: 140, height: 50)
                                        .background(albumTextColor)
                                        .clipShape(Capsule())
                                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                                    }
                                    
                                    Button(action: {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        library.togglePin(localAlbumName: albumName)
                                    }) {
                                        Image(systemName: library.isPinned(localAlbumName: albumName) ? "checkmark" : "plus")
                                            .font(.title3.bold())
                                            .foregroundColor(albumTextColor)
                                            .frame(width: 50, height: 50)
                                            .background(albumTextColor.opacity(0.1))
                                            .background(Material.ultraThin)
                                            .clipShape(Circle())
                                            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                                    }
                                }
                                .offset(y: 30)
                                .opacity(isDisconnectedRemote ? 0.4 : 1.0)
                                .disabled(isDisconnectedRemote)
                            }
                            .padding(.bottom, 46)

                            VStack(spacing: 4) {
                                if library.albumShowTitlePrefs[albumID] ?? true {
                                    Text(albumName).font(.title2).bold().multilineTextAlignment(.center).foregroundColor(albumTextColor)
                                }
                                Text(artistName).font(.title3).foregroundColor(albumTextColor.opacity(0.8))
                                Text("\(albumGenre) · \(songCount) Songs · \(formatRuntime(totalDuration))")
                                    .font(.caption).foregroundColor(albumTextColor.opacity(0.6)).padding(.top, 2)
                            }
                            .padding(.horizontal, 20)

                            if case .remote(let remoteQueue) = activeSongs {
                                if isDownloading {
                                    Button(action: { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); multipeer.cancelDownloads(for: albumName) }) {
                                        HStack { Image(systemName: "xmark.circle.fill"); Text("Cancel Download") }.font(.headline).foregroundColor(.red).padding(.vertical, 8).padding(.horizontal, 16).background(Color.red.opacity(0.1)).cornerRadius(20)
                                    }.padding(.top, 16)
                                } else if songCount > 0 {
                                    Button(action: { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); multipeer.enqueueDownloads(songs: remoteQueue) }) {
                                        HStack { Image(systemName: "arrow.down.circle.fill"); Text("Download Album") }.font(.headline).foregroundColor(.pink).padding(.vertical, 8).padding(.horizontal, 16).background(Color.pink.opacity(0.1)).cornerRadius(20)
                                    }.padding(.top, 16)
                                }
                            }

                            if let desc = library.customAlbumDescriptions[albumID], !desc.isEmpty {
                                let currentBgColor = library.customAlbumColors[albumID] != nil ? Color(customHex: library.customAlbumColors[albumID]!) : Color(.systemBackground)
                                
                                ExpandableDescriptionView(
                                    text: desc,
                                    albumTitle: albumName,
                                    backgroundColor: currentBgColor,
                                    textColor: songTextColor
                                )
                                .padding(.horizontal, 24)
                                .padding(.top, 16)
                            }
                            
                            Spacer().frame(height: 20)
                        }
                        .padding(.top, 0)
                    } else {
                        VStack(spacing: 16) {
                            if let videoURL = library.albumVideoArt[albumID] {
                                AnimatedVideoArtView(videoURL: videoURL, crop: library.albumArtCrops[albumID])
                                    .frame(width: 250, height: 250)
                                    .cornerRadius(12)
                                    .shadow(radius: 10)
                            } else if let img = originalArtwork {
                                Image(uiImage: img).resizable().aspectRatio(contentMode: .fit).frame(width: 250, height: 250).cornerRadius(12).shadow(radius: 10)
                            } else {
                                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 250, height: 250).cornerRadius(12)
                            }
                            
                            VStack(spacing: 4) {
                                if library.albumShowTitlePrefs[albumID] ?? true {
                                    Text(albumName).font(.title2).bold().multilineTextAlignment(.center).foregroundColor(albumTextColor)
                                }
                                Text(artistName).font(.title3).foregroundColor(albumTextColor.opacity(0.8))
                                Text("\(albumGenre) · \(songCount) Songs · \(formatRuntime(totalDuration))")
                                    .font(.caption).foregroundColor(albumTextColor.opacity(0.6)).padding(.top, 2)
                            }
                            .padding(.horizontal, 20)
                            
                            HStack(spacing: 24) {
                                Button(action: { shuffleAlbum(songs: activeSongs) }) {
                                    Image(systemName: "shuffle")
                                        .font(.title3.bold())
                                        .foregroundColor(albumTextColor)
                                        .frame(width: 50, height: 50)
                                        .background(albumTextColor.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                
                                Button(action: {
                                    if isCurrentAlbum {
                                        audioManager.togglePlayPause()
                                    } else {
                                        playAlbum(songs: activeSongs)
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: isPlayingThisAlbum ? "pause.fill" : "play.fill")
                                        Text(isPlayingThisAlbum ? "Pause" : "Play")
                                    }
                                    .font(.title3.bold())
                                    .foregroundColor(customBgColor != nil ? customBgColor : Color(.systemBackground))
                                    .frame(width: 140, height: 50)
                                    .background(albumTextColor)
                                    .clipShape(Capsule())
                                }
                                
                                Button(action: {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    library.togglePin(localAlbumName: albumName)
                                }) {
                                    Image(systemName: library.isPinned(localAlbumName: albumName) ? "checkmark" : "plus")
                                        .font(.title3.bold())
                                        .foregroundColor(albumTextColor)
                                        .frame(width: 50, height: 50)
                                        .background(albumTextColor.opacity(0.1))
                                        .clipShape(Circle())
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            if case .remote(let remoteQueue) = activeSongs {
                                if isDownloading {
                                    Button(action: { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); multipeer.cancelDownloads(for: albumName) }) {
                                        HStack { Image(systemName: "xmark.circle.fill"); Text("Cancel Download") }.font(.headline).foregroundColor(.red).padding(.vertical, 8).padding(.horizontal, 16).background(Color.red.opacity(0.1)).cornerRadius(20)
                                    }.padding(.top, 4)
                                } else if songCount > 0 {
                                    Button(action: { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); multipeer.enqueueDownloads(songs: remoteQueue) }) {
                                        HStack { Image(systemName: "arrow.down.circle.fill"); Text("Download Album") }.font(.headline).foregroundColor(.pink).padding(.vertical, 8).padding(.horizontal, 16).background(Color.pink.opacity(0.1)).cornerRadius(20)
                                    }.padding(.top, 4)
                                }
                            }
                            
                            if let desc = library.customAlbumDescriptions[albumID], !desc.isEmpty {
                                let currentBgColor = library.customAlbumColors[albumID] != nil ? Color(customHex: library.customAlbumColors[albumID]!) : Color(.systemBackground)
                                ExpandableDescriptionView(text: desc, albumTitle: albumName, backgroundColor: currentBgColor)
                                    .padding(.horizontal, 24)
                                    .padding(.top, 8)
                            }
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 20)
                        .opacity(isDisconnectedRemote ? 0.4 : 1.0)
                        .disabled(isDisconnectedRemote)
                    }

                    LazyVStack(spacing: 0) {
                        if songCount == 0 && multipeer.connectionState == .connected {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .padding(.top, 40)
                                Text("Fetching from Mac...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            switch activeSongs {
                            case .downloads(let localQueue):
                                let grouped = Dictionary(grouping: localQueue, by: { $0.discNumber ?? 1 })
                                let discs = grouped.keys.sorted()
                                let showHeaders = discs.count > 1
                                let showArtist = library.albumShowArtistPrefs[albumID] ?? true
                                
                                ForEach(discs, id: \.self) { disc in
                                    if showHeaders {
                                        HStack { Text("Disc \(disc)").font(.headline).foregroundColor(albumTextColor); Spacer() }
                                            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 4)
                                        Divider().padding(.leading, 20)
                                    }
                                    ForEach(grouped[disc]!) { song in
                                        DownloadsSongRow(
                                            song: song,
                                            queue: localQueue,
                                            showArtwork: false,
                                            showTrackNumber: true,
                                            customPrimaryColor: songTextColor,
                                            customSecondaryColor: songTextColor.opacity(0.7),
                                            showArtist: showArtist
                                        )
                                        Divider()
                                            .overlay(customBgColor != nil ? .white.opacity(0.2) : Color.gray.opacity(0.2))
                                            .padding(.leading, 54)
                                    }
                                }
                                
                            case .remote(let remoteQueue):
                                let grouped = Dictionary(grouping: remoteQueue, by: { $0.discNumber ?? 1 })
                                let discs = grouped.keys.sorted()
                                let showHeaders = discs.count > 1
                                ForEach(discs, id: \.self) { disc in
                                    if showHeaders {
                                        HStack { Text("Disc \(disc)").font(.headline).foregroundColor(.primary); Spacer() }
                                            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 4)
                                        Divider().padding(.leading, 20)
                                    }
                                    ForEach(grouped[disc]!) { song in
                                        RemoteSongRow(song: song, queue: remoteQueue, multipeer: multipeer, showArtwork: false, showTrackNumber: true)
                                            .opacity(isDisconnectedRemote ? 0.4 : 1.0)
                                            .disabled(isDisconnectedRemote)
                                        Divider().padding(.leading)
                                    }
                                }
                            }
                        }
                    }
                    Spacer().frame(height: 100)
                }
            }
        }
        .coordinateSpace(name: "albumScroll")
        .ignoresSafeArea(edges: library.isEdgeToEdgeEnabled(for: albumID) == true ? .top : [])
        .onAppear {
            // Fetch full remote tracklist regardless of how the album was opened,
            // as long as we are connected to the Mac!
            if multipeer.connectionState == .connected {
                multipeer.remoteContextQueue = []
                multipeer.sendCommand("REQUEST_ALBUM_SONGS:\(albumName)")
            }
        }
        .onChange(of: multipeer.remoteContextQueue) { newQueue in
            if case .remote(_) = collection {
                if let firstSong = newQueue.first {
                    multipeer.requestArtworkLazily(for: firstSong)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .tabBar)
        .toolbarBackground(library.isEdgeToEdgeEnabled(for: albumID) == true ? .hidden : .automatic, for: .navigationBar)
        .sheet(isPresented: $showAlbumSettings) {
            AlbumSettingsSheet(albumID: albumID, artworkImage: originalArtwork)
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
                        if case .downloads(_) = activeSongs {
                            Button { library.togglePin(localAlbumName: albumName) } label: { Label(library.isPinned(localAlbumName: albumName) ? "Unpin Album" : "Pin to Library", systemImage: library.isPinned(localAlbumName: albumName) ? "pin.slash" : "pin") }
                            Button(role: .destructive) { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); DownloadsManager.shared.deleteAlbum(albumName: albumName); dismiss() } label: { Label("Delete Album", systemImage: "trash") }
                        } else if case .remote(let remoteQueue) = activeSongs {
                            if isDownloading {
                                Button(role: .destructive) { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); multipeer.cancelDownloads(for: albumName) } label: { Label("Cancel Download", systemImage: "xmark.circle") }
                            } else {
                                Button { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); multipeer.enqueueDownloads(songs: remoteQueue) } label: { Label("Download Album", systemImage: "arrow.down.circle") }
                            }
                        }
                    } label: { Image(systemName: "ellipsis.circle").foregroundColor(.pink) }
                }
            }
        }
        .onChange(of: songCount) { count in
            if count == 0 {
                if case .downloads(_) = collection {
                    dismiss()
                }
            }
        }
    }
    
    func formatRuntime(_ duration: TimeInterval) -> String {
        if duration == 0 { return "" }
        let h = Int(duration) / 3600
        let m = (Int(duration) % 3600) / 60
        if h > 0 { return "\(h) hr \(m) min" }
        return "\(m) min"
    }
    enum AlbumFilterType: String, CaseIterable {
        case all = "All Albums"
        case full = "Full Albums Only"
        case downloaded = "Downloaded"
    }
    func playAlbum(songs: AlbumSongCollection) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        switch songs {
        case .downloads(let localSongs):
            if let first = localSongs.first { AudioManager.shared.play(localSong: first, queue: localSongs) }
        case .remote(let remoteSongs):
            if let first = remoteSongs.first { AudioManager.shared.playStream(remoteSong: first, queue: remoteSongs) }
        }
    }
    
    func shuffleAlbum(songs: AlbumSongCollection) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        AudioManager.shared.isShuffled = true
        switch songs {
        case .downloads(let localSongs):
            let shuffled = localSongs.shuffled(); if let first = shuffled.first { AudioManager.shared.play(localSong: first, queue: shuffled) }
        case .remote(let remoteSongs):
            let shuffled = remoteSongs.shuffled(); if let first = shuffled.first { AudioManager.shared.playStream(remoteSong: first, queue: shuffled) }
        }
    }
}
// MARK: - Live Album Progress Overlay
struct AlbumProgressOverlay: View {
    let albumName: String
    @ObservedObject var multipeer = MultipeerManager.shared
    @State private var progress: Double = 0
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        let albumTasks = multipeer.currentDownloads.values.filter { $0.metadata?.album == albumName }
        let queuedCount = multipeer.downloadQueue.filter { $0.album == albumName }.count
        let isActiveHere = multipeer.activeDownloadId != nil && (multipeer.remoteLibrary.first(where: { $0.id == multipeer.activeDownloadId })?.album == albumName || multipeer.remoteContextQueue.first(where: { $0.id == multipeer.activeDownloadId })?.album == albumName)

        if !albumTasks.isEmpty || queuedCount > 0 || isActiveHere {
            ZStack(alignment: .leading) {
                Rectangle().fill(Material.ultraThin).frame(height: 30)
                GeometryReader { geo in
                    Rectangle().fill(Color.pink.opacity(0.6)).frame(width: geo.size.width * CGFloat(progress))
                        .animation(.linear(duration: 0.1), value: progress)
                }
                Text(albumTasks.isEmpty ? "Queued (\(queuedCount))..." : "Downloading...").font(.caption2.bold()).foregroundColor(.white).padding(.leading, 8)
            }
            .frame(height: 30)
            .onReceive(timer) { _ in
                let currentTasks = multipeer.currentDownloads.values.filter { $0.metadata?.album == albumName }
                if !currentTasks.isEmpty {
                    progress = currentTasks.reduce(0) { $0 + $1.fractionCompleted } / Double(currentTasks.count)
                } else {
                    progress = 0
                }
            }
        }
    }
}
#endif
