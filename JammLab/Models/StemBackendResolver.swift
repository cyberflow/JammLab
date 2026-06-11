import Foundation

struct StemBackendCandidate: Equatable {
    var executableURL: URL
    var argumentsPrefix: [String]
    var displayName: String

    func commandDescription(extraArguments: [String]) -> String {
        ([executableURL.path] + argumentsPrefix + extraArguments)
            .map { $0.contains(" ") ? "\"\($0)\"" : $0 }
            .joined(separator: " ")
    }
}

struct StemBackendResolver {
    static let separatorDirectoryName = "JammLabSeparatorHelper"
    static let separatorExecutableName = "JammLabSeparatorHelper"

    var helperExecutableURL: URL

    init(helperExecutableURL: URL = StemBackendResolver.defaultBundledSeparatorExecutableURL()) {
        self.helperExecutableURL = helperExecutableURL
    }

    var bundledSeparatorCandidates: [StemBackendCandidate] {
        [
            StemBackendCandidate(
                executableURL: helperExecutableURL,
                argumentsPrefix: [],
                displayName: "JammLabSeparatorHelper/\(StemBackendResolver.separatorVersion)"
            )
        ]
    }

    static var separatorVersion: String {
        "1"
    }

    static func defaultBundledSeparatorExecutableURL(
        currentExecutableURL: URL = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
    ) -> URL {
        currentExecutableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(separatorDirectoryName, isDirectory: true)
            .appendingPathComponent(separatorExecutableName)
    }
}
