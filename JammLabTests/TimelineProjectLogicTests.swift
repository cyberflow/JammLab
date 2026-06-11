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

}
