import CoreGraphics
import XCTest
@testable import JammLab

final class HarmonyTrackLogicTests: XCTestCase {
    func testHarmonyEventCodablePreservesRawSupportedSymbols() throws {
        let symbols = ["C", "Cm", "C7", "Cmaj7", "Ab", "F#m7b5", "Bb13", "C/E", "N.C."]

        for symbol in symbols {
            let event = HarmonyEvent(startBeat: 4, symbol: symbol)
            let decoded = try JSONDecoder().decode(HarmonyEvent.self, from: JSONEncoder().encode(event))

            XCTAssertEqual(decoded, event)
        }
    }

    func testHarmonySymbolTrimsAndRejectsEmptyInput() {
        XCTAssertEqual(HarmonyEventNormalizer.normalizedSymbol("  Cmaj7\n"), "Cmaj7")
        XCTAssertEqual(HarmonyEventNormalizer.normalizedSymbol(" N.C. "), "N.C.")
        XCTAssertNil(HarmonyEventNormalizer.normalizedSymbol("   \n"))
    }

    func testHarmonyNormalizerClampsSortsAndResolvesDuplicateBeatKeys() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let events = [
            HarmonyEvent(id: firstID, startBeat: 2.2, symbol: "G"),
            HarmonyEvent(id: secondID, startBeat: -5, symbol: "C"),
            HarmonyEvent(id: thirdID, startBeat: 2.49, symbol: "Am")
        ]

        let normalized = HarmonyEventNormalizer.normalizedEvents(events, maximumBeat: 4)

        XCTAssertEqual(normalized.map(\.id), [secondID, firstID, thirdID])
        XCTAssertEqual(normalized.map(\.startBeat), [0, 2, 3])
        XCTAssertEqual(normalized.map(\.symbol), ["C", "G", "Am"])
    }

    func testHarmonyConflictPolicyFindsOccupiedAndNearestFreeBeatToRight() throws {
        let first = HarmonyEvent(startBeat: 0, symbol: "C")
        let second = HarmonyEvent(startBeat: 1, symbol: "F")
        let events = [first, second]

        XCTAssertEqual(
            HarmonyEventNormalizer.occupiedEventID(at: HarmonyBeatKey(0), in: events),
            first.id
        )
        XCTAssertEqual(
            try XCTUnwrap(HarmonyEventNormalizer.nearestFreeBeatKey(from: 0, in: events, maximumBeat: 4)).value,
            2
        )
        XCTAssertEqual(
            try XCTUnwrap(HarmonyEventNormalizer.nearestFreeBeatKey(from: 0, in: events, excluding: first.id, maximumBeat: 4)).value,
            0
        )
    }

    func testBeatCoordinateMapperUsesAbsoluteProjectBeatsAtConstantTempo() {
        let settings = BeatGridSettings(bpm: 120)
        let tempoMap = TempoMap(baseSettings: settings, markers: [], duration: 8)
        let mapper = BeatCoordinateMapper(tempoMap: tempoMap)

        XCTAssertEqual(mapper.time(for: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(mapper.time(for: 4), 2, accuracy: 0.0001)
        XCTAssertEqual(mapper.beat(at: 2), 4, accuracy: 0.0001)
        XCTAssertEqual(mapper.snappedBeat(at: 2.26), 5)
        XCTAssertEqual(mapper.maximumBeat, 16, accuracy: 0.0001)
    }

    func testBeatCoordinateMapperUsesFirstBeatOffsetWithoutNegativeHarmonyBeats() {
        let settings = BeatGridSettings(bpm: 120, firstBeatTime: 1)
        let tempoMap = TempoMap(baseSettings: settings, markers: [], duration: 4)
        let mapper = BeatCoordinateMapper(tempoMap: tempoMap)

        XCTAssertEqual(mapper.time(for: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(mapper.beat(at: 0.5), 0, accuracy: 0.0001)
        XCTAssertEqual(mapper.snappedBeat(at: 1.76), 2)
    }

    func testBeatCoordinateMapperAccumulatesBeatsAcrossTempoChanges() {
        let base = BeatGridSettings(bpm: 120)
        let tempoMarker = TimecodedNote(
            time: 2,
            title: "60 BPM",
            metadata: TempoTimeSignatureMarkerPayload(bpm: 60).metadata
        )
        let tempoMap = TempoMap(baseSettings: base, markers: [tempoMarker], duration: 6)
        let mapper = BeatCoordinateMapper(tempoMap: tempoMap)

        XCTAssertEqual(mapper.time(for: 4), 2, accuracy: 0.0001)
        XCTAssertEqual(mapper.time(for: 5), 3, accuracy: 0.0001)
        XCTAssertEqual(mapper.beat(at: 3), 5, accuracy: 0.0001)
    }

    func testBeatCoordinateMapperDoesNotResetAbsoluteBeatsWhenMarkerSetsNewFirstBeat() {
        let base = BeatGridSettings(bpm: 120)
        let marker = TimecodedNote(
            time: 2,
            title: "New First Beat",
            metadata: TempoTimeSignatureMarkerPayload(setsNewFirstBeat: true).metadata
        )
        let tempoMap = TempoMap(baseSettings: base, markers: [marker], duration: 4)
        let mapper = BeatCoordinateMapper(tempoMap: tempoMap)

        XCTAssertEqual(mapper.time(for: 4), 2, accuracy: 0.0001)
        XCTAssertEqual(mapper.time(for: 5), 2.5, accuracy: 0.0001)
        XCTAssertEqual(mapper.beat(at: 2.5), 5, accuracy: 0.0001)
    }

    func testProjectDecodeDefaultsMissingHarmonyEventsToEmptyArray() throws {
        let project = JammLabProject(
            formatVersion: 9,
            audioBookmarkData: Data("bookmark".utf8),
            audioDisplayName: "song.wav",
            audioDuration: 8,
            notes: [],
            loopStart: 0,
            loopEnd: 8,
            playbackRate: 1,
            pitchShiftSemitones: 0
        )
        let encoded = try JSONEncoder().encode(project)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "harmonyEvents")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(JammLabProject.self, from: legacyData)

        XCTAssertEqual(decoded.formatVersion, 9)
        XCTAssertTrue(decoded.harmonyEvents.isEmpty)
    }

    func testProjectEncodeDecodePreservesHarmonyEvents() throws {
        let event = HarmonyEvent(startBeat: 4, symbol: "C/E")
        let project = JammLabProject(
            audioBookmarkData: Data("bookmark".utf8),
            audioDisplayName: "song.wav",
            audioDuration: 8,
            notes: [],
            harmonyEvents: [event],
            loopStart: 0,
            loopEnd: 8,
            playbackRate: 1,
            pitchShiftSemitones: 0
        )

        let decoded = try JSONDecoder().decode(JammLabProject.self, from: JSONEncoder().encode(project))

        XCTAssertEqual(decoded.formatVersion, 10)
        XCTAssertEqual(decoded.harmonyEvents, [event])
    }

    @MainActor
    func testViewModelCreatesEditsMovesDeletesHarmonyEventsWithUndo() throws {
        let undoManager = UndoManager()
        let viewModel = AudioPlayerViewModel(playbackEngine: MockPlaybackEngine())
        viewModel.undoManager = undoManager
        viewModel.importedFile = ImportedAudioFile(
            url: URL(fileURLWithPath: "/tmp/song.wav"),
            displayName: "song.wav",
            duration: 8
        )
        viewModel.duration = 8
        viewModel.beatGridSettings = BeatGridSettings(bpm: 120)
        viewModel.tempoBPM = 120
        viewModel.markProjectClean()

        let id = try XCTUnwrap(viewModel.createHarmonyEvent(at: 0.1))

        XCTAssertEqual(viewModel.harmonyEvents.count, 1)
        XCTAssertEqual(viewModel.harmonyEvents.first?.symbol, "N.C.")
        XCTAssertEqual(viewModel.selectedHarmonyEventID, id)
        XCTAssertTrue(viewModel.isProjectModified)
        XCTAssertTrue(viewModel.canUndo)

        XCTAssertTrue(viewModel.updateHarmonyEventSymbol(id: id, symbol: "  Cmaj7 "))
        XCTAssertEqual(viewModel.harmonyEvents.first?.symbol, "Cmaj7")

        viewModel.moveHarmonyEvent(id: id, to: 2.26)
        XCTAssertEqual(viewModel.harmonyEvents.first?.startBeat, 5)

        viewModel.deleteHarmonyEvent(id: id)
        XCTAssertTrue(viewModel.harmonyEvents.isEmpty)
    }

    @MainActor
    func testViewModelUndoRedoRestoresHarmonyCreation() throws {
        let undoManager = UndoManager()
        let viewModel = AudioPlayerViewModel(playbackEngine: MockPlaybackEngine())
        viewModel.undoManager = undoManager
        viewModel.duration = 8
        viewModel.beatGridSettings = BeatGridSettings(bpm: 120)
        viewModel.tempoBPM = 120

        let id = try XCTUnwrap(viewModel.createHarmonyEvent(at: 0.1))

        XCTAssertEqual(viewModel.harmonyEvents.first?.id, id)
        viewModel.undoLastEdit()
        XCTAssertTrue(viewModel.harmonyEvents.isEmpty)
        viewModel.redoLastEdit()
        XCTAssertEqual(viewModel.harmonyEvents.first?.id, id)
    }

    @MainActor
    func testViewModelCreateOnOccupiedBeatSelectsExistingAndTabCreatesNextFreeBeat() throws {
        let viewModel = AudioPlayerViewModel(playbackEngine: MockPlaybackEngine())
        viewModel.duration = 8
        viewModel.beatGridSettings = BeatGridSettings(bpm: 120)
        viewModel.tempoBPM = 120

        let firstID = try XCTUnwrap(viewModel.createHarmonyEvent(at: 0.05))
        let occupiedID = try XCTUnwrap(viewModel.createHarmonyEvent(at: 0.1))
        let secondID = try XCTUnwrap(viewModel.commitHarmonyEventAndCreateNext(id: firstID, symbol: "C"))

        XCTAssertEqual(occupiedID, firstID)
        XCTAssertEqual(viewModel.harmonyEvents.count, 2)
        XCTAssertEqual(viewModel.harmonyEvents.first(where: { $0.id == firstID })?.symbol, "C")
        XCTAssertEqual(viewModel.harmonyEvents.first(where: { $0.id == secondID })?.startBeat, 1)
        XCTAssertEqual(viewModel.selectedHarmonyEventID, secondID)
    }

    func testHarmonyTrackHeightParticipatesInTimelineMinimumHeight() {
        XCTAssertEqual(AppTheme.Timeline.harmonyTrackHeight, AppTheme.Timeline.stemTrackHeight)

        let expectedUpperHeight = AppTheme.Timeline.regionTrackHeight
            + AppTheme.Timeline.markerTrackHeight
            + AppTheme.Timeline.tempoTrackHeight
            + AppTheme.Timeline.waveformTrackHeight
            + AppTheme.Timeline.harmonyTrackHeight

        XCTAssertEqual(AppTheme.Timeline.upperTrackStackHeight, expectedUpperHeight)
    }

    func testHarmonyChordLayoutMeasuresAndClampsHitWidths() {
        let shortLayout = HarmonyChordLayout.layout(symbol: "C")
        let slashLayout = HarmonyChordLayout.layout(symbol: "F#m7b5/C#")
        let longLayout = HarmonyChordLayout.layout(symbol: "Cmaj13#11/G# very long")

        XCTAssertGreaterThan(shortLayout.textWidth, 0)
        XCTAssertGreaterThanOrEqual(shortLayout.hitWidth, AppTheme.Timeline.chordSymbolMinHitWidth)
        XCTAssertLessThan(shortLayout.hitWidth, 44)
        XCTAssertGreaterThan(slashLayout.hitWidth, shortLayout.hitWidth)
        XCTAssertLessThan(slashLayout.hitWidth, AppTheme.Timeline.chordSymbolMaxHitWidth)
        XCTAssertEqual(longLayout.hitWidth, AppTheme.Timeline.chordSymbolMaxHitWidth)
    }

    func testHarmonyChordLayoutKeepsTextInsideHitFrame() {
        let layout = HarmonyChordLayout.layout(symbol: "Bb13")

        XCTAssertGreaterThanOrEqual(
            layout.textFrameWidth,
            min(layout.textWidth, AppTheme.Timeline.chordSymbolMaxHitWidth - AppTheme.Timeline.chordSymbolHorizontalInset)
        )
        XCTAssertEqual(
            layout.textFrameWidth,
            layout.hitWidth - AppTheme.Timeline.chordSymbolHorizontalInset
        )
    }

    func testHarmonyChordCollisionLayoutReplacesOverlappingLabelsWithTicks() {
        let events = [
            HarmonyEvent(startBeat: 0, symbol: "Bb13"),
            HarmonyEvent(startBeat: 1, symbol: "G-7"),
            HarmonyEvent(startBeat: 2, symbol: "C9"),
            HarmonyEvent(startBeat: 3, symbol: "F9"),
            HarmonyEvent(startBeat: 4, symbol: "Bb13")
        ]

        let items = renderChordCollisionItems(events: events, width: 150)

        XCTAssertEqual(items.count, events.count)
        XCTAssertTrue(items.contains { $0.mode == .label })
        XCTAssertTrue(items.contains { $0.mode == .tick })
        XCTAssertTrue(items.allSatisfy { $0.tickFrame.width > 0 && $0.hitFrame.width > 0 })
        assertChordLabelsDoNotOverlap(items)
    }

    func testHarmonyChordCollisionLayoutKeepsBarStartBeforeOffBeatWhenColliding() throws {
        let barStartID = UUID()
        let offBeatID = UUID()
        let events = [
            HarmonyEvent(id: barStartID, startBeat: 0, symbol: "Cmaj7"),
            HarmonyEvent(id: offBeatID, startBeat: 1, symbol: "F#m7b5")
        ]

        let items = renderChordCollisionItems(events: events, width: 90)
        let barStartItem = try XCTUnwrap(items.first { $0.id == barStartID })
        let offBeatItem = try XCTUnwrap(items.first { $0.id == offBeatID })

        XCTAssertTrue(barStartItem.isBarStart)
        XCTAssertFalse(offBeatItem.isBarStart)
        XCTAssertEqual(barStartItem.mode, .label)
        XCTAssertEqual(offBeatItem.mode, .tick)
        assertChordLabelsDoNotOverlap(items)
    }

    func testHarmonyChordCollisionLayoutUsesDefaultTempoForBarStartPriorityWhenBPMIsMissing() throws {
        let tempoMap = TempoMap(
            baseSettings: BeatGridSettings(),
            markers: [],
            duration: 8
        )
        let barStartID = UUID()
        let offBeatID = UUID()
        let events = [
            HarmonyEvent(id: barStartID, startBeat: 0, symbol: "Cmaj7"),
            HarmonyEvent(id: offBeatID, startBeat: 1, symbol: "F#m7b5")
        ]

        let items = renderChordCollisionItems(events: events, tempoMap: tempoMap, width: 90)
        let barStartItem = try XCTUnwrap(items.first { $0.id == barStartID })
        let offBeatItem = try XCTUnwrap(items.first { $0.id == offBeatID })

        XCTAssertTrue(barStartItem.isBarStart)
        XCTAssertFalse(offBeatItem.isBarStart)
        XCTAssertEqual(barStartItem.mode, .label)
        XCTAssertEqual(offBeatItem.mode, .tick)
    }

    func testHarmonyChordCollisionLayoutGivesSelectedAndHoveredMarkersPriority() throws {
        let firstID = UUID()
        let secondID = UUID()
        let events = [
            HarmonyEvent(id: firstID, startBeat: 0, symbol: "Cmaj13"),
            HarmonyEvent(id: secondID, startBeat: 1, symbol: "Gmaj13")
        ]

        let selectedItems = renderChordCollisionItems(
            events: events,
            width: 96,
            selectedEventID: secondID
        )
        XCTAssertEqual(try XCTUnwrap(selectedItems.first { $0.id == secondID }).mode, .label)
        XCTAssertEqual(try XCTUnwrap(selectedItems.first { $0.id == firstID }).mode, .tick)
        assertChordLabelsDoNotOverlap(selectedItems)

        let hoveredItems = renderChordCollisionItems(
            events: events,
            width: 96,
            hoveredEventID: secondID
        )
        XCTAssertEqual(try XCTUnwrap(hoveredItems.first { $0.id == secondID }).mode, .label)
        XCTAssertEqual(try XCTUnwrap(hoveredItems.first { $0.id == firstID }).mode, .tick)
        assertChordLabelsDoNotOverlap(hoveredItems)
    }

    func testHarmonyChordCollisionLayoutGivesEditingMarkerTopPriority() throws {
        let selectedID = UUID()
        let editingID = UUID()
        let events = [
            HarmonyEvent(id: selectedID, startBeat: 0, symbol: "Cmaj13"),
            HarmonyEvent(id: editingID, startBeat: 1, symbol: "Gmaj13")
        ]

        let items = renderChordCollisionItems(
            events: events,
            width: 96,
            selectedEventID: selectedID,
            editingEventID: editingID
        )

        XCTAssertEqual(try XCTUnwrap(items.first { $0.id == editingID }).mode, .label)
        XCTAssertEqual(try XCTUnwrap(items.first { $0.id == selectedID }).mode, .tick)
        assertChordLabelsDoNotOverlap(items)
    }

    func testHarmonyChordCollisionLayoutAllowsAllTicksAtExtremeZoomOut() {
        let events = [
            HarmonyEvent(startBeat: 0, symbol: "Cmaj7"),
            HarmonyEvent(startBeat: 1, symbol: "F#m7b5"),
            HarmonyEvent(startBeat: 2, symbol: "Bb13")
        ]

        let items = renderChordCollisionItems(events: events, width: 20)

        XCTAssertEqual(items.count, events.count)
        XCTAssertTrue(items.allSatisfy { $0.mode == .tick })
        XCTAssertTrue(items.allSatisfy { $0.tickFrame.width > 0 && $0.hitFrame.width > 0 })
    }

    func testHarmonyChordCollisionLayoutUsesRaisedDiamondAnchorGeometry() throws {
        let anchorID = UUID()
        let events = [
            HarmonyEvent(startBeat: 4, symbol: "Cmaj7"),
            HarmonyEvent(id: anchorID, startBeat: 5, symbol: "F#m7b5")
        ]

        let items = renderChordCollisionItems(events: events, width: 40)
        let anchorItem = try XCTUnwrap(items.first { $0.id == anchorID })

        XCTAssertEqual(anchorItem.mode, .tick)
        XCTAssertEqual(anchorItem.tickFrame.width, AppTheme.Timeline.chordTickWidth)
        XCTAssertEqual(anchorItem.tickFrame.height, AppTheme.Timeline.chordTickHeight)
        XCTAssertEqual(anchorItem.tickFrame.width, anchorItem.tickFrame.height)
        XCTAssertEqual(anchorItem.tickFrame.minY, AppTheme.Timeline.chordTickTopInset)
        XCTAssertEqual(anchorItem.tickFrame.midX, anchorItem.anchorX, accuracy: 0.0001)
        XCTAssertEqual(anchorItem.hitFrame.width, AppTheme.Timeline.chordTickHitWidth)
        XCTAssertEqual(anchorItem.hitFrame.height, AppTheme.Timeline.chordTickHitHeight)
    }

    func testHarmonyChordCollisionLayoutKeepsNarrowAnchorFramesInsideTrack() throws {
        let anchorID = UUID()
        let events = [
            HarmonyEvent(id: anchorID, startBeat: 0, symbol: "Cmaj7")
        ]
        let trackWidth: CGFloat = 6

        let items = renderChordCollisionItems(events: events, width: trackWidth)
        let anchorItem = try XCTUnwrap(items.first { $0.id == anchorID })

        XCTAssertEqual(anchorItem.mode, .tick)
        XCTAssertGreaterThanOrEqual(anchorItem.tickFrame.minX, 0)
        XCTAssertLessThanOrEqual(anchorItem.tickFrame.maxX, trackWidth)
        XCTAssertGreaterThanOrEqual(anchorItem.hitFrame.minX, 0)
        XCTAssertLessThanOrEqual(anchorItem.hitFrame.maxX, trackWidth)
    }

    func testHarmonyChordCollisionLayoutDetectsBarStartsAcrossTimeSignatureReset() throws {
        let resetMarker = TimecodedNote(
            time: 2,
            title: "3/4 Reset",
            metadata: TempoTimeSignatureMarkerPayload(beatsPerBar: 3, setsNewFirstBeat: true).metadata
        )
        let tempoMap = TempoMap(
            baseSettings: BeatGridSettings(bpm: 120),
            markers: [resetMarker],
            duration: 6
        )
        let resetDownbeatID = UUID()
        let secondBeatID = UUID()
        let nextDownbeatID = UUID()
        let events = [
            HarmonyEvent(id: resetDownbeatID, startBeat: 4, symbol: "C"),
            HarmonyEvent(id: secondBeatID, startBeat: 5, symbol: "F"),
            HarmonyEvent(id: nextDownbeatID, startBeat: 7, symbol: "G")
        ]

        let items = renderChordCollisionItems(events: events, tempoMap: tempoMap, duration: 6, width: 600)

        XCTAssertTrue(try XCTUnwrap(items.first { $0.id == resetDownbeatID }).isBarStart)
        XCTAssertFalse(try XCTUnwrap(items.first { $0.id == secondBeatID }).isBarStart)
        XCTAssertTrue(try XCTUnwrap(items.first { $0.id == nextDownbeatID }).isBarStart)
    }

    private func renderChordCollisionItems(
        events: [HarmonyEvent],
        tempoMap: TempoMap? = nil,
        duration: TimeInterval = 8,
        width: CGFloat,
        selectedEventID: HarmonyEvent.ID? = nil,
        hoveredEventID: HarmonyEvent.ID? = nil,
        editingEventID: HarmonyEvent.ID? = nil
    ) -> [HarmonyChordRenderItem] {
        let resolvedTempoMap = tempoMap ?? TempoMap(
            baseSettings: BeatGridSettings(bpm: 120),
            markers: [],
            duration: duration
        )
        return HarmonyChordCollisionLayout.renderItems(
            events: events,
            tempoMap: resolvedTempoMap,
            viewport: TimelineViewport(duration: duration, visibleRange: 0...duration),
            width: width,
            selectedEventID: selectedEventID,
            hoveredEventID: hoveredEventID,
            editingEventID: editingEventID
        )
    }

    private func assertChordLabelsDoNotOverlap(
        _ items: [HarmonyChordRenderItem],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frames = items.compactMap(\.labelFrame).map {
            $0.insetBy(dx: -AppTheme.Timeline.chordSymbolCollisionGap / 2, dy: 0)
        }
        guard frames.count > 1 else { return }

        for index in frames.indices.dropLast() {
            for otherIndex in frames.indices.dropFirst(index + 1) {
                XCTAssertFalse(
                    frames[index].intersects(frames[otherIndex]),
                    "Chord label frames should not overlap: \(frames[index]) and \(frames[otherIndex])",
                    file: file,
                    line: line
                )
            }
        }
    }

}
