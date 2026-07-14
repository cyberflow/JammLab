import AppKit
import Foundation
import UniformTypeIdentifiers

enum NotationExportFormat {
    case musicXML

    var fileExtension: String {
        switch self {
        case .musicXML:
            return "musicxml"
        }
    }

    var contentType: UTType {
        switch self {
        case .musicXML:
            return UTType(filenameExtension: fileExtension) ?? .xml
        }
    }
}

struct NotationExportRequest {
    var displayName: String
    var score: NotationScoreState
    var parts: [NotationExportPart] = []
    var tempoBPM: Double? = nil

    var exportParts: [NotationExportPart] {
        let readyParts = parts.filter { $0.score.isReady && !$0.score.measures.isEmpty }
        guard !readyParts.isEmpty else {
            return [NotationExportPart(descriptor: .main, score: score)]
        }
        return readyParts
    }
}

struct NotationExportPart: Equatable {
    var descriptor: NotationPartDescriptor
    var score: NotationScoreState
}

protocol NotationExportRenderer {
    var format: NotationExportFormat { get }
    func render(_ request: NotationExportRequest) throws -> Data
}

enum NotationExportError: LocalizedError, Equatable {
    case emptyScore
    case unsupportedChord(rawText: String, measureNumber: Int)
    case invalidXML

    var errorDescription: String? {
        switch self {
        case .emptyScore:
            return "No notation is available to export."
        case .unsupportedChord(let rawText, let measureNumber):
            return "Unsupported chord \"\(rawText)\" in measure \(measureNumber)."
        case .invalidXML:
            return "MusicXML data could not be generated."
        }
    }
}

final class NotationExportService {
    private let renderers: [NotationExportFormat: NotationExportRenderer]

    init(renderers: [NotationExportRenderer] = [MusicXMLNotationExportRenderer()]) {
        self.renderers = Dictionary(uniqueKeysWithValues: renderers.map { ($0.format, $0) })
    }

    func export(_ request: NotationExportRequest, format: NotationExportFormat) throws -> Data {
        guard request.exportParts.contains(where: { $0.score.isReady && !$0.score.measures.isEmpty }) else {
            throw NotationExportError.emptyScore
        }

        guard let renderer = renderers[format] else {
            throw NotationExportError.invalidXML
        }

        return try renderer.render(request)
    }
}

final class NotationExportDocumentService {
    @MainActor
    func chooseExportURL(defaultName: String, format: NotationExportFormat) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Notation"
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = defaultName

        guard panel.runModal() == .OK else {
            return nil
        }

        guard let url = panel.url else { return nil }
        return url.pathExtension.lowercased() == format.fileExtension
            ? url
            : url.deletingPathExtension().appendingPathExtension(format.fileExtension)
    }

    func save(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

final class MusicXMLNotationExportRenderer: NotationExportRenderer {
    let format: NotationExportFormat = .musicXML

    private let divisions = 480
    private let appVersionProvider: () -> String?

    init(appVersionProvider: @escaping () -> String? = MusicXMLNotationExportRenderer.bundledAppVersion) {
        self.appVersionProvider = appVersionProvider
    }

    func render(_ request: NotationExportRequest) throws -> Data {
        let exportParts = request.exportParts
        guard !exportParts.isEmpty else {
            throw NotationExportError.emptyScore
        }

        let root = element("score-partwise", attributes: ["version": "4.0"])
        root.addChild(identification())
        root.addChild(titleCredit(title: request.displayName))
        root.addChild(partList(parts: exportParts, title: request.displayName))
        for (index, exportPart) in exportParts.enumerated() {
            root.addChild(try part(
                id: musicXMLPartID(for: index),
                measures: exportPart.score.measures,
                tempoBPM: index == 0 ? request.tempoBPM : nil,
                includesRegionLabels: index == 0,
                includesHarmonies: exportPart.descriptor.id.isMain
            ))
        }

        let document = XMLDocument(rootElement: root)
        document.version = "1.0"
        document.characterEncoding = "UTF-8"

        guard var xml = String(data: document.xmlData(options: .nodePrettyPrint), encoding: .utf8) else {
            throw NotationExportError.invalidXML
        }

        xml = insertMusicXMLDoctype(into: xml)
        guard let data = xml.data(using: .utf8) else {
            throw NotationExportError.invalidXML
        }
        return data
    }

    private static func bundledAppVersion() -> String? {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }

        return normalizedAppVersion(version)
    }

    private func identification() -> XMLElement {
        let identification = element("identification")
        let encoding = element("encoding")
        let softwareName = Self.normalizedAppVersion(appVersionProvider()).map { "JammLab \($0)" } ?? "JammLab"
        encoding.addChild(element("software", stringValue: softwareName))
        identification.addChild(encoding)
        return identification
    }

    private static func normalizedAppVersion(_ version: String?) -> String? {
        guard let version else { return nil }
        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedVersion.isEmpty ? nil : trimmedVersion
    }

    private func partList(parts: [NotationExportPart], title: String) -> XMLElement {
        let partList = element("part-list")
        for (index, part) in parts.enumerated() {
            let partID = musicXMLPartID(for: index)
            let scorePart = element("score-part", attributes: ["id": partID])
            let partName = part.descriptor.id.isMain ? title : part.descriptor.title
            let attributes = part.descriptor.id.isMain ? ["print-object": "no"] : [:]
            scorePart.addChild(element("part-name", stringValue: partName, attributes: attributes))
            scorePart.addChild(element("part-abbreviation", stringValue: part.descriptor.abbreviation))

            let scoreInstrument = element("score-instrument", attributes: ["id": "\(partID)-I1"])
            scoreInstrument.addChild(element("instrument-name", stringValue: part.descriptor.instrumentName))
            if let instrumentSound = part.descriptor.instrumentSound {
                scoreInstrument.addChild(element("instrument-sound", stringValue: instrumentSound))
            }
            scorePart.addChild(scoreInstrument)
            partList.addChild(scorePart)
        }
        return partList
    }

    private func musicXMLPartID(for index: Int) -> String {
        "P\(index + 1)"
    }

    private func titleCredit(title: String) -> XMLElement {
        let credit = element("credit", attributes: ["page": "1"])
        credit.addChild(element("credit-type", stringValue: "title"))
        credit.addChild(element(
            "credit-words",
            stringValue: title,
            attributes: [
                "default-x": "600.17",
                "default-y": "1611.01",
                "justify": "center",
                "valign": "top",
                "font-size": "22"
            ]
        ))
        return credit
    }

    private func part(
        id: String,
        measures: [ScoreMeasure],
        tempoBPM: Double?,
        includesRegionLabels: Bool,
        includesHarmonies: Bool
    ) throws -> XMLElement {
        let part = element("part", attributes: ["id": id])
        var previousAttributes: MeasureAttributes?

        for (measureIndex, measure) in measures.enumerated() {
            let measureElement = element("measure", attributes: ["number": "\(measure.number)"])
            if previousAttributes == nil || previousAttributes != measure.attributes {
                measureElement.addChild(attributes(for: measure.attributes, includeDivisions: previousAttributes == nil))
            }

            if measureIndex == 0, let metronomeDirection = metronomeDirection(forBPM: tempoBPM) {
                measureElement.addChild(metronomeDirection)
            }

            if includesRegionLabels {
                for regionLabel in measure.regionLabels {
                    measureElement.addChild(regionDirection(for: regionLabel))
                }
            }

            let sortedHarmonies = includesHarmonies
                ? measure.harmonies.sorted(by: isHarmonyOrderedByNotationPosition)
                : []
            var harmonyIndex = sortedHarmonies.startIndex
            var notationCursorOffsetInQuarterNotes = 0.0
            let sortedItems = measure.notationItems.sorted(by: isNotationItemOrderedByNotationPosition)

            for item in sortedItems {
                let restStartOffsetInQuarterNotes = max(notationCursorOffsetInQuarterNotes, item.offsetInQuarterNotes)
                let restEndOffsetInQuarterNotes = restStartOffsetInQuarterNotes + max(0, item.durationInQuarterNotes)
                try addHarmoniesBeforeRestBoundary(
                    from: sortedHarmonies,
                    to: measureElement,
                    measureNumber: measure.number,
                    notationCursorOffsetInQuarterNotes: notationCursorOffsetInQuarterNotes,
                    restBoundaryOffsetInQuarterNotes: restEndOffsetInQuarterNotes,
                    includeBoundaryHarmony: false,
                    harmonyIndex: &harmonyIndex
                )
                measureElement.addChild(notationNote(for: item, isOnlyItem: sortedItems.count == 1))
                notationCursorOffsetInQuarterNotes = restEndOffsetInQuarterNotes
            }

            try addHarmoniesBeforeRestBoundary(
                from: sortedHarmonies,
                to: measureElement,
                measureNumber: measure.number,
                notationCursorOffsetInQuarterNotes: notationCursorOffsetInQuarterNotes,
                restBoundaryOffsetInQuarterNotes: .infinity,
                includeBoundaryHarmony: true,
                harmonyIndex: &harmonyIndex
            )

            part.addChild(measureElement)
            previousAttributes = measure.attributes
        }

        return part
    }

    private func isHarmonyOrderedByNotationPosition(_ lhs: HarmonySymbol, _ rhs: HarmonySymbol) -> Bool {
        if abs(lhs.offsetInQuarterNotes - rhs.offsetInQuarterNotes) > NotationMeasureTiming.timelineTolerance {
            return lhs.offsetInQuarterNotes < rhs.offsetInQuarterNotes
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func isNotationItemOrderedByNotationPosition(
        _ lhs: NotationMeasureItem,
        _ rhs: NotationMeasureItem
    ) -> Bool {
        if abs(lhs.offsetInQuarterNotes - rhs.offsetInQuarterNotes) > NotationMeasureTiming.timelineTolerance {
            return lhs.offsetInQuarterNotes < rhs.offsetInQuarterNotes
        }

        return lhs.id < rhs.id
    }

    private func addHarmoniesBeforeRestBoundary(
        from harmonies: [HarmonySymbol],
        to measureElement: XMLElement,
        measureNumber: Int,
        notationCursorOffsetInQuarterNotes: Double,
        restBoundaryOffsetInQuarterNotes: Double,
        includeBoundaryHarmony: Bool,
        harmonyIndex: inout Array<HarmonySymbol>.Index
    ) throws {
        while harmonyIndex < harmonies.endIndex {
            let harmony = harmonies[harmonyIndex]
            let isBeforeBoundary = harmony.offsetInQuarterNotes < restBoundaryOffsetInQuarterNotes - NotationMeasureTiming.timelineTolerance
            let isAtBoundary = abs(harmony.offsetInQuarterNotes - restBoundaryOffsetInQuarterNotes) <= NotationMeasureTiming.timelineTolerance
            guard isBeforeBoundary || (includeBoundaryHarmony && isAtBoundary) else { break }

            let chord = try MusicXMLChordParser.parse(harmony.rawText, measureNumber: measureNumber)
            measureElement.addChild(harmonyElement(
                for: chord,
                offsetInQuarterNotes: max(0, harmony.offsetInQuarterNotes - notationCursorOffsetInQuarterNotes)
            ))
            harmonyIndex = harmonies.index(after: harmonyIndex)
        }
    }

    private func attributes(for measureAttributes: MeasureAttributes, includeDivisions: Bool) -> XMLElement {
        let attributes = element("attributes")
        if includeDivisions {
            attributes.addChild(element("divisions", stringValue: "\(divisions)"))
        }

        let key = element("key")
        key.addChild(element("fifths", stringValue: "\(measureAttributes.keySignature.fifths)"))
        key.addChild(element("mode", stringValue: measureAttributes.keySignature.mode.rawValue))
        attributes.addChild(key)

        let time = element("time")
        time.addChild(element("beats", stringValue: "\(measureAttributes.timeSignature.beatsPerBar)"))
        time.addChild(element("beat-type", stringValue: "\(measureAttributes.timeSignature.beatUnit)"))
        attributes.addChild(time)

        let clef = element("clef")
        clef.addChild(element("sign", stringValue: measureAttributes.clef.sign))
        clef.addChild(element("line", stringValue: "\(measureAttributes.clef.line)"))
        attributes.addChild(clef)

        return attributes
    }

    private func metronomeDirection(forBPM bpm: Double?) -> XMLElement? {
        guard let bpm, bpm.isFinite, bpm > 0 else { return nil }

        let metronome = element("metronome")
        metronome.addChild(element("beat-unit", stringValue: "quarter"))
        metronome.addChild(element("per-minute", stringValue: TempoTimeSignatureMarkerPayload.formatBPM(bpm)))
        return direction(typeChild: metronome)
    }

    private func regionDirection(for label: NotationRegionLabel) -> XMLElement {
        direction(
            typeChild: element(
                "words",
                stringValue: label.title,
                attributes: [
                    "enclosure": "rectangle",
                    "font-weight": "bold"
                ]
            ),
            offsetInQuarterNotes: label.offsetInQuarterNotes
        )
    }

    private func direction(typeChild: XMLElement, offsetInQuarterNotes: Double? = nil) -> XMLElement {
        let direction = element("direction", attributes: ["placement": "above"])
        let directionType = element("direction-type")
        directionType.addChild(typeChild)
        direction.addChild(directionType)
        if let offsetInQuarterNotes {
            direction.addChild(element("offset", stringValue: "\(durationValue(forQuarterOffset: offsetInQuarterNotes))"))
        }
        return direction
    }

    private func harmonyElement(for chord: MusicXMLChord, offsetInQuarterNotes: Double) -> XMLElement {
        let harmony = element("harmony")

        harmony.addChild(pitchElement(
            "root",
            stepElementName: "root-step",
            alterElementName: "root-alter",
            pitch: chord.root
        ))

        harmony.addChild(element("kind", stringValue: chord.kindValue, attributes: ["text": chord.displayText]))

        for degree in chord.degrees {
            let degreeElement = element("degree")
            degreeElement.addChild(element("degree-value", stringValue: "\(degree.value)"))
            degreeElement.addChild(element("degree-alter", stringValue: "\(degree.alter)"))
            degreeElement.addChild(element("degree-type", stringValue: degree.type.rawValue))
            harmony.addChild(degreeElement)
        }

        if let bass = chord.bass {
            harmony.addChild(pitchElement(
                "bass",
                stepElementName: "bass-step",
                alterElementName: "bass-alter",
                pitch: bass
            ))
        }

        harmony.addChild(element("offset", stringValue: "\(durationValue(forQuarterOffset: offsetInQuarterNotes))"))
        return harmony
    }

    private func pitchElement(
        _ name: String,
        stepElementName: String,
        alterElementName: String,
        pitch: MusicXMLPitchStep
    ) -> XMLElement {
        let pitchElement = element(name)
        pitchElement.addChild(element(stepElementName, stringValue: pitch.step))
        if pitch.alter != 0 {
            pitchElement.addChild(element(alterElementName, stringValue: "\(pitch.alter)"))
        }
        return pitchElement
    }

    private func notationNote(for item: NotationMeasureItem, isOnlyItem: Bool) -> XMLElement {
        switch item.kind {
        case .rest:
            return restNote(for: item, isOnlyItem: isOnlyItem)
        case .note:
            return pitchNote(for: item)
        }
    }

    private func restNote(for item: NotationMeasureItem, isOnlyItem: Bool) -> XMLElement {
        let note = element("note")
        let isMeasureRest = isOnlyItem && item.isSynthesized && item.offsetInQuarterNotes == 0
        note.addChild(element("rest", attributes: isMeasureRest ? ["measure": "yes"] : [:]))
        note.addChild(element("duration", stringValue: "\(durationValue(forQuarterOffset: item.durationInQuarterNotes))"))
        note.addChild(element("voice", stringValue: "1"))
        note.addChild(element("type", stringValue: item.displayDuration.displayName))
        return note
    }

    private func pitchNote(for item: NotationMeasureItem) -> XMLElement {
        let note = element("note")
        let pitch = item.pitch ?? NotationPitch(step: .c, octave: 4)
        let pitchElement = element("pitch")
        pitchElement.addChild(element("step", stringValue: pitch.step.rawValue))
        if pitch.alter != 0 {
            pitchElement.addChild(element("alter", stringValue: "\(pitch.alter)"))
        }
        pitchElement.addChild(element("octave", stringValue: "\(pitch.octave)"))
        note.addChild(pitchElement)
        note.addChild(element("duration", stringValue: "\(durationValue(forQuarterOffset: item.durationInQuarterNotes))"))
        note.addChild(element("voice", stringValue: "1"))
        note.addChild(element("type", stringValue: item.displayDuration.displayName))
        return note
    }

    private func durationValue(forQuarterOffset offset: Double) -> Int {
        max(0, Int((offset * Double(divisions)).rounded()))
    }

    private func element(
        _ name: String,
        stringValue: String? = nil,
        attributes: [String: String] = [:]
    ) -> XMLElement {
        let element = XMLElement(name: name, stringValue: stringValue)
        for key in attributes.keys.sorted() {
            element.addAttribute(XMLNode.attribute(withName: key, stringValue: attributes[key] ?? "") as! XMLNode)
        }
        return element
    }

    private func insertMusicXMLDoctype(into xml: String) -> String {
        let doctype = "<!DOCTYPE score-partwise PUBLIC \"-//Recordare//DTD MusicXML 4.0 Partwise//EN\" \"http://www.musicxml.org/dtds/partwise.dtd\">"
        guard let firstLineEnd = xml.firstIndex(of: "\n") else {
            return "\(doctype)\n\(xml)"
        }

        let insertionIndex = xml.index(after: firstLineEnd)
        return String(xml[..<insertionIndex]) + doctype + "\n" + String(xml[insertionIndex...])
    }
}

struct MusicXMLChord: Equatable {
    var root: MusicXMLPitchStep
    var kindValue: String
    var displayText: String
    var degrees: [MusicXMLChordDegree]
    var bass: MusicXMLPitchStep?
}

struct MusicXMLPitchStep: Equatable {
    var step: String
    var alter: Int
}

struct MusicXMLChordDegree: Equatable {
    enum DegreeType: String, Equatable {
        case add
        case alter
        case subtract
    }

    var value: Int
    var alter: Int
    var type: DegreeType
}

enum MusicXMLChordParser {
    static func parse(_ rawText: String, measureNumber: Int) throws -> MusicXMLChord {
        let displayText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayText.isEmpty else {
            throw NotationExportError.unsupportedChord(rawText: rawText, measureNumber: measureNumber)
        }

        let normalized = displayText
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "∆", with: "maj")
            .replacingOccurrences(of: "Δ", with: "maj")
            .replacingOccurrences(of: "ø", with: "m7b5")
            .replacingOccurrences(of: "°", with: "dim")
            .replacingOccurrences(of: " ", with: "")

        let slashParts = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard slashParts.count <= 2, let chordPart = slashParts.first, !chordPart.isEmpty else {
            throw NotationExportError.unsupportedChord(rawText: displayText, measureNumber: measureNumber)
        }

        let parsedRoot = parsePitchPrefix(String(chordPart))
        guard let root = parsedRoot.pitch else {
            throw NotationExportError.unsupportedChord(rawText: displayText, measureNumber: measureNumber)
        }

        var suffix = String(chordPart.dropFirst(parsedRoot.length))
        var degrees: [MusicXMLChordDegree] = []
        guard extractParenthesizedDegrees(from: &suffix, into: &degrees) else {
            throw NotationExportError.unsupportedChord(rawText: displayText, measureNumber: measureNumber)
        }
        extractInlineDegrees(from: &suffix, into: &degrees)

        guard let kindValue = kindValue(for: suffix) else {
            throw NotationExportError.unsupportedChord(rawText: displayText, measureNumber: measureNumber)
        }

        let bass: MusicXMLPitchStep?
        if slashParts.count == 2 {
            let bassText = String(slashParts[1])
            let parsedBass = parsePitchPrefix(bassText)
            guard let parsedBassPitch = parsedBass.pitch, parsedBass.length == bassText.count else {
                throw NotationExportError.unsupportedChord(rawText: displayText, measureNumber: measureNumber)
            }
            bass = parsedBassPitch
        } else {
            bass = nil
        }

        return MusicXMLChord(
            root: root,
            kindValue: kindValue,
            displayText: displayText,
            degrees: degrees,
            bass: bass
        )
    }

    private static func parsePitchPrefix(_ text: String) -> (pitch: MusicXMLPitchStep?, length: Int) {
        guard let first = text.first else { return (nil, 0) }
        let step = String(first).uppercased()
        guard ["A", "B", "C", "D", "E", "F", "G"].contains(step) else {
            return (nil, 0)
        }

        let remaining = text.dropFirst()
        if remaining.first == "#" {
            return (MusicXMLPitchStep(step: step, alter: 1), 2)
        }
        if remaining.first == "b" {
            return (MusicXMLPitchStep(step: step, alter: -1), 2)
        }
        return (MusicXMLPitchStep(step: step, alter: 0), 1)
    }

    private static func extractParenthesizedDegrees(
        from suffix: inout String,
        into degrees: inout [MusicXMLChordDegree]
    ) -> Bool {
        while let open = suffix.firstIndex(of: "("),
              let close = suffix[open...].firstIndex(of: ")"),
              open < close {
            let content = suffix[suffix.index(after: open)..<close]
            guard parseDegreeList(String(content), into: &degrees) else {
                return false
            }
            suffix.removeSubrange(open...close)
        }
        return !suffix.contains("(") && !suffix.contains(")")
    }

    private static func extractInlineDegrees(
        from suffix: inout String,
        into degrees: inout [MusicXMLChordDegree]
    ) {
        if ["m7b5", "min7b5"].contains(suffix.lowercased()) {
            return
        }

        let tokens = ["add13", "add11", "add9", "no5", "no3", "#11", "b13", "#9", "b9", "#5", "b5"]
        var didRemove = true
        while didRemove {
            didRemove = false
            for token in tokens {
                if suffix.hasSuffix(token), let degree = degree(from: token) {
                    suffix.removeLast(token.count)
                    degrees.append(degree)
                    didRemove = true
                    break
                }
            }
        }
    }

    private static func parseDegreeList(_ text: String, into degrees: inout [MusicXMLChordDegree]) -> Bool {
        let tokens = text
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !tokens.isEmpty else { return false }

        for token in tokens {
            guard let degree = degree(from: token) else {
                return false
            }
            degrees.append(degree)
        }
        return true
    }

    private static func degree(from token: String) -> MusicXMLChordDegree? {
        let normalized = token.lowercased()
        if normalized.hasPrefix("add"),
           let value = Int(normalized.dropFirst(3)) {
            return MusicXMLChordDegree(value: value, alter: 0, type: .add)
        }
        if normalized.hasPrefix("no"),
           let value = Int(normalized.dropFirst(2)) {
            return MusicXMLChordDegree(value: value, alter: 0, type: .subtract)
        }
        if normalized.hasPrefix("#"),
           let value = Int(normalized.dropFirst()) {
            return MusicXMLChordDegree(value: value, alter: 1, type: .alter)
        }
        if normalized.hasPrefix("b"),
           let value = Int(normalized.dropFirst()) {
            return MusicXMLChordDegree(value: value, alter: -1, type: .alter)
        }
        return nil
    }

    private static func kindValue(for suffix: String) -> String? {
        let normalized = normalizedKindSuffix(suffix)
        let kindValues: [String: String] = [
            "": "major",
            "maj": "major",
            "m": "minor",
            "min": "minor",
            "-": "minor",
            "5": "power",
            "6": "major-sixth",
            "m6": "minor-sixth",
            "min6": "minor-sixth",
            "7": "dominant",
            "maj7": "major-seventh",
            "ma7": "major-seventh",
            "m7": "minor-seventh",
            "min7": "minor-seventh",
            "-7": "minor-seventh",
            "mmaj7": "minor-major-seventh",
            "mm7": "minor-major-seventh",
            "minmaj7": "minor-major-seventh",
            "minm7": "minor-major-seventh",
            "dim": "diminished",
            "o": "diminished",
            "dim7": "diminished-seventh",
            "o7": "diminished-seventh",
            "aug": "augmented",
            "+": "augmented",
            "sus": "suspended-fourth",
            "sus4": "suspended-fourth",
            "sus2": "suspended-second",
            "9": "dominant-ninth",
            "maj9": "major-ninth",
            "m9": "minor-ninth",
            "min9": "minor-ninth",
            "11": "dominant-11th",
            "m11": "minor-11th",
            "min11": "minor-11th",
            "13": "dominant-13th",
            "maj13": "major-13th",
            "m13": "minor-13th",
            "min13": "minor-13th",
            "m7b5": "half-diminished",
            "min7b5": "half-diminished"
        ]

        return kindValues[normalized]
    }

    private static func normalizedKindSuffix(_ suffix: String) -> String {
        if suffix.hasPrefix("M") {
            return "maj" + suffix.dropFirst().lowercased()
        }
        return suffix.lowercased()
    }
}
