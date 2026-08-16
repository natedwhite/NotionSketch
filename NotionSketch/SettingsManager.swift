import Foundation
import Observation

/// App-side functions that write to Notion page properties. Raw values are used
/// as keys in the persisted property-mapping dictionary.
enum SketchPropertyFunction: String, CaseIterable, Codable {
    case title
    case ocrText
    case appLink

    /// The Notion property type each function requires.
    var requiredNotionType: String {
        switch self {
        case .title: return "title"
        case .ocrText: return "rich_text"
        case .appLink: return "url"
        }
    }

    /// Property name used when the user has not customized the mapping.
    /// `nil` for title means the data source's title property is discovered from its schema.
    var defaultPropertyName: String? {
        switch self {
        case .title: return nil
        case .ocrText: return "OCR"
        case .appLink: return "Open in App"
        }
    }
}

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
        static let propertyMappings = "notion_property_mappings"
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

    /// User-configured Notion property names, keyed by `SketchPropertyFunction.rawValue`.
    /// A missing key uses the function's default property name; an empty string
    /// explicitly unmaps the function so its property write is skipped.
    var propertyMappings: [String: String] {
        didSet {
            if let data = try? JSONEncoder().encode(propertyMappings) {
                defaults.set(data, forKey: Keys.propertyMappings)
            }
        }
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

        if let mappingData = defaults.data(forKey: Keys.propertyMappings),
           let decodedMappings = try? JSONDecoder().decode([String: String].self, from: mappingData) {
            self.propertyMappings = decodedMappings
        } else {
            self.propertyMappings = [:]
        }

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

    // MARK: - Property Mapping

    /// Returns the effective Notion property name for a sketch function.
    /// A missing mapping falls back to the function's default; an explicitly
    /// empty mapping returns nil, meaning the property write is skipped.
    /// Title defaults to nil, which means "discover the data source's title property".
    func mappedPropertyName(for function: SketchPropertyFunction) -> String? {
        if let mapped = propertyMappings[function.rawValue] {
            let trimmed = mapped.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return function.defaultPropertyName
    }

    // MARK: - Compatibility Extraction

    /// Extracts a Notion container ID from input using the shared parser.
    static func extractContainerID(from input: String) -> String {
        NotionContainerParser.parse(input)?.id ?? ""
    }
}
