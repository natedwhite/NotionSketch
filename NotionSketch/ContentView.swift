import SwiftUI
import SwiftData

/// Root view with split navigation: drawing list on the left, canvas on the right.
struct ContentView: View {

    @Environment(\.modelContext) private var modelContext
    @Query private var sketches: [SketchDocument]
    @State private var selectedSketch: SketchDocument?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isReady = false

    var body: some View {
        ZStack {
            NavigationStack {
                DrawingListView(selectedSketch: $selectedSketch)
                    .navigationTitle("NotionSketch")
                    .navigationDestination(item: $selectedSketch) { sketch in
                        CanvasDetailView(document: sketch)
                            .navigationTitle(sketch.title)
                            .navigationBarTitleDisplayMode(.inline)
                    }
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .onAppear {
                // Start background sync on launch
                Task {
                    await NotionSyncManager.shared.syncLibrary(context: modelContext)
                }
                
                // Give SwiftData and UI a moment to initialize
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        isReady = true
                    }
                }
            }

            // Splash overlay — covers content until ready
            if !isReady {
                SplashScreen()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        SyncLogger.log("🔗 Received deep link: \(url.absoluteString)")
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.scheme == "notionsketch",
              components.host == "open",
              let queryItems = components.queryItems,
              let idString = queryItems.first(where: { $0.name == "id" })?.value,
              let uuid = UUID(uuidString: idString)
        else { 
            SyncLogger.log("❌ Invalid deep link format")
            return 
        }
        
        if let sketch = sketches.first(where: { $0.id == uuid }) {
            SyncLogger.log("✅ Found matching sketch: '\(sketch.title)' — Opening...")
            selectedSketch = sketch
        } else {
            SyncLogger.log("❌ Sketch not found locally for ID: \(uuid)")
        }
    }
}

/// Wrapper that owns the CanvasViewModel via @State so it persists across re-renders.
private struct CanvasDetailView: View {

    let document: SketchDocument
    @State private var viewModel: CanvasViewModel

    init(document: SketchDocument) {
        self.document = document
        self._viewModel = State(initialValue: CanvasViewModel(document: document))
    }

    var body: some View {
        CanvasView(viewModel: viewModel)
            .id(document.id)
            .task {
                await viewModel.fetchRemoteProperties()
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SketchDocument.self, inMemory: true)
}
