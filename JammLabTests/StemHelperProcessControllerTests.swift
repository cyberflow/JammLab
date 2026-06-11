import XCTest
@testable import JammLab

final class StemHelperProcessControllerTests: XCTestCase {
    func testStemHelperControllerDoesNotLaunchWhenHeartbeatIsFresh() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let helperURL = try executableHelperFile(in: directory)
        let heartbeatURL = directory.appendingPathComponent(StemJobFiles.heartbeatFilename)
        try writeHeartbeat(to: heartbeatURL, updatedAt: Date())
        let launcher = MockStemHelperLauncher()
        let controller = StemHelperProcessController(
            helperExecutableURL: helperURL,
            heartbeatURL: heartbeatURL,
            launcher: launcher
        )

        try await controller.ensureRunning(timeout: 0.2)

        XCTAssertEqual(launcher.launchCount, 0)
    }

    func testStemHelperControllerIgnoresWrongVersionHeartbeat() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let helperURL = try executableHelperFile(in: directory)
        let heartbeatURL = directory.appendingPathComponent(StemJobFiles.heartbeatFilename)
        try writeHeartbeat(to: heartbeatURL, helperVersion: StemJobFiles.helperVersion - 1, updatedAt: Date())
        let launcher = MockStemHelperLauncher()
        launcher.onLaunch = { _ in
            try self.writeHeartbeat(to: heartbeatURL, updatedAt: Date())
        }
        let controller = StemHelperProcessController(
            helperExecutableURL: helperURL,
            heartbeatURL: heartbeatURL,
            launcher: launcher
        )

        try await controller.ensureRunning(timeout: 0.5)

        XCTAssertEqual(launcher.launchCount, 1)
    }

    func testStemHelperControllerLaunchesWhenHeartbeatIsMissing() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let helperURL = try executableHelperFile(in: directory)
        let heartbeatURL = directory.appendingPathComponent(StemJobFiles.heartbeatFilename)
        let launcher = MockStemHelperLauncher()
        launcher.onLaunch = { _ in
            try self.writeHeartbeat(to: heartbeatURL, updatedAt: Date())
        }
        let controller = StemHelperProcessController(
            helperExecutableURL: helperURL,
            heartbeatURL: heartbeatURL,
            launcher: launcher
        )

        try await controller.ensureRunning(timeout: 0.5)

        XCTAssertEqual(launcher.launchCount, 1)
    }

    func testStemHelperControllerDoesNotLaunchDuplicateProcess() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let helperURL = try executableHelperFile(in: directory)
        let heartbeatURL = directory.appendingPathComponent(StemJobFiles.heartbeatFilename)
        let launcher = MockStemHelperLauncher()
        launcher.onLaunch = { _ in
            try self.writeHeartbeat(to: heartbeatURL, updatedAt: Date())
        }
        let controller = StemHelperProcessController(
            helperExecutableURL: helperURL,
            heartbeatURL: heartbeatURL,
            launcher: launcher
        )

        try await controller.ensureRunning(timeout: 0.5)
        try await controller.ensureRunning(timeout: 0.5)

        XCTAssertEqual(launcher.launchCount, 1)
    }

    func testStemHelperControllerReportsMissingExecutable() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let helperURL = directory.appendingPathComponent("JammLabStemHelper")
        let heartbeatURL = directory.appendingPathComponent(StemJobFiles.heartbeatFilename)
        let controller = StemHelperProcessController(
            helperExecutableURL: helperURL,
            heartbeatURL: heartbeatURL,
            launcher: MockStemHelperLauncher()
        )

        do {
            try await controller.ensureRunning(timeout: 0.2)
            XCTFail("Expected missing executable error")
        } catch StemHelperLaunchError.missingExecutable(let url) {
            XCTAssertEqual(url, helperURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStemHelperControllerTerminatesAppOwnedProcess() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let helperURL = try executableHelperFile(in: directory)
        let heartbeatURL = directory.appendingPathComponent(StemJobFiles.heartbeatFilename)
        let process = MockStemHelperProcess()
        let launcher = MockStemHelperLauncher(process: process)
        launcher.onLaunch = { _ in
            try self.writeHeartbeat(to: heartbeatURL, updatedAt: Date())
        }

        do {
            let controller = StemHelperProcessController(
                helperExecutableURL: helperURL,
                heartbeatURL: heartbeatURL,
                launcher: launcher
            )
            try await controller.ensureRunning(timeout: 0.5)
            XCTAssertFalse(process.didTerminate)
        }

        XCTAssertTrue(process.didTerminate)
    }

}
