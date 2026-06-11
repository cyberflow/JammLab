import Combine
import Foundation

struct RecentProjectEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var displayName: String
    var bookmarkData: Data
    var lastOpened: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        bookmarkData: Data,
        lastOpened: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.bookmarkData = bookmarkData
        self.lastOpened = lastOpened
    }

    func resolvedURL() throws -> URL {
        var isStale = false
        return try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}

@MainActor
final class RecentProjectsStore: ObservableObject {
    static let shared = RecentProjectsStore()
    static let defaultsKey = "recentJammLabProjects"

    var entries: [RecentProjectEntry] {
        storedEntries.filter { isValidProjectEntry($0) }
    }

    @Published private var storedEntries: [RecentProjectEntry] = []

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let limit: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        limit: Int = 10
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.limit = limit
        load()
    }

    func addProject(url: URL, bookmarkData: Data) {
        guard isValidProjectURL(url) else { return }

        pruneInvalidEntries()
        storedEntries.removeAll { entry in
            guard let resolvedURL = try? entry.resolvedURL() else { return false }
            return resolvedURL == url
        }

        storedEntries.insert(
            RecentProjectEntry(
                displayName: url.deletingPathExtension().lastPathComponent,
                bookmarkData: bookmarkData
            ),
            at: 0
        )
        storedEntries = Array(storedEntries.prefix(limit))
        save()
    }

    func remove(_ entry: RecentProjectEntry) {
        storedEntries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        storedEntries = []
        save()
    }

    func reload() {
        load()
    }

    func pruneInvalidEntries() {
        let prunedEntries = storedEntries.filter { isValidProjectEntry($0) }
        guard prunedEntries != storedEntries else { return }
        storedEntries = prunedEntries
        save()
    }

    func canOpenProject(at url: URL) -> Bool {
        isValidProjectURL(url)
    }

    private func load() {
        guard
            let data = defaults.data(forKey: Self.defaultsKey),
            let decodedEntries = try? decoder.decode([RecentProjectEntry].self, from: data)
        else {
            storedEntries = []
            return
        }

        storedEntries = Array(decodedEntries.prefix(limit))
        pruneInvalidEntries()
    }

    private func save() {
        guard let data = try? encoder.encode(storedEntries) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private func isValidProjectEntry(_ entry: RecentProjectEntry) -> Bool {
        guard let url = try? entry.resolvedURL() else { return false }
        return isValidProjectURL(url)
    }

    private func isValidProjectURL(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == ProjectDocumentService.fileExtension else {
            return false
        }

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return !isDirectory.boolValue
    }
}
