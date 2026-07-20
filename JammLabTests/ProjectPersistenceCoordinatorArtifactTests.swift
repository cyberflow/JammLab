import XCTest
@testable import JammLab

final class ProjectPersistenceCoordinatorArtifactTests: XCTestCase {
    func testProjectPersistenceCoordinatorPersistsVideoAudioAndReturnsTemporaryCleanupURL() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cachedAudioURL = try temporaryFile(in: directory, name: "cached-audio.m4a", contents: "audio")
        let videoURL = directory.appendingPathComponent("lesson.mov")
        let projectURL = directory.appendingPathComponent("Song.jammlab")
        let store = ProjectArtifactStore()
        let coordinator = try makeProjectPersistenceCoordinator(projectArtifactStore: store)
        let input = ProjectSaveArtifactsInput(
            importedFile: ImportedAudioFile(
                url: cachedAudioURL,
                sourceMediaURL: videoURL,
                displayName: "lesson.mov",
                duration: 12,
                mediaKind: .video
            ),
            projectURL: projectURL,
            peakformData: nil,
            stemPeakforms: [:],
            stemFiles: [],
            stemCacheMetadata: nil
        )

        let result = try await coordinator.prepareSaveArtifacts(input)

        XCTAssertEqual(result.importedFile?.url, store.videoAudioURL(for: projectURL))
        XCTAssertEqual(result.temporaryVideoAudioURLToRemove, cachedAudioURL)
        XCTAssertEqual(try String(contentsOf: store.videoAudioURL(for: projectURL), encoding: .utf8), "audio")
    }

    func testProjectPersistenceCoordinatorWritesPeakformsAndStemMetadata() async throws {
        let directory = temporaryDirectory()
        let stemSourceDirectory = directory.appendingPathComponent("stem-source", isDirectory: true)
        try FileManager.default.createDirectory(at: stemSourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let audioURL = try temporaryFile(in: directory, name: "song.wav", contents: "audio")
        let projectURL = directory.appendingPathComponent("Song.jammlab")
        let store = ProjectArtifactStore()
        let coordinator = try makeProjectPersistenceCoordinator(projectArtifactStore: store)
        let peakform = PeakformData(
            duration: 1,
            sampleRate: 44_100,
            levels: [PeakformLevel(samplesPerPeak: 512, peaks: [PeakPoint(min: -0.5, max: 0.5, rms: 0.2)])]
        )
        let stems = try StemSeparationMethod.fourStem.stemTypes.map { type in
            StemFile(
                type: type,
                url: try temporaryFile(in: stemSourceDirectory, name: "\(type.rawValue).wav", contents: type.rawValue),
                displayName: type.title
            )
        }
        let metadata = StemCacheMetadata(
            cacheKey: "cache-key",
            sourceFingerprint: StemSourceFingerprint(path: audioURL.path, fileSize: 5, modificationTime: 10),
            backendIdentifier: "JammLabSeparatorHelper/test",
            separationMethodID: StemSeparationMethod.fourStem.id,
            modelName: StemSeparationMethod.fourStem.modelName,
            settingsVersion: 2,
            createdAt: Date(timeIntervalSince1970: 100),
            stems: stems
        )
        let input = ProjectSaveArtifactsInput(
            importedFile: ImportedAudioFile(url: audioURL, displayName: "song.wav", duration: 1),
            projectURL: projectURL,
            peakformData: peakform,
            stemPeakforms: [.vocals: peakform],
            stemFiles: stems,
            stemCacheMetadata: metadata
        )

        let result = try await coordinator.prepareSaveArtifacts(input)

        XCTAssertNotNil(try store.readMainPeakform(projectURL: projectURL))
        XCTAssertNotNil(try store.readStemPeakform(type: .vocals, projectURL: projectURL))
        XCTAssertEqual(result.peakformURLsToRemove, [audioURL] + stems.map(\.url))
        XCTAssertEqual(result.stemMetadata?.cacheKey, metadata.cacheKey)
        XCTAssertEqual(result.stemCacheKeyToRemove, metadata.cacheKey)
        XCTAssertEqual(result.stemMetadata?.stems.map { $0.url.deletingLastPathComponent() }, Array(repeating: store.stemsDirectory(for: projectURL), count: StemSeparationMethod.fourStem.stemTypes.count))
    }

    func testFinalizeSavedArtifactsRemovesOwnedTemporaryVideoDirectory() async throws {
        let directory = temporaryDirectory()
        let mediaCacheRoot = directory.appendingPathComponent("MediaCache", isDirectory: true)
        let cachedDirectory = mediaCacheRoot.appendingPathComponent("cache-key", isDirectory: true)
        try FileManager.default.createDirectory(at: cachedDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cachedAudioURL = try temporaryFile(in: cachedDirectory, name: "audio.m4a", contents: "temporary")
        let persistedAudioURL = try temporaryFile(in: directory, name: "persisted.m4a", contents: "persisted")
        let coordinator = try makeProjectPersistenceCoordinator(
            projectArtifactStore: ProjectArtifactStore(),
            temporaryVideoAudioCacheRoot: mediaCacheRoot
        )
        let result = ProjectSaveArtifactsResult(
            importedFile: ImportedAudioFile(url: persistedAudioURL, displayName: "persisted.m4a", duration: 1),
            temporaryVideoAudioURLToRemove: cachedAudioURL
        )

        await coordinator.finalizeSavedArtifacts(result)

        XCTAssertFalse(FileManager.default.fileExists(atPath: cachedDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: persistedAudioURL.path))
    }

    func testFinalizeSavedArtifactsPreservesUnownedMediaCacheDirectory() async throws {
        let directory = temporaryDirectory()
        let ownedMediaCacheRoot = directory.appendingPathComponent("Owned/MediaCache", isDirectory: true)
        let unownedDirectory = directory.appendingPathComponent("Unowned/MediaCache/cache-key", isDirectory: true)
        try FileManager.default.createDirectory(at: unownedDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let unownedAudioURL = try temporaryFile(in: unownedDirectory, name: "audio.m4a", contents: "keep")
        let persistedAudioURL = try temporaryFile(in: directory, name: "persisted.m4a", contents: "persisted")
        let coordinator = try makeProjectPersistenceCoordinator(
            projectArtifactStore: ProjectArtifactStore(),
            temporaryVideoAudioCacheRoot: ownedMediaCacheRoot
        )
        let result = ProjectSaveArtifactsResult(
            importedFile: ImportedAudioFile(url: persistedAudioURL, displayName: "persisted.m4a", duration: 1),
            temporaryVideoAudioURLToRemove: unownedAudioURL
        )

        await coordinator.finalizeSavedArtifacts(result)

        XCTAssertTrue(FileManager.default.fileExists(atPath: unownedAudioURL.path))
    }

    func testFinalizeSavedArtifactsPreservesDirectoryReachedThroughSymlinkOutsideMediaCache() async throws {
        let directory = temporaryDirectory()
        let mediaCacheRoot = directory.appendingPathComponent("MediaCache", isDirectory: true)
        let externalRoot = directory.appendingPathComponent("External", isDirectory: true)
        let externalCacheDirectory = externalRoot.appendingPathComponent("cache-key", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaCacheRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalCacheDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let symlinkURL = mediaCacheRoot.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: externalRoot)
        let externalAudioURL = try temporaryFile(in: externalCacheDirectory, name: "audio.m4a", contents: "keep")
        let linkedAudioURL = symlinkURL
            .appendingPathComponent("cache-key", isDirectory: true)
            .appendingPathComponent("audio.m4a")
        let persistedAudioURL = try temporaryFile(in: directory, name: "persisted.m4a", contents: "persisted")
        let coordinator = try makeProjectPersistenceCoordinator(
            projectArtifactStore: ProjectArtifactStore(),
            temporaryVideoAudioCacheRoot: mediaCacheRoot
        )
        let result = ProjectSaveArtifactsResult(
            importedFile: ImportedAudioFile(url: persistedAudioURL, displayName: "persisted.m4a", duration: 1),
            temporaryVideoAudioURLToRemove: linkedAudioURL
        )

        await coordinator.finalizeSavedArtifacts(result)

        XCTAssertTrue(FileManager.default.fileExists(atPath: externalAudioURL.path))
    }

}

private extension ProjectPersistenceCoordinatorArtifactTests {
    func makeProjectPersistenceCoordinator(
        projectArtifactStore: ProjectArtifactStore,
        temporaryVideoAudioCacheRoot: URL? = nil,
        importFileFromURL: ((URL) async throws -> ImportedAudioFile)? = nil,
        decodedDuration: @escaping (URL) throws -> TimeInterval = { _ in 1 }
    ) throws -> ProjectPersistenceCoordinator {
        ProjectPersistenceCoordinator(
            projectArtifactStore: projectArtifactStore,
            projectDocumentService: ProjectDocumentService(),
            peakformProvider: MockPeakformProvider(),
            stemSeparationService: StemSeparationService(
                appSettingsStore: JammLab.AppSettingsStore(defaults: try temporaryUserDefaults()),
                applicationSupportDirectory: temporaryDirectory()
            ),
            temporaryVideoAudioCacheRoot: temporaryVideoAudioCacheRoot,
            importFileFromURL: importFileFromURL,
            decodedDuration: decodedDuration
        )
    }
}
