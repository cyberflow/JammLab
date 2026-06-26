import Foundation

struct BeatCoordinateMapper: Equatable {
    private struct Segment: Equatable {
        var startTime: TimeInterval
        var endTime: TimeInterval
        var anchorTime: TimeInterval
        var anchorBeat: Double
        var beatDuration: TimeInterval

        var endBeat: Double {
            max(anchorBeat, anchorBeat + (endTime - anchorTime) / beatDuration)
        }

        func containsTime(_ time: TimeInterval) -> Bool {
            time >= startTime && time < endTime
        }

        func containsBeat(_ beat: Double) -> Bool {
            beat >= anchorBeat && beat < endBeat
        }
    }

    private(set) var duration: TimeInterval
    private var segments: [Segment]

    init(tempoMap: TempoMap) {
        duration = max(0, tempoMap.duration)

        var mappedSegments: [Segment] = []
        var nextAnchorBeat: Double = 0
        let sourceSegments = tempoMap.segments.isEmpty
            ? [TempoMapSegment(startTime: 0, endTime: duration, settings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM))]
            : tempoMap.segments

        for (index, segment) in sourceSegments.enumerated() {
            var settings = segment.settings.clamped(to: duration)
            if settings.beatDuration == nil {
                settings.bpm = AppDefaults.defaultTempoBPM
            }

            guard let beatDuration = settings.beatDuration, beatDuration > 0 else { continue }

            let startTime = max(0, min(segment.startTime, duration))
            let endTime = max(startTime, min(segment.endTime, duration))
            guard endTime >= startTime else { continue }

            let anchorTime = index == 0
                ? max(startTime, min(settings.firstBeatTime, endTime))
                : startTime
            let mapped = Segment(
                startTime: startTime,
                endTime: endTime,
                anchorTime: anchorTime,
                anchorBeat: nextAnchorBeat,
                beatDuration: beatDuration
            )
            mappedSegments.append(mapped)
            nextAnchorBeat = mapped.endBeat
        }

        if mappedSegments.isEmpty {
            let beatDuration = 60.0 / AppDefaults.defaultTempoBPM
            mappedSegments = [Segment(
                startTime: 0,
                endTime: duration,
                anchorTime: 0,
                anchorBeat: 0,
                beatDuration: beatDuration
            )]
        }

        segments = mappedSegments
    }

    var maximumBeat: Double {
        beat(at: duration)
    }

    func beat(at time: TimeInterval) -> Double {
        guard let segment = segment(containingTime: time) else { return 0 }
        let clampedTime = max(0, min(time, duration))
        return max(0, segment.anchorBeat + (clampedTime - segment.anchorTime) / segment.beatDuration)
    }

    func time(for beat: Double) -> TimeInterval {
        let key = HarmonyBeatKey(beat)
        let requestedBeat = min(key.startBeat, maximumBeat)
        guard let segment = segment(containingBeat: requestedBeat) ?? segments.last else { return 0 }

        let rawTime = segment.anchorTime + (requestedBeat - segment.anchorBeat) * segment.beatDuration
        return max(0, min(rawTime, duration))
    }

    func snappedBeat(at time: TimeInterval) -> Double {
        HarmonyBeatKey(beat(at: time)).startBeat
    }

    private func segment(containingTime time: TimeInterval) -> Segment? {
        let clampedTime = max(0, min(time, duration))
        return segments.last(where: { $0.startTime <= clampedTime && clampedTime < $0.endTime })
            ?? segments.last(where: { $0.startTime <= clampedTime })
            ?? segments.first
    }

    private func segment(containingBeat beat: Double) -> Segment? {
        segments.first(where: { $0.containsBeat(beat) })
    }
}
