import XCTest
@testable import NotionSketch

final class NotionContainerParserTests: XCTestCase {

    // MARK: - normalizedID

    func testNormalizedIDStandardUUID() {
        let input = "11111111-1111-1111-1111-111111111111"
        XCTAssertEqual(NotionContainerParser.normalizedID(input), "11111111-1111-1111-1111-111111111111")
    }

    func testNormalizedIDHexOnly() {
        let input = "11111111111111111111111111111111"
        XCTAssertEqual(NotionContainerParser.normalizedID(input), "11111111-1111-1111-1111-111111111111")
    }

    func testNormalizedIDUppercaseHex() {
        let input = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        XCTAssertEqual(NotionContainerParser.normalizedID(input), "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    }

    func testNormalizedIDShortInput() {
        XCTAssertNil(NotionContainerParser.normalizedID("12345"))
    }

    func testNormalizedIDNonHex() {
        XCTAssertNil(NotionContainerParser.normalizedID("zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz"))
    }

    func testNormalizedIDWithWhitespace() {
        let input = " 11111111-1111-1111-1111-111111111111 "
        XCTAssertEqual(NotionContainerParser.normalizedID(input), "11111111-1111-1111-1111-111111111111")
    }

    // MARK: - parse Database ID

    func testParseDatabaseIDStandard() {
        let input = "11111111-1111-1111-1111-111111111111"
        guard case .database(let id) = NotionContainerParser.parse(input) else {
            XCTFail("Expected database case")
            return
        }
        XCTAssertEqual(id, "11111111-1111-1111-1111-111111111111")
    }

    func testParseDatabaseIDHexOnly() {
        let input = "11111111111111111111111111111111"
        guard case .database(let id) = NotionContainerParser.parse(input) else {
            XCTFail("Expected database case")
            return
        }
        XCTAssertEqual(id, "11111111-1111-1111-1111-111111111111")
    }

    func testParseDatabaseIDFromNotionURL() {
        let input = "https://notion.so/11111111-1111-1111-1111-111111111111"
        guard case .database(let id) = NotionContainerParser.parse(input) else {
            XCTFail("Expected database case")
            return
        }
        XCTAssertEqual(id, "11111111-1111-1111-1111-111111111111")
    }

    func testParseDatabaseIDFromWorkspaceURL() {
        let input = "https://myteam.notion.so/11111111-1111-1111-1111-111111111111"
        guard case .database(let id) = NotionContainerParser.parse(input) else {
            XCTFail("Expected database case")
            return
        }
        XCTAssertEqual(id, "11111111-1111-1111-1111-111111111111")
    }

    // MARK: - Titled URL parsing (suffix fallbacks)

    func testParseTitledURLWithUndashedSuffix() {
        let input = "https://www.notion.so/My-Sketches-11111111111111111111111111111111"
        guard case .database(let id) = NotionContainerParser.parse(input) else {
            XCTFail("Expected database case for titled URL with undashed suffix")
            return
        }
        XCTAssertEqual(id, "11111111-1111-1111-1111-111111111111")
    }

    func testParseTitledURLWithDashedSuffix() {
        let input = "https://www.notion.so/My-Sketches-11111111-1111-1111-1111-111111111111"
        guard case .database(let id) = NotionContainerParser.parse(input) else {
            XCTFail("Expected database case for titled URL with dashed suffix")
            return
        }
        XCTAssertEqual(id, "11111111-1111-1111-1111-111111111111")
    }

    func testParsePercentEncodedTitledURL() {
        let input = "https://www.notion.so/My%20Sketches-11111111111111111111111111111111"
        guard case .database(let id) = NotionContainerParser.parse(input) else {
            XCTFail("Expected database case for percent-encoded titled URL")
            return
        }
        XCTAssertEqual(id, "11111111-1111-1111-1111-111111111111")
    }

    func testParseTitledURLNonNotionHostReturnsNil() {
        let input = "https://example.com/My-Sketches-11111111111111111111111111111111"
        XCTAssertNil(NotionContainerParser.parse(input))
    }

    func testParseNonURLTextEndingInHexReturnsNil() {
        let input = "some random text ending in 11111111111111111111111111111111"
        XCTAssertNil(NotionContainerParser.parse(input))
    }

    // MARK: - Query precedence over database path

    func testParseQueryDSPrecedenceOverDatabasePath() {
        let input = "https://www.notion.so/11111111-1111-1111-1111-111111111111?ds=44444444-4444-4444-4444-444444444444"
        guard case .dataSource(let id) = NotionContainerParser.parse(input) else {
            XCTFail("Expected dataSource case, ds query should take precedence")
            return
        }
        XCTAssertEqual(id, "44444444-4444-4444-4444-444444444444")
    }

    func testParseQueryDataSourcePrecedenceOverDatabasePath() {
        let input = "https://www.notion.so/11111111-1111-1111-1111-111111111111?data_source=44444444-4444-4444-4444-444444444444"
        guard case .dataSource(let id) = NotionContainerParser.parse(input) else {
            XCTFail("Expected dataSource case, data_source query should take precedence")
            return
        }
        XCTAssertEqual(id, "44444444-4444-4444-4444-444444444444")
    }

    // MARK: - parse Data Source ID

    func testParseDataSourceQueryParam() {
        let input = "https://notion.so/data_sources?ds=22222222-2222-2222-2222-222222222222"
        guard case .dataSource(let id) = NotionContainerParser.parse(input) else {
            XCTFail("Expected dataSource case")
            return
        }
        XCTAssertEqual(id, "22222222-2222-2222-2222-222222222222")
    }

    func testParseDataSourceQueryParamAltName() {
        let input = "https://notion.so/page?data_source=22222222-2222-2222-2222-222222222222"
        guard case .dataSource(let id) = NotionContainerParser.parse(input) else {
            XCTFail("Expected dataSource case")
            return
        }
        XCTAssertEqual(id, "22222222-2222-2222-2222-222222222222")
    }

    func testParseDataSourcePathSegment() {
        let input = "https://notion.so/data_sources/22222222-2222-2222-2222-222222222222"
        guard case .dataSource(let id) = NotionContainerParser.parse(input) else {
            XCTFail("Expected dataSource case")
            return
        }
        XCTAssertEqual(id, "22222222-2222-2222-2222-222222222222")
    }

    func testParseDataSourcePathSegmentHyphenated() {
        let input = "https://notion.so/data-source/22222222-2222-2222-2222-222222222222"
        guard case .dataSource(let id) = NotionContainerParser.parse(input) else {
            XCTFail("Expected dataSource case")
            return
        }
        XCTAssertEqual(id, "22222222-2222-2222-2222-222222222222")
    }

    func testParseQueryPrecedenceOverDatabasePath() {
        let input = "https://notion.so/11111111-1111-1111-1111-111111111111?ds=44444444-4444-4444-4444-444444444444"
        guard case .dataSource(let id) = NotionContainerParser.parse(input) else {
            XCTFail("Expected dataSource case, query should take precedence")
            return
        }
        XCTAssertEqual(id, "44444444-4444-4444-4444-444444444444")
    }

    // MARK: - Invalid inputs

    func testParseEmptyInput() {
        XCTAssertNil(NotionContainerParser.parse(""))
    }

    func testParseWhitespaceOnly() {
        XCTAssertNil(NotionContainerParser.parse("   "))
    }

    func testParsePlainWord() {
        XCTAssertNil(NotionContainerParser.parse("mydatabase"))
    }

    func testParseShortHex() {
        XCTAssertNil(NotionContainerParser.parse("12345"))
    }

    func testParseNonNotionHost() {
        XCTAssertNil(NotionContainerParser.parse("https://example.com/11111111-1111-1111-1111-111111111111"))
    }

    func testParseNotionURLWithoutID() {
        XCTAssertNil(NotionContainerParser.parse("https://notion.so"))
    }

    // MARK: - ContainerRef properties

    func testContainerRefID() {
        XCTAssertEqual(NotionContainerRef.database(id: "abc").id, "abc")
        XCTAssertEqual(NotionContainerRef.dataSource(id: "def").id, "def")
    }

    func testContainerRefIsDataSource() {
        XCTAssertFalse(NotionContainerRef.database(id: "abc").isDataSource)
        XCTAssertTrue(NotionContainerRef.dataSource(id: "def").isDataSource)
    }

    func testContainerRefEquatable() {
        XCTAssertEqual(NotionContainerRef.database(id: "a"), NotionContainerRef.database(id: "a"))
        XCTAssertEqual(NotionContainerRef.dataSource(id: "b"), NotionContainerRef.dataSource(id: "b"))
        XCTAssertNotEqual(NotionContainerRef.database(id: "a"), NotionContainerRef.dataSource(id: "a"))
    }

    // MARK: - ResolvedNotionContainer equatability

    func testResolvedContainerEquatable() {
        let a = ResolvedNotionContainer(ref: .database(id: "1"), fallbackDatabaseID: nil)
        let b = ResolvedNotionContainer(ref: .database(id: "1"), fallbackDatabaseID: nil)
        XCTAssertEqual(a, b)

        let c = ResolvedNotionContainer(ref: .database(id: "1"), fallbackDatabaseID: "2")
        XCTAssertNotEqual(a, c)
    }
}
