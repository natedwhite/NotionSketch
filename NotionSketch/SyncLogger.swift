import Foundation

/// Simple file-based logger for sync debugging.
/// Writes to Documents/sync_log.txt on device.
enum SyncLogger {

    private static let fileName = "sync_log.txt"
    private static let maxLogSize = 1024 * 1024 // 1MB

    private static var logFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(fileName)
    }

    /// Appends a timestamped line to the log file.
    static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        print("[Sync] \(message)")

        let url = logFileURL
        
        // Check size and rotate if needed
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64, size > maxLogSize {
            rotateLog()
        }

        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    private static func rotateLog() {
        // Simple rotation: Rename current to .old, delete previous .old
        let url = logFileURL
        let oldUrl = url.deletingPathExtension().appendingPathExtension("old.txt")
        
        try? FileManager.default.removeItem(at: oldUrl)
        try? FileManager.default.moveItem(at: url, to: oldUrl)
    }

    /// Reads the tail of the log file to avoid main thread freeze.
    static func readLog() -> String {
        guard let handle = try? FileHandle(forReadingFrom: logFileURL) else { return "(no log file)" }
        let fileSize = handle.seekToEndOfFile()
        let maxReadSize: UInt64 = 20 * 1024 // 20KB
        
        let startOffset = fileSize > maxReadSize ? fileSize - maxReadSize : 0
        
        do {
            try handle.seek(toOffset: startOffset)
            let data = handle.readDataToEndOfFile()
            handle.closeFile()
            
            var text = String(data: data, encoding: .utf8) ?? "(binary log data)"
            
            // If we truncated, add a note
            if startOffset > 0 {
                text = "[... truncated first \(startOffset) bytes ...]\n" + text
            }
            return text
        } catch {
            return "Error reading log: \(error.localizedDescription)"
        }
    }

    /// Clears the log.
    static func clearLog() {
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
    }
}
