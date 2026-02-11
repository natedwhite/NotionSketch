import Foundation

/// Simple file-based logger for sync debugging.
/// Writes to Documents/sync_log.txt on device.
enum SyncLogger {

    private static let fileName = "sync_log.txt"

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

    /// Reads the full log contents.
    static func readLog() -> String {
        (try? String(contentsOf: logFileURL, encoding: .utf8)) ?? "(no log file)"
    }

    /// Clears the log.
    static func clearLog() {
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
    }
}
