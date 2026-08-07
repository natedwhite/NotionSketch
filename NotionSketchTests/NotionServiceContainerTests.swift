import XCTest
@testable import NotionSketch

final class NotionServiceContainerTests: XCTestCase {

    // MARK: - Fixed IDs

    static let databaseID = "11111111-1111-1111-1111-111111111111"
    static let dataSourceID = "22222222-2222-2222-2222-222222222222"
    static let pageID = "33333333-3333-3333-3333-333333333333"
    static let queryDataSourceID = "44444444-4444-4444-4444-444444444444"

    // MARK: - Container URLs

    static var databaseURL: String { "https://www.notion.so/\(Self.databaseID)" }
    static var dataSourceURL: String { "https://www.notion.so/data-source/\(Self.dataSourceID)" }

    // MARK: - Service and session

    private var service: NotionService!
    private var token: String!
    private var mockSession: URLSession!

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()
        token = "test_token_\(UUID().uuidString)"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)
        service = NotionService(
            session: mockSession,
            tokenOverride: self.token,
            containerInputOverride: nil
        )
    }

    override func tearDown() {
        MockURLProtocol.reset()
        service = nil
        mockSession = nil
        token = nil
        super.tearDown()
    }

    private func makeService(containerInput: String? = nil) -> NotionService {
        NotionService(
            session: mockSession,
            tokenOverride: self.token,
            containerInputOverride: containerInput
        )
    }

    // MARK: - Response helpers

    private func discoveryJSON(dataSourceID: String) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "data_sources": [["id": dataSourceID, "name": "DS"]]
        ], options: [])
    }

    private func discoveryJSONEmpty() -> Data {
        try! JSONSerialization.data(withJSONObject: ["data_sources": []], options: [])
    }

    private func dbSchemaJSON(titleProp: String = "Name") -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "properties": [titleProp: ["type": "title"]]
        ], options: [])
    }

    private func dsSchemaJSON(titleProp: String = "Name") -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "properties": [titleProp: ["type": "title"]]
        ], options: [])
    }

    private func emptyQueryData() -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "results": [],
            "has_more": false
        ], options: [])
    }

    private func queryWithPageData(pageID: String) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "results": [["id": pageID, "archived": false]],
            "has_more": false
        ], options: [])
    }

    private func createPageResponse(id: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["id": id], options: [])
    }

    // MARK: - Body helpers

    private func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let bytesRead = stream.read(buffer, maxLength: 1024)
                if bytesRead > 0 {
                    data.append(buffer, count: bytesRead)
                }
            }
            return data
        }
        return nil
    }

    private func bodyJSON(from request: URLRequest) -> [String: Any] {
        guard let data = bodyData(from: request) else {
            XCTFail("Request has no body data")
            return [:]
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Failed to decode request body as JSON: \(String(data: data, encoding: .utf8) ?? "<binary>")")
            return [:]
        }
        return json
    }

    // MARK: - Section 5: Discovery Tests

    func testDiscoverySuccess() async throws {
        service = makeService(containerInput: Self.databaseURL)

        MockURLProtocol.setHandler { [self] request in
            XCTAssertEqual(request.url?.path, "/v1/databases/\(Self.databaseID)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "1.1", headerFields: ["Content-Type": "application/json"])!, self.discoveryJSON(dataSourceID: Self.dataSourceID))
        }

        let resolved = try await service.resolveSketchesContainer()
        XCTAssertEqual(resolved.ref, .dataSource(id: Self.dataSourceID))
        XCTAssertEqual(resolved.fallbackDatabaseID, Self.databaseID)
        XCTAssertEqual(MockURLProtocol.snapshotRequests().count, 1)
    }

    func testDiscoveryHTTPFailure() async throws {
        service = makeService(containerInput: Self.databaseURL)

        MockURLProtocol.setHandler { [self] request in
            XCTAssertEqual(request.url?.path, "/v1/databases/\(Self.databaseID)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: "1.1", headerFields: nil)!, Data())
        }

        let resolved = try await service.resolveSketchesContainer()
        XCTAssertEqual(resolved.ref, .database(id: Self.databaseID))
        XCTAssertEqual(resolved.fallbackDatabaseID, Self.databaseID)
        XCTAssertEqual(MockURLProtocol.snapshotRequests().count, 1)
    }

    func testDiscoveryDecodingFailure() async throws {
        service = makeService(containerInput: Self.databaseURL)

        MockURLProtocol.setHandler { [self] request in
            XCTAssertEqual(request.url?.path, "/v1/databases/\(Self.databaseID)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "1.1", headerFields: ["Content-Type": "application/json"])!, Data("invalid json".utf8))
        }

        let resolved = try await service.resolveSketchesContainer()
        XCTAssertEqual(resolved.ref, .database(id: Self.databaseID))
        XCTAssertEqual(resolved.fallbackDatabaseID, Self.databaseID)
        XCTAssertEqual(MockURLProtocol.snapshotRequests().count, 1)
    }

    func testExplicitDataSourceInput() async throws {
        service = makeService(containerInput: Self.dataSourceURL)

        let resolved = try await service.resolveSketchesContainer()
        XCTAssertEqual(resolved.ref, .dataSource(id: Self.dataSourceID))
        XCTAssertNil(resolved.fallbackDatabaseID)
        XCTAssertEqual(MockURLProtocol.snapshotRequests().count, 0)
    }

    // MARK: - Section 6: Data-Source Schema Tests

    func testGetDataSourceTitlePropertyNameSuccess() async throws {
        MockURLProtocol.setHandler { [self] request in
            XCTAssertEqual(request.url?.path, "/v1/data_sources/\(Self.dataSourceID)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "1.1", headerFields: ["Content-Type": "application/json"])!, self.dsSchemaJSON(titleProp: "Sketch Title"))
        }

        let propName = await service.getDataSourceTitlePropertyName(dataSourceID: Self.dataSourceID)
        XCTAssertEqual(propName, "Sketch Title")
        XCTAssertEqual(MockURLProtocol.snapshotRequests().count, 1)
    }

    func testGetDataSourceTitlePropertyNameHTTPFailure() async throws {
        MockURLProtocol.setHandler { [self] request in
            XCTAssertEqual(request.url?.path, "/v1/data_sources/\(Self.dataSourceID)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")
            return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "1.1", headerFields: nil)!, Data())
        }

        let propName = await service.getDataSourceTitlePropertyName(dataSourceID: Self.dataSourceID)
        XCTAssertEqual(propName, "Name")
        XCTAssertEqual(MockURLProtocol.snapshotRequests().count, 1)
    }

    func testGetDataSourceTitlePropertyNameDecodingFailure() async throws {
        MockURLProtocol.setHandler { [self] request in
            XCTAssertEqual(request.url?.path, "/v1/data_sources/\(Self.dataSourceID)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "1.1", headerFields: ["Content-Type": "application/json"])!, Data("invalid json".utf8))
        }

        let propName = await service.getDataSourceTitlePropertyName(dataSourceID: Self.dataSourceID)
        XCTAssertEqual(propName, "Name")
        XCTAssertEqual(MockURLProtocol.snapshotRequests().count, 1)
    }

    // MARK: - Section 7: Page Creation Fallback Test

    func testPageCreationDataSourceFallback() async throws {
        service = makeService(containerInput: Self.databaseURL)

        var callCount = 0
        MockURLProtocol.setHandler { [self] request in
            defer { callCount += 1 }
            let count = callCount

            switch count {
            case 0:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v1/databases/\(Self.databaseID)")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "1.1", headerFields: ["Content-Type": "application/json"])!, self.discoveryJSON(dataSourceID: Self.dataSourceID))

            case 1:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v1/data_sources/\(Self.dataSourceID)")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "1.1", headerFields: ["Content-Type": "application/json"])!, self.dsSchemaJSON(titleProp: "Sketch Title"))

            case 2:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v1/pages")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")

                let body = self.bodyJSON(from: request)
                let parent = body["parent"] as? [String: Any]
                XCTAssertEqual(parent?["type"] as? String, "data_source_id")
                XCTAssertEqual(parent?["data_source_id"] as? String, Self.dataSourceID)
                let props = body["properties"] as? [String: Any]
                XCTAssertNotNil(props?["Sketch Title"])

                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "1.1", headerFields: nil)!, Data())

            case 3:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v1/databases/\(Self.databaseID)")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2022-06-28")
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "1.1", headerFields: ["Content-Type": "application/json"])!, self.dbSchemaJSON(titleProp: "Database Title"))

            case 4:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v1/pages")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2022-06-28")

                let body = self.bodyJSON(from: request)
                let parent = body["parent"] as? [String: Any]
                XCTAssertEqual(parent?["type"] as? String, "database_id")
                XCTAssertEqual(parent?["database_id"] as? String, Self.databaseID)
                let props = body["properties"] as? [String: Any]
                XCTAssertNotNil(props?["Database Title"])

                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "1.1", headerFields: ["Content-Type": "application/json"])!, self.createPageResponse(id: Self.pageID))

            default:
                XCTFail("Unexpected request count: \(count)")
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "1.1", headerFields: nil)!, Data())
            }
        }

        let pageID = try await service.createPageInDatabase(title: "Test Page")
        XCTAssertEqual(pageID, Self.pageID)
        XCTAssertEqual(MockURLProtocol.snapshotRequests().count, 5)

        for request in MockURLProtocol.snapshotRequests() {
            if request.url?.path == "/v1/pages" {
                let body = self.bodyJSON(from: request)
                let parent = body["parent"] as? [String: Any]
                if parent?["type"] as? String == "database_id" {
                    XCTAssertNotEqual(parent?["database_id"] as? String, Self.dataSourceID, "dataSourceID should never be used as database_id")
                }
            }
        }
    }

    // MARK: - Section 8: Explicit Data-Source Creation Failure

    func testExplicitDataSourceCreationFailure() async throws {
        service = makeService(containerInput: Self.dataSourceURL)

        var callCount = 0
        MockURLProtocol.setHandler { [self] request in
            defer { callCount += 1 }
            let count = callCount

            switch count {
            case 0:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v1/data_sources/\(Self.dataSourceID)")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "1.1", headerFields: ["Content-Type": "application/json"])!, self.dsSchemaJSON(titleProp: "Sketch Title"))

            case 1:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v1/pages")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")

                let body = self.bodyJSON(from: request)
                let parent = body["parent"] as? [String: Any]
                XCTAssertEqual(parent?["type"] as? String, "data_source_id")
                XCTAssertEqual(parent?["data_source_id"] as? String, Self.dataSourceID)
                XCTAssertNil(parent?["database_id"])

                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "1.1", headerFields: nil)!, Data())

            default:
                XCTFail("Unexpected request count: \(count)")
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "1.1", headerFields: nil)!, Data())
            }
        }

        do {
            _ = try await service.createPageInDatabase(title: "Test")
            XCTFail("Expected error")
        } catch {
            // Error should reach caller
        }

        XCTAssertEqual(MockURLProtocol.snapshotRequests().count, 2)

        let pageRequests = MockURLProtocol.snapshotRequests().filter { $0.url?.path == "/v1/pages" }
        XCTAssertEqual(pageRequests.count, 1)

        let dbRequests = MockURLProtocol.snapshotRequests().filter { $0.url?.path.hasPrefix("/v1/databases/") == true }
        XCTAssertEqual(dbRequests.count, 0)
    }

    // MARK: - Section 9: Active Query Fallback Test

    func testFetchActivePageIDsDataSourceQueryFallback() async throws {
        service = makeService(containerInput: Self.databaseURL)

        var callCount = 0
        MockURLProtocol.setHandler { [self] request in
            defer { callCount += 1 }
            let count = callCount

            switch count {
            case 0:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v1/databases/\(Self.databaseID)")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "1.1", headerFields: ["Content-Type": "application/json"])!, self.discoveryJSON(dataSourceID: Self.dataSourceID))

            case 1:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v1/data_sources/\(Self.dataSourceID)/query")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "1.1", headerFields: nil)!, Data())

            case 2:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v1/databases/\(Self.databaseID)/query")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2022-06-28")
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "1.1", headerFields: ["Content-Type": "application/json"])!, self.queryWithPageData(pageID: Self.pageID))

            default:
                XCTFail("Unexpected request count: \(count)")
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "1.1", headerFields: nil)!, Data())
            }
        }

        let pageIDs = try await service.fetchActivePageIDs()
        XCTAssertTrue(pageIDs.contains(Self.pageID))
        XCTAssertEqual(MockURLProtocol.snapshotRequests().count, 3)

        for req in MockURLProtocol.snapshotRequests() {
            if req.url?.path.hasPrefix("/v1/databases/") == true {
                XCTAssertFalse(req.url?.path.contains(Self.dataSourceID) == true, "dataSourceID should not appear in database requests")
            }
        }
    }

    // MARK: - Section 10: Existing-Page Title Update Test

    func testUpdatePagePropertiesExistingPage() async throws {
        service = makeService(containerInput: Self.dataSourceURL)

        var callCount = 0
        MockURLProtocol.setHandler { [self] request in
            defer { callCount += 1 }
            let count = callCount

            switch count {
            case 0:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v1/data_sources/\(Self.dataSourceID)")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "1.1", headerFields: ["Content-Type": "application/json"])!, self.dsSchemaJSON(titleProp: "Sketch Title"))

            case 1:
                XCTAssertEqual(request.httpMethod, "PATCH")
                XCTAssertEqual(request.url?.path, "/v1/pages/\(Self.pageID)")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2022-06-28")

                let body = self.bodyJSON(from: request)
                let props = body["properties"] as? [String: Any]

                let sketchTitleProp = props?["Sketch Title"] as? [String: Any]
                let titleArr = sketchTitleProp?["title"] as? [[String: Any]]
                let textDict = titleArr?.first?["text"] as? [String: Any]
                let titleContent = textDict?["content"] as? String
                XCTAssertEqual(titleContent, "Renamed sketch")

                XCTAssertNil(props?["Name"])
                XCTAssertNil(props?["name"])

                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "1.1", headerFields: ["Content-Type": "application/json"])!, Data())

            default:
                XCTFail("Unexpected request count: \(count)")
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "1.1", headerFields: nil)!, Data())
            }
        }

        try await service.updatePageProperties(pageID: Self.pageID, title: "Renamed sketch")
        XCTAssertEqual(MockURLProtocol.snapshotRequests().count, 2)

        let dbRequests = MockURLProtocol.snapshotRequests().filter { $0.url?.path.hasPrefix("/v1/databases/") == true }
        XCTAssertEqual(dbRequests.count, 0)
    }

    // MARK: - Section 11: Title Query Tests

    func testDatabaseTitleQuery() async throws {
        service = makeService(containerInput: Self.databaseURL)

        var callCount = 0
        MockURLProtocol.setHandler { [self] request in
            defer { callCount += 1 }
            let count = callCount

            switch count {
            case 0:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v1/databases/\(Self.databaseID)")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2022-06-28")
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "1.1", headerFields: ["Content-Type": "application/json"])!, self.dbSchemaJSON(titleProp: "Name"))

            case 1:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v1/databases/\(Self.databaseID)/query")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2022-06-28")

                let body = self.bodyJSON(from: request)
                XCTAssertEqual(body["page_size"] as? Int, 20)

                let filter = body["filter"] as? [String: Any]
                XCTAssertEqual(filter?["property"] as? String, "Name")
                let titleFilter = filter?["title"] as? [String: Any]
                XCTAssertEqual(titleFilter?["contains"] as? String, "search term")

                let sorts = body["sorts"] as? [[String: Any]]
                let sort = sorts?.first
                XCTAssertEqual(sort?["timestamp"] as? String, "last_edited_time")
                XCTAssertEqual(sort?["direction"] as? String, "descending")

                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "1.1", headerFields: ["Content-Type": "application/json"])!, self.emptyQueryData())

            default:
                XCTFail("Unexpected request count: \(count)")
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "1.1", headerFields: nil)!, Data())
            }
        }

        _ = try await service.queryContainer(ref: .database(id: Self.databaseID), query: "search term")
        XCTAssertEqual(MockURLProtocol.snapshotRequests().count, 2)
    }

    func testDataSourceTitleQuery() async throws {
        var callCount = 0
        MockURLProtocol.setHandler { [self] request in
            defer { callCount += 1 }
            let count = callCount

            switch count {
            case 0:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v1/data_sources/\(Self.queryDataSourceID)")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "1.1", headerFields: ["Content-Type": "application/json"])!, self.dsSchemaJSON(titleProp: "Name"))

            case 1:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v1/data_sources/\(Self.queryDataSourceID)/query")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")

                let body = self.bodyJSON(from: request)
                XCTAssertEqual(body["page_size"] as? Int, 20)

                let filter = body["filter"] as? [String: Any]
                XCTAssertEqual(filter?["property"] as? String, "Name")
                let titleFilter = filter?["title"] as? [String: Any]
                XCTAssertEqual(titleFilter?["contains"] as? String, "search term")

                let sorts = body["sorts"] as? [[String: Any]]
                let sort = sorts?.first
                XCTAssertEqual(sort?["timestamp"] as? String, "last_edited_time")
                XCTAssertEqual(sort?["direction"] as? String, "descending")

                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "1.1", headerFields: ["Content-Type": "application/json"])!, self.emptyQueryData())

            default:
                XCTFail("Unexpected request count: \(count)")
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "1.1", headerFields: nil)!, Data())
            }
        }

        _ = await service.getDataSourceTitlePropertyName(dataSourceID: Self.queryDataSourceID)
        _ = try await service.queryContainer(ref: .dataSource(id: Self.queryDataSourceID), query: "search term")
        XCTAssertEqual(MockURLProtocol.snapshotRequests().count, 2)
    }

    // MARK: - Not Configured Test

    func testNotConfiguredThrowsNotConfiguredError() async throws {
        let emptyService = NotionService(tokenOverride: "")

        do {
            _ = try await emptyService.resolveSketchesContainer()
            XCTFail("Expected notConfigured error")
        } catch let error as NotionServiceError {
            if case .notConfigured = error {
                // Correct error type confirmed
            } else {
                XCTFail("Expected .notConfigured, got \(error)")
            }
        } catch {
            XCTFail("Expected NotionServiceError.notConfigured, got \(error)")
        }
    }
}
