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
