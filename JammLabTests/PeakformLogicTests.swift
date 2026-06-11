import XCTest
@testable import JammLab

final class PeakformLogicTests: XCTestCase {
    func testPeakformDefaultLevels() {
        XCTAssertEqual(PeakformData.defaultSamplesPerPeakLevels, [128, 256, 512, 1_024, 2_048, 4_096])
        XCTAssertEqual(CachedPeakformProvider().samplesPerPeakLevels, PeakformData.defaultSamplesPerPeakLevels)
    }

    func testPeakformBinaryCacheRoundTripsV2Levels() throws {
        let cache = PeakformBinaryCache()
        let url = try temporaryFile(name: "roundtrip.peakform", contents: "")
        let peakform = PeakformData(
            duration: 12,
            sampleRate: 48_000,
            levels: [
                PeakformLevel(samplesPerPeak: 512, peaks: [
                    PeakPoint(min: -0.5, max: 0.7, rms: 0.2),
                    PeakPoint(min: -0.4, max: 0.6, rms: 0.3)
                ]),
                PeakformLevel(samplesPerPeak: 128, peaks: [
                    PeakPoint(min: -0.2, max: 0.3, rms: 0.1)
                ])
            ]
        )

        try cache.write(peakform, to: url)
        let restored = try cache.read(from: url)

        XCTAssertEqual(restored.duration, 12, accuracy: 0.0001)
        XCTAssertEqual(restored.sampleRate, 48_000, accuracy: 0.0001)
        XCTAssertEqual(restored.levels.map(\.samplesPerPeak), [128, 512])
        XCTAssertEqual(restored.level(samplesPerPeak: 128)?.peaks.count, 1)
        XCTAssertEqual(restored.level(samplesPerPeak: 512)?.peaks.count, 2)
        XCTAssertEqual(restored.level(samplesPerPeak: 512)?.peaks.first?.min, -0.5)
    }

    func testPeakformBinaryCacheRejectsV1Cache() throws {
        let cache = PeakformBinaryCache()
        let url = try temporaryFile(name: "legacy.peakform", contents: "")
        var data = Data()
        data.appendTestUInt32(0x5045_414B)
        data.appendTestUInt16(1)
        data.appendTestUInt16(0)
        data.append(contentsOf: repeatElement(UInt8(0), count: 64 - data.count))
        try data.write(to: url)

        XCTAssertThrowsError(try cache.read(from: url)) { error in
            XCTAssertEqual(error as? PeakformProviderError, .unsupportedCacheVersion)
        }
    }

    func testPeakformPreferredLevelFollowsZoomDensity() throws {
        let peakform = PeakformData(
            duration: 120,
            sampleRate: 44_100,
            levels: PeakformData.defaultSamplesPerPeakLevels.map {
                PeakformLevel(samplesPerPeak: $0, peaks: [PeakPoint(min: -0.1, max: 0.1, rms: 0.05)])
            }
        )

        let zoomedIn = try XCTUnwrap(peakform.preferredLevel(
            for: TimelineViewport(duration: 120, visibleRange: 0...1),
            width: 1_000
        ))
        let zoomedOut = try XCTUnwrap(peakform.preferredLevel(
            for: TimelineViewport(duration: 120, visibleRange: 0...120),
            width: 1_000
        ))

        XCTAssertEqual(zoomedIn.samplesPerPeak, 128)
        XCTAssertEqual(zoomedOut.samplesPerPeak, 4_096)
    }

    func testPeakformVisibleRangeUsesOnlyVisibleWindow() throws {
        let level = PeakformLevel(
            samplesPerPeak: 100,
            peaks: Array(repeating: PeakPoint(min: -0.1, max: 0.1, rms: 0.05), count: 100)
        )
        let range = try XCTUnwrap(PeakformRenderer.visiblePeakRange(
            level: level,
            sampleRate: 100,
            viewport: TimelineViewport(duration: 100, visibleRange: 10...20)
        ))

        XCTAssertEqual(range, 10..<20)
        XCTAssertLessThan(range.count, level.peaks.count)
    }

    func testPeakformAggregationPreservesExtremesAndMaxRMS() throws {
        let peaks = [
            PeakPoint(min: -0.1, max: 0.2, rms: 0.1),
            PeakPoint(min: -0.8, max: 0.4, rms: 0.3),
            PeakPoint(min: -0.2, max: 0.9, rms: 0.2)
        ]

        let aggregate = try XCTUnwrap(PeakformRenderer.aggregate(peaks: peaks, in: 0..<peaks.count))

        XCTAssertEqual(aggregate.min, -0.8)
        XCTAssertEqual(aggregate.max, 0.9)
        XCTAssertEqual(aggregate.rms, 0.3)
    }

    func testProjectArtifactStoreCreatesArtifactDirectories() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let projectURL = directory.appendingPathComponent("Song.jammlab")
        let store = ProjectArtifactStore()

        try store.ensureArtifactDirectories(for: projectURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.stemsDirectory(for: projectURL).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.peaksDirectory(for: projectURL).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.mediaDirectory(for: projectURL).path))
    }

    func testProjectArtifactStoreRoundTripsMainPeakform() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let projectURL = directory.appendingPathComponent("Song.jammlab")
        let store = ProjectArtifactStore()
        let peakform = PeakformData(
            duration: 3.5,
            sampleRate: 44_100,
            levels: [
                PeakformLevel(samplesPerPeak: 512, peaks: [
                    PeakPoint(min: -0.4, max: 0.7, rms: 0.2)
                ])
            ]
        )

        try store.writeMainPeakform(peakform, projectURL: projectURL)
        let restored = try XCTUnwrap(store.readMainPeakform(projectURL: projectURL))

        XCTAssertEqual(restored.duration, peakform.duration, accuracy: 0.0001)
        XCTAssertEqual(restored.sampleRate, peakform.sampleRate, accuracy: 0.0001)
        XCTAssertEqual(restored.levels, peakform.levels)
    }

}
