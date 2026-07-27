import AVFAudio
import Foundation
import XCTest
@testable import JammLab

@MainActor
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

    func testSynthesizedDefaultRestsDoNotTriggerOverwriteWarning() throws {
        let stemURL = try makeTemporaryStemFile()
        defer { try? FileManager.default.removeItem(at: stemURL) }
        let viewModel = makeViewModel(stemURL: stemURL, service: StubStemTranscriptionService(result: rawResult))
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "default-rest",
                partID: .stem(.bass),
                kind: .rest,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 4,
                displayDuration: NotationDuration(denominator: 4),
                isSynthesized: true
            )
        ]

        XCTAssertFalse(viewModel.hasMeaningfulStemNotationContent(for: .bass))
    }

    func testServiceRejectsDrumStemBeforeReadingAudio() async {
        do {
            _ = try await StemTranscriptionService().transcribe(
                stemType: .drums,
                stemURL: URL(fileURLWithPath: "/missing.wav"),
                configuration: .neuralNoteDefaults,
                operation: StemTranscriptionOperation(),
                progress: { _, _ in }
            )
            XCTFail("Expected Drum Stem transcription to be rejected")
        } catch let error as StemTranscriptionError {
            XCTAssertEqual(error, .unsupportedStemType)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAudioPreparationDownmixesStereoAndReportsResampledProgress() throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcription-stereo-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 44_100,
                channels: 2,
                interleaved: false
            )
        )
        do {
            let file = try AVAudioFile(forWriting: sourceURL, settings: format.settings)
            let buffer = try XCTUnwrap(
                AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410)
            )
            buffer.frameLength = buffer.frameCapacity
            let channels = try XCTUnwrap(buffer.floatChannelData)
            for index in 0..<Int(buffer.frameLength) {
                channels[0][index] = 0.5
                channels[1][index] = -0.5
            }
            try file.write(from: buffer)
        }

        var progressValues: [Double] = []
        let prepared = try StemTranscriptionService().prepareAudio(
            at: sourceURL,
            operation: StemTranscriptionOperation(),
            progress: { progressValues.append($0) }
        )
        defer { prepared.cleanup() }
        let data = try Data(contentsOf: prepared.url)
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }

        XCTAssertLessThanOrEqual(abs(prepared.sampleCount - 2_205), 1)
        XCTAssertEqual(samples.count, prepared.sampleCount)
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
        XCTAssertLessThan(samples.map { abs($0) }.max() ?? 1, 0.000_1)
        XCTAssertEqual(progressValues.last, 1)
        XCTAssertEqual(progressValues, progressValues.sorted())
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.temporaryDirectory.path))
        prepared.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.temporaryDirectory.path))
    }

    func testBridgeMapsPreCancelledOperationToTypedErrorWithoutProgress() {
        let bridge = JMBasicPitchBridge()
        let token = JMTranscriptionCancellationToken()
        token.cancel()
        var progressValues: [Double] = []

        XCTAssertThrowsError(
            try bridge.transcribePCMFile(
                at: URL(fileURLWithPath: "/missing.f32"),
                sampleCount: 1,
                sampleRate: StemTranscriptionService.modelSampleRate,
                configuration: JMTranscriptionConfiguration(),
                cancellationToken: token,
                progress: { progressValues.append($0) }
            )
        ) { error in
            let error = error as NSError
            XCTAssertEqual(error.domain, JMTranscriptionErrorDomain)
            XCTAssertEqual(error.code, 8)
        }
        XCTAssertTrue(progressValues.isEmpty)
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

    func testNotationMappingAppliesCommonPracticeAccidentalsInChronologicalOrder() throws {
        let rawNotes = [
            transcriptionNote(midiPitch: 66, startTime: 0.75, pitchBends: [2]),
            transcriptionNote(midiPitch: 66, startTime: 0),
            transcriptionNote(midiPitch: 65, startTime: 0.5),
            transcriptionNote(midiPitch: 65, startTime: 0.25)
        ]

        let output = try mapNotation(notes: rawNotes, keyName: "G major")

        XCTAssertNil(
            try rootNotationItem(atRawStartTime: 0, in: output).explicitAccidental
        )
        XCTAssertEqual(
            try rootNotationItem(atRawStartTime: 0.25, in: output).explicitAccidental,
            .natural
        )
        XCTAssertNil(
            try rootNotationItem(atRawStartTime: 0.5, in: output).explicitAccidental
        )
        XCTAssertEqual(
            try rootNotationItem(atRawStartTime: 0.75, in: output).explicitAccidental,
            .sharp
        )
        XCTAssertEqual(
            output.track.notes.map(\.rawStartTimeSeconds),
            rawNotes.map(\.startTimeSeconds)
        )
        XCTAssertEqual(output.track.notes.first?.pitchBends, [2])
        for note in output.track.notes {
            let root = try rootNotationItem(for: note, in: output)
            XCTAssertEqual(root.pitch?.midiNoteNumber, note.midiPitch)
        }
    }

    func testNotationMappingHandlesFlatKeysAndKeepsOctavesIndependent() throws {
        let output = try mapNotation(
            notes: [
                transcriptionNote(midiPitch: 70, startTime: 0),
                transcriptionNote(midiPitch: 63, startTime: 0.25),
                transcriptionNote(midiPitch: 76, startTime: 0.5),
                transcriptionNote(midiPitch: 64, startTime: 0.75),
                transcriptionNote(midiPitch: 71, startTime: 1),
                transcriptionNote(midiPitch: 70, startTime: 1.25)
            ],
            keyName: "F major"
        )

        XCTAssertNil(
            try rootNotationItem(atRawStartTime: 0, in: output).explicitAccidental
        )
        XCTAssertEqual(
            try rootNotationItem(atRawStartTime: 0.25, in: output).explicitAccidental,
            .flat
        )
        XCTAssertNil(
            try rootNotationItem(atRawStartTime: 0.5, in: output).explicitAccidental
        )
        XCTAssertEqual(
            try rootNotationItem(atRawStartTime: 0.75, in: output).explicitAccidental,
            .natural
        )
        XCTAssertEqual(
            try rootNotationItem(atRawStartTime: 1, in: output).explicitAccidental,
            .natural
        )
        XCTAssertEqual(
            try rootNotationItem(atRawStartTime: 1.25, in: output).explicitAccidental,
            .flat
        )
    }

    func testNotationMappingResetsAccidentalsAtBarlineWithoutSeedingFromTieContinuation() throws {
        let output = try mapNotation(
            notes: [
                transcriptionNote(midiPitch: 61, startTime: 1.75, duration: 0.5),
                transcriptionNote(midiPitch: 61, startTime: 2.5),
                transcriptionNote(midiPitch: 61, startTime: 2.75)
            ],
            keyName: "C major",
            projectDuration: 4
        )
        let tiedNote = output.track.notes[0]

        XCTAssertEqual(tiedNote.notationItemIDs.count, 2)
        XCTAssertEqual(
            try notationItem(id: tiedNote.notationItemIDs[0], in: output).explicitAccidental,
            .sharp
        )
        XCTAssertNil(
            try notationItem(id: tiedNote.notationItemIDs[1], in: output).explicitAccidental
        )
        XCTAssertEqual(
            try rootNotationItem(atRawStartTime: 2.5, in: output).explicitAccidental,
            .sharp
        )
        XCTAssertNil(
            try rootNotationItem(atRawStartTime: 2.75, in: output).explicitAccidental
        )
    }

    func testNotationMappingShowsAllConflictingAccidentalsAtSameOnset() throws {
        for conflictingMIDIPitches in [[65, 66], [66, 65]] {
            let output = try mapNotation(
                notes: [
                    transcriptionNote(midiPitch: 65, startTime: 0),
                    transcriptionNote(midiPitch: conflictingMIDIPitches[0], startTime: 0.25),
                    transcriptionNote(midiPitch: conflictingMIDIPitches[1], startTime: 0.25),
                    transcriptionNote(midiPitch: 65, startTime: 0.5)
                ],
                keyName: "G major"
            )
            let sameOnsetNotes = output.track.notes.filter { $0.rawStartTimeSeconds == 0.25 }
            let sameOnsetAccidentals = try sameOnsetNotes.map {
                try rootNotationItem(for: $0, in: output).explicitAccidental
            }

            XCTAssertEqual(
                try rootNotationItem(atRawStartTime: 0, in: output).explicitAccidental,
                .natural
            )
            let renderedAccidentals = sameOnsetAccidentals.compactMap { $0 }
            XCTAssertEqual(renderedAccidentals.count, 2)
            XCTAssertTrue(renderedAccidentals.contains(.natural))
            XCTAssertTrue(renderedAccidentals.contains(.sharp))
            XCTAssertNil(
                try rootNotationItem(atRawStartTime: 0.5, in: output).explicitAccidental
            )
        }
    }

    func testNotationMappingAppliesSourceTrimAndProjectRateWithoutChangingRawTimes() throws {
        let result = RawStemTranscriptionResult(
            notes: [
                RawStemTranscriptionNote(
                    midiPitch: 62,
                    startTimeSeconds: 3,
                    endTimeSeconds: 4,
                    confidence: 0.8,
                    pitchBends: []
                )
            ],
            timings: timings,
            warnings: []
        )
        let output = try StemTranscriptionNotationMapper.map(
            result: result,
            stemType: .guitar,
            sourceFingerprint: fingerprint,
            timelineMapping: StemTimelineMapping(
                sourceStartTime: 2,
                sourceDuration: 4,
                projectStartTime: 1,
                projectDuration: 2
            ),
            configuration: .neuralNoteDefaults,
            tempoMap: TempoMap(
                baseSettings: BeatGridSettings(bpm: 120),
                markers: [],
                duration: 4
            ),
            projectDuration: 4,
            keyName: nil
        )

        let note = try XCTUnwrap(output.track.notes.first)
        XCTAssertEqual(note.rawStartTimeSeconds, 3)
        XCTAssertEqual(note.rawEndTimeSeconds, 4)
        XCTAssertEqual(note.projectStartTimeSeconds, 1.5, accuracy: 0.000_001)
        XCTAssertEqual(note.projectEndTimeSeconds, 2, accuracy: 0.000_001)
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

    func testLegacyTranscriptionTrackDefaultsToStemNotationPart() throws {
        let track = StemTranscriptionTrack(
            stemType: .bass,
            sourceFingerprint: fingerprint,
            configuration: .neuralNoteDefaults,
            notes: []
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(track)) as? [String: Any]
        )
        object.removeValue(forKey: "notationPartID")

        let decoded = try JSONDecoder().decode(
            StemTranscriptionTrack.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.notationPartID, .stem(.bass))
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

        XCTAssertEqual(decoded.formatVersion, 16)
        XCTAssertEqual(decoded.stemTranscriptionTracks, [track])
    }

    func testProjectNormalizerClampsMetadataAndRemovesDanglingNotationLinks() {
        let item = makeNotationItem(id: "linked", partID: .stem(.bass))
        let track = StemTranscriptionTrack(
            stemType: .bass,
            sourceFingerprint: fingerprint,
            configuration: .neuralNoteDefaults,
            notes: [
                StemTranscriptionNote(
                    midiPitch: 40,
                    rawStartTimeSeconds: 0,
                    rawEndTimeSeconds: 8,
                    projectStartTimeSeconds: -1,
                    projectEndTimeSeconds: 8,
                    confidence: 1.5,
                    notationItemIDs: ["linked", "missing"]
                ),
                StemTranscriptionNote(
                    midiPitch: 200,
                    rawStartTimeSeconds: 0,
                    rawEndTimeSeconds: 1,
                    projectStartTimeSeconds: 0,
                    projectEndTimeSeconds: 1,
                    confidence: 1
                )
            ]
        )

        let normalized = ProjectStateNormalizer.normalizedStemTranscriptionTracks(
            [track],
            duration: 4,
            notationItems: [item]
        )

        XCTAssertEqual(normalized.count, 1)
        XCTAssertEqual(normalized[0].notes.count, 1)
        XCTAssertEqual(normalized[0].notes[0].projectStartTimeSeconds, 0)
        XCTAssertEqual(normalized[0].notes[0].projectEndTimeSeconds, 4)
        XCTAssertEqual(normalized[0].notes[0].confidence, 1)
        XCTAssertEqual(normalized[0].notes[0].notationItemIDs, ["linked"])
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

    func testViewModelSuccessfulTranscriptionCommitsAtomicallyAndMarksProjectDirty() async throws {
        let stemURL = try makeTemporaryStemFile()
        defer { try? FileManager.default.removeItem(at: stemURL) }
        let service = StubStemTranscriptionService(result: rawResult)
        let viewModel = makeViewModel(stemURL: stemURL, service: service)

        viewModel.transcribeStem(.bass)
        await waitUntil { viewModel.stemTranscriptionState(for: .bass).phase == .completed }

        XCTAssertEqual(viewModel.stemTranscriptionTracks.count, 1)
        XCTAssertFalse(viewModel.notationItems.isEmpty)
        XCTAssertEqual(viewModel.stemTranscriptionTracks[0].notationPartID, .stem(.bass))
        XCTAssertTrue(viewModel.visibleNotationPartIDs.contains(.stem(.bass)))
        XCTAssertTrue(viewModel.isProjectModified)
    }

    func testViewModelWarnsBeforeOverwritingMeaningfulStemContentAndCancelPreservesIt() async throws {
        let stemURL = try makeTemporaryStemFile()
        defer { try? FileManager.default.removeItem(at: stemURL) }
        let service = StubStemTranscriptionService(result: rawResult)
        let viewModel = makeViewModel(stemURL: stemURL, service: service)
        let existingItem = makeNotationItem(id: "existing-generated", partID: .stem(.bass))
        viewModel.notationItems = [existingItem]

        viewModel.transcribeStem(.bass)

        XCTAssertEqual(viewModel.pendingStemTranscriptionOverwrite?.stemType, .bass)
        XCTAssertFalse(service.hasStarted)
        viewModel.cancelPendingStemTranscriptionOverwrite()
        XCTAssertNil(viewModel.pendingStemTranscriptionOverwrite)
        XCTAssertEqual(viewModel.notationItems, [existingItem])
    }

    func testViewModelConfirmedOverwriteRemovesAllStemInformationIncludingLegacyParts() async throws {
        let stemURL = try makeTemporaryStemFile()
        defer { try? FileManager.default.removeItem(at: stemURL) }
        let service = StubStemTranscriptionService(result: rawResult)
        let viewModel = makeViewModel(stemURL: stemURL, service: service)
        let generated = makeNotationItem(id: "old-generated", partID: .stem(.bass))
        let manual = makeNotationItem(id: "manual-note", partID: .stem(.bass))
        let legacyPart = NotationPartID.stemTranscription(.bass, trackID: UUID())
        let legacyItem = makeNotationItem(id: "legacy-note", partID: legacyPart)
        viewModel.notationItems = [generated, manual, legacyItem]
        viewModel.visibleNotationPartIDs.insert(legacyPart)
        viewModel.stemTranscriptionTracks = [
            StemTranscriptionTrack(
                stemType: .bass,
                notationPartID: legacyPart,
                sourceFingerprint: try StemSeparationService().sourceFingerprint(for: stemURL),
                configuration: .neuralNoteDefaults,
                notes: [
                    StemTranscriptionNote(
                        midiPitch: 48,
                        rawStartTimeSeconds: 0,
                        rawEndTimeSeconds: 0.5,
                        projectStartTimeSeconds: 0,
                        projectEndTimeSeconds: 0.5,
                        confidence: 0.8,
                        notationItemIDs: [generated.id]
                    )
                ]
            )
        ]

        var customConfiguration = StemTranscriptionConfiguration.neuralNoteDefaults
        customConfiguration.noteSensitivity = 0.42
        viewModel.transcribeStem(.bass, configuration: customConfiguration)
        XCTAssertEqual(viewModel.pendingStemTranscriptionOverwrite?.stemType, .bass)
        viewModel.confirmPendingStemTranscriptionOverwrite()
        await waitUntil { viewModel.stemTranscriptionState(for: .bass).phase == .completed }

        XCTAssertEqual(viewModel.stemTranscriptionTracks.count, 1)
        XCTAssertEqual(viewModel.stemTranscriptionTracks[0].notationPartID, .stem(.bass))
        XCTAssertFalse(viewModel.notationItems.contains { $0.id == generated.id })
        XCTAssertFalse(viewModel.notationItems.contains { $0.id == manual.id })
        XCTAssertFalse(viewModel.notationItems.contains { $0.id == legacyItem.id })
        XCTAssertTrue(viewModel.notationItems.allSatisfy { $0.partID == .stem(.bass) })
        XCTAssertFalse(viewModel.visibleNotationPartIDs.contains(legacyPart))
        XCTAssertEqual(service.configuration?.noteSensitivity ?? -1, 0.42, accuracy: 0.000_001)
    }

    func testViewModelDoesNotOfferBasicPitchForDrumStem() throws {
        let stemURL = try makeTemporaryStemFile()
        defer { try? FileManager.default.removeItem(at: stemURL) }
        let service = StubStemTranscriptionService(result: rawResult)
        let viewModel = makeViewModel(stemURL: stemURL, service: service)
        viewModel.stemFiles = [StemFile(type: .drums, url: stemURL, displayName: "Drums")]

        viewModel.transcribeStem(.drums)

        XCTAssertFalse(service.hasStarted)
        XCTAssertNil(viewModel.pendingStemTranscriptionOverwrite)
        XCTAssertTrue(viewModel.stemTranscriptionTracks.isEmpty)
    }

    func testViewModelCancellationDoesNotMutateProject() async throws {
        let stemURL = try makeTemporaryStemFile()
        defer { try? FileManager.default.removeItem(at: stemURL) }
        let service = StubStemTranscriptionService(result: rawResult, waitsForRelease: true)
        let viewModel = makeViewModel(stemURL: stemURL, service: service)

        viewModel.transcribeStem(.bass)
        await waitUntil { service.hasStarted }
        viewModel.cancelStemTranscription(.bass)
        service.release()
        await waitUntil { viewModel.stemTranscriptionState(for: .bass).phase == .cancelled }

        XCTAssertTrue(viewModel.stemTranscriptionTracks.isEmpty)
        XCTAssertTrue(viewModel.notationItems.isEmpty)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    func testViewModelRejectsResultAfterStemRemoval() async throws {
        let stemURL = try makeTemporaryStemFile()
        defer { try? FileManager.default.removeItem(at: stemURL) }
        let service = StubStemTranscriptionService(result: rawResult, waitsForRelease: true)
        let viewModel = makeViewModel(stemURL: stemURL, service: service)

        viewModel.transcribeStem(.bass)
        await waitUntil { service.hasStarted }
        viewModel.stemFiles = []
        service.release()
        await waitUntil { viewModel.stemTranscriptionState(for: .bass).phase == .failed }

        XCTAssertTrue(viewModel.stemTranscriptionTracks.isEmpty)
        XCTAssertTrue(viewModel.notationItems.isEmpty)
        XCTAssertEqual(
            viewModel.errorMessage,
            StemTranscriptionError.sourceStemChanged.localizedDescription
        )
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

    private var rawResult: RawStemTranscriptionResult {
        RawStemTranscriptionResult(
            notes: [
                RawStemTranscriptionNote(
                    midiPitch: 48,
                    startTimeSeconds: 0.2,
                    endTimeSeconds: 0.8,
                    confidence: 0.9,
                    pitchBends: []
                )
            ],
            timings: timings,
            warnings: []
        )
    }

    private func makeViewModel(
        stemURL: URL,
        service: StubStemTranscriptionService
    ) -> AudioPlayerViewModel {
        let viewModel = AudioPlayerViewModel(
            playbackEngine: MockPlaybackEngine(),
            stemTranscriptionService: service
        )
        viewModel.duration = 4
        viewModel.importedFile = ImportedAudioFile(
            url: stemURL,
            displayName: "Source",
            duration: 4
        )
        viewModel.stemFiles = [
            StemFile(type: .bass, url: stemURL, displayName: "Bass")
        ]
        viewModel.markProjectClean()
        return viewModel
    }

    private func makeTemporaryStemFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stem-transcription-\(UUID().uuidString).wav")
        try Data("test-stem".utf8).write(to: url)
        return url
    }

    private func makeNotationItem(id: String, partID: NotationPartID) -> NotationMeasureItem {
        NotationMeasureItem(
            id: id,
            partID: partID,
            kind: .note,
            pitch: NotationPitch(step: .c, octave: 3),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
    }

    private func transcriptionNote(
        midiPitch: Int,
        startTime: TimeInterval,
        duration: TimeInterval = 0.1,
        confidence: Double = 0.9,
        pitchBends: [Int] = []
    ) -> RawStemTranscriptionNote {
        RawStemTranscriptionNote(
            midiPitch: midiPitch,
            startTimeSeconds: startTime,
            endTimeSeconds: startTime + duration,
            confidence: confidence,
            pitchBends: pitchBends
        )
    }

    private func mapNotation(
        notes: [RawStemTranscriptionNote],
        keyName: String,
        projectDuration: TimeInterval = 4
    ) throws -> StemTranscriptionNotationOutput {
        try StemTranscriptionNotationMapper.map(
            result: RawStemTranscriptionResult(
                notes: notes,
                timings: timings,
                warnings: []
            ),
            stemType: .piano,
            sourceFingerprint: fingerprint,
            timelineMapping: .aligned(duration: projectDuration),
            configuration: .neuralNoteDefaults,
            tempoMap: TempoMap(
                baseSettings: BeatGridSettings(
                    bpm: 120,
                    timeSignature: .fourFour
                ),
                markers: [],
                duration: projectDuration
            ),
            projectDuration: projectDuration,
            keyName: keyName
        )
    }

    private func rootNotationItem(
        atRawStartTime rawStartTime: TimeInterval,
        in output: StemTranscriptionNotationOutput
    ) throws -> NotationMeasureItem {
        let storedNote = try XCTUnwrap(
            output.track.notes.first {
                abs($0.rawStartTimeSeconds - rawStartTime)
                    < NotationMeasureTiming.timelineTolerance
            }
        )
        return try rootNotationItem(for: storedNote, in: output)
    }

    private func rootNotationItem(
        for storedNote: StemTranscriptionNote,
        in output: StemTranscriptionNotationOutput
    ) throws -> NotationMeasureItem {
        try notationItem(
            id: XCTUnwrap(storedNote.notationItemIDs.first),
            in: output
        )
    }

    private func notationItem(
        id: String,
        in output: StemTranscriptionNotationOutput
    ) throws -> NotationMeasureItem {
        try XCTUnwrap(output.notationItems.first { $0.id == id })
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<2_000 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for transcription state", file: file, line: line)
    }
}

private final class StubStemTranscriptionService: StemTranscribing, @unchecked Sendable {
    private let lock = NSLock()
    private let result: RawStemTranscriptionResult
    private let waitsForRelease: Bool
    private var started = false
    private var released = false
    private var capturedConfiguration: StemTranscriptionConfiguration?

    init(result: RawStemTranscriptionResult, waitsForRelease: Bool = false) {
        self.result = result
        self.waitsForRelease = waitsForRelease
    }

    var hasStarted: Bool {
        lock.withLock { started }
    }

    var configuration: StemTranscriptionConfiguration? {
        lock.withLock { capturedConfiguration }
    }

    func release() {
        lock.withLock { released = true }
    }

    func transcribe(
        stemType: StemType,
        stemURL: URL,
        configuration: StemTranscriptionConfiguration,
        operation: StemTranscriptionOperation,
        progress: @escaping @Sendable (StemTranscriptionPhase, Double) -> Void
    ) async throws -> RawStemTranscriptionResult {
        lock.withLock {
            started = true
            capturedConfiguration = configuration
        }
        progress(.preparingAudio, 0.5)
        while waitsForRelease && !lock.withLock({ released }) {
            if operation.isCancelled {
                throw StemTranscriptionError.cancelled
            }
            await Task.yield()
        }
        guard !operation.isCancelled else { throw StemTranscriptionError.cancelled }
        progress(.loadingModel, 0)
        progress(.transcribing, 0.5)
        progress(.processingNotes, 1)
        return result
    }
}
