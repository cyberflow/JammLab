import XCTest
@testable import JammLab

final class ProjectSaveDestinationTests: XCTestCase {
    func testProjectSaveDestinationCreatesProjectSubdirectory() {
        let selectedURL = URL(fileURLWithPath: "/tmp/JammLab/Song")
        let destination = ProjectSaveDestination.projectFolder(selectedURL)

        XCTAssertEqual(destination.artifactRootURL.path, "/tmp/JammLab/Song")
        XCTAssertEqual(destination.projectURL.path, "/tmp/JammLab/Song/Song.jammlab")
        XCTAssertEqual(destination.securityScopedAccessURL.path, "/tmp/JammLab/Song")
        XCTAssertTrue(destination.createSubdirectory)
    }

    func testProjectSaveDestinationWithoutSubdirectoryUsesSelectedProjectFile() {
        let selectedURL = URL(fileURLWithPath: "/tmp/JammLab/Song.jammlab")
        let destination = ProjectSaveDestination.projectFile(selectedURL)

        XCTAssertEqual(destination.artifactRootURL.path, "/tmp/JammLab")
        XCTAssertEqual(destination.projectURL.path, "/tmp/JammLab/Song.jammlab")
        XCTAssertEqual(destination.securityScopedAccessURL.path, "/tmp/JammLab")
        XCTAssertFalse(destination.createSubdirectory)
    }

    func testProjectSaveDestinationStripsJammlabExtensionFromProjectFolderSelection() {
        let selectedURL = URL(fileURLWithPath: "/tmp/JammLab/Song.jammlab")
        let destination = ProjectSaveDestination.projectFolder(selectedURL)

        XCTAssertEqual(destination.artifactRootURL.path, "/tmp/JammLab/Song")
        XCTAssertEqual(destination.projectURL.path, "/tmp/JammLab/Song/Song.jammlab")
        XCTAssertEqual(destination.securityScopedAccessURL.path, "/tmp/JammLab/Song")
    }

    func testProjectSaveDestinationAddsJammlabExtensionForFileMode() {
        let selectedURL = URL(fileURLWithPath: "/tmp/JammLab/Song")
        let destination = ProjectSaveDestination.projectFile(selectedURL)

        XCTAssertEqual(destination.artifactRootURL.path, "/tmp/JammLab")
        XCTAssertEqual(destination.projectURL.path, "/tmp/JammLab/Song.jammlab")
        XCTAssertEqual(destination.securityScopedAccessURL.path, "/tmp/JammLab")
        XCTAssertFalse(destination.createSubdirectory)
    }
}
