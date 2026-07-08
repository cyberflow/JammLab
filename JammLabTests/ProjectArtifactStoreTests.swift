import XCTest
@testable import JammLab

final class ProjectArtifactStoreTests: XCTestCase {
    func testProjectArtifactStoreRoundTripsStemMetadataAndFiles() throws {
        let directory = temporaryDirectory()
        let sourceDirectory = directory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceFingerprint = StemSourceFingerprint(path: "/tmp/song.mp3", fileSize: 42, modificationTime: 123)
        let metadata = StemCacheMetadata(
            cacheKey: "cache-key",
            sourceFingerprint: sourceFingerprint,
            backendIdentifier: "JammLabSeparatorHelper/test",
            separationMethodID: StemSeparationMethod.fourStem.id,
            modelName: StemSeparationMethod.fourStem.modelName,
            settingsVersion: 2,
            createdAt: Date(timeIntervalSince1970: 100),
            stems: try StemSeparationMethod.fourStem.stemTypes.map { type in
                let url = try temporaryFile(in: sourceDirectory, name: "\(type.rawValue)-source.wav", contents: type.rawValue)
                return StemFile(type: type, url: url, displayName: type.title)
            }
        )
        let projectURL = directory.appendingPathComponent("Song.jammlab")
        let store = ProjectArtifactStore()

        let localMetadata = try store.writeStemMetadata(metadata, projectURL: projectURL)
        let restored = try XCTUnwrap(store.readStemMetadata(
            projectURL: projectURL,
            expectedFingerprint: sourceFingerprint
        ))

        XCTAssertEqual(localMetadata.cacheKey, metadata.cacheKey)
        XCTAssertEqual(restored.cacheKey, metadata.cacheKey)
        XCTAssertEqual(restored.sourceFingerprint, sourceFingerprint)
        XCTAssertEqual(restored.separationMethodID, StemSeparationMethod.fourStem.id)
        XCTAssertEqual(Set(restored.stems.map(\.type)), Set(StemSeparationMethod.fourStem.stemTypes))
        for stem in restored.stems {
            XCTAssertEqual(stem.url.deletingLastPathComponent(), store.stemsDirectory(for: projectURL))
            XCTAssertEqual(stem.url.lastPathComponent, stem.type.canonicalStemFilename)
            XCTAssertEqual(try String(contentsOf: stem.url, encoding: .utf8), stem.type.rawValue)
        }
    }

    func testProjectArtifactStoreRoundTripsVocalInstrumentalStemMetadataAndFiles() throws {
        let directory = temporaryDirectory()
        let sourceDirectory = directory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceFingerprint = StemSourceFingerprint(path: "/tmp/song.mp3", fileSize: 42, modificationTime: 123)
        let metadata = StemCacheMetadata(
            cacheKey: "cache-key-2",
            sourceFingerprint: sourceFingerprint,
            backendIdentifier: "JammLabSeparatorHelper/test",
            separationMethodID: StemSeparationMethod.vocalInstrumental.id,
            modelName: StemSeparationMethod.vocalInstrumental.modelName,
            settingsVersion: 2,
            createdAt: Date(timeIntervalSince1970: 100),
            stems: try StemSeparationMethod.vocalInstrumental.stemTypes.map { type in
                let url = try temporaryFile(in: sourceDirectory, name: "\(type.rawValue)-source.wav", contents: type.rawValue)
                return StemFile(type: type, url: url, displayName: type.title)
            }
        )
        let projectURL = directory.appendingPathComponent("Song.jammlab")
        let store = ProjectArtifactStore()

        _ = try store.writeStemMetadata(metadata, projectURL: projectURL)
        let restored = try XCTUnwrap(store.readStemMetadata(
            projectURL: projectURL,
            expectedFingerprint: sourceFingerprint
        ))

        XCTAssertEqual(restored.separationMethodID, StemSeparationMethod.vocalInstrumental.id)
        XCTAssertEqual(restored.stems.map(\.type), [.vocals, .instrumental])
        XCTAssertEqual(restored.stems.map(\.displayName), ["Vocals", "Instrumental"])
    }

    func testProjectArtifactStoreRoundTripsSixStemMetadataAndFiles() throws {
        let directory = temporaryDirectory()
        let sourceDirectory = directory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceFingerprint = StemSourceFingerprint(path: "/tmp/song.mp3", fileSize: 42, modificationTime: 123)
        let metadata = StemCacheMetadata(
            cacheKey: "cache-key-6",
            sourceFingerprint: sourceFingerprint,
            backendIdentifier: "JammLabSeparatorHelper/test",
            separationMethodID: StemSeparationMethod.sixStem.id,
            modelName: StemSeparationMethod.sixStem.modelName,
            settingsVersion: 2,
            createdAt: Date(timeIntervalSince1970: 100),
            stems: try StemSeparationMethod.sixStem.stemTypes.map { type in
                let url = try temporaryFile(in: sourceDirectory, name: "\(type.rawValue)-source.wav", contents: type.rawValue)
                return StemFile(type: type, url: url, displayName: type.title)
            }
        )
        let projectURL = directory.appendingPathComponent("Song.jammlab")
        let store = ProjectArtifactStore()

        _ = try store.writeStemMetadata(metadata, projectURL: projectURL)
        let restored = try XCTUnwrap(store.readStemMetadata(
            projectURL: projectURL,
            expectedFingerprint: sourceFingerprint
        ))

        XCTAssertEqual(restored.separationMethodID, StemSeparationMethod.sixStem.id)
        XCTAssertEqual(restored.modelName, StemSeparationMethod.sixStem.modelName)
        XCTAssertEqual(restored.stems.map(\.type), StemSeparationMethod.sixStem.stemTypes)
        XCTAssertEqual(restored.stems.map(\.displayName), StemSeparationMethod.sixStem.stemTypes.map(\.title))
        for stem in restored.stems {
            XCTAssertEqual(stem.url.lastPathComponent, stem.type.canonicalStemFilename)
            XCTAssertEqual(try String(contentsOf: stem.url, encoding: .utf8), stem.type.rawValue)
        }
    }

    func testProjectArtifactStorePersistsVideoAudioBesideProject() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let extractedAudioURL = try temporaryFile(in: directory, name: "cached-audio.m4a", contents: "audio")
        let videoURL = directory.appendingPathComponent("lesson.mp4")
        let file = ImportedAudioFile(
            url: extractedAudioURL,
            sourceMediaURL: videoURL,
            displayName: "lesson.mp4",
            duration: 12,
            mediaKind: .video
        )
        let projectURL = directory.appendingPathComponent("Song.jammlab")
        let store = ProjectArtifactStore()

        let persisted = try store.persistVideoAudioIfNeeded(file, projectURL: projectURL)

        XCTAssertEqual(persisted.url, store.videoAudioURL(for: projectURL))
        XCTAssertEqual(persisted.sourceMediaURL, videoURL)
        XCTAssertEqual(persisted.mediaKind, .video)
        XCTAssertEqual(try String(contentsOf: persisted.url, encoding: .utf8), "audio")
        XCTAssertEqual(store.existingVideoAudioURL(for: projectURL), persisted.url)
    }

}
