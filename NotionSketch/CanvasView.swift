import SwiftUI
import PencilKit

// MARK: - Dot Grid View (draws only visible dots, repositions via offset)

/// Fills its bounds with a dot grid, offset to match canvas scrolling.
/// Only draws dots visible on screen — zero memory overhead.
class DotGridView: UIView {

    /// The content-space coordinate at the screen origin (contentOffset / zoomScale)
    var contentSpaceOrigin: CGPoint = .zero
    var zoomScale: CGFloat = 1.0

    private let baseDotSpacing: CGFloat = 30
    private let dotRadius: CGFloat = 1.5

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let dotColor = UIColor.systemGray3.withAlphaComponent(0.5)
        ctx.setFillColor(dotColor.cgColor)

        let screenSpacing = baseDotSpacing * zoomScale
        guard screenSpacing > 4 else { return } // Don't draw at extreme zoom-out

        // Compute grid phase in CONTENT-SPACE (zoom-independent), then scale to screen.
        // This keeps dots stable during zoom.
        var cModX = contentSpaceOrigin.x.truncatingRemainder(dividingBy: baseDotSpacing)
        var cModY = contentSpaceOrigin.y.truncatingRemainder(dividingBy: baseDotSpacing)
        // Ensure positive modulo
        if cModX < 0 { cModX += baseDotSpacing }
        if cModY < 0 { cModY += baseDotSpacing }

        let modX = cModX * zoomScale
        let modY = cModY * zoomScale

        let r = dotRadius
        var x = -modX
        while x <= rect.width + screenSpacing {
            var y = -modY
            while y <= rect.height + screenSpacing {
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                y += screenSpacing
            }
            x += screenSpacing
        }
    }
}

// MARK: - DrawingCanvas (UIViewRepresentable)

// MARK: - Canvas Container (prevents sidebar scroll shift)

/// Container that preserves PKCanvasView's contentOffset across layout changes
/// (e.g. sidebar opening/closing).
class CanvasContainer: UIView {
    weak var canvasView: PKCanvasView?
    weak var dotGridView: DotGridView?

    /// Closure to activate the tool picker once the view is in a window.
    var onReadyToActivate: (() -> Void)?
    private var hasActivated = false
    private var hasSetInitialOffset = false

    override func layoutSubviews() {
        super.layoutSubviews()

        // Pin canvas to the RIGHT edge of the screen.
        // When the sidebar opens, the container shrinks from the left,
        // but the canvas stays screen-width and extends behind the sidebar (clipped).
        // This means the canvas never resizes → contentOffset never shifts.
        let screenWidth = UIScreen.main.bounds.width
        let canvasFrame = CGRect(
            x: bounds.width - screenWidth,
            y: 0,
            width: screenWidth,
            height: bounds.height
        )

        dotGridView?.frame = canvasFrame
        canvasView?.frame = canvasFrame

        // Set initial contentOffset once we have a real frame
        if !hasSetInitialOffset, bounds.height > 0, let cv = canvasView {
            hasSetInitialOffset = true
            cv.contentOffset = CGPoint(
                x: (DrawingCanvas.canvasSize - screenWidth) / 2,
                y: (DrawingCanvas.canvasSize - bounds.height) / 2
            )
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
    static let canvasSize: CGFloat = 4000

    @Binding var drawing: PKDrawing
    var onDrawingChanged: (PKDrawing) -> Void

    func makeUIView(context: Context) -> CanvasContainer {
        let container = CanvasContainer()
        container.clipsToBounds = true

        // --- Dot grid (behind, fills container) ---
        let dotGrid = DotGridView()
        container.addSubview(dotGrid)

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
        // once we have a real frame (avoids using UIScreen before layout)

        container.addSubview(canvasView)
        container.canvasView = canvasView
        container.dotGridView = dotGrid

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

        // Store references (tool picker is set up later in didMoveToWindow)
        context.coordinator.canvasView = canvasView
        context.coordinator.dotGridView = dotGrid

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
            let zoom = scrollView.zoomScale
            // Convert to content-space origin (zoom-independent)
            grid.contentSpaceOrigin = CGPoint(
                x: scrollView.contentOffset.x / zoom,
                y: scrollView.contentOffset.y / zoom
            )
            grid.zoomScale = zoom
            grid.setNeedsDisplay()
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
