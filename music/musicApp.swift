//
//  musicApp.swift
//  music
//

import SwiftUI

@main
struct musicApp: App {
    @StateObject private var downloads = DownloadsManager.shared
    
    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        
        // This is the "Nuke": passing an empty image forcefully prevents iOS from rendering a UIBlurEffect view.
        appearance.backgroundImage = UIImage()
        appearance.shadowImage = UIImage()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = nil
        appearance.shadowColor = .clear
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    Task {
                        await downloads.importExternalURL(url)
                    }
                }
                .overlay {
                    if downloads.isImporting {
                        ZStack {
                            Color.black.opacity(0.3).ignoresSafeArea()
                            
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.pink)
                                Text("Importing...")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                            }
                            .padding(30)
                            .background(.regularMaterial)
                            .cornerRadius(16)
                            .shadow(radius: 10)
                        }
                        .transition(.opacity)
                        .animation(.easeInOut, value: downloads.isImporting)
                    }
                }
        }
    }
}
