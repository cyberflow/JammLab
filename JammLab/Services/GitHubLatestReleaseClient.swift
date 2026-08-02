import Foundation

protocol HTTPDataLoading {
    func loadData(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionHTTPDataLoader: HTTPDataLoading {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func loadData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

protocol LatestReleaseProviding {
    func fetchLatestRelease(currentVersion: AppVersion) async throws -> AppRelease
}

enum GitHubLatestReleaseError: Error {
    case invalidResponse
    case unsuccessfulStatus(Int)
    case unsupportedRelease
    case invalidReleaseURL
}

final class GitHubLatestReleaseClient: LatestReleaseProviding {
    static let endpoint = URL(string: "https://api.github.com/repos/cyberflow/JammLab/releases/latest")!
    static let apiVersion = "2026-03-10"
    static let timeout: TimeInterval = 10

    private let dataLoader: HTTPDataLoading
    private let decoder: JSONDecoder

    init(
        dataLoader: HTTPDataLoading = URLSessionHTTPDataLoader(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.dataLoader = dataLoader
        self.decoder = decoder
    }

    func fetchLatestRelease(currentVersion: AppVersion) async throws -> AppRelease {
        let request = makeRequest(currentVersion: currentVersion)
        let (data, response) = try await dataLoader.loadData(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubLatestReleaseError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw GitHubLatestReleaseError.unsuccessfulStatus(httpResponse.statusCode)
        }

        let payload = try decoder.decode(GitHubReleaseResponse.self, from: data)
        guard
            !payload.draft,
            !payload.prerelease,
            let version = AppVersion(stableVersionString: payload.tagName)
        else {
            throw GitHubLatestReleaseError.unsupportedRelease
        }
        guard Self.isTrustedReleaseURL(payload.htmlURL) else {
            throw GitHubLatestReleaseError.invalidReleaseURL
        }

        let normalizedTitle = payload.name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNotes = payload.body?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = normalizedTitle.flatMap { $0.isEmpty ? nil : $0 }
            ?? "JammLab \(version.description)"

        return AppRelease(
            version: version,
            title: title,
            notes: normalizedNotes ?? "",
            pageURL: payload.htmlURL
        )
    }

    func makeRequest(currentVersion: AppVersion) -> URLRequest {
        var request = URLRequest(
            url: Self.endpoint,
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: Self.timeout
        )
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("JammLab/\(currentVersion.description)", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func isTrustedReleaseURL(_ url: URL) -> Bool {
        guard
            url.scheme?.lowercased() == "https",
            url.host?.lowercased() == "github.com"
        else {
            return false
        }

        return url.path.hasPrefix("/cyberflow/JammLab/releases/")
    }
}

private struct GitHubReleaseResponse: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}
