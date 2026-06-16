import Foundation

enum BeatGridAlignmentSource: String, Codable {
    case automatic
    case manual
}

struct TimeSignature: Codable, Equatable {
    static let minimumBeatsPerBar = 1
    static let maximumBeatsPerBar = 7
    static let supportedBeatUnit = 4

    var beatsPerBar: Int
    var beatUnit: Int

    static let fourFour = TimeSignature(beatsPerBar: 4, beatUnit: 4)

    init(beatsPerBar: Int, beatUnit: Int) {
        self.beatsPerBar = Self.normalizedBeatsPerBar(beatsPerBar)
        self.beatUnit = Self.normalizedBeatUnit(beatUnit)
    }

    var displayText: String {
        "\(beatsPerBar)/\(beatUnit)"
    }

    func normalized() -> TimeSignature {
        TimeSignature(beatsPerBar: beatsPerBar, beatUnit: beatUnit)
    }

    static func normalizedBeatsPerBar(_ value: Int) -> Int {
        min(maximumBeatsPerBar, max(minimumBeatsPerBar, value))
    }

    static func normalizedBeatUnit(_ value: Int) -> Int {
        supportedBeatUnit
    }
}

struct BeatGridSettings: Codable, Equatable {
    var bpm: Double?
    var firstBeatTime: TimeInterval
    var automaticFirstBeatTime: TimeInterval
    var timeSignature: TimeSignature
    var alignmentSource: BeatGridAlignmentSource
    var lastChangedAt: Date?

    init(
        bpm: Double? = nil,
        firstBeatTime: TimeInterval = 0,
        automaticFirstBeatTime: TimeInterval = 0,
        timeSignature: TimeSignature = .fourFour,
        alignmentSource: BeatGridAlignmentSource = .automatic,
        lastChangedAt: Date? = nil
    ) {
        self.bpm = bpm
        self.firstBeatTime = max(0, firstBeatTime)
        self.automaticFirstBeatTime = max(0, automaticFirstBeatTime)
        self.timeSignature = timeSignature
        self.alignmentSource = alignmentSource
        self.lastChangedAt = lastChangedAt
    }

    var isManuallyAligned: Bool {
        alignmentSource == .manual
    }

    var beatDuration: TimeInterval? {
        guard let bpm, bpm > 0 else { return nil }
        return 60.0 / bpm
    }

    func clamped(to duration: TimeInterval) -> BeatGridSettings {
        var copy = self
        let upper = max(0, duration)
        copy.firstBeatTime = min(max(0, firstBeatTime), upper)
        copy.automaticFirstBeatTime = min(max(0, automaticFirstBeatTime), upper)
        copy.bpm = bpm.map { max(0.1, min($0, 999.9)) }
        copy.timeSignature = timeSignature.normalized()
        return copy
    }
}

struct TempoTimeSignatureMarkerPayload: Equatable {
    static let typeValue = "tempoTimeSignature"
    static let typeKey = "type"
    static let bpmKey = "bpm"
    static let beatsPerBarKey = "beatsPerBar"
    static let beatUnitKey = "beatUnit"
    static let setsNewFirstBeatKey = "setsNewFirstBeat"

    var bpm: Double?
    var beatsPerBar: Int?
    var beatUnit: Int
    var setsNewFirstBeat: Bool

    init(
        bpm: Double? = nil,
        beatsPerBar: Int? = nil,
        beatUnit: Int = TimeSignature.supportedBeatUnit,
        setsNewFirstBeat: Bool = false
    ) {
        self.bpm = ProjectStateNormalizer.normalizedTempo(bpm)
        self.beatsPerBar = beatsPerBar.map(TimeSignature.normalizedBeatsPerBar)
        self.beatUnit = TimeSignature.normalizedBeatUnit(beatUnit)
        self.setsNewFirstBeat = setsNewFirstBeat
    }

    init?(metadata: [String: String]?) {
        guard metadata?[Self.typeKey] == Self.typeValue else { return nil }

        let bpm = metadata?[Self.bpmKey].flatMap(Double.init)
        let beatsPerBar = metadata?[Self.beatsPerBarKey].flatMap(Int.init)
        let beatUnit = metadata?[Self.beatUnitKey].flatMap(Int.init) ?? TimeSignature.supportedBeatUnit
        let setsNewFirstBeat = metadata?[Self.setsNewFirstBeatKey].flatMap(Bool.init) ?? false
        self.init(bpm: bpm, beatsPerBar: beatsPerBar, beatUnit: beatUnit, setsNewFirstBeat: setsNewFirstBeat)

        guard hasChanges else { return nil }
    }

    var hasChanges: Bool {
        bpm != nil || beatsPerBar != nil || setsNewFirstBeat
    }

    var metadata: [String: String] {
        var metadata = [Self.typeKey: Self.typeValue]
        if let bpm {
            metadata[Self.bpmKey] = String(format: "%.1f", bpm)
        }
        if let beatsPerBar {
            metadata[Self.beatsPerBarKey] = "\(beatsPerBar)"
            metadata[Self.beatUnitKey] = "\(beatUnit)"
        }
        if setsNewFirstBeat {
            metadata[Self.setsNewFirstBeatKey] = "true"
        }
        return metadata
    }

    var title: String {
        var parts: [String] = []
        if let bpm {
            parts.append("\(Self.formatBPM(bpm)) BPM")
        }
        if let beatsPerBar {
            parts.append("\(beatsPerBar)/\(beatUnit)")
        }
        if parts.isEmpty, setsNewFirstBeat {
            parts.append("New First Beat")
        }
        return parts.isEmpty ? "Tempo / Time Signature" : parts.joined(separator: " · ")
    }

    static func formatBPM(_ bpm: Double) -> String {
        bpm.rounded() == bpm ? "\(Int(bpm))" : String(format: "%.1f", bpm)
    }
}

extension TimecodedNote {
    var tempoTimeSignaturePayload: TempoTimeSignatureMarkerPayload? {
        guard isMarker else { return nil }
        return TempoTimeSignatureMarkerPayload(metadata: metadata)
    }

    var isTempoTimeSignatureMarker: Bool {
        tempoTimeSignaturePayload != nil
    }
}

struct TempoMapSegment: Equatable {
    var startTime: TimeInterval
    var endTime: TimeInterval
    var settings: BeatGridSettings
    var firstBarNumber: Int = 1

    func contains(_ time: TimeInterval) -> Bool {
        time >= startTime && time < endTime
    }
}

struct TempoMap: Equatable {
    var duration: TimeInterval
    var segments: [TempoMapSegment]

    init(baseSettings: BeatGridSettings, markers: [TimecodedNote], duration: TimeInterval) {
        self.duration = max(0, duration)

        let base = baseSettings.clamped(to: duration)
        let tempoMarkers = markers
            .compactMap { note -> (TimeInterval, TempoTimeSignatureMarkerPayload)? in
                guard let payload = note.tempoTimeSignaturePayload else { return nil }
                return (max(0, min(note.time, duration)), payload)
            }
            .sorted { lhs, rhs in
                lhs.0 < rhs.0
            }

        var resolvedSegments: [TempoMapSegment] = []
        var currentSettings = base
        var currentStart: TimeInterval = 0
        var currentFirstBarNumber = 1

        for (time, payload) in tempoMarkers {
            if time > currentStart {
                resolvedSegments.append(TempoMapSegment(
                    startTime: currentStart,
                    endTime: time,
                    settings: currentSettings,
                    firstBarNumber: currentFirstBarNumber
                ))
            }

            let nextFirstBarNumber = payload.setsNewFirstBeat
                ? 1
                : Self.nextBarNumber(after: time, settings: currentSettings, firstBarNumber: currentFirstBarNumber)
            if let bpm = payload.bpm {
                currentSettings.bpm = bpm
            }
            if let beatsPerBar = payload.beatsPerBar {
                currentSettings.timeSignature = TimeSignature(beatsPerBar: beatsPerBar, beatUnit: payload.beatUnit)
            }
            currentSettings.firstBeatTime = time
            currentSettings.alignmentSource = .manual
            currentSettings.lastChangedAt = nil
            currentFirstBarNumber = nextFirstBarNumber
            currentStart = time
        }

        resolvedSegments.append(TempoMapSegment(
            startTime: currentStart,
            endTime: self.duration,
            settings: currentSettings,
            firstBarNumber: currentFirstBarNumber
        ))

        if resolvedSegments.isEmpty {
            resolvedSegments = [TempoMapSegment(startTime: 0, endTime: self.duration, settings: base)]
        }

        segments = resolvedSegments
    }

    func settings(at time: TimeInterval) -> BeatGridSettings {
        let clampedTime = max(0, min(time, duration))
        return segments.last(where: { $0.startTime <= clampedTime && clampedTime < $0.endTime })?.settings
            ?? segments.last?.settings
            ?? BeatGridSettings()
    }

    func nearestBeatTime(to time: TimeInterval) -> TimeInterval? {
        let clampedTime = max(0, min(time, duration))
        let candidates = segments.enumerated().compactMap { index, segment -> TimeInterval? in
            guard let beatTime = BeatGridCalculator().nearestBeatTime(
                to: clampedTime,
                settings: segment.settings,
                duration: duration
            ) else {
                return nil
            }

            let isLastSegment = index == segments.count - 1
            guard beatTime >= segment.startTime else { return nil }
            if isLastSegment {
                return beatTime <= segment.endTime ? beatTime : nil
            }

            return beatTime < segment.endTime ? beatTime : nil
        }

        return candidates.min { abs($0 - clampedTime) < abs($1 - clampedTime) }
    }

    static func displayedBarNumber(for barOrdinal: Int, firstBarNumber: Int) -> Int {
        guard barOrdinal >= 0 else { return barOrdinal }
        return firstBarNumber + barOrdinal
    }

    private static func nextBarNumber(
        after time: TimeInterval,
        settings: BeatGridSettings,
        firstBarNumber: Int
    ) -> Int {
        guard
            time > 0,
            let beatDuration = settings.beatDuration,
            beatDuration > 0
        else {
            return 1
        }

        let secondsPerBar = beatDuration * Double(max(1, settings.timeSignature.beatsPerBar))
        guard secondsPerBar > 0 else { return 1 }

        let lookupTime = time.nextDown
        let previousBarOrdinal = Int(floor((lookupTime - settings.firstBeatTime) / secondsPerBar))
        let previousBarNumber = displayedBarNumber(for: previousBarOrdinal, firstBarNumber: firstBarNumber)
        let nextBarNumber = previousBarNumber + 1
        return nextBarNumber == 0 ? 1 : nextBarNumber
    }
}
