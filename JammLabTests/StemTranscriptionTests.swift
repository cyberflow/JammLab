import Foundation
import XCTest
@testable import JammLab

final class StemTranscriptionTests: XCTestCase {
    func testTimelineMappingSupportsTrimAndProjectRate() {
        let mapping = StemTimelineMapping(
            sourceStartTime: 2,
            sourceDuration: 8,
            projectStartTime: 10,
            projectDuration: 4
        )

        XCTAssertEqual(mapping.projectTime(forSourceTime: 2), 10, accuracy: 0.000_001)
        XCTAssertEqual(mapping.projectTime(forSourceTime: 6), 12, accuracy: 0.000_001)
        XCTAssertEqual(mapping.projectTime(forSourceTime: 10), 14, accuracy: 0.000_001)
    }

    func testNotationMappingPreservesRawTimesAndOverlappingPolyphony() throws {
        let configuration = StemTranscriptionConfiguration.neuralNoteDefaults
        let result = RawStemTranscriptionResult(
            notes: [
                RawStemTranscriptionNote(
                    midiPitch: 60,
                    startTimeSeconds: 0.12,
                    endTimeSeconds: 1.18,
                    confidence: 0.8,
                    pitchBends: []
                ),
                RawStemTranscriptionNote(
                    midiPitch: 64,
                    startTimeSeconds: 0.42,
                    endTimeSeconds: 1.48,
                    confidence: 0.9,
                    pitchBends: [0, 1]
                )
            ],
            timings: timings,
            warnings: []
        )
        let tempoMap = TempoMap(
            baseSettings: BeatGridSettings(bpm: 120),
            markers: [],
            duration: 4
        )

        let output = try StemTranscriptionNotationMapper.map(
            result: result,
            stemType: .piano,
            sourceFingerprint: fingerprint,
            timelineMapping: .aligned(duration: 4),
            configuration: configuration,
            tempoMap: tempoMap,
            projectDuration: 4,
            keyName: "C major"
        )

        XCTAssertEqual(output.track.notes.count, 2)
        XCTAssertEqual(output.track.notes[0].rawStartTimeSeconds, 0.12, accuracy: 0.000_001)
        XCTAssertEqual(output.track.notes[1].pitchBends, [0, 1])
        XCTAssertEqual(Set(output.notationItems.compactMap(\.pitch?.midiNoteNumber)), [60, 64])
        XCTAssertTrue(output.notationItems.allSatisfy { $0.partID == .stem(.piano) })
        XCTAssertLessThan(
            output.track.notes[1].projectStartTimeSeconds,
            output.track.notes[0].projectEndTimeSeconds
        )
    }

    func testNotationMappingSplitsAndTiesNoteAcrossMeasureBoundary() throws {
        let result = RawStemTranscriptionResult(
            notes: [
                RawStemTranscriptionNote(
                    midiPitch: 67,
                    startTimeSeconds: 1.8,
                    endTimeSeconds: 2.4,
                    confidence: 0.75,
                    pitchBends: []
                )
            ],
            timings: timings,
            warnings: []
        )
        let tempoMap = TempoMap(
            baseSettings: BeatGridSettings(bpm: 120, timeSignature: .fourFour),
            markers: [],
            duration: 5
        )

        let output = try StemTranscriptionNotationMapper.map(
            result: result,
            stemType: .guitar,
            sourceFingerprint: fingerprint,
            timelineMapping: .aligned(duration: 5),
            configuration: .neuralNoteDefaults,
            tempoMap: tempoMap,
            projectDuration: 5,
            keyName: nil
        )

        XCTAssertEqual(output.notationItems.count, 2)
        XCTAssertEqual(output.notationItems[0].tieTargetItemID, output.notationItems[1].id)
        XCTAssertNil(output.notationItems[1].tieTargetItemID)
    }

    func testTranscriptionTrackRoundTripsThroughJSON() throws {
        let track = StemTranscriptionTrack(
            stemType: .bass,
            sourceFingerprint: fingerprint,
            configuration: .neuralNoteDefaults,
            notes: [
                StemTranscriptionNote(
                    midiPitch: 40,
                    rawStartTimeSeconds: 0.1,
                    rawEndTimeSeconds: 0.9,
                    projectStartTimeSeconds: 1.1,
                    projectEndTimeSeconds: 1.9,
                    confidence: 0.88,
                    notationItemIDs: ["note-1"]
                )
            ],
            timings: timings
        )

        let data = try JSONEncoder().encode(track)
        let decoded = try JSONDecoder().decode(StemTranscriptionTrack.self, from: data)

        XCTAssertEqual(decoded, track)
    }

    func testProjectPersistsTranscriptionTrackWithRawNoteMetadata() throws {
        let track = StemTranscriptionTrack(
            stemType: .vocals,
            sourceFingerprint: fingerprint,
            configuration: .neuralNoteDefaults,
            notes: [
                StemTranscriptionNote(
                    midiPitch: 72,
                    rawStartTimeSeconds: 0.13,
                    rawEndTimeSeconds: 0.81,
                    projectStartTimeSeconds: 1.13,
                    projectEndTimeSeconds: 1.81,
                    confidence: 0.91,
                    notationItemIDs: ["transcribed-note"]
                )
            ]
        )
        let project = JammLabProject(
            audioBookmarkData: Data("bookmark".utf8),
            audioDisplayName: "song.wav",
            audioDuration: 8,
            notes: [],
            stemTranscriptionTracks: [track],
            loopStart: 0,
            loopEnd: 8,
            playbackRate: 1,
            pitchShiftSemitones: 0
        )

        let decoded = try JSONDecoder().decode(
            JammLabProject.self,
            from: JSONEncoder().encode(project)
        )

        XCTAssertEqual(decoded.formatVersion, 15)
        XCTAssertEqual(decoded.stemTranscriptionTracks, [track])
    }

    func testMIDIExporterWritesStandardHeaderAndPolyphonicEvents() {
        let track = StemTranscriptionTrack(
            stemType: .piano,
            sourceFingerprint: fingerprint,
            configuration: .neuralNoteDefaults,
            notes: [
                StemTranscriptionNote(
                    midiPitch: 60,
                    rawStartTimeSeconds: 0,
                    rawEndTimeSeconds: 1,
                    projectStartTimeSeconds: 0,
                    projectEndTimeSeconds: 1,
                    confidence: 1
                ),
                StemTranscriptionNote(
                    midiPitch: 64,
                    rawStartTimeSeconds: 0,
                    rawEndTimeSeconds: 1,
                    projectStartTimeSeconds: 0,
                    projectEndTimeSeconds: 1,
                    confidence: 0.5
                )
            ]
        )

        let data = StemTranscriptionMIDIExporter.data(for: track, tempoBPM: 120)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "MThd")
        XCTAssertNotNil(data.range(of: Data("MTrk".utf8)))
        XCTAssertGreaterThan(data.count, 30)
    }

    private var fingerprint: StemSourceFingerprint {
        StemSourceFingerprint(path: "/tmp/test.wav", fileSize: 123, modificationTime: 456)
    }

    private var timings: StemTranscriptionTimings {
        StemTranscriptionTimings(
            audioPreparationSeconds: 0.1,
            modelLoadSeconds: 0.2,
            inferenceSeconds: 0.3,
            postProcessingSeconds: 0.1,
            totalSeconds: 0.7,
            processedDurationSeconds: 4
        )
    }
}
