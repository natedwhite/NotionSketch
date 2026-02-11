import Foundation
import UIKit

// MARK: - Configuration

enum NotionConfig {
    static let apiVersion = "2025-09-03"
    static let baseURL = "https://api.notion.com/v1"
}

// MARK: - Notion API Errors

enum NotionServiceError: LocalizedError {
    case invalidURL
    case imageConversionFailed
    case uploadFailed(String)
    case appendFailed(String)
    case httpError(statusCode: Int, body: String)
    case decodingFailed(String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Notion API URL."
        case .imageConversionFailed:
            return "Failed to convert drawing to PNG data."
        case .uploadFailed(let reason):
            return "File upload failed: \(reason)"
        case .appendFailed(let reason):
            return "Failed to append blocks to Notion: \(reason)"
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        case .decodingFailed(let reason):
            return "Failed to decode response: \(reason)"
        case .notConfigured:
            return "Notion API token or Database ID not configured. Open Settings to add them."
        }
    }
}

// MARK: - File Upload Response Types

private struct FileUploadResponse: Decodable {
    let id: String
    let status: String
}

private struct SendFileUploadResponse: Decodable {
    let id: String
    let status: String
}

// MARK: - Page Creation Response

private struct CreatePageResponse: Decodable {
    let id: String
}

// MARK: - Database Schema Response (for finding title property name)

private struct DatabaseResponse: Decodable {
    let properties: [String: DatabaseProperty]?
}

private struct DatabaseProperty: Decodable {
    let type: String?
    let relation: RelationConfig?
}

private struct RelationConfig: Decodable {
    let database_id: String?
}

private struct PageDetailsResponse: Decodable {
    let id: String
    let properties: [String: PageProperty]
    let icon: NotionIcon?
}

private struct NotionIcon: Decodable {
    let type: String
    let emoji: String?
    let external: ExternalIcon?
    let file: FileIcon?
    
    var value: String? {
        if type == "emoji" { return emoji }
        if type == "external" { return external?.url }
        if type == "file" { return file?.url }
        return nil
    }
}

private struct ExternalIcon: Decodable { let url: String }
private struct FileIcon: Decodable { let url: String }

private struct RelationItem: Decodable { let id: String }

private struct PageProperty: Decodable {
    let type: String
    let title: [RichText]?
    let relation: [RelationItem]?
}

// MARK: - Block List Response (for clearing page)

private struct BlockChildrenResponse: Decodable {
    let results: [BlockResult]
    let hasMore: Bool
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case results
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}

private struct BlockResult: Decodable {
    let id: String
}

// MARK: - Notion Block Types (Encodable)

private struct AppendChildrenRequest: Encodable {
    let children: [Block]
}

private struct Block: Encodable {
    let object = "block"
    let type: String
    let paragraph: ParagraphBlock?
    let image: ImageBlock?

    enum CodingKeys: String, CodingKey {
        case object, type, paragraph, image
    }

    static func paragraphBlock(text: String) -> Block {
        Block(
            type: "paragraph",
            paragraph: ParagraphBlock(richText: [
                RichText(
                    type: "text",
                    text: TextContent(content: text, link: nil),
                    annotations: Annotations(italic: true)
                )
            ]),
            image: nil
        )
    }

    static func imageBlock(fileUploadID: String) -> Block {
        Block(
            type: "image",
            paragraph: nil,
            image: ImageBlock(
                type: "file_upload",
                fileUpload: FileUploadRef(id: fileUploadID)
            )
        )
    }
}

private struct ParagraphBlock: Encodable {
    let richText: [RichText]

    enum CodingKeys: String, CodingKey {
        case richText = "rich_text"
    }
}

private struct RichText: Codable {
    let type: String
    let text: TextContent
    let annotations: Annotations?
}

private struct TextContent: Codable {
    let content: String
    let link: LinkContent?
}

private struct LinkContent: Codable {
    let url: String
}

private struct Annotations: Codable {
    let italic: Bool
    let bold: Bool
    let strikethrough: Bool
    let underline: Bool
    let code: Bool
    let color: String
    
    // Helper init for creating simple annotations
    init(italic: Bool = false) {
        self.italic = italic
        self.bold = false
        self.strikethrough = false
        self.underline = false
        self.code = false
        self.color = "default"
    }
}

private struct ImageBlock: Encodable {
    let type: String
    let fileUpload: FileUploadRef?

    enum CodingKeys: String, CodingKey {
        case type
        case fileUpload = "file_upload"
    }
}

private struct FileUploadRef: Encodable {
    let id: String
}

// MARK: - NotionService Actor

/// Thread-safe actor responsible for all Notion API communication.
/// Reads the API token dynamically from `SettingsManager` on each call.
actor NotionService {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Token Access

    /// Reads the current API token from SettingsManager (must hop to MainActor).
    private func getToken() async -> String {
        await MainActor.run { SettingsManager.shared.apiToken }
    }

    private func getDatabaseID() async -> String {
        await MainActor.run { SettingsManager.shared.databaseID }
    }

    // MARK: - Common Helpers

    private func authorizedRequest(url: URL, method: String = "GET") async throws -> URLRequest {
        let token = await getToken()
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NotionServiceError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(NotionConfig.apiVersion, forHTTPHeaderField: "Notion-Version")
        return request
    }

    private func validate(_ data: Data, _ response: URLResponse) throws -> Data {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionServiceError.appendFailed("Invalid response type.")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw NotionServiceError.httpError(statusCode: httpResponse.statusCode, body: body)
        }
        return data
    }

    // MARK: - File Upload: Step 1 — Create

    private func createFileUpload(filename: String, contentType: String) async throws -> String {
        guard let url = URL(string: "\(NotionConfig.baseURL)/file_uploads") else {
            throw NotionServiceError.invalidURL
        }

        var request = try await authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "mode": "single_part",
            "filename": filename,
            "content_type": contentType
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let validatedData = try validate(data, response)

        let decoded: FileUploadResponse
        do {
            decoded = try JSONDecoder().decode(FileUploadResponse.self, from: validatedData)
        } catch {
            let raw = String(data: validatedData, encoding: .utf8) ?? "<binary>"
            throw NotionServiceError.decodingFailed("createFileUpload: \(error.localizedDescription) — raw: \(raw)")
        }

        guard decoded.status == "pending" else {
            throw NotionServiceError.uploadFailed("Unexpected status: \(decoded.status)")
        }

        return decoded.id
    }

    // MARK: - File Upload: Step 2 — Send

    private func sendFileUpload(
        fileUploadID: String,
        fileData: Data,
        filename: String,
        contentType: String
    ) async throws {
        guard let url = URL(string: "\(NotionConfig.baseURL)/file_uploads/\(fileUploadID)/send") else {
            throw NotionServiceError.invalidURL
        }

        let boundary = "NotionSketch-\(UUID().uuidString)"

        var request = try await authorizedRequest(url: url, method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(contentType)\r\n")
        body.append("\r\n")
        body.append(fileData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        let validatedData = try validate(data, response)

        let decoded: SendFileUploadResponse
        do {
            decoded = try JSONDecoder().decode(SendFileUploadResponse.self, from: validatedData)
        } catch {
            let raw = String(data: validatedData, encoding: .utf8) ?? "<binary>"
            throw NotionServiceError.decodingFailed("sendFileUpload: \(error.localizedDescription) — raw: \(raw)")
        }

        guard decoded.status == "uploaded" else {
            throw NotionServiceError.uploadFailed("File upload did not complete. Status: \(decoded.status)")
        }
    }

    // MARK: - Public: Upload Drawing Image

    /// Full file upload pipeline → returns the Notion File Upload ID.
    func uploadDrawingImage(_ image: UIImage) async throws -> String {
        guard let pngData = image.pngData() else {
            throw NotionServiceError.imageConversionFailed
        }

        let filename = "sketch_\(ISO8601DateFormatter().string(from: Date())).png"

        let fileUploadID = try await createFileUpload(filename: filename, contentType: "image/png")
        try await sendFileUpload(fileUploadID: fileUploadID, fileData: pngData, filename: filename, contentType: "image/png")

        return fileUploadID
    }

    // MARK: - Create Page in Database

    /// Creates a new page in the configured Notion database with the given title.
    ///
    /// `POST /v1/pages`
    ///
    /// - Parameter title: The page title (maps to the database's title property).
    /// - Returns: The newly created Notion page ID.
    func createPageInDatabase(title: String, ocrText: String? = nil, appLink: String? = nil) async throws -> String {
        let databaseID = await getDatabaseID()
        guard !databaseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NotionServiceError.notConfigured
        }

        // First, query the database to find its title property name
        let titlePropertyName = try await getDatabaseTitlePropertyName(databaseID: databaseID)

        guard let url = URL(string: "\(NotionConfig.baseURL)/pages") else {
            throw NotionServiceError.invalidURL
        }

        var request = try await authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build the page creation payload using the actual title property name
        var properties: [String: Any] = [
            titlePropertyName: [
                "title": [
                    ["text": ["content": title]]
                ]
            ]
        ]
        
        if let ocrText {
             properties["OCR"] = [ "rich_text": [ ["text": ["content": ocrText]] ] ]
        }
        
        var finalAppLink = appLink
        if let link = appLink, link.hasPrefix("notionsketch") {
            if let short = await shortenURL(link) {
                finalAppLink = short
            }
        }

        if let finalAppLink {
             properties["Open in App"] = [ "url": finalAppLink ]
        }

        let payload: [String: Any] = [
            "parent": ["database_id": databaseID],
            "properties": properties
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        let validatedData = try validate(data, response)

        let decoded: CreatePageResponse
        do {
            decoded = try JSONDecoder().decode(CreatePageResponse.self, from: validatedData)
        } catch {
            let raw = String(data: validatedData, encoding: .utf8) ?? "<binary>"
            throw NotionServiceError.decodingFailed("createPage: \(error.localizedDescription) — raw: \(raw.prefix(300))")
        }

        return decoded.id
    }

    // MARK: - Query Database Schema

    /// Retrieves the database and finds the name of the title property.
    /// Notion databases always have exactly one title property, but its name varies.
    private func getDatabaseTitlePropertyName(databaseID: String) async throws -> String {
        guard let url = URL(string: "\(NotionConfig.baseURL)/databases/\(databaseID)") else {
            throw NotionServiceError.invalidURL
        }

        let request = try await authorizedRequest(url: url, method: "GET")
        let (data, response) = try await session.data(for: request)
        let validatedData = try validate(data, response)

        let decoded: DatabaseResponse
        do {
            decoded = try JSONDecoder().decode(DatabaseResponse.self, from: validatedData)
        } catch {

            let raw = String(data: validatedData, encoding: .utf8) ?? "<binary>"
            throw NotionServiceError.decodingFailed("dbSchema: \(error.localizedDescription) — raw: \(raw.prefix(1000))")
        }

        // Find the property whose type is "title"
        for (name, property) in decoded.properties ?? [:] {
            if property.type == "title" {
                return name
            }
        }

        // Fallback — shouldn't happen since every database has a title property
        return "Name"
    }

    // MARK: - Clear Page Blocks

    /// Deletes all existing block children from a page (for re-sync / update flow).
    ///
    /// - Parameter pageID: The Notion page to clear.
    func clearPageBlocks(pageID: String) async throws {
        var cursor: String? = nil

        // Paginate through all blocks and collect IDs
        var blockIDs: [String] = []

        repeat {
            var urlString = "\(NotionConfig.baseURL)/blocks/\(pageID)/children?page_size=100"
            if let cursor {
                urlString += "&start_cursor=\(cursor)"
            }

            guard let url = URL(string: urlString) else {
                throw NotionServiceError.invalidURL
            }

            let request = try await authorizedRequest(url: url, method: "GET")
            let (data, response) = try await session.data(for: request)
            let validatedData = try validate(data, response)

            let decoded: BlockChildrenResponse
            do {
                decoded = try JSONDecoder().decode(BlockChildrenResponse.self, from: validatedData)
            } catch {
                let raw = String(data: validatedData, encoding: .utf8) ?? "<binary>"
                throw NotionServiceError.decodingFailed("blockChildren: \(error.localizedDescription) — raw: \(raw.prefix(300))")
            }

            blockIDs.append(contentsOf: decoded.results.map(\.id))
            cursor = decoded.hasMore ? decoded.nextCursor : nil

        } while cursor != nil

        // Delete each block
        for blockID in blockIDs {
            guard let url = URL(string: "\(NotionConfig.baseURL)/blocks/\(blockID)") else {
                continue
            }

            let request = try await authorizedRequest(url: url, method: "DELETE")
            let (data, response) = try await session.data(for: request)
            _ = try validate(data, response)
        }
    }

    // MARK: - Append Blocks to Page

    /// Appends paragraph + image blocks to the specified Notion page.
    ///
    /// - Parameters:
    ///   - pageID: The Notion page ID to append blocks to.
    ///   - fileUploadID: The Notion File Upload ID.
    ///   - recognizedText: OCR-extracted text (may be empty).
    func appendToNotionPage(pageID: String, fileUploadID: String, recognizedText: String) async throws {
        let urlString = "\(NotionConfig.baseURL)/blocks/\(pageID)/children"

        guard let url = URL(string: urlString) else {
            throw NotionServiceError.invalidURL
        }

        var children: [Block] = []



        children.append(Block.imageBlock(fileUploadID: fileUploadID))

        let requestBody = AppendChildrenRequest(children: children)

        var request = try await authorizedRequest(url: url, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await session.data(for: request)
        _ = try validate(data, response)
    }

    // MARK: - Update Page Properties

    /// Updates properties of an existing page: Title, OCR text, and Deep Link.
    func updatePageProperties(pageID: String, title: String? = nil, ocrText: String? = nil, appLink: String? = nil) async throws {
        guard let url = URL(string: "\(NotionConfig.baseURL)/pages/\(pageID)") else {
            throw NotionServiceError.invalidURL
        }
        
        var properties: [String: Any] = [:]
        
        if let title {
             // We need the title property name. It's safe to re-fetch or assume "Name". 
             // Ideally we should cache or reuse logic, but fetching schema every time is safer for correctness.
             let dbID = await getDatabaseID()
             let titleProp = try await getDatabaseTitlePropertyName(databaseID: dbID)
             properties[titleProp] = [ "title": [ ["text": ["content": title]] ] ]
        }

        if let ocrText {
            properties["OCR"] = [ "rich_text": [ ["text": ["content": ocrText]] ] ]
        }


        var finalAppLink = appLink
        if let link = appLink, link.hasPrefix("notionsketch") {
            if let short = await shortenURL(link) {
                finalAppLink = short
            }
        }

        if let finalAppLink {
            properties["Open in App"] = [ "url": finalAppLink ]
        }
        
        // If nothing to update, return early
        guard !properties.isEmpty else { return }
        
        let payload = ["properties": properties]
        
        var request = try await authorizedRequest(url: url, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        
        do {
             _ = try validate(data, response)
        } catch {
             let raw = String(data: data, encoding: .utf8) ?? "<binary>"
             // If property is missing, Notion returns 400 validation_error.
             // We log this as a warning but allow the sync to proceed (clearing blocks/appending image).
            if raw.contains("validation_error") || raw.contains("property_not_found") || raw.contains("does not exist") {
                SyncLogger.log("⚠️ Property update skipped (Missing Notion Property?): \(raw)")
                return
            }
            throw NotionServiceError.decodingFailed("updatePage: \(error.localizedDescription) — raw: \(raw.prefix(300))")
        }
    }
    
    // MARK: - URL Shortening (Workaround for Notion iOS)
    
    /// Shortens a URL using Short.io (priority) or TinyURL (fallback).
    /// This "tricks" Notion iOS into opening the link by adding a web redirect.
    private func shortenURL(_ urlString: String) async -> String? {
        let apiKey = await MainActor.run { SettingsManager.shared.shortIoApiKey }
        let domain = await MainActor.run { SettingsManager.shared.shortIoDomain }
        
        // Priority: Short.io (Ad-Free) if API key is configured
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let short = await shortenShortIo(urlString, apiKey: apiKey, domain: domain) {
                SyncLogger.log("🔗 Shortened with Short.io: \(short)")
                return short
            }
            SyncLogger.log("⚠️ Short.io failed, falling back to TinyURL")
        }
        
        // Fallback: TinyURL (Default)
        if let short = await shortenTinyURL(urlString) {
            SyncLogger.log("🔗 Shortened with TinyURL (Fallback): \(short)")
            return short
        }
        return nil
    }
    
    private func shortenShortIo(_ originalURL: String, apiKey: String, domain: String) async -> String? {
        guard let apiURL = URL(string: "https://api.short.io/links") else { return nil }
        
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "domain": domain.trimmingCharacters(in: .whitespacesAndNewlines),
            "originalURL": originalURL
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let raw = String(data: data, encoding: .utf8)
                SyncLogger.log("⚠️ Short.io API Error: \(httpResponse.statusCode) — \(raw ?? "")")
                return nil
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let shortURL = json["shortURL"] as? String {
                return shortURL
            }
            return nil
        } catch {
            SyncLogger.log("⚠️ Short.io Request failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func shortenTinyURL(_ urlString: String) async -> String? {
        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let apiURL = URL(string: "https://tinyurl.com/api-create.php?url=\(encoded)") else {
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: apiURL)
            if let short = String(data: data, encoding: .utf8), short.hasPrefix("https://tinyurl.com/") {
                return short
            }
            return nil
        } catch {
             SyncLogger.log("⚠️ TinyURL failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Fetch Page Details (Title + Icon + Relations)
    
    /// Fetches the current title, icon, and connected page IDs from Notion.
    func fetchPageDetails(pageID: String) async throws -> (title: String, icon: String?, connectedIDs: [String])? {
        guard let url = URL(string: "\(NotionConfig.baseURL)/pages/\(pageID)") else {
            throw NotionServiceError.invalidURL
        }
        
        let request = try await authorizedRequest(url: url, method: "GET")
        let (data, response) = try await session.data(for: request)
        let validatedData = try validate(data, response)
        
        let decoded: PageDetailsResponse
        do {
            decoded = try JSONDecoder().decode(PageDetailsResponse.self, from: validatedData)
        } catch {
            let raw = String(data: validatedData, encoding: .utf8) ?? "<binary>"
            throw NotionServiceError.decodingFailed("fetchPage: \(error.localizedDescription) — raw: \(raw.prefix(300))")
        }
        
        // Find title property and connected pages relation
        var title = "Untitled"
        var connectedIDs: [String] = []
        
        for (key, property) in decoded.properties {
            if property.type == "title", let titleObjects = property.title {
                title = titleObjects.map { $0.text.content }.joined()
            } else if property.type == "relation", key == "Connected Pages", let relations = property.relation {
                connectedIDs = relations.map { $0.id }
            }
        }
        
        return (title, decoded.icon?.value, connectedIDs)
    }
    
    // MARK: - Archive (Trash) a Page

    
    /// Archives (trashes) a Notion page. Used when a sketch is deleted locally.
    func archivePage(pageID: String) async throws {
        guard let url = URL(string: "\(NotionConfig.baseURL)/pages/\(pageID)") else {
            throw NotionServiceError.invalidURL
        }
        
        var request = try await authorizedRequest(url: url, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = ["archived": true]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        _ = try validate(data, response)
        
        SyncLogger.log("🗑️ Archived Notion page: \(pageID)")
    }
    
    // MARK: - Fetch Active Page IDs (for deletion sync)
    
    /// Queries the database and returns a set of non-archived page IDs.
    /// Used to detect pages deleted/archived in Notion.
    func fetchActivePageIDs() async throws -> Set<String> {
        let rawDatabaseID = await getDatabaseID()
        let databaseID = rawDatabaseID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !databaseID.isEmpty else {
            throw NotionServiceError.notConfigured
        }
        
        // Step 1: Get the data source ID from the database
        // (API version 2025-09-03 deprecated POST /databases/{id}/query
        //  in favor of POST /data_sources/{data_source_id}/query)
        let dataSourceID = try await getDataSourceID(databaseID: databaseID)
        
        let urlString = "\(NotionConfig.baseURL)/data_sources/\(dataSourceID)/query"
        SyncLogger.log("🔍 fetchActivePageIDs URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            SyncLogger.log("❌ fetchActivePageIDs: Could not create URL from: \(urlString)")
            throw NotionServiceError.invalidURL
        }
        
        var allPageIDs = Set<String>()
        var hasMore = true
        var startCursor: String? = nil
        
        while hasMore {
            var request = try await authorizedRequest(url: url, method: "POST")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            var payload: [String: Any] = [
                "page_size": 100
            ]
            if let cursor = startCursor {
                payload["start_cursor"] = cursor
            }
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? "<no body>"
                SyncLogger.log("❌ fetchActivePageIDs HTTP \(httpResponse.statusCode): \(body)")
            }
            
            let validatedData = try validate(data, response)
            
            guard let json = try JSONSerialization.jsonObject(with: validatedData) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else {
                break
            }
            
            for page in results {
                if let id = page["id"] as? String,
                   let archived = page["archived"] as? Bool,
                   !archived {
                    allPageIDs.insert(id)
                }
            }
            
            hasMore = (json["has_more"] as? Bool) ?? false
            startCursor = json["next_cursor"] as? String
        }
        
        SyncLogger.log("📋 Fetched \(allPageIDs.count) active pages from Notion")
        return allPageIDs
    }
    
    // MARK: - Data Source ID Resolution
    
    /// Retrieves the data_source_id for a database (required for API version 2025-09-03+).
    /// The database object contains a `data_sources` array; we use the first one.
    private func getDataSourceID(databaseID: String) async throws -> String {
        guard let url = URL(string: "\(NotionConfig.baseURL)/databases/\(databaseID)") else {
            throw NotionServiceError.invalidURL
        }
        
        let request = try await authorizedRequest(url: url, method: "GET")
        let (data, response) = try await session.data(for: request)
        let validatedData = try validate(data, response)
        
        guard let json = try JSONSerialization.jsonObject(with: validatedData) as? [String: Any] else {
            throw NotionServiceError.decodingFailed("Could not parse database response")
        }
        
        // data_sources is an array of objects, each with an "id" field
        if let dataSources = json["data_sources"] as? [[String: Any]],
           let firstDS = dataSources.first,
           let dsID = firstDS["id"] as? String {
            SyncLogger.log("🔗 Resolved data_source_id: \(dsID)")
            return dsID
        }
        
        if let dataSource = json["data_source"] as? [String: Any],
           let dsID = dataSource["id"] as? String {
            SyncLogger.log("🔗 Resolved data_source_id (singular): \(dsID)")
            return dsID
        }
        
        SyncLogger.log("⚠️ No data_sources found, trying database ID as fallback")
        return databaseID
    }
    
    // MARK: - Search Pages
    
    /// Searches for pages in Notion matching the query string.
    /// Returns a list of (id, title, icon) tuples.
    func searchNotionPages(query: String) async throws -> [(id: String, title: String, icon: String?)] {
        guard let url = URL(string: "\(NotionConfig.baseURL)/search") else {
            throw NotionServiceError.invalidURL
        }
        
        var request = try await authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "query": query,
            "filter": [
                "value": "page",
                "property": "object"
            ],
            "page_size": 20
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        let validatedData = try validate(data, response)
        
        // Decode manually since property names are dynamic
        guard let json = try JSONSerialization.jsonObject(with: validatedData) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }
        
        var foundPages: [(id: String, title: String, icon: String?)] = []
        
        for object in results {
            guard let id = object["id"] as? String,
                  let properties = object["properties"] as? [String: Any] else { continue }
            
            // Find title property
            var titleString = "Untitled"
            
            for (_, propValue) in properties {
                if let propDict = propValue as? [String: Any],
                   let type = propDict["type"] as? String,
                   type == "title",
                   let titleItems = propDict["title"] as? [[String: Any]] {
                    
                    titleString = titleItems.compactMap { item in
                        (item["text"] as? [String: Any])?["content"] as? String
                    }.joined()
                    break
                }
            }
            
            // Parse Icon
            var iconString: String? = nil
            if let iconDict = object["icon"] as? [String: Any],
               let type = iconDict["type"] as? String {
                if type == "emoji" {
                    iconString = iconDict["emoji"] as? String
                } else if type == "external" {
                    iconString = (iconDict["external"] as? [String: Any])?["url"] as? String
                } else if type == "file" {
                    iconString = (iconDict["file"] as? [String: Any])?["url"] as? String
                }
            }
            
            foundPages.append((id: id, title: titleString, icon: iconString))
        }
        
        return foundPages
    }
    
    // MARK: - Update Connected Pages (Relation)
    
    /// Updates the "Connected Pages" relation property for a given page.
    func updateConnectedPages(pageID: String, targetPageIDs: [String]) async throws {
        guard let url = URL(string: "\(NotionConfig.baseURL)/pages/\(pageID)") else {
            throw NotionServiceError.invalidURL
        }
        
        let relationObjects = targetPageIDs.map { ["id": $0] }
        
        let payload: [String: Any] = [
            "properties": [
                "Connected Pages": [
                    "relation": relationObjects
                ]
            ]
        ]
        
        var request = try await authorizedRequest(url: url, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        
        // Custom validation to catch missing property error
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 400 {
             let raw = String(data: data, encoding: .utf8) ?? ""
             if raw.contains("validation_error") || raw.contains("property_not_found") {
                 SyncLogger.log("⚠️ Failed to update 'Connected Pages': Property may not exist in Notion database.")
                 throw NotionServiceError.appendFailed("Property 'Connected Pages' not found in Notion.")
             }
        }
        
        _ = try validate(data, response)
        SyncLogger.log("🔗 Updated Connected Pages for \(pageID) -> \(targetPageIDs.count) links")
    }
    
    // MARK: - Fetch Connected Page Details
    
    /// Fetches details for a set of page IDs to resolve their titles and icons.
    func resolvePageDetails(pageIDs: [String]) async -> [String: (title: String, icon: String?)] {
        var resolved: [String: (title: String, icon: String?)] = [:]
        
        await withTaskGroup(of: (String, (String, String?)?).self) { group in
            for id in pageIDs {
                group.addTask {
                    if let details = try? await self.fetchPageDetails(pageID: id) {
                        return (id, (details.title, details.icon))
                    }
                    return (id, nil)
                }
            }
            
            for await (id, details) in group {
                if let d = details {
                    resolved[id] = d
                }
            }
        }
        return resolved
    }

    // MARK: - Targeted Database Query (Search inside a DB)
    
    /// Queries the parent database to find the 'Connected Pages' relation target database ID.
    func fetchConnectedPagesTargetDatabaseID() async throws -> String? {
        let databaseID = await getDatabaseID()
        guard !databaseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        
        let url = URL(string: "\(NotionConfig.baseURL)/databases/\(databaseID)")!
        let request = try await authorizedRequest(url: url)
        
        let (data, _) = try await session.data(for: request)
        let decoded = try JSONDecoder().decode(DatabaseResponse.self, from: data)
        
        // Find "Connected Pages" property (case-insensitive) and get its relation target
        let key = decoded.properties?.keys.first(where: { $0.localizedCaseInsensitiveCompare("Connected Pages") == .orderedSame })
        
        if let key = key,
           let property = decoded.properties?[key],
           let relation = property.relation {
            return relation.database_id
        }
        return nil
    }

    /// Queries a specific database for pages matching a title query.
    func queryDatabase(databaseID: String, query: String) async throws -> [(id: String, title: String, icon: String?)] {
        // 1. Get correct API endpoint (via Data Source ID usually)
        let dataSourceID = try await getDataSourceID(databaseID: databaseID)
        let url = URL(string: "\(NotionConfig.baseURL)/data_sources/\(dataSourceID)/query")!
        
        // 2. We need to filter by Title. But "Title" property name varies.
        // We'll fetch the target database schema to get its title property name first.
        let titleKey = try await getDatabaseTitlePropertyName(databaseID: databaseID)
        
        var request = try await authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "filter": [
                "property": titleKey,
                "title": [
                    "contains": query
                ]
            ],
            "page_size": 20
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        let validatedData = try validate(data, response)
        
        // Reuse parsing logic from searchNotionPages
        guard let json = try JSONSerialization.jsonObject(with: validatedData) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }
        
        var foundPages: [(id: String, title: String, icon: String?)] = []
        for object in results {
            guard let id = object["id"] as? String,
                  let properties = object["properties"] as? [String: Any] else { continue }
            
            // Find title property
            var titleString = "Untitled"
            for (_, propValue) in properties {
                if let propDict = propValue as? [String: Any],
                   let type = propDict["type"] as? String,
                   type == "title",
                   let titleItems = propDict["title"] as? [[String: Any]] {
                    
                    titleString = titleItems.compactMap { item in
                        (item["text"] as? [String: Any])?["content"] as? String
                    }.joined()
                    break
                }
            }
            
            // Parse Icon
            var iconString: String? = nil
            if let iconDict = object["icon"] as? [String: Any],
               let type = iconDict["type"] as? String {
                if type == "emoji" {
                    iconString = iconDict["emoji"] as? String
                } else if type == "external" {
                    iconString = (iconDict["external"] as? [String: Any])?["url"] as? String
                } else if type == "file" {
                    iconString = (iconDict["file"] as? [String: Any])?["url"] as? String
                }
            }
            foundPages.append((id: id, title: titleString, icon: iconString))
        }
        return foundPages
    }
}


// MARK: - Data + String Append Helper

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
