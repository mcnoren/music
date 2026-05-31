import AVKit
import SwiftUI

struct AnimatedVideoArtView: UIViewRepresentable {
    let videoURL: URL
    var crop: AlbumArtCrop? = nil
    
    func makeUIView(context: Context) -> VideoPlayerView {
        return VideoPlayerView(videoURL: videoURL, crop: crop)
    }
    
    func updateUIView(_ uiView: VideoPlayerView, context: Context) {
        uiView.update(url: videoURL, crop: crop)
    }
}

class VideoPlayerView: UIView {
    private var playerLayer = AVPlayerLayer()
    private var looper: AVPlayerLooper?
    private var currentPlayer: AVQueuePlayer?
    private var statusObserver: NSKeyValueObservation?
    
    private var currentURL: URL?
    private var currentCrop: AlbumArtCrop?
    
    init(videoURL: URL, crop: AlbumArtCrop?) {
        super.init(frame: .zero)
        self.currentCrop = crop
        backgroundColor = .clear
        setupPlayer(url: videoURL)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupPlayer(url: URL) {
        currentURL = url
        
        // 1. Clean up previous player and observers
        currentPlayer?.pause()
        statusObserver?.invalidate()
        looper = nil
        
        // 2. Standard Setup
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        
        // Ensure it doesn't fight for audio or screen sleep
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        if #available(iOS 15.0, *) {
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        }
        
        looper = AVPlayerLooper(player: player, templateItem: item)
        
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        if playerLayer.superlayer == nil {
            layer.addSublayer(playerLayer)
        }
        
        self.currentPlayer = player
        player.play()
        
        // 3. THE FIX: Actively fight the system's auto-pause behavior
        statusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] observedPlayer, _ in
            guard let self = self else { return }
            
            // If iOS pauses the player (e.g., due to PiP or another audio session taking over)
            if observedPlayer.timeControlStatus == .paused {
                // Immediately force it back to playing
                observedPlayer.play()
            }
        }
    }
    
    func update(url: URL, crop: AlbumArtCrop?) {
        let urlChanged = url != currentURL
        let cropChanged = crop != currentCrop
        
        if urlChanged {
            setupPlayer(url: url)
        }
        
        if urlChanged || cropChanged {
            self.currentCrop = crop
            setNeedsLayout()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if let crop = currentCrop {
            let widthFactor = crop.trailing - crop.leading
            let heightFactor = crop.bottom - crop.top
            
            let fullWidth = bounds.width / widthFactor
            let fullHeight = bounds.height / heightFactor
            
            playerLayer.frame = CGRect(
                x: -(crop.leading * fullWidth),
                y: -(crop.top * fullHeight),
                width: fullWidth,
                height: fullHeight
            )
        } else {
            playerLayer.frame = bounds
        }
    }
    
    deinit {
        statusObserver?.invalidate()
    }
}
