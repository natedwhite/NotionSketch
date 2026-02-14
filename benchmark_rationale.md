# Benchmark Rationale

## Current State

The `NotionService` methods `encodeDrawing` and `decodeDrawing` are currently `nonisolated` and synchronous. When called from `NotionSyncManager` (which is `@MainActor` isolated), they execute directly on the Main Thread.

These methods perform CPU-bound tasks:
1.  **Serialization**: `PKDrawing.dataRepresentation()` can be expensive for complex drawings.
2.  **Compression/Decompression**: `(data as NSData).compressed(using: .lzfse)` and `.decompressed(using: .lzfse)` involve heavy computation.
3.  **Base64 Encoding/Decoding**: While generally fast, it adds to the overhead for large datasets.

Executing these on the Main Thread blocks the UI, causing frame drops and unresponsiveness during sync operations, especially for large drawings.

## Optimization Strategy

The proposed optimization is to offload these tasks to a background thread using `Task.detached(priority: .userInitiated)`. This ensures that the heavy lifting happens concurrently, leaving the Main Thread free to handle UI updates.

The signatures will change from:
- `nonisolated func encodeDrawing(_ drawing: PKDrawing) throws -> String`
- `nonisolated func decodeDrawing(from base64String: String) throws -> PKDrawing`

To:
- `nonisolated func encodeDrawing(_ drawing: PKDrawing) async throws -> String`
- `nonisolated func decodeDrawing(from base64String: String) async throws -> PKDrawing`

## Performance Impact Justification

Since the development environment lacks iOS simulators and devices to run `XCTest` or `Instruments`, direct benchmarking is not possible. However, the performance benefits are theoretically guaranteed by the nature of concurrency in Swift:

1.  **Main Thread Unblocking**: By moving the work off the Main Actor, the UI remains responsive.
2.  **Concurrency**: Multiple sync operations (if parallelized in the future) can benefit from multi-core processing.

This change aligns with Apple's recommendations for handling expensive work in UI applications.
