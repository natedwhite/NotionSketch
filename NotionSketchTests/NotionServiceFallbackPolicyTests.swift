import XCTest
@testable import NotionSketch

final class NotionServiceFallbackPolicyTests: XCTestCase {
    private static let databaseID = "11111111-1111-1111-1111-111111111111"
    private static let dataSourceID = "22222222-2222-2222-2222-222222222222"

    private static var databaseURL: String {
        "https://" + "www.notion.so/" + databaseID
    }

    private var service: NotionService!
    private var session: URLSession!

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)
        service = NotionService(
            session: session,
            tokenOverride: "test-token",
            containerInputOverride: Self.databaseURL
        )
    }

    override func tearDown() {
        MockURLProtocol.reset()
        service = nil
        session = nil
        super.tearDown()
    }

    private func response(for request: URLRequest, status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    private func discoveryJSON() -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "data_sources": [["id": Self.dataSourceID, "name": "Drawings"]]
        ])
    }

    private func schemaJSON() -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "properties": ["Name": ["type": "title"]]
        ])
    }

    private func emptyQueryJSON() -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "results": [],
            "has_more": false
        ])
    }

    func testLibraryQueryDoesNotFallBackAfterDecodeFailure() async throws {
        var callCount = 0
        MockURLProtocol.setHandler { [self] request in
            defer { callCount += 1 }

            switch callCount {
            case 0:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v1/databases/\(Self.databaseID)")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")
                return (response(for: request), discoveryJSON())

            case 1:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v1/data_sources/\(Self.dataSourceID)/query")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")
                return (response(for: request), Data("invalid json".utf8))

            default:
                XCTFail("Decode failure must not trigger a legacy database request")
                return (response(for: request, status: 500), Data())
            }
        }

        do {
            _ = try await service.fetchActivePageIDsForLibrarySync()
            XCTFail("Expected the data-source decode failure to reach the caller")
        } catch {
            // Expected: a semantic/decode failure is not eligible for fallback.
        }

        let requests = MockURLProtocol.snapshotRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertFalse(requests.contains {
            $0.url?.path == "/v1/databases/\(Self.databaseID)/query"
        })
    }

    func testLibraryQueryFallsBackAfterHTTPFailure() async throws {
        var callCount = 0
        MockURLProtocol.setHandler { [self] request in
            defer { callCount += 1 }

            switch callCount {
            case 0:
                XCTAssertEqual(request.url?.path, "/v1/databases/\(Self.databaseID)")
                return (response(for: request), discoveryJSON())

            case 1:
                XCTAssertEqual(request.url?.path, "/v1/data_sources/\(Self.dataSourceID)/query")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")
                return (response(for: request, status: 500), Data())

            case 2:
                XCTAssertEqual(request.url?.path, "/v1/databases/\(Self.databaseID)/query")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2022-06-28")
                return (response(for: request), emptyQueryJSON())

            default:
                XCTFail("Unexpected request count: \(callCount)")
                return (response(for: request, status: 500), Data())
            }
        }

        let pageIDs = try await service.fetchActivePageIDsForLibrarySync()
        XCTAssertTrue(pageIDs.isEmpty)
        XCTAssertEqual(MockURLProtocol.snapshotRequests().count, 3)
    }

    func testPageCreationDoesNotFallBackAfterDecodeFailure() async throws {
        var callCount = 0
        MockURLProtocol.setHandler { [self] request in
            defer { callCount += 1 }

            switch callCount {
            case 0:
                XCTAssertEqual(request.url?.path, "/v1/databases/\(Self.databaseID)")
                return (response(for: request), discoveryJSON())

            case 1:
                XCTAssertEqual(request.url?.path, "/v1/data_sources/\(Self.dataSourceID)")
                return (response(for: request), schemaJSON())

            case 2:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v1/pages")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2025-09-03")
                return (response(for: request), Data("invalid json".utf8))

            default:
                XCTFail("Page decode failure must not trigger database-parent creation")
                return (response(for: request, status: 500), Data())
            }
        }

        do {
            _ = try await service.createPageInDatabase(title: "Regression")
            XCTFail("Expected page response decode failure")
        } catch {
            // Expected: the valid 2xx response is not retried through a legacy parent.
        }

        let requests = MockURLProtocol.snapshotRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests.filter { $0.url?.path == "/v1/pages" }.count, 1)
    }
}
