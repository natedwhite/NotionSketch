import Foundation

/// Simple file-based logger for sync debugging.
/// Writes to Documents/sync_log.txt on device.
enum SyncLogger {

    private static let fileName = "sync_log.txt"
    private static let maxLogSize = 1024 * 1024 // 1MB
    private static let fileLock = NSLock()

    private static var logFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(fileName)
    }

    /// Appends a timestamped line to the log file.
    static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        print("[Sync] \(message)")

        fileLock.lock()
        defer { fileLock.unlock() }

        do {
            let url = logFileURL

            // Check size and rotate if needed.
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64,
               size > maxLogSize {
                try rotateLog()
            }

            if !FileManager.default.fileExists(atPath: url.path) {
                guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                    throw NSError(
                        domain: "SyncLogger",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Could not create sync log file at \(url.path)"]
                    )
                }
            }

            let handle = try FileHandle(forWritingTo: url)
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) {
                handle.write(data)
                // Make the latest entry immediately visible to Settings/readLog().
                handle.synchronizeFile()
            }
        } catch {
            // Never hide logger failures: they remain visible in the Xcode/device console.
            print("[SyncLogger] File write failed: \(error.localizedDescription)")
        }
    }

    private static func rotateLog() throws {
        let url = logFileURL
        let oldURL = url.deletingPathExtension().appendingPathExtension("old.txt")

        if FileManager.default.fileExists(atPath: oldURL.path) {
            try FileManager.default.removeItem(at: oldURL)
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.moveItem(at: url, to: oldURL)
        }
    }

    /// Reads the tail of the log file to avoid main thread freeze.
    static func readLog() -> String {
        fileLock.lock()
        defer { fileLock.unlock() }

        let url = logFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return "(no sync log file yet)"
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { handle.closeFile() }

            let fileSize = handle.seekToEndOfFile()
            let maxReadSize: UInt64 = 20 * 1024 // 20KB
            let startOffset = fileSize > maxReadSize ? fileSize - maxReadSize : 0

            try handle.seek(toOffset: startOffset)
            let data = handle.readDataToEndOfFile()
            var text = String(data: data, encoding: .utf8) ?? "(binary log data)"

            if text.isEmpty {
                return "(sync log is empty)"
            }

            // If we truncated, add a note.
            if startOffset > 0 {
                text = "[... truncated first \(startOffset) bytes ...]\n" + text
            }
            return text
        } catch {
            return "Error reading sync log: \(error.localizedDescription)"
        }
    }

    /// Clears the log.
    static func clearLog() {
        fileLock.lock()
        defer { fileLock.unlock() }

        do {
            try Data().write(to: logFileURL, options: .atomic)
        } catch {
            print("[SyncLogger] Clear failed: \(error.localizedDescription)")
        }
    }
}
