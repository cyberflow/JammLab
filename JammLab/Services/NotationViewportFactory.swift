import Foundation

struct NotationViewportFactory {
    func viewportState(
        tempoMap: TempoMap,
        duration: TimeInterval,
        currentTime: TimeInterval,
        playbackMarkerTime: TimeInterval,
        isPlaying: Bool,
        keyName: String?,
        visibleMeasureCount: Int
    ) -> NotationViewportState {
        let safeVisibleMeasureCount = max(1, visibleMeasureCount)
        let keySignature = KeySignature.normalized(from: keyName)
        guard duration > 0 else {
            return .pending(visibleMeasureCount: safeVisibleMeasureCount, keySignature: keySignature)
        }

        let anchorTime = Self.anchorTime(
            currentTime: currentTime,
            playbackMarkerTime: playbackMarkerTime,
            isPlaying: isPlaying,
            duration: duration
        )

        guard let activeMeasure = measure(containing: anchorTime, tempoMap: tempoMap),
              let activeMeasureIndex = globalMeasureIndex(for: activeMeasure, tempoMap: tempoMap),
              let firstMeasure = measure(atGlobalIndex: pageStartIndex(
                forActiveMeasureIndex: activeMeasureIndex,
                visibleMeasureCount: safeVisibleMeasureCount
              ), tempoMap: tempoMap)
        else {
            return .pending(visibleMeasureCount: safeVisibleMeasureCount, keySignature: keySignature)
        }

        var visibleMeasures: [ScoreMeasure] = []
        var cursor = firstMeasure
        for _ in 0..<safeVisibleMeasureCount {
            visibleMeasures.append(cursor.withKeySignature(keySignature))
            guard let next = nextMeasure(after: cursor, tempoMap: tempoMap) else { break }
            cursor = next
        }

        guard let firstVisibleMeasure = visibleMeasures.first else {
            return .pending(visibleMeasureCount: safeVisibleMeasureCount, keySignature: keySignature)
        }

        return NotationViewportState(
            availability: .ready,
            clef: firstVisibleMeasure.attributes.clef,
            keySignature: firstVisibleMeasure.attributes.keySignature,
            timeSignature: firstVisibleMeasure.attributes.timeSignature,
            firstVisibleMeasureNumber: firstVisibleMeasure.number,
            visibleMeasureCount: safeVisibleMeasureCount,
            visibleMeasures: visibleMeasures,
            anchorTime: anchorTime,
            activeMeasureNumber: activeMeasure.number
        )
    }

    static func anchorTime(
        currentTime: TimeInterval,
        playbackMarkerTime: TimeInterval,
        isPlaying: Bool,
        duration: TimeInterval
    ) -> TimeInterval {
        let rawTime = isPlaying ? currentTime : playbackMarkerTime
        guard duration > 0 else { return 0 }

        let upperBound = duration.nextDown
        return max(0, min(rawTime, upperBound))
    }

    private func measure(containing time: TimeInterval, tempoMap: TempoMap) -> ScoreMeasure? {
        guard let segmentIndex = segmentIndex(containing: time, tempoMap: tempoMap) else { return nil }
        let segment = tempoMap.segments[segmentIndex]
        guard let secondsPerBar = secondsPerBar(for: segment), secondsPerBar > 0 else { return nil }

        let barOrdinal = Int(floor((time - segment.settings.firstBeatTime) / secondsPerBar))
        return measure(segmentIndex: segmentIndex, barOrdinal: barOrdinal, tempoMap: tempoMap)
    }

    private func nextMeasure(after measure: ScoreMeasure, tempoMap: TempoMap) -> ScoreMeasure? {
        guard let segmentIndex = segmentIndex(containing: measure.startTime, tempoMap: tempoMap) else { return nil }
        let segment = tempoMap.segments[segmentIndex]
        guard let secondsPerBar = secondsPerBar(for: segment), secondsPerBar > 0 else { return nil }

        let currentOrdinal = Int(round((measure.nominalStartTime - segment.settings.firstBeatTime) / secondsPerBar))
        if segmentIndex < tempoMap.segments.count - 1,
           measure.endTime >= segment.endTime {
            return self.measure(containing: tempoMap.segments[segmentIndex + 1].startTime, tempoMap: tempoMap)
        }

        return self.measure(segmentIndex: segmentIndex, barOrdinal: currentOrdinal + 1, tempoMap: tempoMap)
    }

    private func pageStartIndex(forActiveMeasureIndex activeMeasureIndex: Int, visibleMeasureCount: Int) -> Int {
        let safeVisibleMeasureCount = max(1, visibleMeasureCount)
        return (activeMeasureIndex / safeVisibleMeasureCount) * safeVisibleMeasureCount
    }

    private func globalMeasureIndex(for target: ScoreMeasure, tempoMap: TempoMap) -> Int? {
        guard var cursor = measure(containing: 0, tempoMap: tempoMap) else { return nil }

        var index = 0
        while index < Self.maximumMeasureTraversalCount {
            if cursor.hasSameTimelineIdentity(as: target) {
                return index
            }

            guard let next = nextMeasure(after: cursor, tempoMap: tempoMap),
                  !next.hasSameTimelineIdentity(as: cursor)
            else {
                return nil
            }

            cursor = next
            index += 1
        }

        return nil
    }

    private func measure(atGlobalIndex targetIndex: Int, tempoMap: TempoMap) -> ScoreMeasure? {
        guard targetIndex >= 0, var cursor = measure(containing: 0, tempoMap: tempoMap) else { return nil }
        guard targetIndex > 0 else { return cursor }

        var index = 0
        while index < targetIndex, index < Self.maximumMeasureTraversalCount {
            guard let next = nextMeasure(after: cursor, tempoMap: tempoMap),
                  !next.hasSameTimelineIdentity(as: cursor)
            else {
                return nil
            }

            cursor = next
            index += 1
        }

        return index == targetIndex ? cursor : nil
    }

    private func measure(segmentIndex: Int, barOrdinal: Int, tempoMap: TempoMap) -> ScoreMeasure? {
        guard tempoMap.segments.indices.contains(segmentIndex) else { return nil }
        let segment = tempoMap.segments[segmentIndex]
        guard let secondsPerBar = secondsPerBar(for: segment), secondsPerBar > 0 else { return nil }

        let nominalStartTime = segment.settings.firstBeatTime + Double(barOrdinal) * secondsPerBar
        let nominalEndTime = nominalStartTime + secondsPerBar
        let segmentEndTime = segmentIndex < tempoMap.segments.count - 1
            ? tempoMap.segments[segmentIndex].endTime
            : max(tempoMap.segments[segmentIndex].endTime, nominalEndTime)
        let startTime = max(0, max(segment.startTime, nominalStartTime))
        let endTime = max(startTime, min(nominalEndTime, segmentEndTime))
        let number = TempoMap.displayedBarNumber(for: barOrdinal, firstBarNumber: segment.firstBarNumber)

        return ScoreMeasure(
            number: number,
            startTime: startTime,
            endTime: endTime,
            attributes: MeasureAttributes(
                keySignature: .cMajor,
                timeSignature: segment.settings.timeSignature,
                clef: .treble
            )
        )
    }

    private func segmentIndex(containing time: TimeInterval, tempoMap: TempoMap) -> Int? {
        guard !tempoMap.segments.isEmpty else { return nil }

        if let index = tempoMap.segments.lastIndex(where: { segment in
            time >= segment.startTime && time < segment.endTime
        }) {
            return index
        }

        if let first = tempoMap.segments.first, time < first.startTime {
            return tempoMap.segments.startIndex
        }

        return tempoMap.segments.indices.last
    }

    private func secondsPerBar(for segment: TempoMapSegment) -> TimeInterval? {
        guard let beatDuration = segment.settings.beatDuration, beatDuration > 0 else { return nil }
        return beatDuration * Double(max(1, segment.settings.timeSignature.beatsPerBar))
    }

    private static let maximumMeasureTraversalCount = 100_000
}

private extension ScoreMeasure {
    var nominalStartTime: TimeInterval {
        startTime
    }

    func withKeySignature(_ keySignature: KeySignature) -> ScoreMeasure {
        var copy = self
        copy.attributes.keySignature = keySignature
        return copy
    }

    func hasSameTimelineIdentity(as other: ScoreMeasure) -> Bool {
        abs(startTime - other.startTime) < 0.000_001
            && abs(endTime - other.endTime) < 0.000_001
    }
}
