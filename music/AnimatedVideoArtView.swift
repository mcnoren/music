
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
        
        // Stop current playback
        playerLayer.player?.pause()
        looper = nil
        
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = true
        
        looper = AVPlayerLooper(player: player, templateItem: item)
        
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        if playerLayer.superlayer == nil {
            layer.addSublayer(playerLayer)
        }
        player.play()
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
            
            // We want the cropped area to fill the current bounds.
            // So the total size of the playerLayer should be larger.
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
}
