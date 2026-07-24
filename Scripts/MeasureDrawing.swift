
import PencilKit
import Foundation
import UIKit

// Create a dummy drawing
let canvas = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 500, height: 500))
let tool = PKInkingTool(.pen, color: .black, width: 5)

// Simulate a stroke
// Note: We can't easily simulate touches in a CLI script without a host app context for UIEvent,
// but we can manually construct PKStroke if needed, or just create an empty drawing and realize it has some overhead.
// Actually, creating a PKDrawing programmatically with strokes is complex in pure Swift script.
// Instead, let's load a base64 string of a known simple drawing if possible, or just create a VERY simple stroke structure if we can.

// Attempt 2: Minimal PKDrawing
// Since we can't easily generate strokes, let's just checking the empty state overhead
// and maybe one simple path if possible.
let drawing = PKDrawing()
let data = drawing.dataRepresentation()
print("Empty Drawing Size: \(data.count) bytes")

// Let's create a more complex data structure to simulate compression
let complexString = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 100)
if let rawData = complexString.data(using: .utf8) {
    print("Simulated Complex Data Size: \(rawData.count) bytes")
    
    // Base64
    let base64 = rawData.base64EncodedString()
    print("Base64 Encoded Size: \(base64.count) chars")
}
