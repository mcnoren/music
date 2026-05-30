import Foundation
import GCDWebServer

class MacStreamServer {
    static let shared = MacStreamServer()
    private let webServer = GCDWebServer()
    
    func start() -> String? {
        print("🚀 MacStreamServer is booting up!") // <--- ADD THIS
        
        if webServer.isRunning {
            return webServer.serverURL?.absoluteString
        }
        
        // 2. Clear any existing handlers just to be safe before adding a new one
        webServer.removeAllHandlers()
        
        webServer.addDefaultHandler(forMethod: "GET", request: GCDWebServerRequest.self) { request in
            guard let id = request.query?["id"] as? String else {
                print("❌ Stream failed: No ID found in query: \(request.query ?? [:])")
                return GCDWebServerResponse(statusCode: 400)
            }
            
            guard let song = MacLibrary.shared.songs.first(where: { $0.id == id }) else {
                print("❌ Stream failed: Could not find song with ID: \(id)")
                return GCDWebServerResponse(statusCode: 404)
            }
            
            print("✅ Successfully serving stream for: \(song.title)")
            return GCDWebServerFileResponse(file: song.url.path, byteRange: request.byteRange)
        }
        
        do {
            try webServer.start(options: [
                GCDWebServerOption_Port: 8080,
                GCDWebServerOption_BindToLocalhost: false
            ])
            return webServer.serverURL?.absoluteString
        } catch {
            print("Server failed to start: \(error)")
            return nil
        }
    }
}
