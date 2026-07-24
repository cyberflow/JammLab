import Foundation

struct ScoreMeasure: Equatable, Identifiable {
    var number: Int
    var startTime: TimeInterval
    var endTime: TimeInterval
    var attributes: MeasureAttributes
    var notationItems: [NotationMeasureItem]
    var harmonies: [HarmonySymbol]
    var regionLabels: [NotationRegionLabel]

    init(
        number: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        attributes: MeasureAttributes,
        notationItems: [NotationMeasureItem] = [],
        harmonies: [HarmonySymbol] = [],
        regionLabels: [NotationRegionLabel] = []
    ) {
        self.number = number
        self.startTime = startTime
        self.endTime = endTime
        self.attributes = attributes
        self.notationItems = notationItems
        self.harmonies = harmonies
        self.regionLabels = regionLabels
    }

    var id: String {
        "\(number)-\(startTime)"
    }

    var duration: TimeInterval {
        max(0, endTime - startTime)
    }
}

struct NotationRegionLabel: Identifiable, Equatable {
    var id: UUID
    var time: TimeInterval
    var measureNumber: Int
    var offsetInQuarterNotes: Double
    var title: String

    init(
        id: UUID,
        time: TimeInterval,
        measureNumber: Int,
        offsetInQuarterNotes: Double,
        title: String
    ) {
        self.id = id
        self.time = time
        self.measureNumber = measureNumber
        self.offsetInQuarterNotes = offsetInQuarterNotes
        self.title = title
    }
}

struct NotationMeasureSelection: Equatable, Identifiable {
    var partID: NotationPartID
    var number: Int
    var startTime: TimeInterval
    var endTime: TimeInterval
    var attributes: MeasureAttributes

    init(measure: ScoreMeasure, partID: NotationPartID = .main) {
        self.partID = partID
        self.number = measure.number
        self.startTime = measure.startTime
        self.endTime = measure.endTime
        self.attributes = measure.attributes
    }

    var id: String {
        "\(partID.rawValue)-\(number)-\(startTime)-\(endTime)"
    }

    func matches(_ measure: ScoreMeasure) -> Bool {
        matches(measure, partID: partID)
    }

    func matches(_ measure: ScoreMeasure, partID: NotationPartID) -> Bool {
        self.partID == partID
            && number == measure.number
            && abs(startTime - measure.startTime) < NotationMeasureTiming.timelineTolerance
            && abs(endTime - measure.endTime) < NotationMeasureTiming.timelineTolerance
    }
}

struct NotationItemSelection: Equatable, Identifiable {
    var partID: NotationPartID
    var measureNumber: Int
    var measureStartTime: TimeInterval
    var measureEndTime: TimeInterval
    var attributes: MeasureAttributes
    var itemID: String
    var offsetInQuarterNotes: Double
    var durationInQuarterNotes: Double

    init(measure: ScoreMeasure, item: NotationMeasureItem, partID: NotationPartID? = nil) {
        self.partID = partID ?? item.partID
        self.measureNumber = measure.number
        self.measureStartTime = measure.startTime
        self.measureEndTime = measure.endTime
        self.attributes = measure.attributes
        self.itemID = item.id
        self.offsetInQuarterNotes = item.offsetInQuarterNotes
        self.durationInQuarterNotes = item.durationInQuarterNotes
    }

    var id: String {
        "\(partID.rawValue)-\(measureNumber)-\(measureStartTime)-\(measureEndTime)-\(itemID)-\(offsetInQuarterNotes)-\(durationInQuarterNotes)"
    }

    func matches(_ measure: ScoreMeasure, item: NotationMeasureItem) -> Bool {
        matches(NotationItemSelection(measure: measure, item: item))
    }

    func matches(_ candidate: NotationItemSelection) -> Bool {
        partID == candidate.partID
            && measureNumber == candidate.measureNumber
            && abs(measureStartTime - candidate.measureStartTime)
                < NotationMeasureTiming.timelineTolerance
            && abs(measureEndTime - candidate.measureEndTime)
                < NotationMeasureTiming.timelineTolerance
            && attributes == candidate.attributes
            && itemID == candidate.itemID
            && abs(offsetInQuarterNotes - candidate.offsetInQuarterNotes)
                < NotationMeasureTiming.timelineTolerance
            && abs(durationInQuarterNotes - candidate.durationInQuarterNotes)
                < NotationMeasureTiming.timelineTolerance
    }
}

struct NotationMeasureClipboard: Equatable {
    var measures: [NotationMeasureClipboardMeasure]
}

struct NotationMeasureClipboardMeasure: Equatable {
    var items: [NotationMeasureClipboardItem]
    var notationItems: [NotationMeasureClipboardNotationItem] = []
}

struct NotationMeasureClipboardItem: Equatable {
    var offsetInQuarterNotes: Double
    var rawText: String
}

struct NotationMeasureClipboardNotationItem: Equatable {
    var sourceItemID: String
    var kind: NotationMeasureItem.Kind = .rest
    var pitch: NotationPitch? = nil
    var explicitAccidental: NotationAccidental? = nil
    var offsetInQuarterNotes: Double
    var durationInQuarterNotes: Double
    var displayDuration: NotationDuration
    var tieTargetItemID: String? = nil
}

struct NotationPartID: Codable, Hashable, Identifiable, Equatable {
    var rawValue: String

    var id: String { rawValue }

    static let main = NotationPartID(rawValue: "main")

    static func stem(_ type: StemType) -> NotationPartID {
        NotationPartID(rawValue: "stem:\(type.rawValue)")
    }

    static func stemTranscription(_ type: StemType, trackID: UUID) -> NotationPartID {
        NotationPartID(rawValue: "transcription:\(type.rawValue):\(trackID.uuidString.lowercased())")
    }

    var stemType: StemType? {
        if rawValue.hasPrefix("stem:") {
            return StemType(rawValue: String(rawValue.dropFirst("stem:".count)))
        }
        guard rawValue.hasPrefix("transcription:") else { return nil }
        let components = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 3 else { return nil }
        return StemType(rawValue: String(components[1]))
    }

    var isMain: Bool {
        self == .main
    }
}

struct NotationPartDescriptor: Equatable, Identifiable {
    var id: NotationPartID
    var title: String
    var abbreviation: String
    var instrumentName: String
    var instrumentSound: String?

    static let main = make(
        id: .main,
        title: "Main",
        abbreviation: "Main"
    )

    static func stem(_ type: StemType) -> NotationPartDescriptor {
        switch type {
        case .vocals:
            return make(
                id: .stem(type),
                title: "Vocals",
                abbreviation: "Voc.",
                instrumentSound: "voice.vocals"
            )
        case .instrumental:
            return make(
                id: .stem(type),
                title: "Instrumental",
                abbreviation: "Instr."
            )
        case .drums:
            return make(
                id: .stem(type),
                title: "Drum Set",
                abbreviation: "Dr.",
                instrumentSound: "drum.group.set"
            )
        case .bass:
            return make(
                id: .stem(type),
                title: "Bass Guitar",
                abbreviation: "B. Guit.",
                instrumentSound: "pluck.bass"
            )
        case .other:
            return make(
                id: .stem(type),
                title: "Other",
                abbreviation: "Other"
            )
        case .guitar:
            return make(
                id: .stem(type),
                title: "Guitar",
                abbreviation: "Guit.",
                instrumentSound: "pluck.guitar"
            )
        case .piano:
            return make(
                id: .stem(type),
                title: "Piano",
                abbreviation: "Pno.",
                instrumentSound: "keyboard.piano"
            )
        }
    }

    static func stemTranscription(
        _ type: StemType,
        id: NotationPartID,
        sequence: Int
    ) -> NotationPartDescriptor {
        let base = stem(type)
        return NotationPartDescriptor(
            id: id,
            title: "\(base.title) Transcription \(sequence)",
            abbreviation: "\(base.abbreviation) T\(sequence)",
            instrumentName: base.instrumentName,
            instrumentSound: base.instrumentSound
        )
    }

    private static func make(
        id: NotationPartID,
        title: String,
        abbreviation: String,
        instrumentSound: String? = nil
    ) -> NotationPartDescriptor {
        NotationPartDescriptor(
            id: id,
            title: title,
            abbreviation: abbreviation,
            instrumentName: title,
            instrumentSound: instrumentSound
        )
    }
}

enum NotationMeasureTiming {
    static let timelineTolerance: TimeInterval = 0.000_001

    static func containsEventTime(_ time: TimeInterval, in measure: ScoreMeasure) -> Bool {
        time >= measure.startTime - timelineTolerance
            && (
                time < measure.endTime - timelineTolerance
                    || abs(time - measure.startTime) < timelineTolerance
            )
    }

    static func quarterOffset(for time: TimeInterval, in measure: ScoreMeasure) -> Double {
        let length = quarterLength(for: measure.attributes.timeSignature)
        guard measure.duration > 0, length > 0 else { return 0 }
        let progress = max(0, min((time - measure.startTime) / measure.duration, 1))
        return progress * length
    }

    static func time(forQuarterOffset offset: Double, in measure: ScoreMeasure) -> TimeInterval {
        let length = quarterLength(for: measure.attributes.timeSignature)
        guard measure.duration > 0, length > 0 else { return measure.startTime }
        let progress = max(0, min(offset / length, 1))
        return measure.startTime + progress * measure.duration
    }

    static func isValidHarmonyOffset(_ offset: Double, in timeSignature: TimeSignature) -> Bool {
        let length = quarterLength(for: timeSignature)
        return offset >= -timelineTolerance && offset < length - timelineTolerance
    }

    static func quarterLength(for timeSignature: TimeSignature) -> Double {
        Double(timeSignature.beatsPerBar) * 4.0 / Double(max(1, timeSignature.beatUnit))
    }
}

struct HarmonySymbol: Identifiable, Codable, Equatable {
    var id: UUID
    var time: TimeInterval
    var measureNumber: Int
    var offsetInQuarterNotes: Double
    var rawText: String

    init(
        id: UUID = UUID(),
        time: TimeInterval,
        measureNumber: Int,
        offsetInQuarterNotes: Double,
        rawText: String
    ) {
        self.id = id
        self.time = time
        self.measureNumber = measureNumber
        self.offsetInQuarterNotes = offsetInQuarterNotes
        self.rawText = rawText
    }
}

struct HarmonyEditorRequest: Equatable, Identifiable {
    var id = UUID()
    var time: TimeInterval
}

struct HarmonyPlacement: Equatable {
    var time: TimeInterval
    var measureNumber: Int
    var offsetInQuarterNotes: Double
}

enum HarmonyNavigationDirection: Equatable {
    case previous
    case next
}

struct NotationDuration: Codable, Equatable, Identifiable {
    static let entryDenominators = [1, 2, 4, 8, 16]
    static let restDecompositionDenominators = entryDenominators + [32]
    static let defaultDenominator = 1

    var denominator: Int
    var isDotted: Bool

    init(denominator: Int = Self.defaultDenominator, isDotted: Bool = false) {
        self.denominator = Self.restDecompositionDenominators.contains(denominator)
            ? denominator
            : Self.normalizedDenominator(denominator)
        self.isDotted = isDotted
    }

    var id: String { "\(denominator)-\(isDotted ? 1 : 0)" }

    var baseDurationInQuarterNotes: Double {
        4.0 / Double(denominator)
    }

    var durationInQuarterNotes: Double {
        baseDurationInQuarterNotes * (isDotted ? 1.5 : 1)
    }

    var displayName: String {
        switch denominator {
        case 1:
            return "whole"
        case 2:
            return "half"
        case 4:
            return "quarter"
        case 8:
            return "eighth"
        case 16:
            return "16th"
        case 32:
            return "32nd"
        default:
            return "duration"
        }
    }

    var humanDisplayName: String {
        isDotted ? "dotted \(displayName)" : displayName
    }

    var pluralDisplayName: String {
        "\(humanDisplayName) notes"
    }

    var capitalizedDisplayName: String {
        humanDisplayName.prefix(1).uppercased() + humanDisplayName.dropFirst()
    }

    static func normalizedDenominator(_ denominator: Int) -> Int {
        entryDenominators.min { lhs, rhs in
            abs(lhs - denominator) < abs(rhs - denominator)
        } ?? defaultDenominator
    }

    private enum CodingKeys: String, CodingKey {
        case denominator
        case isDotted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            denominator: try container.decodeIfPresent(Int.self, forKey: .denominator) ?? Self.defaultDenominator,
            isDotted: try container.decodeIfPresent(Bool.self, forKey: .isDotted) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(denominator, forKey: .denominator)
        if isDotted {
            try container.encode(true, forKey: .isDotted)
        }
    }
}

enum NotationAccidental: String, Codable, CaseIterable, Equatable {
    case flat
    case natural
    case sharp

    var alter: Int {
        switch self {
        case .flat: return -1
        case .natural: return 0
        case .sharp: return 1
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}

struct NotationMeasureItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, Equatable {
        case rest
        case note
    }

    var id: String
    var partID: NotationPartID
    var kind: Kind
    var pitch: NotationPitch?
    var explicitAccidental: NotationAccidental?
    var measureNumber: Int
    var measureStartTime: TimeInterval
    var offsetInQuarterNotes: Double
    var durationInQuarterNotes: Double
    var displayDuration: NotationDuration
    var tieTargetItemID: String?
    var isSynthesized: Bool

    init(
        id: String = UUID().uuidString,
        partID: NotationPartID = .main,
        kind: Kind = .rest,
        pitch: NotationPitch? = nil,
        explicitAccidental: NotationAccidental? = nil,
        measureNumber: Int,
        measureStartTime: TimeInterval,
        offsetInQuarterNotes: Double,
        durationInQuarterNotes: Double,
        displayDuration: NotationDuration,
        tieTargetItemID: String? = nil,
        isSynthesized: Bool = false
    ) {
        self.id = id
        self.partID = partID
        self.kind = kind
        if kind == .note, var pitch {
            if let explicitAccidental {
                pitch.alter = explicitAccidental.alter
            }
            self.pitch = pitch
        } else {
            self.pitch = nil
        }
        self.explicitAccidental = kind == .note ? explicitAccidental : nil
        self.measureNumber = measureNumber
        self.measureStartTime = measureStartTime
        self.offsetInQuarterNotes = offsetInQuarterNotes
        self.durationInQuarterNotes = durationInQuarterNotes
        self.displayDuration = displayDuration
        self.tieTargetItemID = kind == .note ? tieTargetItemID : nil
        self.isSynthesized = isSynthesized
    }

    func persistedCopy() -> NotationMeasureItem {
        NotationMeasureItem(
            id: isSynthesized ? UUID().uuidString : id,
            partID: partID,
            kind: kind,
            pitch: pitch,
            explicitAccidental: explicitAccidental,
            measureNumber: measureNumber,
            measureStartTime: measureStartTime,
            offsetInQuarterNotes: offsetInQuarterNotes,
            durationInQuarterNotes: durationInQuarterNotes,
            displayDuration: displayDuration,
            tieTargetItemID: tieTargetItemID
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case partID
        case kind
        case pitch
        case explicitAccidental
        case measureNumber
        case measureStartTime
        case offsetInQuarterNotes
        case durationInQuarterNotes
        case displayDuration
        case tieTargetItemID
        case isSynthesized
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        partID = try container.decodeIfPresent(NotationPartID.self, forKey: .partID) ?? .main
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .rest
        var decodedPitch = try container.decodeIfPresent(NotationPitch.self, forKey: .pitch)
        let decodedExplicitAccidental = kind == .note
            ? try container.decodeIfPresent(NotationAccidental.self, forKey: .explicitAccidental)
            : nil
        if let decodedExplicitAccidental {
            decodedPitch?.alter = decodedExplicitAccidental.alter
        }
        pitch = kind == .note ? decodedPitch : nil
        explicitAccidental = decodedExplicitAccidental
        measureNumber = try container.decode(Int.self, forKey: .measureNumber)
        measureStartTime = try container.decode(TimeInterval.self, forKey: .measureStartTime)
        offsetInQuarterNotes = try container.decode(Double.self, forKey: .offsetInQuarterNotes)
        durationInQuarterNotes = try container.decode(Double.self, forKey: .durationInQuarterNotes)
        displayDuration = try container.decode(NotationDuration.self, forKey: .displayDuration)
        let decodedTieTargetItemID = try container.decodeIfPresent(String.self, forKey: .tieTargetItemID)
        tieTargetItemID = kind == .note ? decodedTieTargetItemID : nil
        isSynthesized = try container.decodeIfPresent(Bool.self, forKey: .isSynthesized) ?? false
    }
}

enum NotationPitchStep: String, Codable, CaseIterable, Equatable {
    case c = "C"
    case d = "D"
    case e = "E"
    case f = "F"
    case g = "G"
    case a = "A"
    case b = "B"

    var diatonicIndex: Int {
        switch self {
        case .c: return 0
        case .d: return 1
        case .e: return 2
        case .f: return 3
        case .g: return 4
        case .a: return 5
        case .b: return 6
        }
    }
}

struct NotationPitch: Codable, Equatable {
    var step: NotationPitchStep
    var octave: Int
    var alter: Int

    init(step: NotationPitchStep, octave: Int, alter: Int = 0) {
        self.step = step
        self.octave = octave
        self.alter = min(1, max(-1, alter))
    }

    var midiNoteNumber: Int {
        let semitone: Int
        switch step {
        case .c:
            semitone = 0
        case .d:
            semitone = 2
        case .e:
            semitone = 4
        case .f:
            semitone = 5
        case .g:
            semitone = 7
        case .a:
            semitone = 9
        case .b:
            semitone = 11
        }

        return min(127, max(0, (octave + 1) * 12 + semitone + alter))
    }
}

enum DrumNoteheadStyle: String, Equatable {
    case normal
    case x
    case circleX
}

struct DrumInstrumentDefinition: Identifiable, Equatable {
    let midiNoteNumber: Int
    let name: String
    let staffPosition: Int
    let noteheadStyle: DrumNoteheadStyle
    let isPrimaryAtPosition: Bool

    var id: Int { midiNoteNumber }

    var displayPitch: NotationPitch {
        let ordinal = Clef.drums.notationMetrics.topLineDiatonicOrdinal - staffPosition
        let octave = Int(floor(Double(ordinal) / Double(NotationPitchStep.allCases.count)))
        let stepIndex = ordinal - octave * NotationPitchStep.allCases.count
        return NotationPitch(step: NotationPitchStep.allCases[stepIndex], octave: octave)
    }

    var pitchLabel: String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        let number = min(127, max(0, midiNoteNumber))
        return "\(names[number % 12])\(number / 12 - 1)"
    }
}

enum DrumInstrumentMap {
    static let defaultMIDINoteNumber = 36

    /// Palette order mirrors the two-row drum selector presented in the UI.
    static let instruments: [DrumInstrumentDefinition] = [
        instrument(36, "Bass Drum", 7, .normal, primary: true),
        instrument(38, "Snare", 3, .normal, primary: true),
        instrument(42, "Closed Hi-Hat", -1, .x, primary: true),
        instrument(46, "Open Hi-Hat", -1, .circleX, primary: false),
        instrument(49, "Crash Cymbal", -2, .x, primary: true),
        instrument(51, "Ride Cymbal", 0, .x, primary: true),
        instrument(50, "High Tom", 1, .normal, primary: true),
        instrument(41, "Floor Tom", 5, .normal, primary: true),
        instrument(35, "Bass Drum 2", 8, .normal, primary: true),
        instrument(37, "Cross-stick", 3, .x, primary: false),
        instrument(55, "Splash Cymbal", -4, .x, primary: true),
        instrument(44, "Pedal Hi-Hat", 9, .x, primary: true),
        instrument(57, "Crash Cymbal 2", -3, .x, primary: true),
        instrument(53, "Ride Bell", 0, .x, primary: false),
        instrument(47, "Low Tom", 2, .normal, primary: true),
        instrument(52, "China Cymbal", -3, .x, primary: false)
    ]

    static let allowedMIDINoteNumbers = Set(instruments.map(\.midiNoteNumber))

    private static let instrumentsByMIDINoteNumber = Dictionary(
        uniqueKeysWithValues: instruments.map { ($0.midiNoteNumber, $0) }
    )
    private static let primaryInstrumentsInStaffOrder = instruments
        .filter(\.isPrimaryAtPosition)
        .sorted { $0.staffPosition > $1.staffPosition }

    static var defaultInstrument: DrumInstrumentDefinition {
        instrument(forMIDINoteNumber: defaultMIDINoteNumber) ?? instruments[0]
    }

    static func instrument(forMIDINoteNumber midiNoteNumber: Int) -> DrumInstrumentDefinition? {
        instrumentsByMIDINoteNumber[midiNoteNumber]
    }

    static func nearestPrimaryInstrument(forStaffPosition staffPosition: Int) -> DrumInstrumentDefinition {
        primaryInstrumentsInStaffOrder.min {
            let lhsDistance = abs($0.staffPosition - staffPosition)
            let rhsDistance = abs($1.staffPosition - staffPosition)
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            return $0.staffPosition > $1.staffPosition
        } ?? defaultInstrument
    }

    static func adjacentPrimaryInstrument(
        from instrument: DrumInstrumentDefinition,
        staffPositionDelta: Int
    ) -> DrumInstrumentDefinition? {
        guard staffPositionDelta != 0 else { return nil }
        guard let sourceIndex = primaryInstrumentsInStaffOrder.firstIndex(where: {
            $0.staffPosition == instrument.staffPosition
        }) else {
            return nil
        }
        let targetIndex = sourceIndex + (staffPositionDelta < 0 ? 1 : -1)
        return primaryInstrumentsInStaffOrder.indices.contains(targetIndex)
            ? primaryInstrumentsInStaffOrder[targetIndex]
            : nil
    }

    private static func instrument(
        _ midiNoteNumber: Int,
        _ name: String,
        _ staffPosition: Int,
        _ noteheadStyle: DrumNoteheadStyle,
        primary: Bool
    ) -> DrumInstrumentDefinition {
        DrumInstrumentDefinition(
            midiNoteNumber: midiNoteNumber,
            name: name,
            staffPosition: staffPosition,
            noteheadStyle: noteheadStyle,
            isPrimaryAtPosition: primary
        )
    }
}

struct NotationNotePresentation: Equatable {
    let staffPosition: Int
    let noteheadStyle: DrumNoteheadStyle
}

enum NotationNotePresentationResolver {
    static func presentation(for pitch: NotationPitch, clef: Clef) -> NotationNotePresentation {
        if clef == .drums,
           let instrument = DrumInstrumentMap.instrument(forMIDINoteNumber: pitch.midiNoteNumber) {
            return NotationNotePresentation(
                staffPosition: instrument.staffPosition,
                noteheadStyle: instrument.noteheadStyle
            )
        }

        return NotationNotePresentation(
            staffPosition: NotationPitchMapper.pitchedStaffPosition(for: pitch, clef: clef),
            noteheadStyle: .normal
        )
    }
}

enum NotationInputPolicy {
    static func isEditableMIDINoteNumber(_ midiNoteNumber: Int, in clef: Clef) -> Bool {
        if clef == .drums {
            return DrumInstrumentMap.allowedMIDINoteNumbers.contains(midiNoteNumber)
        }
        return NotationPitchMapper.editableMIDINoteBounds(for: clef).contains(midiNoteNumber)
    }

    static func isEditable(_ pitch: NotationPitch, in clef: Clef) -> Bool {
        isEditableMIDINoteNumber(pitch.midiNoteNumber, in: clef)
    }
}

enum NotationPitchMapper {
    static var minimumStaffPosition: Int {
        Clef.treble.notationMetrics.editableStaffPositionRange.lowerBound
    }

    static var maximumStaffPosition: Int {
        Clef.treble.notationMetrics.editableStaffPositionRange.upperBound
    }

    static func editableStaffPositionRange(for clef: Clef) -> ClosedRange<Int> {
        clef.notationMetrics.editableStaffPositionRange
    }

    static func pitch(
        forStaffPosition staffPosition: Int,
        keySignature: KeySignature,
        clef: Clef = .treble
    ) -> NotationPitch {
        if clef == .drums {
            let instrument = DrumInstrumentMap.nearestPrimaryInstrument(forStaffPosition: staffPosition)
            return pitch(forMIDINoteNumber: instrument.midiNoteNumber, keySignature: .cMajor)
        }
        let range = editableStaffPositionRange(for: clef)
        let clampedPosition = min(range.upperBound, max(range.lowerBound, staffPosition))
        let ordinal = clef.notationMetrics.topLineDiatonicOrdinal - clampedPosition
        let octave = Int(floor(Double(ordinal) / Double(NotationPitchStep.allCases.count)))
        let stepIndex = ordinal - octave * NotationPitchStep.allCases.count
        var pitch = NotationPitch(
            step: NotationPitchStep.allCases[stepIndex],
            octave: octave
        )
        pitch.alter = keySignature.defaultAlter(for: pitch.step)
        return pitch
    }

    static func staffPosition(for pitch: NotationPitch, clef: Clef = .treble) -> Int {
        NotationNotePresentationResolver.presentation(for: pitch, clef: clef).staffPosition
    }

    static func pitchedStaffPosition(for pitch: NotationPitch, clef: Clef = .treble) -> Int {
        let ordinal = pitch.octave * NotationPitchStep.allCases.count + pitch.step.diatonicIndex
        return clef.notationMetrics.topLineDiatonicOrdinal - ordinal
    }

    static func adjacentPitch(
        from pitch: NotationPitch,
        staffPositionDelta: Int,
        keySignature: KeySignature,
        clef: Clef = .treble
    ) -> NotationPitch? {
        guard staffPositionDelta != 0 else { return nil }

        if clef == .drums {
            guard let instrument = DrumInstrumentMap.instrument(forMIDINoteNumber: pitch.midiNoteNumber),
                  let adjacent = DrumInstrumentMap.adjacentPrimaryInstrument(
                    from: instrument,
                    staffPositionDelta: staffPositionDelta
                  )
            else { return nil }
            return self.pitch(forMIDINoteNumber: adjacent.midiNoteNumber, keySignature: .cMajor)
        }

        let currentPosition = staffPosition(for: pitch, clef: clef)
        let targetPosition = currentPosition + staffPositionDelta
        let range = editableStaffPositionRange(for: clef)
        guard range.contains(targetPosition)
        else {
            return nil
        }

        return self.pitch(
            forStaffPosition: targetPosition,
            keySignature: keySignature,
            clef: clef
        )
    }

    static func pitch(
        forMIDINoteNumber midiNoteNumber: Int,
        keySignature: KeySignature
    ) -> NotationPitch {
        let clampedNumber = min(127, max(0, midiNoteNumber))
        let pitchClass = clampedNumber % 12
        let octave = clampedNumber / 12 - 1
        let usesFlats = keySignature.fifths < 0
        let spelling: (NotationPitchStep, Int)

        switch pitchClass {
        case 0: spelling = (.c, 0)
        case 1: spelling = usesFlats ? (.d, -1) : (.c, 1)
        case 2: spelling = (.d, 0)
        case 3: spelling = usesFlats ? (.e, -1) : (.d, 1)
        case 4: spelling = (.e, 0)
        case 5: spelling = (.f, 0)
        case 6: spelling = usesFlats ? (.g, -1) : (.f, 1)
        case 7: spelling = (.g, 0)
        case 8: spelling = usesFlats ? (.a, -1) : (.g, 1)
        case 9: spelling = (.a, 0)
        case 10: spelling = usesFlats ? (.b, -1) : (.a, 1)
        default: spelling = (.b, 0)
        }

        return NotationPitch(step: spelling.0, octave: octave, alter: spelling.1)
    }

    static func isEditable(_ pitch: NotationPitch, in clef: Clef) -> Bool {
        NotationInputPolicy.isEditable(pitch, in: clef)
    }

    static func editableMIDINoteBounds(for clef: Clef) -> ClosedRange<Int> {
        if clef == .drums {
            let values = DrumInstrumentMap.allowedMIDINoteNumbers
            return (values.min() ?? 0)...(values.max() ?? 0)
        }
        let staffRange = editableStaffPositionRange(for: clef)
        let first = pitch(
            forStaffPosition: staffRange.lowerBound,
            keySignature: .cMajor,
            clef: clef
        ).midiNoteNumber
        let last = pitch(
            forStaffPosition: staffRange.upperBound,
            keySignature: .cMajor,
            clef: clef
        ).midiNoteNumber
        return min(first, last)...max(first, last)
    }
}

enum NotationRestItemFactory {
    struct Segment: Equatable {
        var offsetInQuarterNotes: Double
        var durationInQuarterNotes: Double
        var displayDuration: NotationDuration
        var isTail: Bool
    }

    static func greedySegments(
        startOffset: Double,
        remaining: Double,
        includeTail: Bool = false,
        tolerance: Double = NotationMeasureTiming.timelineTolerance
    ) -> [Segment] {
        var segments: [Segment] = []
        var cursor = startOffset
        var rest = remaining
        for denominator in NotationDuration.restDecompositionDenominators {
            let duration = NotationDuration(denominator: denominator)
            let length = duration.durationInQuarterNotes
            while rest >= length - tolerance {
                segments.append(Segment(
                    offsetInQuarterNotes: cursor,
                    durationInQuarterNotes: min(length, rest),
                    displayDuration: duration,
                    isTail: false
                ))
                cursor += length
                rest -= length
            }
        }

        if includeTail, rest > tolerance {
            let duration = NotationDuration(denominator: NotationDuration.entryDenominators.last ?? 8)
            segments.append(Segment(
                offsetInQuarterNotes: cursor,
                durationInQuarterNotes: rest,
                displayDuration: duration,
                isTail: true
            ))
        }

        return segments
    }

    static func restItems(
        measureNumber: Int,
        measureStartTime: TimeInterval,
        startOffset: Double,
        remaining: Double,
        partID: NotationPartID = .main,
        isSynthesized: Bool = false,
        includeTail: Bool = false,
        id: (Segment) -> String? = { _ in nil }
    ) -> [NotationMeasureItem] {
        greedySegments(startOffset: startOffset, remaining: remaining, includeTail: includeTail)
            .map { segment in
                restItem(
                    id: id(segment),
                    partID: partID,
                    measureNumber: measureNumber,
                    measureStartTime: measureStartTime,
                    offsetInQuarterNotes: segment.offsetInQuarterNotes,
                    durationInQuarterNotes: segment.durationInQuarterNotes,
                    displayDuration: segment.displayDuration,
                    isSynthesized: isSynthesized
                )
            }
    }

    static func metricAwareRestItems(
        in measure: ScoreMeasure,
        partID: NotationPartID,
        startOffset: Double,
        remaining: Double
    ) -> [NotationMeasureItem] {
        guard remaining > NotationMeasureTiming.timelineTolerance else { return [] }

        var output: [NotationMeasureItem] = []
        var cursor = startOffset
        var rest = remaining
        let nextQuarterBoundary = floor(cursor + NotationMeasureTiming.timelineTolerance) + 1
        let distanceToQuarterBoundary = nextQuarterBoundary - cursor
        let isOnQuarterBoundary = abs(cursor.rounded() - cursor) <= NotationMeasureTiming.timelineTolerance

        if !isOnQuarterBoundary,
           distanceToQuarterBoundary > NotationMeasureTiming.timelineTolerance,
           distanceToQuarterBoundary < rest - NotationMeasureTiming.timelineTolerance,
           let duration = exactDuration(for: distanceToQuarterBoundary) {
            output.append(restItem(
                partID: partID,
                measureNumber: measure.number,
                measureStartTime: measure.startTime,
                offsetInQuarterNotes: cursor,
                durationInQuarterNotes: distanceToQuarterBoundary,
                displayDuration: duration
            ))
            cursor += distanceToQuarterBoundary
            rest -= distanceToQuarterBoundary
        }

        output.append(contentsOf: restItems(
            measureNumber: measure.number,
            measureStartTime: measure.startTime,
            startOffset: cursor,
            remaining: rest,
            partID: partID
        ))
        return output
    }

    private static func exactDuration(for length: Double) -> NotationDuration? {
        restDecompositionDurations.first {
            abs($0.durationInQuarterNotes - length) <= NotationMeasureTiming.timelineTolerance
        }
    }

    private static var restDecompositionDurations: [NotationDuration] {
        NotationDuration.restDecompositionDenominators.map {
            NotationDuration(denominator: $0)
        }
    }

    static func restItem(
        id: String? = nil,
        partID: NotationPartID = .main,
        measureNumber: Int,
        measureStartTime: TimeInterval,
        offsetInQuarterNotes: Double,
        durationInQuarterNotes: Double,
        displayDuration: NotationDuration,
        isSynthesized: Bool = false
    ) -> NotationMeasureItem {
        if let id {
            return NotationMeasureItem(
                id: id,
                partID: partID,
                measureNumber: measureNumber,
                measureStartTime: measureStartTime,
                offsetInQuarterNotes: offsetInQuarterNotes,
                durationInQuarterNotes: durationInQuarterNotes,
                displayDuration: displayDuration,
                isSynthesized: isSynthesized
            )
        }

        return NotationMeasureItem(
            partID: partID,
            measureNumber: measureNumber,
            measureStartTime: measureStartTime,
            offsetInQuarterNotes: offsetInQuarterNotes,
            durationInQuarterNotes: durationInQuarterNotes,
            displayDuration: displayDuration,
            isSynthesized: isSynthesized
        )
    }
}

struct NotationTimeSpan: Equatable {
    var start: Double
    var end: Double

    var duration: Double {
        max(0, end - start)
    }

    func contains(_ span: NotationTimeSpan) -> Bool {
        span.start >= start - NotationMeasureTiming.timelineTolerance
            && span.end <= end + NotationMeasureTiming.timelineTolerance
    }

    func overlaps(_ span: NotationTimeSpan) -> Bool {
        start < span.end - NotationMeasureTiming.timelineTolerance
            && end > span.start + NotationMeasureTiming.timelineTolerance
    }
}

enum NotationMeasureRhythmRecomposer {
    static func projectedItems(
        in measure: ScoreMeasure,
        partID: NotationPartID,
        items: [NotationMeasureItem]
    ) -> [NotationMeasureItem] {
        recomposedItems(
            in: measure,
            partID: partID,
            notes: items,
            preferredRests: items,
            generatedRestsAreSynthesized: true
        )
    }

    static func persistedItems(
        in measure: ScoreMeasure,
        partID: NotationPartID,
        notes: [NotationMeasureItem],
        preferredRests: [NotationMeasureItem]
    ) -> [NotationMeasureItem] {
        recomposedItems(
            in: measure,
            partID: partID,
            notes: notes,
            preferredRests: preferredRests,
            generatedRestsAreSynthesized: false
        )
    }

    static func occupiedSpans(
        in measure: ScoreMeasure,
        partID: NotationPartID,
        items: [NotationMeasureItem]
    ) -> [NotationTimeSpan] {
        let measureLength = NotationMeasureTiming.quarterLength(
            for: measure.attributes.timeSignature
        )
        guard measureLength > NotationMeasureTiming.timelineTolerance else { return [] }

        let spans = items.compactMap { item -> NotationTimeSpan? in
            guard item.partID == partID,
                  item.kind == .note,
                  item.pitch != nil,
                  item.offsetInQuarterNotes.isFinite,
                  item.durationInQuarterNotes.isFinite
            else { return nil }
            let start = min(measureLength, max(0, item.offsetInQuarterNotes))
            let end = min(
                measureLength,
                max(start, item.offsetInQuarterNotes + item.durationInQuarterNotes)
            )
            guard end > start + NotationMeasureTiming.timelineTolerance else { return nil }
            return NotationTimeSpan(start: start, end: end)
        }
        .sorted {
            if abs($0.start - $1.start) > NotationMeasureTiming.timelineTolerance {
                return $0.start < $1.start
            }
            return $0.end < $1.end
        }

        var merged: [NotationTimeSpan] = []
        for span in spans {
            guard let lastIndex = merged.indices.last else {
                merged.append(span)
                continue
            }
            if span.start <= merged[lastIndex].end + NotationMeasureTiming.timelineTolerance {
                merged[lastIndex].end = max(merged[lastIndex].end, span.end)
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    static func silentSpans(
        in measure: ScoreMeasure,
        partID: NotationPartID,
        items: [NotationMeasureItem]
    ) -> [NotationTimeSpan] {
        let measureLength = NotationMeasureTiming.quarterLength(
            for: measure.attributes.timeSignature
        )
        guard measureLength > NotationMeasureTiming.timelineTolerance else { return [] }

        var output: [NotationTimeSpan] = []
        var cursor = 0.0
        for occupied in occupiedSpans(in: measure, partID: partID, items: items) {
            if occupied.start > cursor + NotationMeasureTiming.timelineTolerance {
                output.append(NotationTimeSpan(start: cursor, end: occupied.start))
            }
            cursor = max(cursor, occupied.end)
        }
        if cursor < measureLength - NotationMeasureTiming.timelineTolerance {
            output.append(NotationTimeSpan(start: cursor, end: measureLength))
        }
        return output
    }

    static func isSilent(
        _ span: NotationTimeSpan,
        in measure: ScoreMeasure,
        partID: NotationPartID,
        items: [NotationMeasureItem]
    ) -> Bool {
        silentSpans(in: measure, partID: partID, items: items).contains { $0.contains(span) }
    }

    static func itemSort(_ lhs: NotationMeasureItem, _ rhs: NotationMeasureItem) -> Bool {
        if abs(lhs.offsetInQuarterNotes - rhs.offsetInQuarterNotes)
            > NotationMeasureTiming.timelineTolerance {
            return lhs.offsetInQuarterNotes < rhs.offsetInQuarterNotes
        }
        if lhs.kind != rhs.kind {
            return lhs.kind == .note
        }
        if lhs.kind == .note,
           let lhsPitch = lhs.pitch,
           let rhsPitch = rhs.pitch,
           lhsPitch.midiNoteNumber != rhsPitch.midiNoteNumber {
            return lhsPitch.midiNoteNumber < rhsPitch.midiNoteNumber
        }
        if abs(lhs.durationInQuarterNotes - rhs.durationInQuarterNotes)
            > NotationMeasureTiming.timelineTolerance {
            return lhs.durationInQuarterNotes > rhs.durationInQuarterNotes
        }
        return lhs.id < rhs.id
    }

    private static func recomposedItems(
        in measure: ScoreMeasure,
        partID: NotationPartID,
        notes sourceNotes: [NotationMeasureItem],
        preferredRests sourceRests: [NotationMeasureItem],
        generatedRestsAreSynthesized: Bool
    ) -> [NotationMeasureItem] {
        let measureLength = NotationMeasureTiming.quarterLength(
            for: measure.attributes.timeSignature
        )
        guard measureLength > NotationMeasureTiming.timelineTolerance else { return [] }

        let notes = sourceNotes.compactMap { item -> NotationMeasureItem? in
            guard item.partID == partID,
                  item.kind == .note,
                  item.pitch != nil,
                  item.offsetInQuarterNotes.isFinite,
                  item.durationInQuarterNotes.isFinite
            else { return nil }
            let start = min(measureLength, max(0, item.offsetInQuarterNotes))
            let end = min(
                measureLength,
                max(start, item.offsetInQuarterNotes + item.durationInQuarterNotes)
            )
            guard end > start + NotationMeasureTiming.timelineTolerance else { return nil }
            var copy = item.persistedCopy()
            copy.partID = partID
            copy.measureNumber = measure.number
            copy.measureStartTime = measure.startTime
            copy.offsetInQuarterNotes = start
            copy.durationInQuarterNotes = end - start
            return copy
        }

        let silent = silentSpans(in: measure, partID: partID, items: notes)
        if notes.isEmpty,
           !sourceRests.contains(where: { $0.partID == partID && $0.kind == .rest && !$0.isSynthesized }) {
            return [NotationRestItemFactory.restItem(
                id: generatedRestsAreSynthesized
                    ? "default-rest-\(partID.rawValue)-\(measure.number)-\(measure.startTime)-\(measure.endTime)"
                    : nil,
                partID: partID,
                measureNumber: measure.number,
                measureStartTime: measure.startTime,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: measureLength,
                displayDuration: NotationDuration(denominator: NotationDuration.defaultDenominator),
                isSynthesized: generatedRestsAreSynthesized
            )]
        }

        let preferred = sourceRests
            .filter { $0.partID == partID && $0.kind == .rest && !$0.isSynthesized }
            .compactMap { item -> (NotationMeasureItem, NotationTimeSpan)? in
                guard item.offsetInQuarterNotes.isFinite,
                      item.durationInQuarterNotes.isFinite
                else { return nil }
                let start = min(measureLength, max(0, item.offsetInQuarterNotes))
                let end = min(
                    measureLength,
                    max(start, item.offsetInQuarterNotes + item.durationInQuarterNotes)
                )
                guard end > start + NotationMeasureTiming.timelineTolerance else { return nil }
                var copy = item.persistedCopy()
                copy.partID = partID
                copy.measureNumber = measure.number
                copy.measureStartTime = measure.startTime
                copy.offsetInQuarterNotes = start
                copy.durationInQuarterNotes = end - start
                return (copy, NotationTimeSpan(start: start, end: end))
            }
            .sorted {
                if abs($0.1.start - $1.1.start) > NotationMeasureTiming.timelineTolerance {
                    return $0.1.start < $1.1.start
                }
                return $0.0.id < $1.0.id
            }

        var accepted: [(NotationMeasureItem, NotationTimeSpan)] = []
        for candidate in preferred {
            guard silent.contains(where: { $0.contains(candidate.1) }),
                  !accepted.contains(where: { $0.1.overlaps(candidate.1) })
            else { continue }
            accepted.append(candidate)
        }

        var rests: [NotationMeasureItem] = accepted.map(\.0)
        for silentSpan in silent {
            let contained = accepted
                .filter { silentSpan.contains($0.1) }
                .sorted { $0.1.start < $1.1.start }
            var cursor = silentSpan.start
            for entry in contained {
                rests.append(contentsOf: fillerItems(
                    in: measure,
                    partID: partID,
                    start: cursor,
                    end: entry.1.start,
                    synthesized: generatedRestsAreSynthesized
                ))
                cursor = max(cursor, entry.1.end)
            }
            rests.append(contentsOf: fillerItems(
                in: measure,
                partID: partID,
                start: cursor,
                end: silentSpan.end,
                synthesized: generatedRestsAreSynthesized
            ))
        }

        return (notes + rests).sorted(by: itemSort)
    }

    private static func fillerItems(
        in measure: ScoreMeasure,
        partID: NotationPartID,
        start: Double,
        end: Double,
        synthesized: Bool
    ) -> [NotationMeasureItem] {
        let remaining = end - start
        guard remaining > NotationMeasureTiming.timelineTolerance else { return [] }
        return NotationRestItemFactory.metricAwareRestItems(
            in: measure,
            partID: partID,
            startOffset: start,
            remaining: remaining
        ).map { item in
            var copy = item
            copy.isSynthesized = synthesized
            if synthesized {
                copy.id = "fill-rest-\(partID.rawValue)-\(measure.number)-\(measure.startTime)-\(copy.offsetInQuarterNotes)-\(copy.durationInQuarterNotes)"
            }
            return copy
        }
    }
}

struct MeasureAttributes: Equatable {
    var keySignature: KeySignature
    var timeSignature: TimeSignature
    var clef: Clef

    static let defaultTreble = MeasureAttributes(
        keySignature: .cMajor,
        timeSignature: .fourFour,
        clef: .treble
    )
}

struct KeySignatureAccidental: Equatable {
    var symbol: String
    var staffPositionFromTopLine: Int
}

struct KeySignature: Equatable {
    enum Mode: String, Codable, CaseIterable, Equatable {
        case major
        case minor

        var displayName: String {
            switch self {
            case .major: return "Major"
            case .minor: return "Minor"
            }
        }
    }

    var fifths: Int
    var mode: Mode
    var displayName: String

    static let cMajor = KeySignature(fifths: 0, mode: .major, displayName: "C major")

    var accidentalCount: Int {
        abs(fifths)
    }

    func notationAccidentalGlyphs(for clef: Clef) -> [KeySignatureAccidental] {
        guard clef != .drums else { return [] }
        let source: ArraySlice<KeySignatureAccidental>
        if fifths > 0 {
            source = Self.trebleSharpAccidentals.prefix(accidentalCount)
        } else if fifths < 0 {
            source = Self.trebleFlatAccidentals.prefix(accidentalCount)
        } else {
            return []
        }

        let positionOffset = clef.notationMetrics.keySignatureStaffPositionOffset
        return source.map { accidental in
            KeySignatureAccidental(
                symbol: accidental.symbol,
                staffPositionFromTopLine: accidental.staffPositionFromTopLine + positionOffset
            )
        }
    }

    func defaultAlter(for step: NotationPitchStep) -> Int {
        if fifths > 0 {
            return Self.sharpSteps.prefix(accidentalCount).contains(step) ? 1 : 0
        }

        if fifths < 0 {
            return Self.flatSteps.prefix(accidentalCount).contains(step) ? -1 : 0
        }

        return 0
    }

    static func normalized(from keyName: String?) -> KeySignature {
        guard let keyName else { return .cMajor }

        let normalized = keyName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "Major", with: "major")
            .replacingOccurrences(of: "Minor", with: "minor")
            .replacingOccurrences(of: "MAJOR", with: "major")
            .replacingOccurrences(of: "MINOR", with: "minor")

        guard !normalized.isEmpty else { return .cMajor }

        let lowercased = normalized.lowercased()
        if lowercased == "pending" || lowercased == "unknown" {
            return .cMajor
        }

        let mode: Mode
        var tonic = normalized
        if lowercased.hasSuffix(" major") {
            mode = .major
            tonic = String(normalized.dropLast(" major".count))
        } else if lowercased.hasSuffix(" minor") {
            mode = .minor
            tonic = String(normalized.dropLast(" minor".count))
        } else if lowercased.hasSuffix(" maj") {
            mode = .major
            tonic = String(normalized.dropLast(" maj".count))
        } else if lowercased.hasSuffix(" min") {
            mode = .minor
            tonic = String(normalized.dropLast(" min".count))
        } else if lowercased.hasSuffix("m"), normalized.count > 1 {
            mode = .minor
            tonic = String(normalized.dropLast())
        } else {
            mode = .major
        }

        tonic = tonic.trimmingCharacters(in: .whitespacesAndNewlines)
        let lookup = normalizedTonic(tonic)
        let fifths: Int?
        switch mode {
        case .major:
            fifths = majorFifths[lookup]
        case .minor:
            fifths = minorFifths[lookup]
        }

        guard let fifths else { return .cMajor }

        return KeySignature(
            fifths: fifths,
            mode: mode,
            displayName: "\(displayTonic(lookup)) \(mode.rawValue)"
        )
    }

    private static func normalizedTonic(_ tonic: String) -> String {
        let compact = tonic.replacingOccurrences(of: " ", with: "")
        guard let first = compact.first else { return compact }
        return first.uppercased() + compact.dropFirst()
    }

    private static func displayTonic(_ tonic: String) -> String {
        tonic
            .replacingOccurrences(of: "#", with: "♯")
            .replacingOccurrences(of: "b", with: "♭")
    }

    private static let majorFifths: [String: Int] = [
        "Cb": -7, "Gb": -6, "Db": -5, "Ab": -4, "Eb": -3, "Bb": -2, "F": -1,
        "C": 0,
        "G": 1, "D": 2, "A": 3, "E": 4, "B": 5, "F#": 6, "C#": 7
    ]

    private static let minorFifths: [String: Int] = [
        "Ab": -7, "Eb": -6, "Bb": -5, "F": -4, "C": -3, "G": -2, "D": -1,
        "A": 0,
        "E": 1, "B": 2, "F#": 3, "C#": 4, "G#": 5, "D#": 6, "A#": 7
    ]

    private static let sharpSteps: [NotationPitchStep] = [.f, .c, .g, .d, .a, .e, .b]
    private static let flatSteps: [NotationPitchStep] = [.b, .e, .a, .d, .g, .c, .f]

    private static let trebleSharpAccidentals: [KeySignatureAccidental] = [
        KeySignatureAccidental(symbol: "♯", staffPositionFromTopLine: 0),
        KeySignatureAccidental(symbol: "♯", staffPositionFromTopLine: 3),
        KeySignatureAccidental(symbol: "♯", staffPositionFromTopLine: -1),
        KeySignatureAccidental(symbol: "♯", staffPositionFromTopLine: 2),
        KeySignatureAccidental(symbol: "♯", staffPositionFromTopLine: 5),
        KeySignatureAccidental(symbol: "♯", staffPositionFromTopLine: 1),
        KeySignatureAccidental(symbol: "♯", staffPositionFromTopLine: 4)
    ]

    private static let trebleFlatAccidentals: [KeySignatureAccidental] = [
        KeySignatureAccidental(symbol: "♭", staffPositionFromTopLine: 4),
        KeySignatureAccidental(symbol: "♭", staffPositionFromTopLine: 1),
        KeySignatureAccidental(symbol: "♭", staffPositionFromTopLine: 5),
        KeySignatureAccidental(symbol: "♭", staffPositionFromTopLine: 2),
        KeySignatureAccidental(symbol: "♭", staffPositionFromTopLine: 6),
        KeySignatureAccidental(symbol: "♭", staffPositionFromTopLine: 3),
        KeySignatureAccidental(symbol: "♭", staffPositionFromTopLine: 7)
    ]
}

struct NotationClefMetrics: Equatable {
    let editableStaffPositionRange: ClosedRange<Int>
    let topLineDiatonicOrdinal: Int
    let keySignatureStaffPositionOffset: Int
    let storedPitchOctaveOffset: Int
}

enum Clef: String, Codable, CaseIterable, Identifiable, Equatable {
    case treble
    case bass
    case bass8
    case drums

    var id: String { rawValue }

    var sign: String {
        switch self {
        case .treble: return "G"
        case .bass, .bass8: return "F"
        case .drums: return "percussion"
        }
    }

    var line: Int? {
        switch self {
        case .treble: return 2
        case .bass, .bass8: return 4
        case .drums: return nil
        }
    }

    var displayName: String {
        switch self {
        case .treble: return "Treble Clef"
        case .bass: return "Bass Clef"
        case .bass8: return "Bass 8 Clef"
        case .drums: return "Drum Clef"
        }
    }

    var musicXMLOctaveChange: Int? {
        self == .bass8 ? -1 : nil
    }

    var notationMetrics: NotationClefMetrics {
        switch self {
        case .treble:
            return NotationClefMetrics(
                editableStaffPositionRange: -5...13,
                topLineDiatonicOrdinal: 5 * NotationPitchStep.allCases.count + NotationPitchStep.f.diatonicIndex,
                keySignatureStaffPositionOffset: 0,
                storedPitchOctaveOffset: 0
            )
        case .bass:
            return NotationClefMetrics(
                editableStaffPositionRange: -3...15,
                topLineDiatonicOrdinal: 3 * NotationPitchStep.allCases.count + NotationPitchStep.a.diatonicIndex,
                keySignatureStaffPositionOffset: 2,
                storedPitchOctaveOffset: -2
            )
        case .bass8:
            return NotationClefMetrics(
                editableStaffPositionRange: -3...15,
                topLineDiatonicOrdinal: 2 * NotationPitchStep.allCases.count + NotationPitchStep.a.diatonicIndex,
                keySignatureStaffPositionOffset: 2,
                storedPitchOctaveOffset: -3
            )
        case .drums:
            return NotationClefMetrics(
                editableStaffPositionRange: -4...9,
                topLineDiatonicOrdinal: 5 * NotationPitchStep.allCases.count + NotationPitchStep.f.diatonicIndex,
                keySignatureStaffPositionOffset: 0,
                storedPitchOctaveOffset: 0
            )
        }
    }
}

enum NotationPartClefOverrides {
    private static let drumDefaultClefProjectFormatVersion = 14
    private static let bass8DefaultClefProjectFormatVersion = 16

    static func normalized(_ overrides: [NotationPartID: Clef]) -> [NotationPartID: Clef] {
        overrides.filter { $0.value != defaultClef(for: $0.key) }
    }

    static func clef(
        for partID: NotationPartID,
        in overrides: [NotationPartID: Clef]
    ) -> Clef {
        overrides[partID] ?? defaultClef(for: partID)
    }

    static func defaultClef(for partID: NotationPartID) -> Clef {
        if partID.stemType == .drums {
            return .drums
        }
        if partID.stemType == .bass {
            return .bass8
        }
        return .treble
    }

    static func restored(
        _ overrides: [NotationPartID: Clef],
        projectFormatVersion: Int,
        hasLegacyDrumNotationEvidence: Bool,
        legacyBassPartIDs: Set<NotationPartID>
    ) -> [NotationPartID: Clef] {
        var restored = overrides
        let drumPartID = NotationPartID.stem(.drums)
        if projectFormatVersion < drumDefaultClefProjectFormatVersion,
           restored[drumPartID] == nil,
           hasLegacyDrumNotationEvidence {
            restored[drumPartID] = .treble
        }
        if projectFormatVersion < bass8DefaultClefProjectFormatVersion {
            for partID in legacyBassPartIDs
                where partID.stemType == .bass && restored[partID] == nil {
                restored[partID] = .treble
            }
        }
        return normalized(restored)
    }
}
