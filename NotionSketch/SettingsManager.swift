import Foundation
import Observation

/// Manages user settings (API token, database ID) persisted in UserDefaults.
@Observable
@MainActor
final class SettingsManager {

    // MARK: - Singleton

    static let shared = SettingsManager()

    // MARK: - Keys

    private enum Keys {
        static let apiToken = "notion_api_token"
        static let databaseID = "notion_database_id"
        static let connectedPagesDatabaseID = "notion_connected_pages_database_id"
        static let shortIoApiKey = "short_io_api_key"
        static let shortIoDomain = "short_io_domain"
    }

    private enum Constants {
        static let keychainService = "com.notionsketch.auth"
    }

    // MARK: - Stored Properties

    var apiToken: String {
        didSet {
            KeychainHelper.standard.save(apiToken, service: Constants.keychainService, account: Keys.apiToken)
        }
    }
    
    var shortIoApiKey: String {
        didSet {
            KeychainHelper.standard.save(shortIoApiKey, service: Constants.keychainService, account: Keys.shortIoApiKey)
        }
    }
    
    var shortIoDomain: String {
        didSet { UserDefaults.standard.set(shortIoDomain, forKey: Keys.shortIoDomain) }
    }

    /// Raw input from the user — could be a full Notion URL or just the ID.
    var databaseInput: String {
        didSet {
            let extracted = SettingsManager.extractDatabaseID(from: databaseInput)
            UserDefaults.standard.set(extracted, forKey: Keys.databaseID)
        }
    }

    /// The cleaned database ID (always a UUID with dashes).
    var databaseID: String {
        SettingsManager.extractDatabaseID(from: databaseInput)
    }
    
    /// Raw input for the Connected Pages database.
    var connectedPagesDatabaseInput: String {
        didSet {
            let extracted = SettingsManager.extractDatabaseID(from: connectedPagesDatabaseInput)
            UserDefaults.standard.set(extracted, forKey: Keys.connectedPagesDatabaseID)
        }
    }
    
    /// The cleaned Connected Pages database ID.
    var connectedPagesDatabaseID: String {
        SettingsManager.extractDatabaseID(from: connectedPagesDatabaseInput)
    }

    // MARK: - Computed

    /// Returns `true` when both the API token and database ID are non-empty.
    var isConfigured: Bool {
        !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !databaseID.isEmpty
    }

    // MARK: - Init

    private init() {
        // Load apiToken (with migration from UserDefaults)
        if let legacyApiToken = UserDefaults.standard.string(forKey: Keys.apiToken) {
            self.apiToken = legacyApiToken
            KeychainHelper.standard.save(legacyApiToken, service: Constants.keychainService, account: Keys.apiToken)
            UserDefaults.standard.removeObject(forKey: Keys.apiToken)
        } else {
            self.apiToken = KeychainHelper.standard.read(service: Constants.keychainService, account: Keys.apiToken) ?? ""
        }

        // Load shortIoApiKey (with migration from UserDefaults)
        if let legacyShortIoKey = UserDefaults.standard.string(forKey: Keys.shortIoApiKey) {
            self.shortIoApiKey = legacyShortIoKey
            KeychainHelper.standard.save(legacyShortIoKey, service: Constants.keychainService, account: Keys.shortIoApiKey)
            UserDefaults.standard.removeObject(forKey: Keys.shortIoApiKey)
        } else {
            self.shortIoApiKey = KeychainHelper.standard.read(service: Constants.keychainService, account: Keys.shortIoApiKey) ?? ""
        }

        self.shortIoDomain = UserDefaults.standard.string(forKey: Keys.shortIoDomain) ?? "short.gy"
        // Load saved database ID and put it in databaseInput
        self.databaseInput = UserDefaults.standard.string(forKey: Keys.databaseID) ?? ""
        self.connectedPagesDatabaseInput = UserDefaults.standard.string(forKey: Keys.connectedPagesDatabaseID) ?? ""
    }

    // MARK: - URL Parsing

    /// Extracts a Notion database ID from a pasted URL or raw ID string.
    ///
    /// Supports formats like:
    /// - `https://www.notion.so/workspace/abc123def456...?v=...`
    /// - `https://notion.so/abc123def456...`
    /// - `abc123def456...` (raw 32-char hex)
    /// - `abc123de-f456-7890-abcd-ef1234567890` (UUID with dashes)
    static func extractDatabaseID(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Try to parse as URL first
        if let url = URL(string: trimmed), let host = url.host,
           host.contains("notion") {
            // The path looks like /workspace/Title-<id> or just /<id>
            let path = url.path
            // Remove leading slash and split by /
            let segments = path.split(separator: "/")

            // The last path segment contains the ID (possibly with a title prefix)
            if let lastSegment = segments.last {
                let segmentStr = String(lastSegment)
                // The ID is the last 32 hex characters of the segment
                if let id = extractHexID(from: segmentStr) {
                    return formatAsUUID(id)
                }
            }
        }

        // Try to extract a 32-char hex ID directly from the input
        if let id = extractHexID(from: trimmed) {
            return formatAsUUID(id)
        }

        // Already a UUID with dashes? Return as-is if valid
        let noDashes = trimmed.replacingOccurrences(of: "-", with: "")
        if noDashes.count == 32 && noDashes.allSatisfy(\.isHexDigit) {
            return formatAsUUID(noDashes)
        }

        // Can't parse — return the raw input so the error is visible to the user
        return trimmed
    }

    /// Finds 32 consecutive hex characters at the end of a string.
    private static func extractHexID(from string: String) -> String? {
        // Remove any query parameters
        let noQuery = string.components(separatedBy: "?").first ?? string

        // Remove dashes to normalize
        let noDashes = noQuery.replacingOccurrences(of: "-", with: "")

        // Look for a 32-char hex sequence at the end
        guard noDashes.count >= 32 else { return nil }

        let suffix = String(noDashes.suffix(32))
        guard suffix.allSatisfy(\.isHexDigit) else { return nil }

        return suffix
    }

    /// Formats a 32-char hex string as a UUID with dashes (8-4-4-4-12).
    private static func formatAsUUID(_ hex: String) -> String {
        guard hex.count == 32 else { return hex }
        let chars = Array(hex)
        let parts = [
            String(chars[0..<8]),
            String(chars[8..<12]),
            String(chars[12..<16]),
            String(chars[16..<20]),
            String(chars[20..<32])
        ]
        return parts.joined(separator: "-")
    }
}
