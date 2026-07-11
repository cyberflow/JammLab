import XCTest
@testable import JammLab

final class StemWorkflowPersistenceTests: XCTestCase {
    func testProjectVersionSevenPersistsProjectEditablePlaybackStateMediaKindArtifactRootBookmarkAndVideoWindowState() throws {
        let artifactRootBookmarkData = Data("artifact-root-bookmark".utf8)
        let metadata = StemProjectState(
            cacheKey: "cache-123",
            sourceFingerprint: StemSourceFingerprint(path: "/tmp/song.mp3", fileSize: 42, modificationTime: 1234),
            backendIdentifier: "demucs:/opt/homebrew/bin/demucs",
            modelName: "htdemucs",
            settingsVersion: 1,
            playbackMode: .stems,
            mixState: StemMixState(items: [
                StemMixItem(type: .vocals, volume: 0, isMuted: true, isSoloed: false, isAvailable: true),
                StemMixItem(type: .drums, volume: 0.8, isMuted: false, isSoloed: true, isAvailable: true)
            ])
        )
        let project = JammLabProject(
            audioBookmarkData: Data("bookmark".utf8),
            artifactRootBookmarkData: artifactRootBookmarkData,
            audioDisplayName: "lesson.mp4",
            audioDuration: 120,
            mediaKind: .video,
            notes: [],
            loopStart: 0,
            loopEnd: 120,
            isLoopEnabled: true,
            playbackRate: 1,
            pitchShiftSemitones: 0,
            tempoBPM: 120,
            beatGridSettings: BeatGridSettings(bpm: 120, timeSignature: TimeSignature(beatsPerBar: 7, beatUnit: 4)),
            mainTrackVolume: 0.64,
            isClickEnabled: true,
            clickVolume: 0.42,
            isSnapEnabled: true,
            playbackMode: .stems,
            playbackMarkerTime: 12.5,
            stemState: metadata,
            isVideoWindowOpen: true,
            isNotationTrackCollapsed: false
        )

        let decoded = try JSONDecoder().decode(JammLabProject.self, from: JSONEncoder().encode(project))

        XCTAssertEqual(decoded.formatVersion, 11)
        XCTAssertEqual(decoded.artifactRootBookmarkData, artifactRootBookmarkData)
        XCTAssertEqual(decoded.mediaKind, .video)
        XCTAssertEqual(decoded.isLoopEnabled, true)
        XCTAssertEqual(decoded.mainTrackVolume, 0.64)
        XCTAssertEqual(decoded.beatGridSettings?.timeSignature, TimeSignature(beatsPerBar: 7, beatUnit: 4))
        XCTAssertEqual(decoded.isClickEnabled, true)
        XCTAssertEqual(decoded.clickVolume, 0.42)
        XCTAssertEqual(decoded.playbackMarkerTime, 12.5)
        XCTAssertEqual(decoded.isSnapEnabled, true)
        XCTAssertEqual(decoded.playbackMode, .stems)
        XCTAssertEqual(decoded.isVideoWindowOpen, true)
        XCTAssertEqual(decoded.isNotationTrackCollapsed, false)
        XCTAssertEqual(decoded.stemState?.cacheKey, "cache-123")
        XCTAssertEqual(decoded.stemState?.playbackMode, .stems)
        XCTAssertEqual(try XCTUnwrap(decoded.stemState?.mixState.effectiveVolume(for: .vocals)), 0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(decoded.stemState?.mixState.effectiveVolume(for: .drums)), 0.8, accuracy: 0.0001)
    }

    func testProjectVersionElevenPersistsPitchedNotationItems() throws {
        let pitch = NotationPitch(step: .f, octave: 4, alter: 1)
        let project = JammLabProject(
            audioBookmarkData: Data("bookmark".utf8),
            audioDisplayName: "lesson.mp3",
            audioDuration: 8,
            notes: [],
            notationItems: [
                NotationMeasureItem(
                    id: "note",
                    kind: .note,
                    pitch: pitch,
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4)
                ),
                NotationMeasureItem(
                    id: "rest",
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 1,
                    durationInQuarterNotes: 2,
                    displayDuration: NotationDuration(denominator: 2)
                )
            ],
            loopStart: 0,
            loopEnd: 8,
            playbackRate: 1,
            pitchShiftSemitones: 0
        )

        let decoded = try JSONDecoder().decode(JammLabProject.self, from: JSONEncoder().encode(project))

        XCTAssertEqual(decoded.formatVersion, 11)
        XCTAssertEqual(decoded.notationItems.map(\.id), ["note", "rest"])
        XCTAssertEqual(decoded.notationItems.map(\.kind), [.note, .rest])
        XCTAssertEqual(decoded.notationItems.map(\.pitch), [pitch, nil])
        XCTAssertEqual(decoded.notationItems.map(\.offsetInQuarterNotes), [0, 1])
        XCTAssertEqual(decoded.notationItems.map(\.durationInQuarterNotes), [1, 2])
        XCTAssertEqual(decoded.notationItems.map(\.displayDuration.denominator), [4, 2])
    }

    func testLegacyProjectWithoutStemStateStillDecodes() throws {
        let json = """
        {
          "formatVersion": 1,
          "audioBookmarkData": "Ym9va21hcms=",
          "audioDisplayName": "legacy.mp3",
          "audioDuration": 90,
          "notes": [],
          "loopStart": 0,
          "loopEnd": 90,
          "playbackRate": 1,
          "pitchShiftSemitones": 0,
          "tempoBPM": 120,
          "beatGridSettings": null
        }
        """

        let decoded = try JSONDecoder().decode(JammLabProject.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(decoded.audioDisplayName, "legacy.mp3")
        XCTAssertNil(decoded.artifactRootBookmarkData)
        XCTAssertNil(decoded.stemState)
        XCTAssertNil(decoded.mainTrackVolume)
        XCTAssertNil(decoded.isLoopEnabled)
        XCTAssertNil(decoded.isClickEnabled)
        XCTAssertNil(decoded.clickVolume)
        XCTAssertNil(decoded.isSnapEnabled)
        XCTAssertNil(decoded.playbackMode)
        XCTAssertNil(decoded.mediaKind)
        XCTAssertNil(decoded.isVideoWindowOpen)
        XCTAssertNil(decoded.isNotationTrackCollapsed)
    }
}
