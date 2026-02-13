import SwiftUI
import SwiftData

@main
struct NotionSketchApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    SyncLogger.log("📱 App received URL (Top Level): \(url)")
                }
        }
        .modelContainer(for: SketchDocument.self)
    }
}

// MARK: - Network Monitor

import Network
import Observation

@Observable
@MainActor
class NetworkMonitor {
    static let shared = NetworkMonitor()
    
    var isConnected = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}
