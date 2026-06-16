import Foundation

enum MetronomeClickKind: Equatable {
    case accent
    case regular
}

struct MetronomeClickEvent: Equatable {
    var sourceTime: TimeInterval
    var kind: MetronomeClickKind
}

struct MetronomeClickScheduler {
    private let calculator = BeatGridCalculator()

    func events(
        settings: BeatGridSettings,
        segmentStartTime: TimeInterval,
        segmentEndTime: TimeInterval
    ) -> [MetronomeClickEvent] {
        guard
            settings.beatDuration != nil,
            segmentEndTime > segmentStartTime
        else {
            return []
        }

        return calculator.markers(
            settings: settings,
            visibleStartTime: segmentStartTime,
            visibleEndTime: segmentEndTime
        )
        .map { marker in
            MetronomeClickEvent(
                sourceTime: marker.time,
                kind: marker.isBarStart ? .accent : .regular
            )
        }
    }

    func events(
        tempoMap: TempoMap,
        segmentStartTime: TimeInterval,
        segmentEndTime: TimeInterval
    ) -> [MetronomeClickEvent] {
        guard segmentEndTime > segmentStartTime else { return [] }

        return calculator.markers(
            tempoMap: tempoMap,
            visibleStartTime: segmentStartTime,
            visibleEndTime: segmentEndTime
        )
        .map { marker in
            MetronomeClickEvent(
                sourceTime: marker.time,
                kind: marker.isBarStart ? .accent : .regular
            )
        }
    }
}

struct MetronomeClickTimingMapper {
    func sampleTime(
        for event: MetronomeClickEvent,
        segmentStartTime: TimeInterval,
        playbackRate: Double,
        sampleRate: Double,
        outputLatency: TimeInterval = 0
    ) -> Int64? {
        guard
            event.sourceTime >= segmentStartTime,
            playbackRate > 0,
            sampleRate > 0
        else {
            return nil
        }

        let audibleOffset = (event.sourceTime - segmentStartTime) / playbackRate
        let outputOffset = max(0, audibleOffset + max(0, outputLatency))
        return Int64((outputOffset * sampleRate).rounded())
    }
}
