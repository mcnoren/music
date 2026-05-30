//
//  musicApp.swift
//  music
//
//  Created by Matthew Noren on 12/10/25.
//

import SwiftUI

@main
struct musicApp: App {
    // Inject the shared instance so the view observes its changes
    @StateObject private var downloads = DownloadsManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    Task {
                        await downloads.importExternalURL(url)
                    }
                }
                // Add the loading overlay
                .overlay {
                    if downloads.isImporting {
                        ZStack {
                            // Dim the background to prevent user interaction while loading
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
                        // Smooth fade in and out
                        .transition(.opacity)
                        .animation(.easeInOut, value: downloads.isImporting)
                    }
                }
        }
    }
}
