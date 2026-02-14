# Performance Benchmark Strategy: Optimized PKDrawing Access

## Problem Analysis

The `SketchDocument` class in `NotionSketch/SketchDocument.swift` currently deserializes `PKDrawing` data from `drawingData` every time the `drawing` computed property is accessed.

```swift
    var drawing: PKDrawing {
        get {
            guard !drawingData.isEmpty else { return PKDrawing() }
            return (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        }
        set {
            drawingData = newValue.dataRepresentation()
        }
    }
```

`PKDrawing(data:)` is a computationally expensive operation involving parsing and object graph reconstruction. In scenarios where `drawing` is accessed frequently (e.g., during rendering updates, thumbnail generation, or sync operations), this redundant deserialization causes significant overhead.

## Proposed Optimization

We introduce a transient caching mechanism using `@Transient private var _cachedDrawing: PKDrawing?`. The `drawing` property will first check this cache before attempting deserialization.

## Measurement Methodology (Theoretical)

Since the current development environment is Linux-based and lacks the iOS `PencilKit` framework and XCTest infrastructure, we cannot execute a live benchmark. However, the following methodology describes how the performance improvement would be verified in a standard iOS development environment.

### Benchmark Test Case

We would create a performance test using `XCTest`'s `measure` block.

```swift
import XCTest
import PencilKit
@testable import NotionSketch

final class SketchDocumentPerformanceTests: XCTestCase {

    func testDrawingAccessPerformance() {
        // Setup: Create a SketchDocument with a non-trivial amount of drawing data.
        // In a real test, we would load a sample drawing data file.
        let sampleData = Data(count: 1024 * 1024) // 1MB dummy data for simulation
        // Note: Real PKDrawing data would be needed for actual deserialization cost.

        let document = SketchDocument(drawingData: sampleData)

        // Measure the time taken to access the `drawing` property 1000 times.
        measure {
            for _ in 0..<1000 {
                _ = document.drawing
            }
        }
    }
}
```

### Expected Results

*   **Baseline (Current Implementation):** The `measure` block would execute `PKDrawing(data:)` 1000 times. Given that deserialization is O(N) with the size of the drawing data, this would be slow (e.g., several seconds for complex drawings).
*   **Optimized Implementation:** The first access would deserialize the data. Subsequent 999 accesses would return the cached reference, which is O(1).
*   **Improvement:** We expect a dramatic reduction in execution time, likely by orders of magnitude (e.g., from 2.5s to 0.001s for 1000 iterations on a complex drawing).

## Verification in `NotionSyncManager`

The `syncLibrary` function in `NotionSyncManager.swift` decodes a `PKDrawing` from Notion data and then initializes a `SketchDocument`.

```swift
let drawing = try notionService.decodeDrawing(from: drawingEncoded)
let drawingData = drawing.dataRepresentation()
let newSketch = SketchDocument(..., drawingData: drawingData, ...)
newSketch.updateThumbnail() // Accesses .drawing immediately
```

**Optimization:**
By passing the already decoded `drawing` to the `SketchDocument` initializer, we avoid an immediate re-deserialization when `updateThumbnail()` is called. This saves one full deserialization cycle per imported document during library sync.
