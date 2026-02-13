import Foundation
import UIKit
import PencilKit
import Vision
import Observation

// MARK: - Configuration

enum NotionConfig {
    static let apiVersion = "2022-06-28"
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
    let rich_text: [RichText]?
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
    let type: String
    let code: CodeBlockResult?
    let toggle: ToggleBlockResult?
    let has_children: Bool?
}

private struct CodeBlockResult: Decodable {
    let caption: [RichText]
    let richText: [RichText]
    let language: String
    
    enum CodingKeys: String, CodingKey {
        case caption
        case richText = "rich_text"
        case language
    }
}


private struct ToggleBlockResult: Decodable {
    let rich_text: [RichText]
}

// MARK: - Notion Block Types (Encodable)

private struct ToggleBlock: Encodable {
    let rich_text: [RichText]
    let color: String
}

private struct AppendChildrenRequest: Encodable {
    let children: [Block]
}

private struct Block: Encodable {
    let object = "block"
    let type: String
    let paragraph: ParagraphBlock?
    let image: ImageBlock?
    let code: CodeBlock?
    let toggle: ToggleBlock?
    let synced_block: SyncedBlock?
    let children: [Block]?

    enum CodingKeys: String, CodingKey {
        case object, type, paragraph, image, code, toggle, synced_block, children
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
            image: nil,
            code: nil,
            toggle: nil,
            synced_block: nil,
            children: nil
        )
    }

    static func imageBlock(fileUploadID: String) -> Block {
        Block(
            type: "image",
            paragraph: nil,
            image: ImageBlock(
                type: "file_upload",
                fileUpload: FileUploadRef(id: fileUploadID)
            ),
            code: nil,
            toggle: nil,
            synced_block: nil,
            children: nil
        )
    }
    
    static func codeBlock(text: String, caption: String = "NotionSketch Data") -> Block {
        Block(
            type: "code",
            paragraph: nil,
            image: nil,
            code: CodeBlock(
                caption: [RichText(type: "text", text: TextContent(content: caption, link: nil), annotations: nil)],
                richText: [RichText(type: "text", text: TextContent(content: text, link: nil), annotations: nil)],
                language: "json"
            ),
            toggle: nil,
            synced_block: nil,
            children: nil
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
    init(italic: Bool = false, bold: Bool = false, color: String = "default") {
        self.italic = italic
        self.bold = bold
        self.strikethrough = false
        self.underline = false
        self.code = false
        self.color = color
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

private struct CodeBlock: Encodable {
    let caption: [RichText]
    let richText: [RichText]
    let language: String
    
    enum CodingKeys: String, CodingKey {
        case caption
        case richText = "rich_text"
        case language
    }
}

private struct FileUploadRef: Encodable {
    let id: String
}

private struct SyncedBlock: Encodable {
    let synced_from: SyncedFrom?

    enum CodingKeys: String, CodingKey {
        case synced_from
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let syncedFrom = synced_from {
            try container.encode(syncedFrom, forKey: .synced_from)
        } else {
            try container.encodeNil(forKey: .synced_from)
        }
    }
}

private struct SyncedFrom: Encodable {
    let block_id: String
}

// MARK: - NotionService Actor

/// Thread-safe actor responsible for all Notion API communication.
/// Reads the API token dynamically from `SettingsManager` on each call.
actor NotionService {

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15 // Fail quickly on timeout
            config.timeoutIntervalForResource = 30
            config.waitsForConnectivity = false // Don't hang waiting for connection
            self.session = URLSession(configuration: config)
        }
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

        let (data, response) = try await safeRequest(request, context: "createFileUpload")
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

        let (data, response) = try await safeRequest(request, context: "sendFileUpload")
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
    func createPageInDatabase(title: String, ocrText: String? = nil, appLink: String? = nil, drawingEncoding: String? = nil) async throws -> String {
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
        
        if let drawingEncoding {
            let chunks = chunkString(drawingEncoding, size: 2000)
            let richTextObjects = chunks.map { chunk in
                ["text": ["content": chunk]]
            }
            properties["Drawing Encode"] = [ "rich_text": richTextObjects ]
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

        let (data, response) = try await safeRequest(request, context: "createPage")
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
        let (data, response) = try await safeRequest(request, context: "getDatabaseTitle")
        let validatedData = try validate(data, response)

        let decoded: DatabaseResponse
        do {
            decoded = try JSONDecoder().decode(DatabaseResponse.self, from: validatedData)
        } catch {

            let raw = String(data: validatedData, encoding: .utf8) ?? "<binary>"
            throw NotionServiceError.decodingFailed("dbSchema: \(error.localizedDescription) — raw: \(raw.prefix(1000))")
        }

        // Find the property whose type is "title"
        // Find the property whose type is "title"
        for (name, property) in decoded.properties ?? [:] {
            if property.type == "title" {
                return name
            }
        }

        // Fallback — shouldn't happen since every database has a title property
        return "Name"
    }
    // MARK: - Page Content (Using Blocks)
    
    /// Fetches drawing data from the page.
    /// Priority 1: Checks for a Toggle Block named "Image Data" and reads its children.
    /// Priority 2: Checks for top-level Code Blocks named "NotionSketch Data" (Legacy).
    func fetchPageBlocks(pageID: String) async throws -> String? {
        let pageBlocks = try await fetchAllChildren(blockID: pageID)
        
        // 1. Check for "Image Data" Toggle Block
        if let toggleBlock = pageBlocks.first(where: { block in
            guard block.type == "toggle", let toggle = block.toggle else { return false }
            // Check title (rich_text)
            let title = toggle.rich_text.compactMap { $0.text.content }.joined()
            return title == "Image Data"
        }) {
            // Found toggle, fetch its children
            let childBlocks = try await fetchAllChildren(blockID: toggleBlock.id)
            if let content = extractCodeContent(from: childBlocks) {
                return content
            }
        }
        
        // 2. Fallback: Check top-level blocks
        return extractCodeContent(from: pageBlocks)
    }
    
    // MARK: - internal helpers
    
    private func fetchAllChildren(blockID: String) async throws -> [BlockResult] {
        var allBlocks: [BlockResult] = []
        var cursor: String? = nil
        
        repeat {
            var urlString = "\(NotionConfig.baseURL)/blocks/\(blockID)/children?page_size=100"
            if let cursor { urlString += "&start_cursor=\(cursor)" }
            
            guard let url = URL(string: urlString) else { throw NotionServiceError.invalidURL }
            
            let request = try await authorizedRequest(url: url, method: "GET")
            let (data, response) = try await safeRequest(request, context: "fetchAllChildren")
            let validatedData = try validate(data, response)
            
            let decoded = try JSONDecoder().decode(BlockChildrenResponse.self, from: validatedData)
            allBlocks.append(contentsOf: decoded.results)
            
            cursor = decoded.hasMore ? decoded.nextCursor : nil
        } while cursor != nil
        
        return allBlocks
    }
    
    private func extractCodeContent(from blocks: [BlockResult]) -> String? {
        var accumulatedContent = ""
        var foundAny = false
        
        for block in blocks {
            if block.type == "code",
               let code = block.code,
               let caption = code.caption.first?.text.content,
               caption == "NotionSketch Data" {
                
                let blockContent = code.richText.map { $0.text.content }.joined()
                accumulatedContent += blockContent
                foundAny = true
            }
        }
        return foundAny ? accumulatedContent : nil
    }
    
    /// Updates the page content by storing the drawing data inside a Toggle Block named "Image Data".
    /// Finds and deletes any existing data blocks (Legacy or Toggle) before appending the new one.
    func updatePageContent(pageID: String, drawingString: String) async throws {
        // 1. Find existing data blocks using helper
        let pageBlocks = try await fetchAllChildren(blockID: pageID)
        var blocksToDelete: [String] = []

        for block in pageBlocks {
            // Check for "Image Data" Toggle
            if block.type == "toggle",
               let toggle = block.toggle,
               toggle.rich_text.compactMap({ $0.text.content }).joined() == "Image Data" {
                blocksToDelete.append(block.id)
            }
            // Check for Legacy Code Blocks (cleanup)
            else if block.type == "code",
                    let code = block.code,
                    let caption = code.caption.first?.text.content,
                    caption == "NotionSketch Data" {
                 blocksToDelete.append(block.id)
            }
        }
        
        // 2. Delete existing blocks
        for blockID in blocksToDelete {
            guard let url = URL(string: "\(NotionConfig.baseURL)/blocks/\(blockID)") else { continue }
            let request = try await authorizedRequest(url: url, method: "DELETE")
            _ = try await safeRequest(request, context: "deleteDataBlock")
        }
        
        // 3. Prepare New Code Blocks (Chunked)
        // Notion Code blocks limited to 100 items in rich_text array.
        let allChunks = chunkString(drawingString, size: 2000)
        let blockGroups = stride(from: 0, to: allChunks.count, by: 100).map {
            Array(allChunks[$0..<min($0 + 100, allChunks.count)])
        }
        
        var codeBlocks: [Block] = []
        for group in blockGroups {
            let richTextObjects = group.map { chunk in
                RichText(type: "text", text: TextContent(content: chunk, link: nil), annotations: nil)
            }
            
            let block = Block(
                type: "code", paragraph: nil, image: nil, 
                code: CodeBlock(
                    caption: [RichText(type: "text", text: TextContent(content: "NotionSketch Data", link: nil), annotations: nil)],
                    richText: richTextObjects, language: "json"
                ), 
                toggle: nil,
                synced_block: nil,
                children: nil
            )
            codeBlocks.append(block)
        }
        
        // 4. Create Container Toggle Block (Without Children initially)
        let toggleBlock = Block(
            type: "toggle", paragraph: nil, image: nil, code: nil,
            toggle: ToggleBlock(
                rich_text: [
                    RichText(type: "text", text: TextContent(content: "Image Data", link: nil), annotations: Annotations(color: "gray"))
                ],
                color: "gray"
            ),
            synced_block: nil,
            children: nil // Do not send children in first request
        )
        
        // 5. Append Toggle Block to Page
        let urlString = "\(NotionConfig.baseURL)/blocks/\(pageID)/children"
        guard let url = URL(string: urlString) else { throw NotionServiceError.invalidURL }
        
        var request = try await authorizedRequest(url: url, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = AppendChildrenRequest(children: [toggleBlock])
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await safeRequest(request, context: "appendDataBlock(Toggle)")
        let validatedData = try validate(data, response)
        
        // 6. Get New Toggle Block ID
        let decoded = try JSONDecoder().decode(BlockChildrenResponse.self, from: validatedData)
        guard let newToggleID = decoded.results.first?.id else {
            // If we can't get ID for some reason, we can't append data.
            // Just return (data is lost for this sync but prevents crash).
            // In strict mode we could throw.
            SyncLogger.log("⚠️ Could not retrieve new Toggle Block ID. Data not saved inside toggle.")
            return
        }
        
        // 7. Append Code Blocks as children of the new Toggle Block
        let childUrlString = "\(NotionConfig.baseURL)/blocks/\(newToggleID)/children"
        guard let childUrl = URL(string: childUrlString) else { throw NotionServiceError.invalidURL }
        
        var childRequest = try await authorizedRequest(url: childUrl, method: "PATCH")
        childRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Append in batches of 100 blocks if needed (Notion limit)
        // Though unlikely for one drawing to exceed 100 blocks (20MB)
        let childRequestBody = AppendChildrenRequest(children: codeBlocks)
        childRequest.httpBody = try JSONEncoder().encode(childRequestBody)
        
        let (childData, childResponse) = try await safeRequest(childRequest, context: "appendDataBlock(Children)")
        _ = try validate(childData, childResponse)
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
            let (data, response) = try await safeRequest(request, context: "clearPageBlocks")
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
            let (data, response) = try await safeRequest(request, context: "deleteBlock")
            _ = try validate(data, response)
        }
    }

    // MARK: - Update Sketch Preview (Persistent)

    /// Updates the "Sketch Preview" toggle block with the new image.
    /// Finds existing block -> Clears children -> Appends new image.
    /// Does NOT delete other page content.
    func updateSketchPreview(pageID: String, fileUploadID: String, recognizedText: String) async throws {
        // 1. Fetch children of the page to find our block
        let pageBlocks = try await fetchAllChildren(blockID: pageID)
        
        var previewBlockID: String? = nil
        
        for block in pageBlocks {
            if block.type == "toggle",
               let toggle = block.toggle,
               toggle.rich_text.first?.text.content == "Sketch Preview" {
                previewBlockID = block.id
                break
            }
        }
        
        if let id = previewBlockID {
            // 2a. Block exists: Clear its children (the old image)
            let children = try await fetchAllChildren(blockID: id)
            for child in children {
                 guard let url = URL(string: "\(NotionConfig.baseURL)/blocks/\(child.id)") else { continue }
                 let request = try await authorizedRequest(url: url, method: "DELETE")
                 _ = try await safeRequest(request, context: "deletePreviewChild")
            }
        } else {
            // 2b. Block doesn't exist: Create it
            let toggleBlock = Block(
                type: "toggle", paragraph: nil, image: nil, code: nil,
                toggle: ToggleBlock(
                    rich_text: [
                        RichText(type: "text", text: TextContent(content: "Sketch Preview", link: nil), annotations: Annotations(bold: true))
                    ],
                    color: "default"
                ),
                synced_block: nil,
                children: nil
            )
             
            // Append to page
             let urlString = "\(NotionConfig.baseURL)/blocks/\(pageID)/children"
             guard let url = URL(string: urlString) else { throw NotionServiceError.invalidURL }
             
             var request = try await authorizedRequest(url: url, method: "PATCH")
             request.setValue("application/json", forHTTPHeaderField: "Content-Type")
             request.httpBody = try JSONEncoder().encode(AppendChildrenRequest(children: [toggleBlock]))
             
             let (data, response) = try await safeRequest(request, context: "createPreviewBlock")
             let validatedData = try validate(data, response)
             let decoded = try JSONDecoder().decode(BlockChildrenResponse.self, from: validatedData)
             previewBlockID = decoded.results.first?.id
        }
        
        guard let targetID = previewBlockID else { return }

        // 3. Append Image to the Toggle Block
        let urlString = "\(NotionConfig.baseURL)/blocks/\(targetID)/children"
        guard let url = URL(string: urlString) else { throw NotionServiceError.invalidURL }
        
        var children: [Block] = []
        children.append(Block.imageBlock(fileUploadID: fileUploadID))
        
        if !recognizedText.isEmpty {
             children.append(Block.paragraphBlock(text: "OCR: " + recognizedText))
        }

        let requestBody = AppendChildrenRequest(children: children)
        var request = try await authorizedRequest(url: url, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await safeRequest(request, context: "appendImageToPreview")
        _ = try validate(data, response)
    }

    // MARK: - Update Synced Image (Synced Block)

    /// Updates the image inside a Synced Block.
    /// If `syncedBlockID` is provided and valid, it updates that block.
    /// Otherwise, it creates a new Synced Block and returns its ID.
    func updateSyncedImage(
        pageID: String,
        syncedBlockID: String?,
        fileUploadID: String,
        recognizedText: String
    ) async throws -> String {
        
        var targetBlockID = syncedBlockID
        var isNewBlock = false
        
        // 1. Validate Existing Synced Block
        if let existingID = syncedBlockID {
            do {
                _ = try await fetchAllChildren(blockID: existingID)
                SyncLogger.log("found existing synced block: \(existingID)")
            } catch {
                SyncLogger.log("⚠️ Synced Block \(existingID) not found or inaccessible. creating new one.")
                targetBlockID = nil
            }
        }
        
        // 2. Create New Synced Block (Empty) if needed
        if targetBlockID == nil {
            // Create pure empty synced block wrapper
            // We do NOT send children here to avoid "children not present" validation error
            let createBlock = Block(
                type: "synced_block",
                paragraph: nil, image: nil, code: nil, toggle: nil,
                synced_block: SyncedBlock(synced_from: nil),
                children: nil
            )
            
            let urlString = "\(NotionConfig.baseURL)/blocks/\(pageID)/children"
            guard let url = URL(string: urlString) else { throw NotionServiceError.invalidURL }
            
            var request = try await authorizedRequest(url: url, method: "PATCH")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(AppendChildrenRequest(children: [createBlock]))
            
            let (data, response) = try await safeRequest(request, context: "createSyncedBlock")
            let validatedData = try validate(data, response)
            let decoded = try JSONDecoder().decode(BlockChildrenResponse.self, from: validatedData)
            
            if let newID = decoded.results.first?.id {
                targetBlockID = newID
                isNewBlock = true
            } else {
                 throw NotionServiceError.appendFailed("Created Synced Block but got no ID.")
            }
        }
        
        guard let finalID = targetBlockID else { return "" }
        
        // 3. Clear Existing Children (Update Mode Only)
        if !isNewBlock {
            let children = try await fetchAllChildren(blockID: finalID)
            for child in children {
                 guard let url = URL(string: "\(NotionConfig.baseURL)/blocks/\(child.id)") else { continue }
                 let request = try await authorizedRequest(url: url, method: "DELETE")
                 _ = try await safeRequest(request, context: "deleteSyncedBlockChild")
            }
        }
        
        // 4. Append Content (Image + OCR)
        // We do this for both New and Existing blocks to ensure content is there
        let urlString = "\(NotionConfig.baseURL)/blocks/\(finalID)/children"
        guard let url = URL(string: urlString) else { throw NotionServiceError.invalidURL }
        
        var newChildren: [Block] = []
        newChildren.append(Block.imageBlock(fileUploadID: fileUploadID))
        // Removed OCR text block as per request
        
        let requestBody = AppendChildrenRequest(children: newChildren)
        var request = try await authorizedRequest(url: url, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await safeRequest(request, context: "appendImageToSyncedBlock")
        _ = try validate(data, response)
        
        return finalID
    }

    // MARK: - Update Page Properties

    /// Updates properties of an existing page: Title, OCR text, Deep Link, and Drawing Encoding.
    func updatePageProperties(
        pageID: String,
        title: String? = nil,
        ocrText: String? = nil,
        appLink: String? = nil,
        drawingEncoding: String? = nil
    ) async throws {
        guard let url = URL(string: "\(NotionConfig.baseURL)/pages/\(pageID)") else {
            throw NotionServiceError.invalidURL
        }
        
        var properties: [String: Any] = [:]
        
        if let title {
             // We need the title property name.
             let dbID = await getDatabaseID()
             let titleProp = try await getDatabaseTitlePropertyName(databaseID: dbID)
             properties[titleProp] = [ "title": [ ["text": ["content": title]] ] ]
        }

        if let ocrText {
            properties["OCR"] = [ "rich_text": [ ["text": ["content": ocrText]] ] ]
        }

        if let drawingEncoding {
            // Chunk the drawing data into 2000-char text objects
            let chunks = chunkString(drawingEncoding, size: 2000)
            let richTextObjects = chunks.map { chunk in
                ["text": ["content": chunk]]
            }
            properties["Drawing Encode"] = [ "rich_text": richTextObjects ]
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

        let (data, response) = try await safeRequest(request, context: "updatePageProperties")
        
        do {
             _ = try validate(data, response)
        } catch {
             let raw = String(data: data, encoding: .utf8) ?? "<binary>"
             // If property is missing, Notion returns 400 validation_error.
            if raw.contains("validation_error") || raw.contains("property_not_found") || raw.contains("does not exist") {
                SyncLogger.log("⚠️ Property update skipped (Missing Notion Property?): \(raw)")
                return
            }
            throw NotionServiceError.decodingFailed("updatePage: \(error.localizedDescription) — raw: \(raw.prefix(300))")
        }
    }
    
    // MARK: - Drawing Encoding Helpers
    
    /// Compresses and encodes drawing data into a Base64 string.
    /// Uses LZFSE compression to minimize payload size for Notion.
    nonisolated func encodeDrawing(_ drawing: PKDrawing) throws -> String {
        let data = drawing.dataRepresentation() 
        
        // Attempt LZFSE compression
        if let compressed = try? (data as NSData).compressed(using: .lzfse) {
             let base64 = compressed.base64EncodedString()
             return "LZFSE:" + base64
        }
        
        // Fallback to raw base64 if compression fails (unlikely)
        return data.base64EncodedString()
    }
    
    /// Decodes a Base64 string back into a PKDrawing.
    /// Supports both compressed ("LZFSE:") and legacy raw formats.
    nonisolated func decodeDrawing(from base64String: String) throws -> PKDrawing {
        var base64 = base64String
        var isCompressed = false
        
        if base64String.hasPrefix("LZFSE:") {
            base64 = String(base64String.dropFirst(6))
            isCompressed = true
        }
        
        guard let data = Data(base64Encoded: base64) else {
            throw NotionServiceError.decodingFailed("Invalid Base64 string")
        }
        
        if isCompressed {
            do {
                let decompressed = try (data as NSData).decompressed(using: .lzfse)
                return try PKDrawing(data: decompressed as Data)
            } catch {
                throw NotionServiceError.decodingFailed("Decompression failed: \(error.localizedDescription)")
            }
        }
        
        return try PKDrawing(data: data)
    }
    
    /// Splits a string into chunks of standard Notion limit (2000 chars).
    nonisolated func chunkString(_ string: String, size: Int = 2000) -> [String] {
        var chunks: [String] = []
        var currentIndex = string.startIndex
        
        while currentIndex < string.endIndex {
            let endIndex = string.index(currentIndex, offsetBy: size, limitedBy: string.endIndex) ?? string.endIndex
            chunks.append(String(string[currentIndex..<endIndex]))
            currentIndex = endIndex
        }
        
        return chunks
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

    // MARK: - Fetch Page Details (Title + Icon + Relations + Drawing)
    
    /// Fetches the current title, icon, connected page IDs, and drawing encoding from Notion.
    func fetchPageDetails(pageID: String) async throws -> (title: String, icon: String?, connectedIDs: [String], drawingNum: String?)? {
        guard let url = URL(string: "\(NotionConfig.baseURL)/pages/\(pageID)") else {
            throw NotionServiceError.invalidURL
        }
        
        let request = try await authorizedRequest(url: url, method: "GET")
        let (data, response) = try await safeRequest(request, context: "fetchPageDetails")
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
        var drawingEncoded: String? = nil
        
        for (key, property) in decoded.properties {
            if property.type == "title", let titleObjects = property.title {
                title = titleObjects.map { $0.text.content }.joined()
            } else if property.type == "relation", key == "Connected Pages", let relations = property.relation {
                connectedIDs = relations.map { $0.id }
            } else if property.type == "rich_text", key == "Drawing Encode", let richTexts = property.rich_text {
                // Determine if there is content
                let fullText = richTexts.map { $0.text.content }.joined()
                if !fullText.isEmpty {
                    drawingEncoded = fullText
                }
            }
        }
        
        return (title, decoded.icon?.value, connectedIDs, drawingEncoded)
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
        
        let (data, response) = try await safeRequest(request, context: "archivePage")
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
        
        let urlString = "\(NotionConfig.baseURL)/databases/\(databaseID)/query"
        SyncLogger.log("🔍 fetchActivePageIDs URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
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
            
            let (data, response) = try await safeRequest(request, context: "fetchActivePageIDs")
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
    

    
    // MARK: - Search Pages
    
    /// Searches for pages in Notion matching the query string.
    /// Returns a list of (id, title, icon, parentID) tuples.
    func searchNotionPages(query: String) async throws -> [(id: String, title: String, icon: String?, parentID: String?)] {
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
        
        let (data, response) = try await safeRequest(request, context: "searchNotionPages")
        let validatedData = try validate(data, response)
        
        // Decode manually since property names are dynamic
        guard let json = try JSONSerialization.jsonObject(with: validatedData) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }
        
        var foundPages: [(id: String, title: String, icon: String?, parentID: String?)] = []
        
        for object in results {
            guard let id = object["id"] as? String,
                  let properties = object["properties"] as? [String: Any] else { continue }
            
            // Extract Parent Database ID
            var parentID: String? = nil
            if let parent = object["parent"] as? [String: Any] {
                parentID = parent["database_id"] as? String
            }

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
            
            foundPages.append((id: id, title: titleString, icon: iconString, parentID: parentID))
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
        
        let (data, response) = try await safeRequest(request, context: "updateConnectedPages")
        
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
        
        // Notion API will send a 302 redirect if the ID is a page ID but treated as a database ID? 
        // Or if the content is "Compact" vs "Full".
        // Use GET /v1/databases/{id}
        // If properties are empty, it might be that the integration doesn't have access to the CONTENT of the database, only the title?
        // Or the 'properties' field is not returned for some reason?
        
        let url = URL(string: "\(NotionConfig.baseURL)/databases/\(databaseID)")!
        let request = try await authorizedRequest(url: url)
        
        let (data, _) = try await safeRequest(request, context: "fetchConnectedPagesTarget")
        
        // Debug: Inspect raw keys
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let objectType = json["object"] as? String ?? "unknown"
            SyncLogger.log("ℹ️ API Object Type: \(objectType)")
            
            if let props = json["properties"] as? [String: Any] {
                 let keys = props.keys.sorted().joined(separator: ", ")
                 SyncLogger.log("🔎 RAW API Properties: \(keys)")
            } else {
                 SyncLogger.log("⚠️ 'properties' key missing or not a dictionary. Keys found: \(json.keys.joined(separator: ", "))")
            }
        } else {
             let rawStr = String(data: data, encoding: .utf8) ?? ""
             SyncLogger.log("⚠️ Failed to parse JSON. Raw: \(rawStr.prefix(200))...")
        }

        let decoded = try JSONDecoder().decode(DatabaseResponse.self, from: data)
        
        // Find "Connected Pages" property (case-insensitive) and get its relation target
        let allKeys = decoded.properties?.keys.map { $0 } ?? []
        SyncLogger.log("📋 Database Properties Found: \(allKeys.joined(separator: ", "))")
        
        let key = decoded.properties?.keys.first(where: { $0.localizedCaseInsensitiveCompare("Connected Pages") == .orderedSame })
        
        if let key = key,
           let property = decoded.properties?[key],
           let relation = property.relation {
            SyncLogger.log("🔗 Found 'Connected Pages' Relation Target DB: \(relation.database_id ?? "nil")")
            return relation.database_id
        }
        SyncLogger.log("⚠️ Could not find 'Connected Pages' property or relation config in database schema.")
        return nil
    }

    /// Queries a specific database for pages matching a title query.
    func queryDatabase(databaseID: String, query: String) async throws -> [(id: String, title: String, icon: String?)] {
        guard let url = URL(string: "\(NotionConfig.baseURL)/search") else {
            throw NotionServiceError.invalidURL
        }

        var request = try await authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Re-attempting strictly with POST /v1/databases/{id}/query
        // This is the standard way to search WITHIN a database.
        guard let dbQueryUrl = URL(string: "\(NotionConfig.baseURL)/databases/\(databaseID)/query") else {
             throw NotionServiceError.invalidURL
        }
        
        // We override the request
        request = try await authorizedRequest(url: dbQueryUrl, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // We need to filter by title.
        // We need the property name for the title.
        let titleKey = try await getDatabaseTitlePropertyName(databaseID: databaseID)

        let dbPayload: [String: Any] = [
            "filter": [
                "property": titleKey,
                "title": [
                    "contains": query
                ]
            ],
            "sorts": [
                [
                    "timestamp": "last_edited_time",
                    "direction": "descending"
                ]
            ],
            "page_size": 20
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: dbPayload)
        
        let (data, response) = try await safeRequest(request, context: "queryDatabase_strict")
        let validatedData = try validate(data, response)
        
        // Parse results
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
    // MARK: - Legacy Cleanup

    /// Removes the old "Sketch Preview" toggle block and any standalone image blocks if they exist.
    func deleteLegacyPreview(pageID: String) async throws {
        // 1. Fetch children of the page
        let pageBlocks = try await fetchAllChildren(blockID: pageID)
        
        var blocksToDelete: [String] = []
        
        // 2. Find legacy blocks
        for block in pageBlocks {
            // A. "Sketch Preview" Toggle Block
            if block.type == "toggle",
               let toggle = block.toggle,
               toggle.rich_text.first?.text.content == "Sketch Preview" {
                blocksToDelete.append(block.id)
            }
            // B. Standalone Image Blocks (Legacy before Toggle/Synced)
            // We assume ANY top-level image on this page is a legacy sketch preview 
            // because we now put them inside synced blocks.
            else if block.type == "image" {
                blocksToDelete.append(block.id)
            }
        }
        
        // 3. Delete them
        for blockID in blocksToDelete {
            guard let url = URL(string: "\(NotionConfig.baseURL)/blocks/\(blockID)") else { continue }
            let request = try await authorizedRequest(url: url, method: "DELETE")
            let (data, response) = try await safeRequest(request, context: "deleteLegacyPreview")
            _ = try validate(data, response)
        }
        
        if !blocksToDelete.isEmpty {
            SyncLogger.log("🧹 Removed \(blocksToDelete.count) legacy blocks (toggles/images)")
        }
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

// MARK: - Safe Network Helper
extension NotionService {
    /// Wrapper for session.data(for:) to catch and log "cannot parse response" errors
    private func safeRequest(_ request: URLRequest, context: String) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            let nsError = error as NSError
            // Log specific networking errors
            if nsError.domain == NSURLErrorDomain {
                // Suppress verbose logging for cancelled requests (normal debounce flow)
                if nsError.code != NSURLErrorCancelled {
                     SyncLogger.log("❌ Network Error in \(context): \(nsError.localizedDescription) (Code: \(nsError.code))")
                }
                
                if nsError.code == NSURLErrorCannotParseResponse {
                     SyncLogger.log("⚠️ This usually means the server returned an empty body or invalid headers for the request type.")
                }
            }
            throw error
        }
    }
}
