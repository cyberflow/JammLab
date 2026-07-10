import Foundation

struct TransportPositionDisplay: Equatable {
    static let invalidMusicalPosition = "--.--.--"
    private static let beatBoundaryTolerance = 1e-9

    var musicalPosition: String
    var elapsedTime: String

    var displayText: String {
        "\(musicalPosition) / \(elapsedTime)"
    }

    static func make(time: TimeInterval, tempoMap: TempoMap) -> TransportPositionDisplay {
        let elapsedTime = TimeFormatter.mmssMilliseconds(time)
        let musicalPosition = musicalPositionText(time: time, tempoMap: tempoMap)
        return TransportPositionDisplay(musicalPosition: musicalPosition, elapsedTime: elapsedTime)
    }

    private static func musicalPositionText(time: TimeInterval, tempoMap: TempoMap) -> String {
        let normalizedTime = normalizedPlaybackTime(time)
        guard
            let segment = tempoMap.segment(at: normalizedTime),
            let beatDuration = segment.settings.beatDuration,
            beatDuration.isFinite,
            beatDuration > 0
        else {
            return invalidMusicalPosition
        }

        let beatsPerBar = max(1, segment.settings.timeSignature.beatsPerBar)
        let rawBeatPosition = (normalizedTime - segment.settings.firstBeatTime) / beatDuration
        let beatPosition = rawBeatPosition + beatBoundaryTolerance
        guard beatPosition.isFinite else { return invalidMusicalPosition }

        let beatIndex = Int(floor(beatPosition))
        let barOrdinal = floorDiv(beatIndex, beatsPerBar)
        let beatInBar = beatIndex - (barOrdinal * beatsPerBar) + 1
        let beatFraction = beatPosition - Double(beatIndex)
        let hundredths = min(99, max(0, Int(floor(beatFraction * 100))))
        let barNumber = TempoMap.displayedBarNumber(
            for: barOrdinal,
            firstBarNumber: segment.firstBarNumber
        )

        return String(format: "%d.%d.%02d", barNumber, beatInBar, hundredths)
    }

    private static func normalizedPlaybackTime(_ time: TimeInterval) -> TimeInterval {
        guard time.isFinite, time >= 0 else { return 0 }
        return time
    }

    private static func floorDiv(_ value: Int, _ divisor: Int) -> Int {
        Int(floor(Double(value) / Double(divisor)))
    }
}
