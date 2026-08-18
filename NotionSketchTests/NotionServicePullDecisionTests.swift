import XCTest
@testable import NotionSketch

/// Pull-decision tests for the last-write-wins library sync rule.
/// NotionSyncManager.shouldPullRemoteChanges is pure timestamp logic —
/// no network or ModelContext needed.
final class NotionServicePullDecisionTests: XCTestCase {

    private let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let localEdit = Date(timeIntervalSince1970: 1_700_001_000)
    private let synced = Date(timeIntervalSince1970: 1_700_002_000)
    private let remoteNewer = Date(timeIntervalSince1970: 1_700_003_000)

    func testRequiresRemoteTimestamp() async {
        let shouldPull = await NotionSyncManager.shouldPullRemoteChanges(
            remoteEditedAt: nil,
            lastSyncedAt: synced,
            lastEditedLocally: localEdit,
            createdAt: createdAt
        )
        XCTAssertFalse(shouldPull)
    }

    func testRejectsRemoteEditOlderThanLocalEdit() async {
        let shouldPull = await NotionSyncManager.shouldPullRemoteChanges(
            remoteEditedAt: createdAt.addingTimeInterval(500),
            lastSyncedAt: nil,
            lastEditedLocally: localEdit,
            createdAt: createdAt
        )
        XCTAssertFalse(shouldPull)
    }

    func testRejectsEchoOfOwnPush() async {
        // lastSyncedAt >= remoteEditedAt means the remote edit is our own push.
        let shouldPull = await NotionSyncManager.shouldPullRemoteChanges(
            remoteEditedAt: synced,
            lastSyncedAt: synced,
            lastEditedLocally: localEdit,
            createdAt: createdAt
        )
        XCTAssertFalse(shouldPull)
    }

    func testAcceptsGenuineRemoteEdit() async {
        let shouldPull = await NotionSyncManager.shouldPullRemoteChanges(
            remoteEditedAt: remoteNewer,
            lastSyncedAt: synced,
            lastEditedLocally: localEdit,
            createdAt: createdAt
        )
        XCTAssertTrue(shouldPull)
    }

    func testRejectsFreshImport() async {
        // Imported seconds ago: local creation is newer than the remote edit.
        let shouldPull = await NotionSyncManager.shouldPullRemoteChanges(
            remoteEditedAt: createdAt,
            lastSyncedAt: nil,
            lastEditedLocally: nil,
            createdAt: remoteNewer
        )
        XCTAssertFalse(shouldPull)
    }

    func testAcceptsWhenNeverSyncedAndRemoteIsNewer() async {
        let shouldPull = await NotionSyncManager.shouldPullRemoteChanges(
            remoteEditedAt: remoteNewer,
            lastSyncedAt: nil,
            lastEditedLocally: nil,
            createdAt: createdAt
        )
        XCTAssertTrue(shouldPull)
    }
}
