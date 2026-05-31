import Foundation
import LiveKitWebRTC
import Combine
import AVFoundation
import Network

class WebRTCManager: NSObject, ObservableObject, AVAssetResourceLoaderDelegate {
    static let shared = WebRTCManager()
    
    @Published var connectionState: LKRTCIceConnectionState = .new
    @Published var receivedMessages: [String] = []
    
    private var peerConnection: LKRTCPeerConnection?
    private var dataChannel: LKRTCDataChannel?
    private var webSocket: URLSessionWebSocketTask?
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    
    // Replace this with your actual Render URL!
    private let signalingURL = URL(string: "wss://my-music-relay.onrender.com")!
    
    #if os(macOS)
    // These IDs will ONLY compile into the Mac app
    private var myDeviceId = "mac-server"
    private var targetDeviceId = "iphone-client"
    #else
    // These IDs will ONLY compile into the iPhone app
    private var myDeviceId = "iphone-client"
    private var targetDeviceId = "mac-server"
    #endif
    
    private let factory: LKRTCPeerConnectionFactory
    
    private var reconnectTimer: Timer?
    private var isIntentionallyDisconnected = false
    private var pingTimer: Timer?
    
    // MARK: - Streaming Properties
    @Published var downloadedData: [String: Data] = [:]
    var expectedTotalBytes: [String: Int] = [:]
    var pendingRequests: [AVAssetResourceLoadingRequest] = []
    private var connectionTimeoutTimer: Timer?
    
    var receivingSongId: String = ""
    var requestedStreams: Set<String> = []
    var fileNames: [String: String] = [:]
    
    // NEW: Cancellation Set
    var cancelledStreams: Set<String> = []
    
    // Mac Upload Queue properties
    var uploadQueue: [(URL, String)] = []
    var isUploading = false
    
    private var _activeSeekOffsets: [String: Double] = [:]
    private let seekLock = NSLock()
    var streamBaseOffsets: [String: Int] = [:]
    
    override init() {
        LKRTCInitializeSSL()
        let videoEncoderFactory = LKRTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = LKRTCDefaultVideoDecoderFactory()
        self.factory = LKRTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
        super.init()
        setupNetworkMonitoring()
        
        #if os(iOS)
        // ⚠️ CRITICAL FIX 3: Wake up WebRTC Signaling when returning to the app
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            if self?.webSocket?.state != .running { self?.connectSignaling() }
        }
        #endif
    }
    
    func setSeekOffset(_ offset: Double, for id: String) {
        seekLock.lock()
        _activeSeekOffsets[id] = offset
        seekLock.unlock()
    }

    func getSeekOffset(for id: String) -> Double? {
        seekLock.lock()
        defer { seekLock.unlock() } // Ensures unlock happens even if we return early
        return _activeSeekOffsets[id]
    }

    func clearSeekOffset(for id: String) {
        seekLock.lock()
        _activeSeekOffsets.removeValue(forKey: id)
        seekLock.unlock()
    }
    
    // MARK: - 1. Connect to Render (Signaling)
    func startConnection(myId: String, targetId: String, isInitiator: Bool) {
        self.myDeviceId = myId
        self.targetDeviceId = targetId
        
        startConnectionWatchdog() // <--- ADD THIS HERE
        
        connectSignaling()
        setupPeerConnection()
        
        if isInitiator { createOffer() }
    }
    
    // MARK: - 2. Setup the P2P Connection
    private func setupPeerConnection() {
        let config = LKRTCConfiguration()
        
        let stunServer = LKRTCIceServer(urlStrings: [
            "stun:stun.l.google.com:19302",
            "stun:stun1.l.google.com:19302"
        ])
        
        // Your new Metered.ca TURN server
        let turnServer = LKRTCIceServer(
            urlStrings: [
                "turn:global.relay.metered.ca:80",
                "turn:global.relay.metered.ca:443",
                "turn:global.relay.metered.ca:443?transport=tcp"
            ],
            username: "15f318fefbeedaa9746ab1bc",
            credential: "snlgNjifkn+Dz6Yq"
        )
        
        // Add BOTH to the configuration
        config.iceServers = [stunServer, turnServer]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        
        let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)
        
        let dcConfig = LKRTCDataChannelConfiguration()
        dcConfig.isOrdered = true
        dataChannel = peerConnection?.dataChannel(forLabel: "MusicStream", configuration: dcConfig)
        dataChannel?.delegate = self
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            if path.status == .satisfied {
                // If we have internet, but our connection is dead or disconnected, Nuke and Pave.
                if self.webSocket?.state != .running || self.connectionState == .disconnected || self.connectionState == .failed {
                    
                    // Prevent it from looping constantly if it's already trying to connect
                    guard self.reconnectTimer == nil else { return }
                    
                    DispatchQueue.main.async {
                        self.performHardResetAndReconnect()
                    }
                }
            } else {
                // We lost internet entirely. Stop everything so it doesn't burn battery.
                self.disconnect()
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }
    
    private func startConnectionWatchdog() {
        connectionTimeoutTimer?.invalidate() // Clear any existing timer
        
        DispatchQueue.main.async { [weak self] in
            self?.connectionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 12.0, repeats: false) { _ in
                guard let self = self else { return }
                
                // If we aren't connected after 12 seconds, kill it and show the error UI
                if self.connectionState != .connected && self.connectionState != .completed {
                    print("Watchdog: Connection timed out. Forcing failure state.")
                    
                    // Stop trying to connect in the background
                    self.webSocket?.cancel(with: .goingAway, reason: nil)
                    self.peerConnection?.close()
                    
                    DispatchQueue.main.async {
                        self.connectionState = .failed
                    }
                }
            }
        }
    }
    
    private func restartIceAndReconnect() {
        let constraints = LKRTCMediaConstraints(mandatoryConstraints: ["IceRestart": "true"], optionalConstraints: nil)
        self.peerConnection?.offer(for: constraints, completionHandler: { sdp, error in
            guard let sdp = sdp else { return }
            self.peerConnection?.setLocalDescription(sdp, completionHandler: { error in
                let offerDict: [String: Any] = ["type": "offer", "sdp": sdp.sdp, "targetId": self.targetDeviceId]
                self.sendToWebSocket(offerDict)
            })
        })
    }
    
    private func connectSignaling() {
        webSocket = URLSession.shared.webSocketTask(with: signalingURL)
        webSocket?.resume()
        listenToWebSocket()
        
        if !myDeviceId.isEmpty {
            let registerMsg = ["type": "register", "deviceId": myDeviceId]
            sendToWebSocket(registerMsg)
        }
        
        // Keep the cellular WebSocket alive!
        startPingTimer()
    }
    
    // MARK: - 3. WebRTC Negotiation
    private func createOffer() {
        peerConnection?.offer(for: LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { [weak self] sdp, error in
            guard let sdp = sdp else { return }
            self?.peerConnection?.setLocalDescription(sdp, completionHandler: { _ in })
            self?.sendToWebSocket(["type": "offer", "sdp": sdp.sdp, "targetId": self?.targetDeviceId ?? ""])
        }
    }
    
    private func sendToWebSocket(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []) else { return }
        let message = URLSessionWebSocketTask.Message.string(String(data: data, encoding: .utf8)!)
        webSocket?.send(message) { _ in }
    }
    
    private func listenToWebSocket() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message,
                   let data = text.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    self.handleSignalingMessage(dict)
                }
            case .failure(let error):
                print("WebSocket Error: \(error)")
            }
            self.listenToWebSocket()
        }
    }
    
    private func handleSignalingMessage(_ dict: [String: Any]) {
        guard let type = dict["type"] as? String else { return }
        
        if type == "offer", let sdpString = dict["sdp"] as? String {
            let sdp = LKRTCSessionDescription(type: .offer, sdp: sdpString)
            peerConnection?.setRemoteDescription(sdp) { [weak self] _ in
                self?.peerConnection?.answer(for: LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { answer, _ in
                    guard let answer = answer else { return }
                    self?.peerConnection?.setLocalDescription(answer, completionHandler: { _ in })
                    self?.sendToWebSocket(["type": "answer", "sdp": answer.sdp, "targetId": self?.targetDeviceId ?? ""])
                }
            }
        } else if type == "answer", let sdpString = dict["sdp"] as? String {
            let sdp = LKRTCSessionDescription(type: .answer, sdp: sdpString)
            peerConnection?.setRemoteDescription(sdp, completionHandler: { _ in })
        } else if type == "candidate", let candidateDict = dict["candidate"] as? [String: Any],
                  let sdp = candidateDict["candidate"] as? String,
                  let sdpMLineIndex = candidateDict["sdpMLineIndex"] as? Int32,
                  let sdpMid = candidateDict["sdpMid"] as? String {
            let candidate = LKRTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
            peerConnection?.add(candidate)
        }
    }
    
    private func startPingTimer() {
        // Clear any existing timer to avoid duplicates
        pingTimer?.invalidate()
        
        // Ping the server every 20 seconds to keep the connection alive
        DispatchQueue.main.async { [weak self] in
            self?.pingTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { _ in
                self?.webSocket?.sendPing { error in
                    if let error = error {
                        print("WebSocket Ping failed: \(error.localizedDescription)")
                        // If the ping fails, the connection is likely dead. Force a reconnect.
                        self?.handleDisconnection()
                    }
                }
            }
        }
    }
    
    // MARK: - 1. Requesting the Stream
    func requestStream(songId: String) {
        sendString("REQUEST_STREAM:\(songId)")
    }

    func sendString(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        // Call MultipeerManager directly to avoid naming conflicts!
        MultipeerManager.shared.sendDataToPeers(data, isBinary: false, isReliable: true)
    }
    
    // NEW HELPER: Allows MultipeerManager to route data back here if Wi-Fi drops
    func sendToDataChannel(_ data: Data, isBinary: Bool) {
        let buffer = LKRTCDataBuffer(data: data, isBinary: isBinary)
        dataChannel?.sendData(buffer)
    }
    
    func sendData(_ data: Data, isBinary: Bool) {
        // Send data through the unified network router
        MultipeerManager.shared.sendDataToPeers(data, isBinary: isBinary, isReliable: true)
    }

    func connect() {
        // 1. Prevent duplicate connections if we're already running
        guard webSocket == nil || webSocket?.state != .running else { return }
        
        print("Connecting to signaling server at \(signalingURL)...")
        
        // 2. Create and start the WebSocket connection
        let request = URLRequest(url: signalingURL)
        webSocket = URLSession.shared.webSocketTask(with: request)
        webSocket?.resume()
        
        // 3. Start the continuous listening loop (assuming you have a receive method, usually called receiveMessages or similar)
        // If your receive function is named differently, update this line!
        listenToWebSocket()
        
        // 4. THE CRITICAL STEP: Tell the Render server who we are so it can route traffic to us
        let registerMessage: [String: Any] = [
            "type": "register",
            "deviceId": myDeviceId
        ]
        
        // Convert to JSON and send (assuming you have a sendToWebSocket helper)
        sendToWebSocket(registerMessage)
    }
    
    func connectToSignalingServer() {
        isIntentionallyDisconnected = false
        let request = URLRequest(url: signalingURL)
        webSocket = URLSession.shared.webSocketTask(with: request)
        webSocket?.resume()
        receiveWebSocketMessage()
        
        // Ping the server every 20 seconds to keep the Render instance awake
        startPingTimer()
    }

    func disconnect() {
        isIntentionallyDisconnected = true
        webSocket?.cancel(with: .goingAway, reason: nil)
        reconnectTimer?.invalidate()
        pingTimer?.invalidate()
    }

    private func receiveWebSocketMessage() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                // ... (Handle your existing signaling messages here) ...
                self.receiveWebSocketMessage() // Continue listening
                
            case .failure(let error):
                print("WebSocket Disconnected: \(error.localizedDescription)")
                self.handleDisconnection()
            }
        }
    }

    private func handleDisconnection() {
        guard !isIntentionallyDisconnected else { return }
        
        // Attempt to reconnect every 5 seconds if the connection drops
        DispatchQueue.main.async {
            self.reconnectTimer?.invalidate()
            self.reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                print("Attempting to reconnect WebSocket...")
                self?.connectToSignalingServer()
            }
        }
    }
    
    private func handleWebSocketDisconnect() {
        guard !isIntentionallyDisconnected else { return }
        print("WebSocket disconnected. Forcing hard reset...")
        
        DispatchQueue.main.async {
            self.performHardResetAndReconnect()
        }
    }
    
    func sendCommandOverWebRTC(_ command: String) {
        guard let dataChannel = self.dataChannel, dataChannel.readyState == .open else {
            print("Data channel not open. Cannot send command.")
            return
        }
        let data = Data(command.utf8)
        let buffer = LKRTCDataBuffer(data: data, isBinary: false)
        dataChannel.sendData(buffer)
    }

    // Add a closure that the UI can listen to
    var onReceiveWebRTCCommand: ((String) -> Void)?

    // Trigger the closure when the Data Channel receives text
    func dataChannel(_ dataChannel: LKRTCDataChannel, didReceiveMessageWith buffer: LKRTCDataBuffer) {
        if !buffer.isBinary, let message = String(data: buffer.data, encoding: .utf8) {
            DispatchQueue.main.async {
                self.onReceiveWebRTCCommand?(message)
            }
        }
    }

    func handleCommand(_ message: String) -> Bool {
        if message.starts(with: "REQUEST_STREAM:") {
            #if os(macOS)
            let songId = message.replacingOccurrences(of: "REQUEST_STREAM:", with: "")
            if let song = MacLibrary.shared.songs.first(where: { $0.id == songId }) {
                
                let meta = DownloadMetadataPayload(fileName: song.url.lastPathComponent, title: song.title, artist: song.artist, album: song.album, lyrics: song.lyrics, syncedLyrics: MacLibrary.shared.syncedLyrics[song.id]?.lines, trackNumber: song.trackNumber, discNumber: song.discNumber)
                if let encoded = try? JSONEncoder().encode(meta), let jsonStr = String(data: encoded, encoding: .utf8) {
                    self.sendString("STREAM_METADATA:\(songId):\(jsonStr)")
                }
                
                self.uploadQueue.append((song.url, song.id))
                self.processUploadQueue()
            }
            #endif
            return true
            
        } else if message.starts(with: "STREAM_METADATA:") {
            #if os(iOS)
            let parts = message.components(separatedBy: ":")
            if parts.count >= 3 {
                let json = parts.dropFirst(2).joined(separator: ":")
                if let data = json.data(using: .utf8), let meta = try? JSONDecoder().decode(DownloadMetadataPayload.self, from: data) {
                    let songId = parts[1]
                    self.fileNames[songId] = meta.fileName
                    NotificationCenter.default.post(name: NSNotification.Name("WebRTCStreamReady"), object: meta)
                }
            }
            #endif
            return true
            
        } else if message.starts(with: "START_STREAM:") {
            let parts = message.components(separatedBy: ":")
            if parts.count >= 3 {
                let songId = parts[1]
                let total = Int(parts[2]) ?? 0
                
                if parts.count >= 4 { self.fileNames[songId] = "stream.\(parts[3])" }
                else if self.fileNames[songId] == nil { self.fileNames[songId] = "stream.mp3" }
                
                self.receivingSongId = songId
                self.expectedTotalBytes[songId] = total
                self.downloadedData[songId] = Data()
                self.streamBaseOffsets[songId] = 0 // <--- ADD THIS
                self.processPendingRequests()
            }
            return true
            
        } else if message.starts(with: "SEEK_STREAM:") {
            #if os(macOS)
            let parts = message.components(separatedBy: ":")
            
            // Check if we have all 3 pieces, then grab the offset
            if parts.count >= 3, let newOffset = Int(parts[2]) {
                let extractedSongId = parts[1] // <--- THIS IS THE MISSING PIECE
                
                self.setSeekOffset(Double(newOffset), for: extractedSongId)
            }
            #endif
            return true
        } else if message.starts(with: "OFFSET_MARKER:") {
            #if os(iOS)
            let parts = message.components(separatedBy: ":")
            if parts.count >= 3, let newOffset = Int(parts[2]) {
                let songId = parts[1]
                self.downloadedData[songId] = Data() // Clear out the old chunks
                self.streamBaseOffsets[songId] = newOffset // Sync to the Mac's new position
            }
            #endif
            return true
            
        } else if message.starts(with: "CANCEL_STREAM:") {
            let songId = message.replacingOccurrences(of: "CANCEL_STREAM:", with: "")
            self.cancelledStreams.insert(songId)
            
            #if os(macOS)
            // 1. Remove it if it's waiting in line
            self.uploadQueue.removeAll(where: { $0.1 == songId })
            
            // 2. If it is actively uploading right now, the while-loop below
            // will catch the `cancelledStreams` flag and kill itself.
            #endif
            return true
            
        } else if message.starts(with: "END_STREAM") {
            self.processPendingRequests()
            return true
        }
        
        return false
    }
    
    // Add this anywhere inside your WebRTCManager class
    func performHardResetAndReconnect() {
        print("Performing hard reset of network states...")
        
        // Kill everything
        connectionTimeoutTimer?.invalidate() // <--- Make sure this is here
        reconnectTimer?.invalidate()
        pingTimer?.invalidate()
        
        // 1. Invalidate all timers to stop runaway reconnect loops
        reconnectTimer?.invalidate()
        pingTimer?.invalidate()
        reconnectTimer = nil
        pingTimer = nil
        
        // 2. Kill the WebSockets
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        
        // 3. Purge WebRTC objects completely from memory
        dataChannel?.close()
        dataChannel = nil
        
        peerConnection?.close()
        peerConnection = nil
        
        // 4. Reset the state
        DispatchQueue.main.async {
            self.connectionState = .new
        }
        
        // 5. Re-initiate the connection from scratch after a brief pause
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            print("Restarting connection...")
            // If myDeviceId isn't empty, we know what role we are playing
            if !self.myDeviceId.isEmpty {
                self.startConnection(myId: self.myDeviceId, targetId: self.targetDeviceId, isInitiator: self.myDeviceId == "iphone-client")
            }
        }
    }

    #if os(macOS)
    private var activeUploadSongId: String? = nil
    
    private func processUploadQueue() {
        guard !isUploading, let next = uploadQueue.first else { return }
        isUploading = true
        activeUploadSongId = next.1
        uploadQueue.removeFirst() // Remove from queue immediately so finishUpload is safer
        sendFileInChunks(url: next.0, songId: next.1)
    }
    
    private func finishUpload() {
        isUploading = false
        activeUploadSongId = nil
        processUploadQueue() // Automatically start the next song in line!
    }
    #endif

    // MARK: - 2. Mac Side: Chunking & Sending the Audio File
    func sendFileInChunks(url: URL, songId: String) {
        guard let data = try? Data(contentsOf: url) else {
            #if os(macOS)
            self.finishUpload()
            #endif
            return
        }
        let total = data.count
        let ext = url.pathExtension.lowercased()
        
        // 1. PREVENT STALE CANCELS: Clear any lingering cancellations for this song before we start!
        self.cancelledStreams.remove(songId)
        
        sendString("START_STREAM:\(songId):\(total):\(ext)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let chunkSize = 16384
            var offset = 0
            
            while offset < total {
                guard let self = self else { return }
                
                if self.cancelledStreams.contains(songId) {
                    self.cancelledStreams.remove(songId)
                    break
                }
                
                #if os(macOS)
                // 2. DYNAMIC SEEKING: Jump to the end for M4A metadata if requested
                if let requestedSeek = self.getSeekOffset(for: songId) {
                    
                    // 🚨 SAFELY clamp the offset so it never crashes the background thread!
                    offset = min(max(Int(requestedSeek), 0), total)
                    self.clearSeekOffset(for: songId)
                    
                    // Wait for the data channel to clear (only if open!), then sync the iPhone's sliding window
                    while let dc = self.dataChannel, dc.readyState == .open, dc.bufferedAmount > 0 { usleep(5000) }
                    self.sendString("OFFSET_MARKER:\(songId):\(offset)")
                    
                    // If the seek pushed us to the very end of the file, break the loop naturally
                    if offset >= total { break }
                }
                #endif
                
                // 3. BACKPRESSURE: Prevent "buffer bloat", but ensure the channel is actually open
                while let dc = self.dataChannel, dc.readyState == .open, dc.bufferedAmount > 524288 {
                    usleep(10000)
                    if self.cancelledStreams.contains(songId) { break }
                }
                
                let end = min(offset + chunkSize, total)
                
                // 🚨 EXTRA SAFETY: Ensure the range is mathematically valid before slicing
                guard offset <= end, end <= total else { break }
                
                let chunk = data.subdata(in: offset..<end)
                MultipeerManager.shared.sendDataToPeers(chunk, isBinary: true, isReliable: true)
                offset += chunk.count
            }
            
            self?.sendString("END_STREAM:\(songId)")
            DispatchQueue.main.async {
                #if os(macOS)
                self?.finishUpload()
                #endif
            }
        }
    }

    // MARK: - 4. AVAssetResourceLoaderDelegate (iOS NATIVE PROXY)
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        pendingRequests.append(loadingRequest)
        
        if let url = loadingRequest.request.url,
           let songId = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value {
            if !requestedStreams.contains(songId) {
                requestedStreams.insert(songId)
                self.requestStream(songId: songId)
            }
        }
        processPendingRequests()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        if let index = pendingRequests.firstIndex(of: loadingRequest) { pendingRequests.remove(at: index) }
        
        // ⚠️ REMOVED the CANCEL_STREAM logic from here.
        // AVPlayer natively drops and recreates requests constantly to adjust its buffer.
        // Canceling the stream here was corrupting the downloadedData buffer!
    }
    
    // MARK: - NEW HELPER: Smart Memory Management
    func cleanupOldStreams(keepActiveIds: [String]) {
        let activeSet = Set(keepActiveIds)
        let streamsToCancel = requestedStreams.subtracting(activeSet)
        
        for songId in streamsToCancel {
            self.sendString("CANCEL_STREAM:\(songId)")
            self.requestedStreams.remove(songId)
            self.downloadedData.removeValue(forKey: songId)
            self.expectedTotalBytes.removeValue(forKey: songId)
        }
    }

    func processPendingRequests() {
        var requestsToComplete: [AVAssetResourceLoadingRequest] = []
        var servedAnyData = false

        // PASS 1: Try to serve data to any request that is currently within our buffer window.
        // If we are actively serving data, we DO NOT want to trigger a seek and interrupt it.
        for request in pendingRequests {
            guard let dataRequest = request.dataRequest,
                  let url = request.request.url,
                  let songId = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value else { continue }

            guard let totalBytes = expectedTotalBytes[songId] else { continue }
            let songData = downloadedData[songId] ?? Data()

            if request.contentInformationRequest != nil {
                request.contentInformationRequest?.isByteRangeAccessSupported = true
                
                let fileName = fileNames[songId] ?? ""
                let ext = (fileName as NSString).pathExtension.lowercased()
                
                if ext == "m4a" || ext == "m4p" {
                    request.contentInformationRequest?.contentType = "com.apple.m4a-audio"
                } else if ext == "mp4" {
                    request.contentInformationRequest?.contentType = "public.mpeg-4-audio"
                } else if ext == "wav" {
                    request.contentInformationRequest?.contentType = "com.microsoft.waveform-audio"
                } else if ext == "flac" {
                    request.contentInformationRequest?.contentType = "org.xiph.flac"
                } else {
                    request.contentInformationRequest?.contentType = "public.mp3"
                }
                
                request.contentInformationRequest?.contentLength = Int64(totalBytes)
            }

            let requestedOffset = Int(dataRequest.requestedOffset)
            let requestedLength = dataRequest.requestedLength
            let currentOffset = Int(dataRequest.currentOffset)
            let unreadOffset = currentOffset - requestedOffset
            
            let baseOffset = self.streamBaseOffsets[songId] ?? 0
            let bufferEnd = baseOffset + songData.count
            
            // Check if the requested data falls inside our currently downloaded buffer
            if currentOffset >= baseOffset && currentOffset <= bufferEnd {
                let localOffset = currentOffset - baseOffset
                let availableLength = songData.count - localOffset

                if availableLength > 0 {
                    let lengthToRespond = min(availableLength, requestedLength - unreadOffset)
                    let chunk = songData.subdata(in: localOffset..<(localOffset + lengthToRespond))
                    dataRequest.respond(with: chunk)
                    
                    servedAnyData = true // We successfully fed AVPlayer!

                    if dataRequest.currentOffset >= requestedOffset + requestedLength {
                        request.finishLoading()
                        requestsToComplete.append(request)
                    }
                } else if songData.count >= totalBytes && totalBytes > 0 {
                    // Failsafe for AVPlayer requesting EOF
                    request.finishLoading()
                    requestsToComplete.append(request)
                }
            }
        }

        // Clean up requests that successfully finished
        for completed in requestsToComplete {
            if let index = pendingRequests.firstIndex(of: completed) { pendingRequests.remove(at: index) }
        }

        // PASS 2: If we couldn't serve ANY data, AVPlayer is starved and needs us to jump.
        // We only look at the MOST RECENT request (last in the array) to prevent ping-ponging.
        if !servedAnyData, let mostUrgentRequest = pendingRequests.last {
            guard let dataRequest = mostUrgentRequest.dataRequest,
                  let url = mostUrgentRequest.request.url,
                  let songId = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value else { return }
            
            let currentOffset = Int(dataRequest.currentOffset)
            let baseOffset = self.streamBaseOffsets[songId] ?? 0
            let bufferEnd = baseOffset + (self.downloadedData[songId]?.count ?? 0)

            // Only issue a seek command if it is truly out of bounds
            if currentOffset < baseOffset || currentOffset > bufferEnd + 262144 {
                self.sendString("SEEK_STREAM:\(songId):\(currentOffset)")
                
                // Pause serving until the Mac's OFFSET_MARKER text arrives
                self.streamBaseOffsets[songId] = currentOffset
                self.downloadedData[songId] = Data()
            }
        }
    }
}

// MARK: - WebRTC Delegates
extension WebRTCManager: LKRTCPeerConnectionDelegate, LKRTCDataChannelDelegate {
    
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange stateChanged: LKRTCIceConnectionState) {
        DispatchQueue.main.async {
            self.connectionState = stateChanged
            
            // <--- ADD THIS BLOCK --->
            // If we connected successfully, cancel the timeout!
            if stateChanged == .connected || stateChanged == .completed {
                self.connectionTimeoutTimer?.invalidate()
                self.connectionTimeoutTimer = nil
            }
        }
    }
    
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didGenerate candidate: LKRTCIceCandidate) {
        let candidateDict: [String: Any] = ["candidate": candidate.sdp, "sdpMLineIndex": candidate.sdpMLineIndex, "sdpMid": candidate.sdpMid ?? ""]
        sendToWebSocket(["type": "candidate", "candidate": candidateDict, "targetId": targetDeviceId])
    }
    
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didOpen dataChannel: LKRTCDataChannel) {
        self.dataChannel = dataChannel
        self.dataChannel?.delegate = self
    }
    
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceGatheringState) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange stateChanged: LKRTCSignalingState) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didAdd stream: LKRTCMediaStream) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove stream: LKRTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: LKRTCPeerConnection) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove candidates: [LKRTCIceCandidate]) {}
    func dataChannelDidChangeState(_ dataChannel: LKRTCDataChannel) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didAdd rtpReceiver: LKRTCRtpReceiver, streams mediaStreams: [LKRTCMediaStream]) {}
}

extension WebRTCManager: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        // This is triggered when the connection drops or the server closes it
        handleWebSocketDisconnect()
    }
    
    // Also, handle the case where the initial connection fails to even open
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("WebSocket error: \(error.localizedDescription)")
            handleWebSocketDisconnect()
        }
    }
}
