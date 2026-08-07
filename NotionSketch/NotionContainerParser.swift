import Foundation

// MARK: - Container Reference

/// Represents the type of Notion container the app is using.
enum NotionContainerRef: Equatable {
    case database(id: String)
    case dataSource(id: String)

    var id: String {
        switch self {
        case .database(let id), .dataSource(let id): return id
        }
    }

    var isDataSource: Bool {
        switch self {
        case .dataSource: return true
        case .database: return false
        }
    }
}

// MARK: - Resolved Container

struct ResolvedNotionContainer: Equatable {
    let ref: NotionContainerRef
    let fallbackDatabaseID: String?
}

// MARK: - Shared Parser

enum NotionContainerParser {
    /// Normalizes a raw ID string to lowercase dashed UUID form (8-4-4-4-12).
    /// Returns nil if the value is not a valid 32-character hex string.
    static func normalizedID(_ input: String) -> String? {
        var hex = input.trimmingCharacters(in: .whitespacesAndNewlines)
        hex = hex.replacingOccurrences(of: "-", with: "")

        guard hex.count == 32 else { return nil }
        guard hex.allSatisfy(\.isHexDigit) else { return nil }

        let lower = hex.lowercased()
        let c = Array(lower)
        return "\(String(c[0..<8]))-\(String(c[8..<12]))-\(String(c[12..<16]))-\(String(c[16..<20]))-\(String(c[20..<32]))"
    }

    /// Parses raw user input into a NotionContainerRef.
    /// Returns nil for malformed, short, non-hex, unrelated-host, or arbitrary text input.
    static func parse(_ input: String) -> NotionContainerRef? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Attempt URL parsing
        if let components = URLComponents(string: trimmed),
           let scheme = components.scheme,
           let host = components.host {

            // Require http or https
            guard scheme.lowercased() == "http" || scheme.lowercased() == "https" else { return nil }

            // Require notion.so, *.notion.so, notion.site, *.notion.site, notion.com, *.notion.com, app.notion.com, or *.app.notion.com (case-insensitive)
            let lowerHost = host.lowercased()
            let isNotionSo = lowerHost == "notion.so" || lowerHost.hasSuffix(".notion.so")
            let isNotionSite = lowerHost == "notion.site" || lowerHost.hasSuffix(".notion.site")
            let isNotionCom = lowerHost == "notion.com" || lowerHost.hasSuffix(".notion.com")
            let isAppNotion = lowerHost == "app.notion.com" || lowerHost.hasSuffix(".app.notion.com")
            guard isNotionSo || isNotionSite || isNotionCom || isAppNotion else { return nil }

            // 1. Check query items FIRST (ds= or data_source=)
            if let queryItems = components.queryItems {
                for item in queryItems {
                    if item.name == "ds" || item.name == "data_source" {
                        if let value = item.value, !value.isEmpty,
                           let normalized = normalizedID(value) {
                            return .dataSource(id: normalized)
                        }
                    }
                }
            }

            // 2. Check path segments for data_sources/<id> or data-source/<id>
            let path = components.path
            let segments = path.split(separator: "/").compactMap { String($0).trimmingCharacters(in: .whitespaces) }
            let nonEmptySegments = segments.filter { !$0.isEmpty }

            for (index, segment) in nonEmptySegments.enumerated() {
                if segment == "data_sources" || segment == "data-source" {
                    if index + 1 < nonEmptySegments.count,
                       let normalized = normalizedID(nonEmptySegments[index + 1]) {
                        return .dataSource(id: normalized)
                    }
                }
            }

            // 3. Parse final path component as database ID (with titled-component suffix fallbacks)
            if let lastSegment = nonEmptySegments.last {
                // 3a. Direct match
                if let normalized = normalizedID(lastSegment) {
                    return .database(id: normalized)
                }
                // 3b. Titled component ending in dashed UUID (36 chars)
                if lastSegment.count >= 36,
                   let normalized = normalizedID(String(lastSegment.suffix(36))) {
                    return .database(id: normalized)
                }
                // 3c. Titled component ending in undashed 32-char hex ID
                if lastSegment.count >= 32,
                   let normalized = normalizedID(String(lastSegment.suffix(32))) {
                    return .database(id: normalized)
                }
            }

            // URL was valid notion.so but no parsable ID found
            return nil
        }

        // Non-URL input: try to normalize as a database ID
        if let normalized = normalizedID(trimmed) {
            return .database(id: normalized)
        }

        return nil
    }
}
