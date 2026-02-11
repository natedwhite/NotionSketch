import SwiftUI
import SwiftData

/// Gallery view showing all saved sketches with thumbnails.
struct DrawingListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \SketchDocument.createdAt, order: .reverse) private var sketches: [SketchDocument]

    @Binding var selectedSketch: SketchDocument?
    @State private var showSettings = false
    @State private var renamingSketch: SketchDocument?
    @State private var renameText = ""
    @State private var isSyncingDeletions = false
    @State private var deletionSyncID = UUID()
    @State private var searchText = ""

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 20)
    ]
    
    private let notionService = NotionService()
    
    // Filtered Sketches
    var filteredSketches: [SketchDocument] {
        if searchText.isEmpty {
            return sketches
        }
        return sketches.filter { sketch in
            // Title match
            if sketch.title.localizedCaseInsensitiveContains(searchText) { return true }
            
            // Date match
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            if formatter.string(from: sketch.createdAt).localizedCaseInsensitiveContains(searchText) { return true }
            
            // Connected Pages match
            if sketch.connectedPageIDs.compactMap({ sketch.connectedPageCache[$0] }).contains(where: { $0.title.localizedCaseInsensitiveContains(searchText) }) { return true }
            
            return false
        }
    }

    var body: some View {
        Group {
            if sketches.isEmpty {
                emptyState
            } else {
                sketchGrid
            }
        }
        .navigationTitle("NotionSketch")
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search sketches, dates, or links")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    createNewSketch()
                } label: {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .task(id: deletionSyncID) {
            await syncDeletionsFromNotion()
        }
        .onAppear {
            // Trigger a new deletion sync each time the list appears
            deletionSyncID = UUID()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                deletionSyncID = UUID()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Sketches", systemImage: "pencil.tip.crop.circle")
        } description: {
            Text("Tap + to create your first sketch")
        } actions: {
            Button("New Sketch") {
                createNewSketch()
            }
            .buttonStyle(.borderedProminent)

            if !SettingsManager.shared.isConfigured {
                Button("Open Settings") {
                    showSettings = true
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Grid

    private var sketchGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(filteredSketches) { sketch in
                    SketchCard(sketch: sketch, isSelected: selectedSketch?.id == sketch.id)
                        .onTapGesture {
                            selectedSketch = sketch
                        }
                        .contextMenu {
                            Button {
                                renameText = sketch.title
                                renamingSketch = sketch
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }

                            Button("Delete", role: .destructive) {
                                deleteSketch(sketch)
                            }
                        }
                }
            }
            .padding()
        }
        .refreshable {
            await syncDeletionsFromNotion()
        }
        .alert("Rename Sketch", isPresented: Binding(
            get: { renamingSketch != nil },
            set: { if !$0 { renamingSketch = nil } }
        )) {
            TextField("Sketch name", text: $renameText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            Button("Rename") {
                renamingSketch?.title = renameText
                renamingSketch = nil
            }
            Button("Cancel", role: .cancel) {
                renamingSketch = nil
            }
        }
    }

    // MARK: - Actions

    private func createNewSketch() {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy h:mm a"
        let dateString = formatter.string(from: Date())
        let title = "Sketch \(dateString)"
        
        let sketch = SketchDocument(title: title)
        modelContext.insert(sketch)
        selectedSketch = sketch
    }

    private func deleteSketch(_ sketch: SketchDocument) {
        let pageID = sketch.notionPageID
        
        if selectedSketch?.id == sketch.id {
            selectedSketch = nil
        }
        modelContext.delete(sketch)
        
        // Archive in Notion (fire-and-forget)
        if let pageID, SettingsManager.shared.isConfigured {
            Task {
                do {
                    try await notionService.archivePage(pageID: pageID)
                } catch {
                    SyncLogger.log("⚠️ Failed to archive Notion page \(pageID): \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Sync Deletions from Notion
    
    /// Checks Notion for pages that have been archived/trashed remotely.
    /// Removes matching local sketches.
    private func syncDeletionsFromNotion() async {
        guard SettingsManager.shared.isConfigured else { return }
        guard !isSyncingDeletions else { return }
        
        isSyncingDeletions = true
        defer { isSyncingDeletions = false }
        
        do {
            let activePageIDs = try await notionService.fetchActivePageIDs()
            
            // Normalize IDs: strip hyphens, lowercase (Notion API formats can vary)
            let normalizedActive = Set(activePageIDs.map { $0.replacingOccurrences(of: "-", with: "").lowercased() })
            
            SyncLogger.log("🔍 Deletion sync: \(normalizedActive.count) active pages, \(sketches.filter { $0.notionPageID != nil }.count) synced sketches")
            
            // Find local sketches whose Notion page no longer exists (or is archived)
            let sketchesToRemove = sketches.filter { sketch in
                guard let pageID = sketch.notionPageID else { return false }
                let normalizedLocal = pageID.replacingOccurrences(of: "-", with: "").lowercased()
                let isActive = normalizedActive.contains(normalizedLocal)
                if !isActive {
                    SyncLogger.log("🗑️ Page \(pageID) not found in active pages — will remove '\(sketch.title)'")
                }
                return !isActive
            }
            
            for sketch in sketchesToRemove {
                SyncLogger.log("🗑️ Removing locally (archived in Notion): '\(sketch.title)'")
                if selectedSketch?.id == sketch.id {
                    selectedSketch = nil
                }
                modelContext.delete(sketch)
            }
            
            if sketchesToRemove.isEmpty {
                SyncLogger.log("✅ Deletion sync complete — all synced sketches still active")
            } else {
                SyncLogger.log("🗑️ Removed \(sketchesToRemove.count) sketch(es) deleted in Notion")
            }
        } catch {
            SyncLogger.log("⚠️ Failed to sync deletions from Notion: \(error.localizedDescription)")
        }
    }
}

// MARK: - Sketch Card

private struct SketchCard: View {

    let sketch: SketchDocument
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))

                if let data = sketch.thumbnailData,
                   let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                } else {
                    Image(systemName: "pencil.tip")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(sketch.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(sketch.createdAt, style: .date)
                    if sketch.notionPageID != nil {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .foregroundStyle(.green)
                            .imageScale(.small)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)

                // Connected Pages (First 2)
                if !sketch.connectedPageIDs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            let pages = sketch.connectedPageIDs
                                .compactMap { sketch.connectedPageCache[$0] }
                                .sorted { $0.title < $1.title }
                            
                            ForEach(Array(pages.prefix(3)), id: \.title) { info in
                            HStack(spacing: 2) {
                                if let icon = info.icon, !icon.isEmpty {
                                    if icon.hasPrefix("http") {
                                        AsyncImage(url: URL(string: icon)) { phase in
                                            if let image = phase.image {
                                                image.resizable().scaledToFill()
                                            } else {
                                                Color.gray.opacity(0.3)
                                            }
                                        }
                                        .frame(width: 12, height: 12)
                                        .clipShape(RoundedRectangle(cornerRadius: 2))
                                    } else {
                                        Text(icon).font(.caption2)
                                    }
                                } else {
                                    Image(systemName: "doc.text.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                }
                                
                                Text(info.title)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                        }
                        
                        if sketch.connectedPageCache.count > 3 {
                            Text("+\(sketch.connectedPageCache.count - 3)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
    }
}

#Preview {
    NavigationStack {
        DrawingListView(selectedSketch: .constant(nil))
    }
    .modelContainer(for: SketchDocument.self, inMemory: true)
}
