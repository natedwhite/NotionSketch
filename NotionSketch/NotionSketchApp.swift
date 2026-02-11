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
