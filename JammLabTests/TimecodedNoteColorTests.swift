import XCTest
@testable import JammLab

final class TimecodedNoteColorTests: XCTestCase {
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
}
