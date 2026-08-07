import XCTest
@testable import NotionSketch

final class SettingsManagerTests: XCTestCase {

    // MARK: - Helpers

    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "NotionSketchTests.Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    // MARK: - A) Full titled URL persistence

    @MainActor
    func testFullTitledURLPersistence() {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }

        let titledURL = "https://" + "www.notion.so/My-Sketches-11111111111111111111111111111111"
        let raw = "  \(titledURL)  "

        let mgr = SettingsManager(defaults: context.defaults)
        mgr.containerInput = raw

        XCTAssertEqual(context.defaults.string(forKey: "notion_container_input"), titledURL)
        XCTAssertTrue(context.defaults.string(forKey: "notion_container_input")!.contains("My-Sketches"))
        XCTAssertNotEqual(context.defaults.string(forKey: "notion_container_input"), "11111111-1111-1111-1111-111111111111")
    }

    // MARK: - B) Whitespace-only new key migrates a valid legacy value

    @MainActor
    func testWhitespaceOnlyNewKeyMigratesValidLegacyValue() {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }

        context.defaults.set("11111111-1111-1111-1111-111111111111", forKey: "notion_database_id")
        context.defaults.set("   ", forKey: "notion_container_input")

        let mgr = SettingsManager(defaults: context.defaults)

        XCTAssertEqual(mgr.containerInput, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(context.defaults.string(forKey: "notion_container_input"), "11111111-1111-1111-1111-111111111111")
    }

    // MARK: - C) Nonempty new key is not overwritten

    @MainActor
    func testNonemptyNewKeyIsNotOverwritten() {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }

        context.defaults.set("11111111-1111-1111-1111-111111111111", forKey: "notion_database_id")
        context.defaults.set("22222222-2222-2222-2222-222222222222", forKey: "notion_container_input")

        let mgr = SettingsManager(defaults: context.defaults)

        XCTAssertEqual(mgr.containerInput, "22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(context.defaults.string(forKey: "notion_container_input"), "22222222-2222-2222-2222-222222222222")
    }

    // MARK: - D) Invalid configuration

    @MainActor
    func testInvalidConfiguration() {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }

        let mgr = SettingsManager(defaults: context.defaults)
        mgr.apiToken = "some_token"
        mgr.containerInput = "not-a-notion-container"

        XCTAssertFalse(mgr.isConfigured)
    }

    // MARK: - Additional useful tests

    @MainActor
    func testSetContainerInputPreservesRawURLTrimmed() {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }

        let mgr = SettingsManager(defaults: context.defaults)
        let url = "https://www.notion.so/My-Sketches-11111111111111111111111111111111"
        mgr.containerInput = url

        XCTAssertEqual(mgr.containerInput, url)
    }

    @MainActor
    func testSetContainerInputTrimsWhitespace() {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }

        let mgr = SettingsManager(defaults: context.defaults)
        let raw = "  https://www.notion.so/11111111-1111-1111-1111-111111111111  "
        mgr.containerInput = raw

        XCTAssertEqual(context.defaults.string(forKey: "notion_container_input"), "https://www.notion.so/11111111-1111-1111-1111-111111111111")
    }

    @MainActor
    func testNonEmptyNewKeyPreservedWithoutMigration() {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }

        let originalURL = "https://www.notion.so/11111111-1111-1111-1111-111111111111"
        context.defaults.set(originalURL, forKey: "notion_container_input")

        let mgr = SettingsManager(defaults: context.defaults)
        XCTAssertEqual(mgr.containerInput, originalURL)
    }

    @MainActor
    func testIsConfiguredFalseForInvalidContainerInput() {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }

        let mgr = SettingsManager(defaults: context.defaults)
        mgr.apiToken = "valid_token"
        mgr.containerInput = "not-a-valid-id"

        XCTAssertFalse(mgr.isConfigured)
    }

    @MainActor
    func testIsConfiguredFalseForEmptyContainerInput() {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }

        let mgr = SettingsManager(defaults: context.defaults)
        mgr.apiToken = "valid_token"

        XCTAssertFalse(mgr.isConfigured)
    }

    @MainActor
    func testIsConfiguredTrueForValidInput() {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }

        let mgr = SettingsManager(defaults: context.defaults)
        mgr.apiToken = "valid_token"
        mgr.containerInput = "11111111-1111-1111-1111-111111111111"

        XCTAssertTrue(mgr.isConfigured)
    }

    @MainActor
    func testClearContainerInput() {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }

        let mgr = SettingsManager(defaults: context.defaults)
        mgr.containerInput = "https://notion.so/11111111-1111-1111-1111-111111111111"
        mgr.containerInput = ""

        XCTAssertEqual(mgr.containerInput, "")
    }

    @MainActor
    func testLegacyDatabaseIDMigratedToContainerInput() {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }

        let legacyID = "11111111-1111-1111-1111-111111111111"
        context.defaults.set(legacyID, forKey: "notion_database_id")

        let mgr = SettingsManager(defaults: context.defaults)
        XCTAssertEqual(mgr.containerInput, legacyID)
    }
}
