import SwiftUI
import PencilKit

// MARK: - Dot Grid View (CALayer-based for smooth animation)

/// Fills its bounds with a dot grid, stable against sidebar shifts.
/// Uses a pattern layer to ensure Core Animation handles changes smoothly (no jitter).
class DotGridView: UIView {
    
    // Fixed pattern configuration
    private let dotSpacing: CGFloat = 40
    private let dotRadius: CGFloat = 1.5
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = createPatternColor()
        isUserInteractionEnabled = false
        // Anchor point at top-left to make scaling/positioning math easier
        layer.anchorPoint = .zero
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func createPatternColor() -> UIColor? {
        let size = CGSize(width: dotSpacing, height: dotSpacing)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor.tertiaryLabel.withAlphaComponent(0.4).cgColor)
            c.fillEllipse(in: CGRect(x: 0, y: 0, width: dotRadius * 2, height: dotRadius * 2))
        }
        return UIColor(patternImage: image)
    }
}

// MARK: - DrawingCanvas (UIViewRepresentable)

// MARK: - Canvas Container (prevents sidebar scroll shift)

/// Container that preserves PKCanvasView's contentOffset across layout changes
/// (e.g. sidebar opening/closing).
class CanvasContainer: UIView {
    weak var canvasView: PKCanvasView?

    /// Closure to activate the tool picker once the view is in a window.
    var onReadyToActivate: (() -> Void)?
    private var hasActivated = false
    private var hasSetInitialOffset = false
    private var lastGlobalOrigin: CGPoint?

    override func layoutSubviews() {
        super.layoutSubviews()

        // Standard full-width layout
        canvasView?.frame = bounds

        // 1. Initial Setup: Center on Content
        if !hasSetInitialOffset, bounds.height > 0, let cv = canvasView {
            hasSetInitialOffset = true
            
            // 1. Center on existing drawing content if available
            let drawingBounds = cv.drawing.bounds
            if !drawingBounds.isNull, !drawingBounds.isEmpty, drawingBounds.width > 0, drawingBounds.height > 0 {
                
                // Calculate "Zoom to Fit" scale with padding
                let padding: CGFloat = 50
                let availableWidth = bounds.width - (padding * 2)
                let availableHeight = bounds.height - (padding * 2)
                
                let scaleX = availableWidth / drawingBounds.width
                let scaleY = availableHeight / drawingBounds.height
                
                // Use the smaller scale to ensure it fits, but clamp to allowed range
                let targetScale = min(scaleX, scaleY)
                let clampedScale = min(max(targetScale, cv.minimumZoomScale), cv.maximumZoomScale)
                
                cv.zoomScale = clampedScale
                
                // Center based on the NEW scale
                // Content coordinates scale with zoomScale
                let scaledMidX = drawingBounds.midX * clampedScale
                let scaledMidY = drawingBounds.midY * clampedScale
                
                let offsetX = scaledMidX - (bounds.width / 2)
                let offsetY = scaledMidY - (bounds.height / 2)
                
                cv.contentOffset = CGPoint(x: offsetX, y: offsetY)
            } else {
                // 2. Default: Center the vast canvas
                // Reset zoom to sensible default
                if cv.zoomScale < 0.5 { cv.zoomScale = 0.5 } 
                
                cv.contentOffset = CGPoint(
                    x: (DrawingCanvas.canvasSize * cv.zoomScale - bounds.width) / 2,
                    y: (DrawingCanvas.canvasSize * cv.zoomScale - bounds.height) / 2
                )
            }
            
            // Initialize tracker
            lastGlobalOrigin = convert(CGPoint.zero, to: nil)
            return
        }
        
        // 2. Continuous Stabilization: Lock content to Screen
        // If the view moves (e.g. sidebar opens/closes), adjust offset to keep content stationary visually.
        if let lastOrigin = lastGlobalOrigin, let cv = canvasView {
            let currentOrigin = convert(CGPoint.zero, to: nil)
            
            let deltaX = currentOrigin.x - lastOrigin.x
            let deltaY = currentOrigin.y - lastOrigin.y
            
            if abs(deltaX) > 0.1 || abs(deltaY) > 0.1 {
                var off = cv.contentOffset
                off.x += deltaX
                off.y += deltaY
                
                // Ensure we don't scroll out of bounds (clamping)
                let maxOffsetX = cv.contentSize.width - cv.bounds.width
                let maxOffsetY = cv.contentSize.height - cv.bounds.height
                off.x = max(0, min(off.x, maxOffsetX))
                off.y = max(0, min(off.y, maxOffsetY))
                
                cv.contentOffset = off
                
                // Note: DotGrid update is handled automatically because it is a subview of canvasView
            }
            lastGlobalOrigin = currentOrigin
        } else {
             lastGlobalOrigin = convert(CGPoint.zero, to: nil)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Activate tool picker once the view is in a real window
        if window != nil && !hasActivated {
            hasActivated = true
            // Small delay lets UIKit finish laying out the responder chain
            DispatchQueue.main.async { [weak self] in
                self?.onReadyToActivate?()
                self?.onReadyToActivate = nil
            }
        }
    }
}

// MARK: - DrawingCanvas (UIViewRepresentable)

/// Wraps PKCanvasView in a container with a dot grid behind it.
/// - Finger scrolls/zooms, Apple Pencil draws
/// - Dot grid tracks canvas scroll position
/// - 2-finger undo, 3-finger redo
struct DrawingCanvas: UIViewRepresentable {

    // Drawable canvas size — large enough to feel infinite.
    // Memory-safe because the dot grid is a separate sibling view.
    static let canvasSize: CGFloat = 8000

    @Binding var drawing: PKDrawing
    var onDrawingChanged: (PKDrawing) -> Void

    func makeUIView(context: Context) -> CanvasContainer {
        let container = CanvasContainer()
        container.clipsToBounds = true



        // --- PKCanvasView (on top, transparent) ---
        let canvasView = PKCanvasView()
        canvasView.drawingPolicy = .pencilOnly
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false

        // Delegate
        canvasView.delegate = context.coordinator

        // Large drawable area
        canvasView.contentSize = CGSize(
            width: DrawingCanvas.canvasSize,
            height: DrawingCanvas.canvasSize
        )
        canvasView.contentInsetAdjustmentBehavior = .never

        // Hide scroll bars & disable tap-to-top
        canvasView.showsVerticalScrollIndicator = false
        canvasView.showsHorizontalScrollIndicator = false
        canvasView.scrollsToTop = false

        // Zoom
        canvasView.minimumZoomScale = 0.2
        canvasView.maximumZoomScale = 3.0
        canvasView.bouncesZoom = true

        // Load drawing
        canvasView.drawing = drawing

        // contentOffset will be set in CanvasContainer.layoutSubviews
        
        // --- Dot grid (inside PKCanvasView) ---
        // We place it inside to sync with scroll, but we must manually manage its zoom/position
        // because PKCanvasView manages its own content view.
        let dotGrid = DotGridView(frame: CGRect(origin: .zero, size: canvasView.contentSize))
        canvasView.insertSubview(dotGrid, at: 0)
        canvasView.sendSubviewToBack(dotGrid)

        container.addSubview(canvasView)
        container.canvasView = canvasView
        
        // Store references in Coordinator immediately
        context.coordinator.canvasView = canvasView
        context.coordinator.dotGridView = dotGrid
        
        // Initial sync
        context.coordinator.updateDotGrid(canvasView)

        // --- Undo / Redo gestures ---
        let undoGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleUndo(_:))
        )
        undoGesture.numberOfTouchesRequired = 2
        undoGesture.numberOfTapsRequired = 1
        undoGesture.delaysTouchesEnded = false
        canvasView.addGestureRecognizer(undoGesture)

        let redoGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleRedo(_:))
        )
        redoGesture.numberOfTouchesRequired = 3
        redoGesture.numberOfTapsRequired = 1
        redoGesture.delaysTouchesEnded = false
        canvasView.addGestureRecognizer(redoGesture)

        undoGesture.require(toFail: redoGesture)

        // Reference storing handled above


        // --- Deferred Tool Picker activation ---
        // PKToolPicker.setVisible + becomeFirstResponder must happen
        // AFTER the view is in the window hierarchy. On first launch
        // after a rebuild, makeUIView runs before the view is in a window,
        // so the tool picker silently fails to attach.
        let coordinator = context.coordinator
        container.onReadyToActivate = {
            let toolPicker = PKToolPicker()
            toolPicker.setVisible(true, forFirstResponder: canvasView)
            toolPicker.addObserver(canvasView)
            canvasView.becomeFirstResponder()
            coordinator.toolPicker = toolPicker
            coordinator.updateDotGrid(canvasView)
        }

        return container
    }

    func updateUIView(_ uiView: CanvasContainer, context: Context) {
        if context.coordinator.shouldAcceptExternalUpdate {
            context.coordinator.canvasView?.drawing = drawing
            context.coordinator.shouldAcceptExternalUpdate = false
        }
        
        // Ensure ToolPicker remains visible (Fixes "disappearing tools" bug)
        if let canvasView = uiView.canvasView, let toolPicker = context.coordinator.toolPicker {
             toolPicker.setVisible(true, forFirstResponder: canvasView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing, onDrawingChanged: onDrawingChanged)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, PKCanvasViewDelegate {

        var drawing: Binding<PKDrawing>
        var onDrawingChanged: (PKDrawing) -> Void
        var toolPicker: PKToolPicker?
        weak var canvasView: PKCanvasView?
        weak var dotGridView: DotGridView?

        var shouldAcceptExternalUpdate = true

        init(drawing: Binding<PKDrawing>, onDrawingChanged: @escaping (PKDrawing) -> Void) {
            self.drawing = drawing
            self.onDrawingChanged = onDrawingChanged
        }

        // MARK: - PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
            onDrawingChanged(canvasView.drawing)
        }

        // MARK: - UIScrollViewDelegate (inherited from PKCanvasViewDelegate)

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updateDotGrid(scrollView)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            updateDotGrid(scrollView)
        }

        func updateDotGrid(_ scrollView: UIScrollView) {
            guard let grid = dotGridView else { return }
            
            // Standard UIScrollView Zoom/Scroll Logic for a "background" subview
            // typical approach: keep it large and just scale it.
            let zoom = scrollView.zoomScale
            
            // Apply scale
            // DotGridView has anchorPoint = .zero
            grid.transform = CGAffineTransform(scaleX: zoom, y: zoom)
            
            // Usually, if a view is a subview of the scroll view, it scrolls automatically.
            // But PKCanvasView might have internal subview hierarchy.
            // If we added it at index 0, it should be at (0,0) of the verifiable content area.
            // We just ensure it sticks to (0,0) origin despite transforms.
            grid.frame.origin = .zero
        }

        // MARK: - Undo / Redo

        @objc func handleUndo(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            canvasView?.undoManager?.undo()
        }

        @objc func handleRedo(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            canvasView?.undoManager?.redo()
        }
    }
}

// MARK: - CanvasView (Main SwiftUI View)

struct CanvasView: View {

    @Bindable var viewModel: CanvasViewModel
    @State private var showConnectedPages = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DrawingCanvas(
                drawing: $viewModel.currentDrawing,
                onDrawingChanged: { drawing in
                    viewModel.drawingDidChange(drawing)
                }
            )
            .ignoresSafeArea(.all, edges: .bottom)

            if viewModel.syncState != .idle {
                StatusPill(state: viewModel.syncState)
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.syncState)
        .navigationTitle($viewModel.document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Link Pages Button
                Button {
                    showConnectedPages = true
                } label: {
                    Image(systemName: "link")
                }
                .popover(isPresented: $showConnectedPages) {
                    ConnectedPagesSheet(viewModel: viewModel)
                        .frame(minWidth: 320, minHeight: 400)
                }

                // Open in Notion button
                if let pageID = viewModel.document.notionPageID {
                    Button {
                        let cleanID = pageID.replacingOccurrences(of: "-", with: "")
                        let urlString = "https://www.notion.so/\(cleanID)"
                        if let url = URL(string: urlString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                }

                // Force sync button
                Button {
                    viewModel.forceSyncNow()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(viewModel.syncState == .syncing || viewModel.currentDrawing.strokes.isEmpty)
            }
        }
        .task {
            // Ensure titles are loaded for existing links
            await viewModel.fetchRemoteProperties()
            await viewModel.refreshConnectedPageDetails()
        }
    }
}

// MARK: - Connected Pages Sheet

struct ConnectedPagesSheet: View {
    @Bindable var viewModel: CanvasViewModel
    @State private var searchQuery = ""
    @State private var searchResults: [CanvasViewModel.ConnectedPageItem] = []
    @State private var isSearching = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Section 1: Connected Pages
                Section("Connected Pages") {
                    if viewModel.connectedPages.isEmpty {
                        Text("No pages connected")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        ForEach(viewModel.connectedPages) { page in
                            HStack {
                                NotionIconView(icon: page.icon)
                                Text(page.title)
                                Spacer()
                                Button {
                                    viewModel.removeConnectedPage(id: page.id)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                // Section 2: Search
                Section("Link New Page") {
                    TextField("Search Notion...", text: $searchQuery)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    
                    if isSearching {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if !searchQuery.isEmpty && searchResults.isEmpty {
                        Text("No results found")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(searchResults) { page in
                            HStack {
                                NotionIconView(icon: page.icon)
                                Text(page.title)
                                Spacer()
                                if viewModel.document.connectedPageIDs.contains(page.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.green)
                                } else {
                                    Button {
                                        viewModel.addConnectedPage(page)
                                    } label: {
                                        Image(systemName: "plus.circle")
                                            .foregroundStyle(.blue)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Connect Pages")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: searchQuery) {
                guard !searchQuery.isEmpty else {
                    searchResults = []
                    return
                }
                
                // Debounce
                do {
                    isSearching = true
                    try await Task.sleep(for: .milliseconds(500))
                    let results = await viewModel.searchPages(query: searchQuery)
                    searchResults = results
                    isSearching = false
                } catch {
                    // Canceled
                }
            }
        }
    }
}

// MARK: - Notion Icon View

struct NotionIconView: View {
    let icon: String?
    
    var body: some View {
        if let icon = icon {
            if icon.hasPrefix("http") {
                AsyncImage(url: URL(string: icon)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Text(icon) // Emoji
            }
        } else {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Status Pill

struct StatusPill: View {

    let state: SyncState

    var body: some View {
        HStack(spacing: 6) {
            Group {
                switch state {
                case .syncing:
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                case .success:
                    Image(systemName: state.iconName)
                        .foregroundColor(.white)
                        .font(.system(size: 13, weight: .semibold))
                case .error:
                    Image(systemName: state.iconName)
                        .foregroundColor(.white)
                        .font(.system(size: 13, weight: .semibold))
                case .idle:
                    EmptyView()
                }
            }

            Text(state.displayText)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(pillColor.gradient)
                .shadow(color: pillColor.opacity(0.4), radius: 8, y: 4)
        )
    }

    private var pillColor: Color {
        switch state {
        case .idle:     return .clear
        case .syncing:  return .blue
        case .success:  return .green
        case .error:    return .red
        }
    }
}
