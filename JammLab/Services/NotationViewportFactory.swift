import Foundation

struct NotationViewportFactory {
    func scoreState(
        tempoMap: TempoMap,
        duration: TimeInterval,
        currentTime: TimeInterval,
        playbackMarkerTime: TimeInterval,
        isPlaying: Bool,
        keyName: String?,
        harmonySymbols: [HarmonySymbol] = [],
        notes: [TimecodedNote] = []
    ) -> NotationScoreState {
        let keySignature = KeySignature.normalized(from: keyName)
        guard duration > 0 else {
            return .pending(keySignature: keySignature)
        }
        let regionNotes = Self.regionLabelSourceNotes(from: notes)

        let rawAnchorTime = Self.anchorTime(
            currentTime: currentTime,
            playbackMarkerTime: playbackMarkerTime,
            isPlaying: isPlaying,
            duration: duration
        )

        guard let activeMeasure = measure(containing: rawAnchorTime, tempoMap: tempoMap),
              var cursor = measure(containing: 0, tempoMap: tempoMap)
        else {
            return .pending(keySignature: keySignature)
        }

        var measures: [ScoreMeasure] = []
        for _ in 0..<Self.maximumMeasureTraversalCount {
            measures.append(decoratedMeasure(
                cursor,
                keySignature: keySignature,
                harmonySymbols: harmonySymbols,
                regionNotes: regionNotes
            ))

            guard cursor.endTime < duration - Self.timelineTolerance,
                  let next = nextMeasure(after: cursor, tempoMap: tempoMap),
                  !next.hasSameTimelineIdentity(as: cursor)
            else {
                break
            }

            cursor = next
        }

        guard !measures.isEmpty else {
            return .pending(keySignature: keySignature)
        }

        return NotationScoreState(
            availability: .ready,
            keySignature: keySignature,
            measures: measures,
            anchorTime: Self.viewportAnchorTime(rawAnchorTime, in: activeMeasure),
            activeMeasureNumber: activeMeasure.number
        )
    }

    func viewportState(
        tempoMap: TempoMap,
        duration: TimeInterval,
        currentTime: TimeInterval,
        playbackMarkerTime: TimeInterval,
        isPlaying: Bool,
        keyName: String?,
        visibleMeasureCount: Int,
        harmonySymbols: [HarmonySymbol] = [],
        notes: [TimecodedNote] = []
    ) -> NotationViewportState {
        let safeVisibleMeasureCount = max(1, visibleMeasureCount)
        let keySignature = KeySignature.normalized(from: keyName)
        guard duration > 0 else {
            return .pending(visibleMeasureCount: safeVisibleMeasureCount, keySignature: keySignature)
        }
        let regionNotes = Self.regionLabelSourceNotes(from: notes)

        let rawAnchorTime = Self.anchorTime(
            currentTime: currentTime,
            playbackMarkerTime: playbackMarkerTime,
            isPlaying: isPlaying,
            duration: duration
        )

        guard let activeMeasure = measure(containing: rawAnchorTime, tempoMap: tempoMap),
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
            visibleMeasures.append(decoratedMeasure(
                cursor,
                keySignature: keySignature,
                harmonySymbols: harmonySymbols,
                regionNotes: regionNotes
            ))
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
            anchorTime: Self.viewportAnchorTime(rawAnchorTime, in: activeMeasure),
            activeMeasureNumber: activeMeasure.number
        )
    }

    private func decoratedMeasure(
        _ measure: ScoreMeasure,
        keySignature: KeySignature,
        harmonySymbols: [HarmonySymbol],
        regionNotes: [TimecodedNote]
    ) -> ScoreMeasure {
        let keyedMeasure = measure.withKeySignature(keySignature)
        return keyedMeasure
            .withHarmonies(harmonies(for: keyedMeasure, from: harmonySymbols))
            .withRegionLabels(regionLabels(for: keyedMeasure, from: regionNotes))
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

    private static func viewportAnchorTime(_ anchorTime: TimeInterval, in measure: ScoreMeasure) -> TimeInterval {
        guard measure.duration > 0 else { return anchorTime }
        return max(measure.startTime, min(anchorTime, measure.endTime))
    }

    func harmonyPlacement(
        for time: TimeInterval,
        tempoMap: TempoMap,
        duration: TimeInterval,
        resolution: HarmonyInputResolution? = nil
    ) -> HarmonyPlacement? {
        let clampedTime = Self.anchorTime(
            currentTime: time,
            playbackMarkerTime: time,
            isPlaying: true,
            duration: duration
        )
        guard let measure = measure(containing: clampedTime, tempoMap: tempoMap) else { return nil }
        let rawOffset = quarterOffset(for: clampedTime, in: measure)
        let offset = resolution.map { snappedOffset(rawOffset, in: measure, resolution: $0) } ?? rawOffset
        let resolvedTime = timeForQuarterOffset(offset, in: measure)

        return HarmonyPlacement(
            time: max(0, min(resolvedTime, max(0, duration.nextDown))),
            measureNumber: measure.number,
            offsetInQuarterNotes: offset
        )
    }

    func adjacentHarmonyPlacement(
        from time: TimeInterval,
        direction: HarmonyNavigationDirection,
        tempoMap: TempoMap,
        duration: TimeInterval,
        resolution: HarmonyInputResolution
    ) -> HarmonyPlacement? {
        let clampedTime = Self.anchorTime(
            currentTime: time,
            playbackMarkerTime: time,
            isPlaying: true,
            duration: duration
        )
        guard let measure = measure(containing: clampedTime, tempoMap: tempoMap) else { return nil }

        let currentOffset = snappedOffset(
            quarterOffset(for: clampedTime, in: measure),
            in: measure,
            resolution: resolution
        )
        let step = resolution.stepInQuarterNotes
        let nextOffset: Double
        switch direction {
        case .previous:
            nextOffset = currentOffset - step
        case .next:
            nextOffset = currentOffset + step
        }

        if nextOffset >= 0, nextOffset <= maximumHarmonyOffset(in: measure, resolution: resolution) {
            let targetTime = timeForQuarterOffset(nextOffset, in: measure)
            return harmonyPlacement(
                for: targetTime,
                tempoMap: tempoMap,
                duration: duration,
                resolution: resolution
            )
        }

        let adjacentMeasure: ScoreMeasure?
        switch direction {
        case .previous:
            adjacentMeasure = previousMeasure(before: measure, tempoMap: tempoMap)
        case .next:
            adjacentMeasure = nextMeasure(after: measure, tempoMap: tempoMap)
        }

        guard let adjacentMeasure else { return nil }
        let targetOffset: Double
        switch direction {
        case .previous:
            targetOffset = maximumHarmonyOffset(in: adjacentMeasure, resolution: resolution)
        case .next:
            targetOffset = 0
        }

        let targetTime = timeForQuarterOffset(targetOffset, in: adjacentMeasure)
        return harmonyPlacement(
            for: targetTime,
            tempoMap: tempoMap,
            duration: duration,
            resolution: resolution
        )
    }

    private func measure(containing time: TimeInterval, tempoMap: TempoMap) -> ScoreMeasure? {
        guard let segmentIndex = segmentIndex(containing: time, tempoMap: tempoMap) else { return nil }
        let segment = tempoMap.segments[segmentIndex]
        guard let secondsPerBar = secondsPerBar(for: segment), secondsPerBar > 0 else { return nil }

        let rawBarOrdinal = Int(floor((time - segment.settings.firstBeatTime) / secondsPerBar))
        let barOrdinal = max(0, rawBarOrdinal)
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

    private func previousMeasure(before measure: ScoreMeasure, tempoMap: TempoMap) -> ScoreMeasure? {
        guard let targetIndex = globalMeasureIndex(for: measure, tempoMap: tempoMap), targetIndex > 0 else {
            return nil
        }

        return self.measure(atGlobalIndex: targetIndex - 1, tempoMap: tempoMap)
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

    private func harmonies(for measure: ScoreMeasure, from harmonySymbols: [HarmonySymbol]) -> [HarmonySymbol] {
        harmonySymbols
            .compactMap { symbol -> HarmonySymbol? in
                guard Self.isNotationEventTime(symbol.time, within: measure) else {
                    return nil
                }

                return symbol.withPosition(
                    measureNumber: measure.number,
                    offsetInQuarterNotes: quarterOffset(for: symbol.time, in: measure)
                )
            }
            .sorted {
                Self.isOrderedByNotationPosition(
                    lhsOffset: $0.offsetInQuarterNotes,
                    lhsID: $0.id,
                    rhsOffset: $1.offsetInQuarterNotes,
                    rhsID: $1.id
                )
            }
    }

    private func regionLabels(for measure: ScoreMeasure, from regionNotes: [TimecodedNote]) -> [NotationRegionLabel] {
        regionNotes
            .compactMap { note -> NotationRegionLabel? in
                guard Self.isNotationEventTime(note.time, within: measure) else {
                    return nil
                }

                return NotationRegionLabel(
                    id: note.id,
                    time: note.time,
                    measureNumber: measure.number,
                    offsetInQuarterNotes: quarterOffset(for: note.time, in: measure),
                    title: Self.regionLabelTitle(for: note)
                )
            }
            .sorted {
                Self.isOrderedByNotationPosition(
                    lhsOffset: $0.offsetInQuarterNotes,
                    lhsID: $0.id,
                    rhsOffset: $1.offsetInQuarterNotes,
                    rhsID: $1.id
                )
            }
    }

    private static func regionLabelSourceNotes(from notes: [TimecodedNote]) -> [TimecodedNote] {
        notes
            .filter(\.isRegion)
            .sorted {
                if abs($0.time - $1.time) > timelineTolerance {
                    return $0.time < $1.time
                }

                return $0.id.uuidString < $1.id.uuidString
            }
    }

    private static func regionLabelTitle(for note: TimecodedNote) -> String {
        let trimmedTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Region" : trimmedTitle
    }

    private static func isNotationEventTime(_ time: TimeInterval, within measure: ScoreMeasure) -> Bool {
        time >= measure.startTime - timelineTolerance
            && (
                time < measure.endTime - timelineTolerance
                    || abs(time - measure.startTime) < timelineTolerance
            )
    }

    private static func isOrderedByNotationPosition(
        lhsOffset: Double,
        lhsID: UUID,
        rhsOffset: Double,
        rhsID: UUID
    ) -> Bool {
        if abs(lhsOffset - rhsOffset) > timelineTolerance {
            return lhsOffset < rhsOffset
        }

        return lhsID.uuidString < rhsID.uuidString
    }

    private func quarterOffset(for time: TimeInterval, in measure: ScoreMeasure) -> Double {
        let length = quarterLength(for: measure.attributes.timeSignature)
        guard measure.duration > 0, length > 0 else { return 0 }
        let progress = max(0, min((time - measure.startTime) / measure.duration, 1))
        return progress * length
    }

    private func timeForQuarterOffset(_ offset: Double, in measure: ScoreMeasure) -> TimeInterval {
        let length = quarterLength(for: measure.attributes.timeSignature)
        guard measure.duration > 0, length > 0 else { return measure.startTime }
        let progress = max(0, min(offset / length, 1))
        return measure.startTime + progress * measure.duration
    }

    private func snappedOffset(
        _ offset: Double,
        in measure: ScoreMeasure,
        resolution: HarmonyInputResolution
    ) -> Double {
        let step = resolution.stepInQuarterNotes
        guard step > 0 else { return 0 }
        let maximumOffset = maximumHarmonyOffset(in: measure, resolution: resolution)
        let snapped = (offset / step).rounded() * step
        return max(0, min(snapped, maximumOffset))
    }

    private func maximumHarmonyOffset(
        in measure: ScoreMeasure,
        resolution: HarmonyInputResolution
    ) -> Double {
        let length = quarterLength(for: measure.attributes.timeSignature)
        let step = resolution.stepInQuarterNotes
        guard length > 0, step > 0 else { return 0 }
        let slots = max(0, Int(floor((length - Self.timelineTolerance) / step)))
        return Double(slots) * step
    }

    private func quarterLength(for timeSignature: TimeSignature) -> Double {
        Double(timeSignature.beatsPerBar) * 4.0 / Double(max(1, timeSignature.beatUnit))
    }

    private static let maximumMeasureTraversalCount = 100_000
    private static let timelineTolerance: TimeInterval = 0.000_001
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

    func withHarmonies(_ harmonies: [HarmonySymbol]) -> ScoreMeasure {
        var copy = self
        copy.harmonies = harmonies
        return copy
    }

    func withRegionLabels(_ regionLabels: [NotationRegionLabel]) -> ScoreMeasure {
        var copy = self
        copy.regionLabels = regionLabels
        return copy
    }

    func hasSameTimelineIdentity(as other: ScoreMeasure) -> Bool {
        abs(startTime - other.startTime) < 0.000_001
            && abs(endTime - other.endTime) < 0.000_001
    }
}

private extension HarmonySymbol {
    func withPosition(measureNumber: Int, offsetInQuarterNotes: Double) -> HarmonySymbol {
        var copy = self
        copy.measureNumber = measureNumber
        copy.offsetInQuarterNotes = max(0, offsetInQuarterNotes)
        return copy
    }
}
