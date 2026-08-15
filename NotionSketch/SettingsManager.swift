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

    /// Cached data source ID resolved from the currently configured database.
    var dataSourceID: String {
        didSet { defaults.set(dataSourceID, forKey: Keys.dataSourceID) }
    }

    /// Raw input from the user — could be a database URL, data source URL, or just an ID.
    var containerInput: String {
        didSet {
            let trimmed = containerInput.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed, forKey: Keys.containerInput)

            // A resolved data source ID belongs to the previous container. Keeping it
            // after the user changes containers can make legacy paths address the wrong
            // object, so invalidate it immediately.
            let oldTrimmed = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != oldTrimmed, !dataSourceID.isEmpty {
                dataSourceID = ""
            }
        }
    }

    /// The cleaned container ID (always a UUID with dashes). Used by legacy code.
    var databaseID: String {
        NotionContainerParser.parse(containerInput)?.id ?? ""
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
    }

    // MARK: - Compatibility Extraction

    /// Extracts a Notion container ID from input using the shared parser.
    static func extractContainerID(from input: String) -> String {
        NotionContainerParser.parse(input)?.id ?? ""
    }
}
