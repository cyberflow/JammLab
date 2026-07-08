import XCTest
@testable import JammLab

final class RecentProjectsStoreTests: XCTestCase {
    @MainActor
    func testRecentProjectsStoreLoadsValidProjectEntries() throws {
        let defaults = try temporaryUserDefaults()
        let projectURL = try temporaryFile(name: "valid.jammlab", contents: "{}")
        defer { try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent()) }
        let entry = RecentProjectEntry(
            displayName: "Valid",
            bookmarkData: try ProjectDocumentService().bookmarkData(for: projectURL)
        )

        defaults.set(try JSONEncoder().encode([entry]), forKey: RecentProjectsStore.defaultsKey)
        let store = RecentProjectsStore(defaults: defaults)

        XCTAssertEqual(store.entries.map(\.displayName), ["Valid"])
    }

    @MainActor
    func testRecentProjectsStorePrunesMissingProjectEntriesOnLoad() throws {
        let defaults = try temporaryUserDefaults()
        let projectURL = try temporaryFile(name: "missing.jammlab", contents: "{}")
        let projectDirectory = projectURL.deletingLastPathComponent()
        let entry = RecentProjectEntry(
            displayName: "Missing",
            bookmarkData: try ProjectDocumentService().bookmarkData(for: projectURL)
        )
        try FileManager.default.removeItem(at: projectDirectory)

        defaults.set(try JSONEncoder().encode([entry]), forKey: RecentProjectsStore.defaultsKey)
        let store = RecentProjectsStore(defaults: defaults)

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(RecentProjectsStore(defaults: defaults).entries.isEmpty)
    }

    @MainActor
    func testRecentProjectsStorePrunesUnsupportedExtensionsOnLoad() throws {
        let defaults = try temporaryUserDefaults()
        let textURL = try temporaryFile(name: "notes.txt", contents: "not a project")
        defer { try? FileManager.default.removeItem(at: textURL.deletingLastPathComponent()) }
        let entry = RecentProjectEntry(
            displayName: "Notes",
            bookmarkData: try ProjectDocumentService().bookmarkData(for: textURL)
        )

        defaults.set(try JSONEncoder().encode([entry]), forKey: RecentProjectsStore.defaultsKey)
        let store = RecentProjectsStore(defaults: defaults)

        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testRecentProjectsStoreDeduplicatesProjectsWhenAdding() throws {
        let defaults = try temporaryUserDefaults()
        let projectURL = try temporaryFile(name: "dedupe.jammlab", contents: "{}")
        defer { try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent()) }
        let projectService = ProjectDocumentService()
        let store = RecentProjectsStore(defaults: defaults)

        store.addProject(url: projectURL, bookmarkData: try projectService.bookmarkData(for: projectURL))
        store.addProject(url: projectURL, bookmarkData: try projectService.bookmarkData(for: projectURL))

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.displayName, "dedupe")
    }

    @MainActor
    func testRecentProjectsStoreClearPersistsEmptyList() throws {
        let defaults = try temporaryUserDefaults()
        let projectURL = try temporaryFile(name: "clear.jammlab", contents: "{}")
        defer { try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent()) }
        let projectService = ProjectDocumentService()
        let store = RecentProjectsStore(defaults: defaults)

        store.addProject(url: projectURL, bookmarkData: try projectService.bookmarkData(for: projectURL))
        XCTAssertFalse(store.entries.isEmpty)

        store.clear()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(RecentProjectsStore(defaults: defaults).entries.isEmpty)
    }
}
