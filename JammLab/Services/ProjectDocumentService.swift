import AppKit
import Foundation
import UniformTypeIdentifiers

struct ProjectSaveDestination: Equatable {
    let projectURL: URL
    let artifactRootURL: URL
    let securityScopedAccessURL: URL
    let createSubdirectory: Bool

    static func projectFolder(_ folderURL: URL) -> ProjectSaveDestination {
        let artifactRootURL = folderURL.pathExtension.lowercased() == ProjectDocumentService.fileExtension
            ? folderURL.deletingPathExtension()
            : folderURL
        let projectURL = artifactRootURL
            .appendingPathComponent(artifactRootURL.lastPathComponent, isDirectory: false)
            .appendingPathExtension(ProjectDocumentService.fileExtension)

        return ProjectSaveDestination(
            projectURL: projectURL,
            artifactRootURL: artifactRootURL,
            securityScopedAccessURL: artifactRootURL,
            createSubdirectory: true
        )
    }

    static func projectFile(_ fileURL: URL) -> ProjectSaveDestination {
        let projectURL = fileURL.pathExtension.lowercased() == ProjectDocumentService.fileExtension
            ? fileURL
            : fileURL.deletingPathExtension().appendingPathExtension(ProjectDocumentService.fileExtension)

        return ProjectSaveDestination(
            projectURL: projectURL,
            artifactRootURL: projectURL.deletingLastPathComponent(),
            securityScopedAccessURL: projectURL.deletingLastPathComponent(),
            createSubdirectory: false
        )
    }
}

enum ProjectDocumentError: LocalizedError {
    case missingAudioFile
    case invalidProjectData(String)
    case projectArtifactAccessDenied
    case projectArtifactAccessDeniedUseProjectFolder

    var errorDescription: String? {
        switch self {
        case .missingAudioFile:
            return "Import an audio or video file before saving a project."
        case .invalidProjectData(let reason):
            return "Project data is invalid: \(reason)"
        case .projectArtifactAccessDenied:
            return "Project folder access is required to save stems, peaks, and media next to the project file."
        case .projectArtifactAccessDeniedUseProjectFolder:
            return "Project folder access is required to save stems, peaks, and media next to the project file. Enable Create subdirectory for project and choose a project folder."
        }
    }
}

final class ProjectDocumentService {
    static let fileExtension = "jammlab"
    static let contentType = UTType(filenameExtension: fileExtension) ?? .json

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    @MainActor
    func chooseProjectToOpen() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open JammLab Project"
        panel.prompt = "Open"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [Self.contentType]

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
    }

    @MainActor
    func chooseProjectSaveDestination(defaultName: String) -> ProjectSaveDestination? {
        let panel = NSSavePanel()
        panel.title = "Save JammLab Project"
        panel.message = "Choose a project folder name. With Create subdirectory enabled, the project file and artifacts are saved inside that folder."
        panel.prompt = "Save"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = (defaultName as NSString).deletingPathExtension
        let createSubdirectoryCheckbox = NSButton(checkboxWithTitle: "Create subdirectory for project", target: nil, action: nil)
        createSubdirectoryCheckbox.state = .on
        panel.accessoryView = createSubdirectoryCheckbox

        guard panel.runModal() == .OK else {
            return nil
        }

        guard let url = panel.url else { return nil }
        if createSubdirectoryCheckbox.state == .on {
            return .projectFolder(url)
        }

        return .projectFile(url)
    }

    func load(from url: URL) throws -> JammLabProject {
        let data = try Data(contentsOf: url)
        return try decoder.decode(JammLabProject.self, from: data)
    }

    func save(_ project: JammLabProject, to url: URL) throws {
        let data = try encoder.encode(project)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func bookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}
