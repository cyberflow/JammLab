import Foundation

struct BeatGridMarker: Identifiable, Equatable {
    var beatIndex: Int
    var time: TimeInterval
    var isBarStart: Bool

    var id: Int {
        beatIndex
    }

    func barNumber(beatsPerBar: Int) -> Int? {
        let beatsPerBar = max(1, beatsPerBar)
        guard isBarStart else { return nil }

        if beatIndex >= 0 {
            return beatIndex / beatsPerBar + 1
        }

        return beatIndex / beatsPerBar
    }
}

struct BeatGridCalculator {
    func markers(
        settings: BeatGridSettings,
        visibleStartTime: TimeInterval,
        visibleEndTime: TimeInterval
    ) -> [BeatGridMarker] {
        guard
            let beatDuration = settings.beatDuration,
            beatDuration > 0,
            visibleEndTime > visibleStartTime
        else {
            return []
        }

        let firstBeatTime = settings.firstBeatTime
        let startIndex = Int(floor((visibleStartTime - firstBeatTime) / beatDuration)) - 1
        let endIndex = Int(ceil((visibleEndTime - firstBeatTime) / beatDuration)) + 1
        let beatsPerBar = settings.timeSignature.beatsPerBar

        return (startIndex...endIndex).compactMap { beatIndex in
            let time = firstBeatTime + Double(beatIndex) * beatDuration
            guard time >= visibleStartTime, time <= visibleEndTime else { return nil }

            return BeatGridMarker(
                beatIndex: beatIndex,
                time: time,
                isBarStart: beatIndex == 0 || beatIndex % beatsPerBar == 0
            )
        }
    }

    func marker(at time: TimeInterval, settings: BeatGridSettings) -> BeatGridMarker? {
        guard let beatDuration = settings.beatDuration, beatDuration > 0 else {
            return nil
        }

        let beatIndex = Int(floor((time - settings.firstBeatTime) / beatDuration))
        return BeatGridMarker(
            beatIndex: beatIndex,
            time: settings.firstBeatTime + Double(beatIndex) * beatDuration,
            isBarStart: beatIndex == 0 || beatIndex % settings.timeSignature.beatsPerBar == 0
        )
    }

    func nearestBeatTime(to time: TimeInterval, settings: BeatGridSettings, duration: TimeInterval) -> TimeInterval? {
        guard let beatDuration = settings.beatDuration, beatDuration > 0 else {
            return nil
        }

        let beatIndex = Int(round((time - settings.firstBeatTime) / beatDuration))
        let beatTime = settings.firstBeatTime + Double(beatIndex) * beatDuration
        return max(0, min(beatTime, duration))
    }

    func markers(
        tempoMap: TempoMap,
        visibleStartTime: TimeInterval,
        visibleEndTime: TimeInterval
    ) -> [BeatGridMarker] {
        tempoMap.segments.enumerated().flatMap { index, segment in
            let start = max(visibleStartTime, segment.startTime)
            let segmentEnd = index == tempoMap.segments.count - 1 ? segment.endTime : segment.endTime.nextDown
            let end = min(visibleEndTime, segmentEnd)
            guard end >= start else { return [BeatGridMarker]() }
            return markers(settings: segment.settings, visibleStartTime: start, visibleEndTime: end)
        }
        .sorted { $0.time < $1.time }
    }

    func nearestBeatTime(to time: TimeInterval, tempoMap: TempoMap) -> TimeInterval? {
        tempoMap.nearestBeatTime(to: time)
    }
}
