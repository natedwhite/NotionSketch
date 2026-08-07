import Foundation
import Observation

/// Manages user settings (API token, database ID) persisted in UserDefaults.
@Observable
@MainActor
final class SettingsManager {

    // MARK: - Singleton

    static let shared = SettingsManager()

    private let defaults: UserDefaults

    // MARK: - Keys

    private enum Keys {
        static let apiToken = "notion_api_token"
        static let databaseID = "notion_database_id" // Legacy key, migrated to containerInput
        static let containerInput = "notion_container_input"
        static let connectedPagesDatabaseID = "notion_connected_pages_database_id"
        static let shortIoApiKey = "short_io_api_key"
        static let shortIoDomain = "short_io_domain"
        static let dataSourceID = "notion_data_source_id"
    }

    // MARK: - Stored Properties

    var apiToken: String {
        didSet { defaults.set(apiToken, forKey: Keys.apiToken) }
    }

    var shortIoApiKey: String {
        didSet { defaults.set(shortIoApiKey, forKey: Keys.shortIoApiKey) }
    }

    var shortIoDomain: String {
        didSet { defaults.set(shortIoDomain, forKey: Keys.shortIoDomain) }
    }

    /// Cached data source ID resolved from the database via Notion API.
    var dataSourceID: String {
        didSet { defaults.set(dataSourceID, forKey: Keys.dataSourceID) }
    }

    /// Raw input from the user — could be a database URL, data source URL, or just an ID.
    var containerInput: String {
        didSet {
            defaults.set(containerInput.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.containerInput)
        }
    }

    /// The cleaned container ID (always a UUID with dashes). Used by legacy code.
    var databaseID: String {
        NotionContainerParser.parse(containerInput)?.id ?? ""
    }

    /// Raw input for the Connected Pages database.
    var connectedPagesDatabaseInput: String {
        didSet {
            let extracted = Self.extractContainerID(from: connectedPagesDatabaseInput)
            defaults.set(extracted, forKey: Keys.connectedPagesDatabaseID)
        }
    }

    /// The cleaned Connected Pages database ID.
    var connectedPagesDatabaseID: String {
        Self.extractContainerID(from: connectedPagesDatabaseInput)
    }

    // MARK: - Computed

    /// Returns `true` when both the API token and container are configured.
    var isConfigured: Bool {
        !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        NotionContainerParser.parse(containerInput) != nil
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.apiToken = defaults.string(forKey: Keys.apiToken) ?? ""
        self.shortIoApiKey = defaults.string(forKey: Keys.shortIoApiKey) ?? ""
        self.shortIoDomain = defaults.string(forKey: Keys.shortIoDomain) ?? "short.gy"
        self.dataSourceID = defaults.string(forKey: Keys.dataSourceID) ?? ""

        // Read both old and new keys
        let legacyValue = defaults.string(forKey: Keys.databaseID) ?? ""
        var newValue = defaults.string(forKey: Keys.containerInput) ?? ""

        // Migrate: if new value is missing, empty, or whitespace-only and legacy has content
        let newTrimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyTrimmed = legacyValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if newTrimmed.isEmpty && !legacyTrimmed.isEmpty {
            newValue = legacyValue
            defaults.set(legacyValue, forKey: Keys.containerInput)
        }

        self.containerInput = newValue
        self.connectedPagesDatabaseInput = defaults.string(forKey: Keys.connectedPagesDatabaseID) ?? ""
    }

    // MARK: - Compatibility Extraction

    /// Extracts a Notion container ID from input using the shared parser.
    static func extractContainerID(from input: String) -> String {
        NotionContainerParser.parse(input)?.id ?? ""
    }
}
