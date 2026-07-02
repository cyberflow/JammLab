import Foundation

struct ScoreMeasure: Equatable, Identifiable {
    var number: Int
    var startTime: TimeInterval
    var endTime: TimeInterval
    var attributes: MeasureAttributes
    var harmonies: [HarmonySymbol]
    var regionLabels: [NotationRegionLabel]

    init(
        number: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        attributes: MeasureAttributes,
        harmonies: [HarmonySymbol] = [],
        regionLabels: [NotationRegionLabel] = []
    ) {
        self.number = number
        self.startTime = startTime
        self.endTime = endTime
        self.attributes = attributes
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
    var number: Int
    var startTime: TimeInterval
    var endTime: TimeInterval
    var attributes: MeasureAttributes

    init(measure: ScoreMeasure) {
        self.number = measure.number
        self.startTime = measure.startTime
        self.endTime = measure.endTime
        self.attributes = measure.attributes
    }

    var id: String {
        "\(number)-\(startTime)-\(endTime)"
    }

    func matches(_ measure: ScoreMeasure) -> Bool {
        number == measure.number
            && abs(startTime - measure.startTime) < NotationMeasureTiming.timelineTolerance
            && abs(endTime - measure.endTime) < NotationMeasureTiming.timelineTolerance
    }
}

struct NotationBeatSelection: Equatable, Identifiable {
    var measureNumber: Int
    var measureStartTime: TimeInterval
    var measureEndTime: TimeInterval
    var attributes: MeasureAttributes
    var offsetInQuarterNotes: Double

    init(measure: ScoreMeasure, offsetInQuarterNotes: Double) {
        self.measureNumber = measure.number
        self.measureStartTime = measure.startTime
        self.measureEndTime = measure.endTime
        self.attributes = measure.attributes
        self.offsetInQuarterNotes = offsetInQuarterNotes
    }

    var id: String {
        "\(measureNumber)-\(measureStartTime)-\(measureEndTime)-\(offsetInQuarterNotes)"
    }

    func matches(_ measure: ScoreMeasure, offsetInQuarterNotes offset: Double) -> Bool {
        measureNumber == measure.number
            && abs(measureStartTime - measure.startTime) < NotationMeasureTiming.timelineTolerance
            && abs(measureEndTime - measure.endTime) < NotationMeasureTiming.timelineTolerance
            && attributes == measure.attributes
            && abs(offsetInQuarterNotes - offset) < NotationMeasureTiming.timelineTolerance
    }
}

struct NotationMeasureClipboard: Equatable {
    var measures: [NotationMeasureClipboardMeasure]
}

struct NotationMeasureClipboardMeasure: Equatable {
    var items: [NotationMeasureClipboardItem]
}

struct NotationMeasureClipboardItem: Equatable {
    var offsetInQuarterNotes: Double
    var rawText: String
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

struct HarmonyInputResolution: Equatable {
    static let allowedDenominators = [1, 2, 4, 8]
    static let defaultDenominator = 4

    var denominator: Int

    init(denominator: Int = Self.defaultDenominator) {
        self.denominator = Self.normalizedDenominator(denominator)
    }

    var stepInQuarterNotes: Double {
        4.0 / Double(denominator)
    }

    static func normalizedDenominator(_ denominator: Int) -> Int {
        allowedDenominators.min { lhs, rhs in
            abs(lhs - denominator) < abs(rhs - denominator)
        } ?? defaultDenominator
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
        switch clef {
        case .treble:
            if fifths > 0 {
                return Array(Self.trebleSharpAccidentals.prefix(accidentalCount))
            }

            if fifths < 0 {
                return Array(Self.trebleFlatAccidentals.prefix(accidentalCount))
            }

            return []
        }
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

enum Clef: String, Equatable {
    case treble

    var sign: String {
        "G"
    }

    var line: Int {
        2
    }

    var displaySymbol: String {
        "𝄞"
    }
}
