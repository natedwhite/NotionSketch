import Foundation

extension NotionService {
    /// Fetches active page IDs for library sync while enforcing the migration's
    /// fallback contract: the legacy database endpoint is available only when
    /// the data-source request fails at the transport or HTTP layer.
    ///
    /// Decode and other semantic failures are surfaced to the caller. Falling
    /// back for those errors could hide an incompatible 2xx response and make a
    /// destructive library sync act on data from a different API path.
    internal func fetchActivePageIDsForLibrarySync() async throws -> Set<String> {
        let resolved = try await resolveSketchesContainer()

        switch resolved.ref {
        case .dataSource(let id):
            do {
                return try await queryActivePageIDs(ref: .dataSource(id: id))
            } catch {
                guard Self.allowsLegacyDatabaseFallback(for: error),
                      let fallbackDatabaseID = resolved.fallbackDatabaseID else {
                    SyncLogger.log(
                        "❌ Data source query failed (\(id)); legacy fallback not allowed: \(error.localizedDescription)"
                    )
                    throw error
                }

                SyncLogger.log(
                    "⚠️ Data source query transport/HTTP failure (\(id)); falling back to database (\(fallbackDatabaseID)): \(error.localizedDescription)"
                )
                return try await queryActivePageIDs(ref: .database(id: fallbackDatabaseID))
            }

        case .database(let id):
            return try await queryActivePageIDs(ref: .database(id: id))
        }
    }

    private static func allowsLegacyDatabaseFallback(for error: Error) -> Bool {
        if let notionError = error as? NotionServiceError {
            if case .httpError = notionError {
                return true
            }
            return false
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code != NSURLErrorCancelled
    }

    // MARK: - Page Title + Last-Edited Time

    /// Fetches a page's title and last-edited timestamp in one GET.
    ///
    /// Self-contained on purpose: the actor's request helpers (authorizedRequest,
    /// safeRequest, validate) are private to NotionService.swift, so this extension
    /// reads the token from SettingsManager directly and uses URLSession.shared.
    /// Library sync uses this for its last-write-wins pull check.
    internal func fetchPageTitleAndEditTime(pageID: String) async throws -> (title: String, lastEditedTime: Date?) {
        let token = await MainActor.run { SettingsManager.shared.apiToken }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NotionServiceError.notConfigured
        }

        guard let url = URL(string: "\(NotionConfig.baseURL)/pages/\(pageID)") else {
            throw NotionServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(NotionConfig.apiVersion, forHTTPHeaderField: "Notion-Version")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionServiceError.appendFailed("Invalid response type.")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw NotionServiceError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NotionServiceError.decodingFailed("fetchPageTitleAndEditTime: response was not a JSON object")
        }

        // Find the title property (property names are dynamic, so scan by type)
        var title = "Untitled"
        if let properties = json["properties"] as? [String: Any] {
            for (_, propValue) in properties {
                if let propDict = propValue as? [String: Any],
                   propDict["type"] as? String == "title",
                   let titleItems = propDict["title"] as? [[String: Any]] {
                    title = titleItems.compactMap { item in
                        (item["text"] as? [String: Any])?["content"] as? String
                    }.joined()
                    break
                }
            }
        }

        var lastEditedTime: Date? = nil
        if let timestamp = json["last_edited_time"] as? String {
            lastEditedTime = Self.parseNotionTimestamp(timestamp)
        }

        return (title, lastEditedTime)
    }

    /// Parses Notion's ISO-8601 timestamps, which normally carry fractional seconds.
    private static func parseNotionTimestamp(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}
