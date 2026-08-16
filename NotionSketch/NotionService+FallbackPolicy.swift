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
}
