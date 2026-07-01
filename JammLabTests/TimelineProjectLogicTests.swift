import AppKit
import XCTest
@testable import JammLab

final class TimelineProjectLogicTests: XCTestCase {
    func testTimelineViewportMapsAndBoundsVisibleRange() {
        let viewport = TimelineViewport(duration: 100, visibleRange: 20...60)

        XCTAssertEqual(viewport.clampedRange.lowerBound, 20)
        XCTAssertEqual(viewport.clampedRange.upperBound, 60)
        XCTAssertEqual(viewport.xPosition(for: 40, width: 200), 100, accuracy: 0.0001)
        XCTAssertEqual(viewport.time(forX: 50, width: 200), 30, accuracy: 0.0001)
        XCTAssertEqual(viewport.intersection(start: 10, end: 30)?.lowerBound, 20)
        XCTAssertEqual(viewport.intersection(start: 10, end: 30)?.upperBound, 30)
    }

    func testTimelineViewportZoomAndPanStayInBounds() {
        let viewport = TimelineViewport(duration: 100, visibleRange: 20...60)

        let zoomed = viewport.zoomed(to: 20, anchoredAt: 30)
        XCTAssertEqual(zoomed.visibleDuration, 20, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(zoomed.clampedRange.lowerBound, 0)
        XCTAssertLessThanOrEqual(zoomed.clampedRange.upperBound, 100)

        let pannedToStart = viewport.panned(by: -1000)
        XCTAssertEqual(pannedToStart.clampedRange.lowerBound, 0, accuracy: 0.0001)

        let pannedToEnd = viewport.panned(by: 1000)
        XCTAssertEqual(pannedToEnd.clampedRange.upperBound, 100, accuracy: 0.0001)
    }

    func testTimelineViewportPositionsTimeNearLeadingEdgePreservingZoom() {
        let viewport = TimelineViewport(duration: 100, visibleRange: 20...40)

        let followed = viewport.positionedWithTimeNearLeadingEdge(30)

        XCTAssertEqual(followed.visibleDuration, 20, accuracy: 0.0001)
        XCTAssertEqual(followed.clampedRange.lowerBound, 28.4, accuracy: 0.0001)
        XCTAssertEqual(followed.clampedRange.upperBound, 48.4, accuracy: 0.0001)
        XCTAssertEqual(followed.xPosition(for: 30, width: 100), 8, accuracy: 0.0001)
    }

    func testTimelineViewportFollowPositionClampsAtTrackEdges() {
        let viewport = TimelineViewport(duration: 100, visibleRange: 20...40)

        let start = viewport.positionedWithTimeNearLeadingEdge(1)
        let end = viewport.positionedWithTimeNearLeadingEdge(98)

        XCTAssertEqual(start.clampedRange.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(start.clampedRange.upperBound, 20, accuracy: 0.0001)
        XCTAssertEqual(end.clampedRange.lowerBound, 80, accuracy: 0.0001)
        XCTAssertEqual(end.clampedRange.upperBound, 100, accuracy: 0.0001)
    }

    func testTimelineViewportFollowIsNoOpForFullRange() {
        let viewport = TimelineViewport(duration: 100, visibleRange: 0...100)

        let followed = viewport.positionedWithTimeNearLeadingEdge(90)

        XCTAssertEqual(followed.clampedRange.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(followed.clampedRange.upperBound, 100, accuracy: 0.0001)
        XCTAssertFalse(viewport.shouldFollowPlaybackTime(90))
    }

    func testTimelineViewportShouldFollowNearRightEdgeOnlyWhenZoomed() {
        let viewport = TimelineViewport(duration: 100, visibleRange: 0...20)

        XCTAssertFalse(viewport.shouldFollowPlaybackTime(18.39))
        XCTAssertTrue(viewport.shouldFollowPlaybackTime(18.4))
        XCTAssertTrue(viewport.shouldFollowPlaybackTime(21))
        XCTAssertTrue(viewport.shouldFollowPlaybackTime(-1))
    }

    func testTimelineViewportScrollerMetricsMapsVisibleRangeToThumb() {
        let metrics = TimelineViewportScrollerMetrics(
            duration: 100,
            visibleRange: 25...75,
            trackWidth: 200,
            minimumThumbWidth: 24
        )

        XCTAssertEqual(metrics.thumbWidth, 100, accuracy: 0.0001)
        XCTAssertEqual(metrics.thumbX, 50, accuracy: 0.0001)
    }

    func testTimelineViewportScrollerDragPreservesVisibleDuration() {
        let metrics = TimelineViewportScrollerMetrics(
            duration: 100,
            visibleRange: 20...60,
            trackWidth: 200,
            minimumThumbWidth: 24
        )

        let range = metrics.range(draggedBy: 50)

        XCTAssertEqual(range.upperBound - range.lowerBound, 40, accuracy: 0.0001)
        XCTAssertGreaterThan(range.lowerBound, 20)
    }

    func testTimelineViewportScrollerDragClampsAtTrackEdges() {
        let metrics = TimelineViewportScrollerMetrics(
            duration: 100,
            visibleRange: 20...60,
            trackWidth: 200,
            minimumThumbWidth: 24
        )

        let startRange = metrics.range(draggedBy: -1_000)
        let endRange = metrics.range(draggedBy: 1_000)

        XCTAssertEqual(startRange.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(startRange.upperBound, 40, accuracy: 0.0001)
        XCTAssertEqual(endRange.lowerBound, 60, accuracy: 0.0001)
        XCTAssertEqual(endRange.upperBound, 100, accuracy: 0.0001)
    }

    func testTimelineViewportScrollerHandlesZeroDuration() {
        let metrics = TimelineViewportScrollerMetrics(
            duration: 0,
            visibleRange: 0...0,
            trackWidth: 200,
            minimumThumbWidth: 24
        )

        XCTAssertEqual(metrics.thumbWidth, 200, accuracy: 0.0001)
        XCTAssertEqual(metrics.thumbX, 0, accuracy: 0.0001)
        XCTAssertEqual(metrics.range(draggedBy: 50).lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(metrics.range(draggedBy: 50).upperBound, 0, accuracy: 0.0001)
    }

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

    func testLoopRegionRespectsCustomMinimumLength() {
        let region = LoopRegion(start: 2, end: 5)

        let movedStart = region.movingStart(to: 4.5, trackDuration: 10, minimumLength: 2)
        XCTAssertEqual(movedStart.start, 3, accuracy: 0.0001)
        XCTAssertEqual(movedStart.end, 5, accuracy: 0.0001)

        let movedEnd = region.movingEnd(to: 2.5, trackDuration: 10, minimumLength: 2)
        XCTAssertEqual(movedEnd.start, 2, accuracy: 0.0001)
        XCTAssertEqual(movedEnd.end, 4, accuracy: 0.0001)

        let shifted = region.offset(by: 20, trackDuration: 10, minimumLength: 2)
        XCTAssertEqual(shifted.start, 7, accuracy: 0.0001)
        XCTAssertEqual(shifted.end, 10, accuracy: 0.0001)
    }

    func testRegionNotePersistsDurationAndComputesEnd() throws {
        let note = TimecodedNote(kind: .region, time: 12.3, duration: 4.5, title: "Chorus", color: .regionBlue)
        let data = try JSONEncoder().encode(note)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(try XCTUnwrap(object["time"] as? Double), 12.3, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(object["duration"] as? Double), 4.5, accuracy: 0.0001)
        XCTAssertNil(object["endTime"])

        let decoded = try JSONDecoder().decode(TimecodedNote.self, from: data)
        XCTAssertEqual(decoded.regionEndTime, 16.8, accuracy: 0.0001)
    }

    func testDefaultNoteColorsResolveByKind() {
        let marker = TimecodedNote(time: 1, title: "Marker")
        let region = TimecodedNote(kind: .region, time: 2, duration: 3, title: "Region")

        XCTAssertEqual(marker.color, .markerDefault)
        XCTAssertEqual(marker.resolvedColorHex, "#A00000")
        XCTAssertEqual(region.color, .regionDefault)
        XCTAssertEqual(region.resolvedColorHex, "#567272")
    }

    func testNoteColorPresetMenusUseKindSpecificPalettes() {
        let marker = TimecodedNote(time: 1, title: "Marker")
        let region = TimecodedNote(kind: .region, time: 2, duration: 3, title: "Region")

        let markerPresets = NoteColorPreset.presets(for: marker)
        let regionPresets = NoteColorPreset.presets(for: region)

        XCTAssertEqual(markerPresets.first?.title, "Default")
        XCTAssertEqual(markerPresets.first?.id, .markerDefault)
        XCTAssertEqual(markerPresets.map(\.title), ["Default", "Orange", "Yellow", "Blue", "Purple"])
        XCTAssertEqual(markerPresets.map(\.id), [.markerDefault, .markerOrange, .markerYellow, .markerBlue, .markerPurple])
        XCTAssertEqual(markerPresets.map(\.hex), ["#A00000", "#B85A00", "#A88A00", "#1F6FA8", "#7A3FA0"])
        XCTAssertFalse(markerPresets.map(\.title).contains("Marker Default"))
        XCTAssertFalse(markerPresets.map(\.title).contains("Region Default"))

        XCTAssertEqual(regionPresets.map(\.title), ["Default", "Green", "Amber", "Blue", "Plum"])
        XCTAssertEqual(regionPresets.map(\.id), [.regionDefault, .regionGreen, .regionAmber, .regionBlue, .regionPlum])
        XCTAssertEqual(regionPresets.map(\.hex), ["#567272", "#66805A", "#9A8048", "#5B7188", "#7A617E"])
        XCTAssertFalse(regionPresets.map(\.title).contains("Marker Default"))
        XCTAssertFalse(regionPresets.map(\.title).contains("Region Default"))
    }

    func testCustomNoteColorPersistsThroughRoundTrip() throws {
        let note = TimecodedNote(
            kind: .region,
            time: 12.3,
            duration: 4.5,
            title: "Chorus",
            color: .regionBlue,
            customColorHex: "12ab34"
        )
        let data = try JSONEncoder().encode(note)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(try XCTUnwrap(object["color"] as? String), "regionBlue")
        XCTAssertEqual(try XCTUnwrap(object["customColorHex"] as? String), "#12AB34")

        let decoded = try JSONDecoder().decode(TimecodedNote.self, from: data)
        XCTAssertEqual(decoded.color, .regionBlue)
        XCTAssertEqual(decoded.customColorHex, "#12AB34")
        XCTAssertEqual(decoded.resolvedColorHex, "#12AB34")
    }

    func testInvalidCustomNoteColorFallsBackToPreset() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000010",
          "kind": "marker",
          "time": 3.0,
          "title": "Bad Color",
          "color": "blue",
          "customColorHex": "bad-color"
        }
        """

        let decoded = try JSONDecoder().decode(TimecodedNote.self, from: Data(json.utf8))

        XCTAssertNil(decoded.customColorHex)
        XCTAssertEqual(decoded.color, .markerDefault)
        XCTAssertEqual(decoded.resolvedColorHex, MarkerColor.markerDefault.defaultHex)
    }

    func testUnknownOldColorRawValuesDefaultByKind() throws {
        let markerJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000013",
          "kind": "marker",
          "time": 3.0,
          "title": "Old Marker",
          "color": "blue"
        }
        """
        let regionJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000014",
          "kind": "region",
          "time": 4.0,
          "duration": 2.0,
          "title": "Old Region",
          "color": "green"
        }
        """

        let marker = try JSONDecoder().decode(TimecodedNote.self, from: Data(markerJSON.utf8))
        let region = try JSONDecoder().decode(TimecodedNote.self, from: Data(regionJSON.utf8))

        XCTAssertEqual(marker.color, .markerDefault)
        XCTAssertEqual(marker.resolvedColorHex, "#A00000")
        XCTAssertEqual(region.color, .regionDefault)
        XCTAssertEqual(region.resolvedColorHex, "#567272")
    }

    func testMissingColorDefaultsByDecodedKind() throws {
        let markerJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000011",
          "kind": "marker",
          "time": 3.0,
          "title": "Marker"
        }
        """
        let regionJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000012",
          "kind": "region",
          "time": 4.0,
          "duration": 2.0,
          "title": "Region"
        }
        """

        let marker = try JSONDecoder().decode(TimecodedNote.self, from: Data(markerJSON.utf8))
        let region = try JSONDecoder().decode(TimecodedNote.self, from: Data(regionJSON.utf8))

        XCTAssertEqual(marker.color, .markerDefault)
        XCTAssertEqual(marker.resolvedColorHex, "#A00000")
        XCTAssertEqual(region.color, .regionDefault)
        XCTAssertEqual(region.resolvedColorHex, "#567272")
    }

    func testLegacyRegionEndTimeDecodesToDuration() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "kind": "loop",
          "time": 3.0,
          "endTime": 8.25,
          "title": "Legacy Loop",
          "color": "green"
        }
        """

        let decoded = try JSONDecoder().decode(TimecodedNote.self, from: Data(json.utf8))

        XCTAssertTrue(decoded.isRegion)
        XCTAssertEqual(try XCTUnwrap(decoded.duration), 5.25, accuracy: 0.0001)
        XCTAssertEqual(decoded.regionEndTime, 8.25, accuracy: 0.0001)
        XCTAssertEqual(decoded.color, .regionDefault)
    }

    func testProjectDecodeDefaultsMissingHarmonySymbolsToEmptyArray() throws {
        let project = JammLabProject(
            audioBookmarkData: Data([1, 2, 3]),
            audioDisplayName: "song.wav",
            audioDuration: 12,
            notes: [],
            loopStart: 0,
            loopEnd: 4,
            playbackRate: 1,
            pitchShiftSemitones: 0
        )
        let data = try JSONEncoder().encode(project)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "harmonySymbols")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(JammLabProject.self, from: legacyData)

        XCTAssertTrue(decoded.harmonySymbols.isEmpty)
    }

    func testProjectPersistsHarmonySymbolsAsRawText() throws {
        let symbol = HarmonySymbol(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            time: 1.25,
            measureNumber: 1,
            offsetInQuarterNotes: 2.5,
            rawText: "Bb13(#11)/D"
        )
        let project = JammLabProject(
            audioBookmarkData: Data([1, 2, 3]),
            audioDisplayName: "song.wav",
            audioDuration: 12,
            notes: [],
            harmonySymbols: [symbol],
            loopStart: 0,
            loopEnd: 4,
            playbackRate: 1,
            pitchShiftSemitones: 0
        )

        let decoded = try JSONDecoder().decode(JammLabProject.self, from: JSONEncoder().encode(project))

        XCTAssertEqual(decoded.harmonySymbols, [symbol])
    }

    func testProjectStateNormalizerClampsInvalidValues() throws {
        let region = TimecodedNote(kind: .region, time: -5, duration: 100, title: "", color: .regionPlum)
        let marker = TimecodedNote(time: 999, title: "")
        let notes = ProjectStateNormalizer.normalizedNotes([region, marker], duration: 12)

        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes[0].time, 0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(notes[0].duration), 12, accuracy: 0.0001)
        XCTAssertEqual(notes[0].title, "Region")
        XCTAssertEqual(notes[1].time, 12, accuracy: 0.0001)
        XCTAssertEqual(notes[1].title, "Marker")

        let loop = ProjectStateNormalizer.normalizedLoopRegion(start: 11.9, end: 11.95, duration: 12, minimumLength: 1)
        XCTAssertEqual(loop.start, 11, accuracy: 0.0001)
        XCTAssertEqual(loop.end, 12, accuracy: 0.0001)
    }

    func testProjectStateNormalizerClampsAndSortsHarmonySymbols() throws {
        let laterID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let earlierID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!

        let symbols = ProjectStateNormalizer.normalizedHarmonySymbols([
            HarmonySymbol(
                id: laterID,
                time: 999,
                measureNumber: 0,
                offsetInQuarterNotes: .nan,
                rawText: "G7 alt"
            ),
            HarmonySymbol(
                id: earlierID,
                time: -5,
                measureNumber: -3,
                offsetInQuarterNotes: 1.5,
                rawText: " Cmaj7 "
            )
        ], duration: 12)

        XCTAssertEqual(symbols.map(\.id), [earlierID, laterID])
        XCTAssertEqual(symbols[0].time, 0, accuracy: 0.0001)
        XCTAssertEqual(symbols[0].measureNumber, 1)
        XCTAssertEqual(symbols[0].offsetInQuarterNotes, 1.5, accuracy: 0.0001)
        XCTAssertEqual(symbols[0].rawText, " Cmaj7 ")
        XCTAssertEqual(symbols[1].time, 12, accuracy: 0.0001)
        XCTAssertEqual(symbols[1].measureNumber, 1)
        XCTAssertEqual(symbols[1].offsetInQuarterNotes, 0, accuracy: 0.0001)
        XCTAssertEqual(symbols[1].rawText, "G7 alt")
    }

    func testProjectStateNormalizerUsesSliderDefaultsForPlaybackControls() {
        XCTAssertEqual(
            ProjectStateNormalizer.normalizedPlaybackRate(0),
            AppSliderDefaults.minimumPlaybackRate,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ProjectStateNormalizer.normalizedPlaybackRate(2),
            AppSliderDefaults.maximumPlaybackRate,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ProjectStateNormalizer.normalizedPlaybackRate(.nan),
            AppSliderDefaults.playbackRate,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ProjectStateNormalizer.normalizedPitchShift(-24),
            AppSliderDefaults.minimumPitchShiftSemitones,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ProjectStateNormalizer.normalizedPitchShift(24),
            AppSliderDefaults.maximumPitchShiftSemitones,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ProjectStateNormalizer.normalizedPitchShift(.nan),
            AppSliderDefaults.pitchShiftSemitones,
            accuracy: 0.0001
        )
    }

    func testAppHotkeyRecognizesTabForPlaybackModeToggle() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        ))

        XCTAssertEqual(AppHotkey(event: event), .togglePlaybackMode)
        XCTAssertEqual(AppHotkey.togglePlaybackMode.key, "Tab")
    }

    func testAppHotkeyRecognizesSpaceForPlayStop() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        ))

        XCTAssertEqual(AppHotkey(event: event), .playPause)
        XCTAssertEqual(AppHotkey.playPause.key, "Space")
        XCTAssertEqual(AppHotkey.playPause.title, "Play / Stop")
        XCTAssertEqual(AppHotkey.playPause.detail, "Start playback from the position marker or stop and return to it.")
    }

    func testAppHotkeyEventFilterScopesAllowedHotkeysToAttachedWindow() throws {
        let spaceEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        ))
        let repeatSpaceEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: true,
            keyCode: 49
        ))
        let tabEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        ))

        XCTAssertEqual(
            AppHotkeyEventFilter.hotkey(
                for: spaceEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.playPause]
            ),
            .playPause
        )
        XCTAssertEqual(
            AppHotkeyEventFilter.hotkey(
                for: spaceEvent,
                attachedWindowNumber: 42,
                firstResponder: NSView(),
                allowedHotkeys: [.playPause]
            ),
            .playPause
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: spaceEvent,
                attachedWindowNumber: 42,
                firstResponder: AbletonNumberFieldNSView(),
                allowedHotkeys: [.playPause]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: spaceEvent,
                attachedWindowNumber: 42,
                firstResponder: NSTextView(),
                allowedHotkeys: [.playPause]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: spaceEvent,
                attachedWindowNumber: 7,
                firstResponder: nil,
                allowedHotkeys: [.playPause]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: repeatSpaceEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.playPause]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: tabEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.playPause]
            )
        )
    }

    func testAppHotkeyDoesNotExposeHarmonyShortcutMetadata() {
        XCTAssertFalse(AppHotkey.allCases.contains { $0.key == "A" })
        XCTAssertFalse(AppHotkey.allCases.contains { $0.title == "Add Harmony" })
    }

    func testAppHotkeyDoesNotRecognizeAOrHForHarmony() throws {
        let aEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))
        let hEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "h",
            charactersIgnoringModifiers: "h",
            isARepeat: false,
            keyCode: 4
        ))
        let commandAEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))
        let shiftAEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "A",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))

        XCTAssertNil(AppHotkey(event: aEvent))
        XCTAssertNil(AppHotkey(event: hEvent))
        XCTAssertNil(AppHotkey(event: commandAEvent))
        XCTAssertNil(AppHotkey(event: shiftAEvent))
    }

    func testAppHotkeyRecognizesOptionVForVideoWindowToggle() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "v",
            charactersIgnoringModifiers: "v",
            isARepeat: false,
            keyCode: 9
        ))

        XCTAssertEqual(AppHotkey(event: event), .toggleVideoWindow)
        XCTAssertEqual(AppHotkey.toggleVideoWindow.key, "Opt+V")
        XCTAssertEqual(AppHotkey.toggleVideoWindow.title, "Video Window")
        XCTAssertEqual(
            AppHotkey.toggleVideoWindow.detail,
            "Open or close the sidecar video window for the current video project."
        )
    }

    func testAppHotkeyRecognizesShiftCForTempoTimeSignatureMarker() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "C",
            charactersIgnoringModifiers: "c",
            isARepeat: false,
            keyCode: 8
        ))

        XCTAssertEqual(AppHotkey(event: event), .addTempoTimeSignatureMarker)
        XCTAssertEqual(AppHotkey.addTempoTimeSignatureMarker.key, "Shift+C")
        XCTAssertEqual(AppHotkey.addTempoTimeSignatureMarker.title, "Add Tempo / Time Signature Marker")
    }

    func testAppHotkeyRecognizesCommandCAndVForNotationMeasureCopyPaste() throws {
        let copyEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "c",
            charactersIgnoringModifiers: "c",
            isARepeat: false,
            keyCode: 8
        ))
        let pasteEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "v",
            charactersIgnoringModifiers: "v",
            isARepeat: false,
            keyCode: 9
        ))

        XCTAssertEqual(AppHotkey(event: copyEvent), .copyMeasure)
        XCTAssertEqual(AppHotkey.copyMeasure.key, "Cmd+C")
        XCTAssertEqual(AppHotkey.copyMeasure.title, "Copy Measure")
        XCTAssertEqual(AppHotkey(event: pasteEvent), .pasteMeasure)
        XCTAssertEqual(AppHotkey.pasteMeasure.key, "Cmd+V")
        XCTAssertEqual(AppHotkey.pasteMeasure.title, "Paste Measure")
    }

    func testAppHotkeyRecognizesEscapeForNotationMeasureSelectionClear() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ))

        XCTAssertEqual(AppHotkey(event: event), .clearNotationMeasureSelection)
        XCTAssertEqual(AppHotkey.clearNotationMeasureSelection.key, "Esc")
        XCTAssertEqual(AppHotkey.clearNotationMeasureSelection.title, "Clear Measure Selection")
    }

    func testAppHotkeyEventFilterDoesNotStealMeasureCopyPasteFromTextRespondersOrUnavailableScopes() throws {
        let copyEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: "c",
            charactersIgnoringModifiers: "c",
            isARepeat: false,
            keyCode: 8
        ))

        XCTAssertEqual(
            AppHotkeyEventFilter.hotkey(
                for: copyEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.copyMeasure]
            ),
            .copyMeasure
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: copyEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.playPause]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: copyEvent,
                attachedWindowNumber: 42,
                firstResponder: NSTextView(),
                allowedHotkeys: [.copyMeasure]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: copyEvent,
                attachedWindowNumber: 42,
                firstResponder: AbletonNumberFieldNSView(),
                allowedHotkeys: [.copyMeasure]
            )
        )
    }

    func testAppHotkeyEventFilterDoesNotStealEscapeFromTextRespondersOrUnavailableScopes() throws {
        let escapeEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ))

        XCTAssertEqual(
            AppHotkeyEventFilter.hotkey(
                for: escapeEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.clearNotationMeasureSelection]
            ),
            .clearNotationMeasureSelection
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: escapeEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.playPause]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: escapeEvent,
                attachedWindowNumber: 42,
                firstResponder: NSTextView(),
                allowedHotkeys: [.clearNotationMeasureSelection]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: escapeEvent,
                attachedWindowNumber: 42,
                firstResponder: AbletonNumberFieldNSView(),
                allowedHotkeys: [.clearNotationMeasureSelection]
            )
        )
    }

}
