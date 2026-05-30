import SwiftUI
import Combine

struct MacRemotePlayerView: View {
    @ObservedObject var multipeer: MultipeerManager
    @Binding var showRemotePlayer: Bool
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Blurred Background
                Group {
                    if let data = multipeer.remoteArtworkData, let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 80)
                            .overlay(Color.black.opacity(0.6))
                    } else {
                        Color.black
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                
                if let payload = multipeer.latestPayload {
                    if !multipeer.remoteSyncedLyrics.isEmpty {
                        // MARK: - Split Layout for Lyrics
                        HStack(spacing: 60) {
                            VStack {
                                Spacer()
                                if let data = multipeer.remoteArtworkData, let nsImage = NSImage(data: data) {
                                    Image(nsImage: nsImage).resizable().aspectRatio(contentMode: .fit)
                                        .cornerRadius(24)
                                        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 15)
                                } else {
                                    Rectangle().fill(Color.white.opacity(0.05)).aspectRatio(1.0, contentMode: .fit)
                                        .cornerRadius(24).overlay(Image(systemName: "music.note").font(.system(size: 80)).foregroundColor(.white.opacity(0.2)))
                                }
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(payload.title).font(.system(size: 46, weight: .bold)).foregroundColor(.white).lineLimit(2)
                                    Text(payload.artist).font(.system(size: 32, weight: .medium)).foregroundColor(.white.opacity(0.7)).lineLimit(1)
                                }
                                .padding(.top, 30)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Spacer()
                            }
                            .frame(width: geo.size.width * 0.35)
                            
                            MacRemoteLyricsView(multipeer: multipeer)
                                .frame(width: geo.size.width * 0.5)
                        }
                        .padding(80)
                    } else {
                        // MARK: - Full Screen Centered Layout
                        VStack(spacing: 40) {
                            if let data = multipeer.remoteArtworkData, let nsImage = NSImage(data: data) {
                                Image(nsImage: nsImage).resizable().aspectRatio(contentMode: .fit)
                                    .frame(height: geo.size.height * 0.55)
                                    .cornerRadius(32).shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 20)
                            } else {
                                Rectangle().fill(Color.white.opacity(0.05)).aspectRatio(1.0, contentMode: .fit)
                                    .frame(height: geo.size.height * 0.55)
                                    .cornerRadius(32).overlay(Image(systemName: "music.note").font(.system(size: 150)).foregroundColor(.white.opacity(0.2)))
                            }
                            
                            VStack(spacing: 16) {
                                Text(payload.title).font(.system(size: 86, weight: .bold)).foregroundColor(.white).multilineTextAlignment(.center).lineLimit(2)
                                Text(payload.artist).font(.system(size: 56, weight: .medium)).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    Image(systemName: "music.note").font(.system(size: 150)).foregroundColor(.white.opacity(0.2))
                }
                
                // Exit Button
                VStack {
                    HStack {
                        Button(action: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { showRemotePlayer = false }
                        }) {
                            Image(systemName: "xmark").font(.title2.bold()).foregroundColor(.white).padding(16).background(Circle().fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(30)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Cinematic 4K AirPlay Lyrics Viewer
struct MacRemoteLyricsView: View {
    @ObservedObject var multipeer: MultipeerManager
    
    @State private var playbackLineIndex: Int = -1
    @State private var playbackGapIndex: Int = -1
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                let lines = multipeer.remoteSyncedLyrics
                if !lines.isEmpty {
                    ScrollViewReader { scrollProxy in
                        ScrollView(showsIndicators: false) {
                            // 1. MASSIVE SPACING (Provides room for the scale-down effect)
                            VStack(spacing: 140) {
                                
                                // Top Spacer
                                Color.clear.frame(height: geo.size.height / 2 - 100)
                                
                                ForEach(Array(lines.enumerated()), id: \.offset) { i, lineData in
                                    
                                    // Instrumental Gap Line
                                    if playbackGapIndex == i {
                                        Capsule()
                                            .fill(Color.red)
                                            .frame(width: 140, height: 10)
                                            .id("gap_\(i)")
                                            .transition(.opacity.combined(with: .scale))
                                    }
                                    
                                    let isCurrentLine = (i == playbackLineIndex)
                                    let isPast = (i < playbackLineIndex)
                                    let isInstrumental = lineData.text == "[Instrumental]"
                                    
                                    Group {
                                        if isInstrumental {
                                            if isCurrentLine {
                                                PulsingDots(isPlaying: multipeer.latestPayload?.isPlaying ?? true)
                                                    .scaleEffect(3.0)
                                                    .padding(.vertical, 40)
                                            } else {
                                                Text("•••")
                                                    .font(.system(size: 90, weight: .black))
                                                    .foregroundColor(.white.opacity(0.1))
                                                    .padding(.vertical, 40)
                                            }
                                        } else {
                                            Text(lineData.text)
                                                .font(.system(size: 110, weight: .black))
                                                .foregroundColor(isCurrentLine ? .red : .white)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(nil)
                                                .fixedSize(horizontal: false, vertical: true)
                                                
                                                // 2. AGGRESSIVE SCALE CONTRAST (Inactive is much smaller)
                                                .scaleEffect(isCurrentLine ? 1.0 : 0.55, anchor: .center)
                                                
                                                // 3. SMOOTH OPACITY & BLUR
                                                .opacity(isCurrentLine ? 1.0 : (isPast ? 0.15 : 0.3))
                                                .blur(radius: isCurrentLine ? 0 : 2.0)
                                                
                                                .shadow(color: Color.black.opacity(isCurrentLine ? 0.4 : 0), radius: 25, x: 0, y: 15)
                                        }
                                    }
                                    .id(i)
                                    // 4. SLOWER MODIFIER SPRING (Makes text feel like it's morphing)
                                    .animation(.spring(response: 0.9, dampingFraction: 0.85), value: playbackLineIndex)
                                }
                                
                                if playbackGapIndex == lines.count {
                                    Capsule().fill(Color.red).frame(width: 140, height: 10).id("gap_end")
                                }
                                
                                // Bottom Spacer
                                Color.clear.frame(height: geo.size.height / 2)
                            }
                            .padding(.horizontal, 60)
                        }
                        .scrollDisabled(true)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .black, location: 0.25),
                                    .init(color: .black, location: 0.75),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
                            // Adding a touch more look-ahead (0.3s) to make transitions feel predictive
                            let time = (multipeer.latestPayload?.currentTime ?? 0) + 0.3
                            var activeL = -1
                            var gapL = -1
                            
                            for (index, line) in lines.enumerated() {
                                let nextStartTime = (index + 1 < lines.count) ? lines[index + 1].startTime : .infinity
                                if time >= line.startTime && time < nextStartTime {
                                    if let end = line.endTime, time > end {
                                        gapL = index + 1
                                        activeL = -1
                                    } else {
                                        activeL = index
                                        gapL = -1
                                    }
                                    break
                                }
                            }
                            
                            if activeL != playbackLineIndex || gapL != playbackGapIndex {
                                // 5. HEAVY CINEMATIC SCROLL (response 1.2 is the key to removing jerkiness)
                                withAnimation(.spring(response: 1.2, dampingFraction: 0.9)) {
                                    playbackLineIndex = activeL
                                    playbackGapIndex = gapL
                                    
                                    if activeL >= 0 {
                                        scrollProxy.scrollTo(activeL, anchor: .center)
                                    } else if gapL >= 0 {
                                        let id = (gapL == lines.count) ? "gap_end" : "gap_\(gapL)"
                                        scrollProxy.scrollTo(id, anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Liquid Pulsing Dots
struct PulsingDots: View {
    var isPlaying: Bool
    @State private var pulse = false
    
    var body: some View {
        HStack(spacing: 24) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.red)
                    .frame(width: 18, height: 18)
                    .scaleEffect(pulse && isPlaying ? 1.4 : 1.0)
                    .opacity(pulse && isPlaying ? 1.0 : 0.2)
                    .animation(
                        isPlaying ?
                        Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(Double(i) * 0.25) :
                        .easeInOut(duration: 0.4),
                        value: pulse
                    )
            }
        }
        .onAppear { pulse = true }
    }
}

