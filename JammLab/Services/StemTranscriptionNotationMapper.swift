import Foundation

struct StemTranscriptionNotationOutput: Equatable {
    var track: StemTranscriptionTrack
    var notationItems: [NotationMeasureItem]
}

enum StemTranscriptionNotationMapper {
    static func map(
        result: RawStemTranscriptionResult,
        stemType: StemType,
        trackID: UUID = UUID(),
        notationPartID: NotationPartID? = nil,
        sourceFingerprint: StemSourceFingerprint,
        timelineMapping: StemTimelineMapping,
        configuration: StemTranscriptionConfiguration,
        tempoMap: TempoMap,
        projectDuration: TimeInterval,
        keyName: String?
    ) throws -> StemTranscriptionNotationOutput {
        let resolvedPartID = notationPartID ?? .stem(stemType)
        let content = NotationViewportFactory().scoreContent(
            tempoMap: tempoMap,
            duration: projectDuration,
            keyName: keyName,
            partID: resolvedPartID
        )
        guard content.isReady, !content.measures.isEmpty else {
            throw StemTranscriptionError.resultCouldNotBeAdded
        }

        let measureStarts = absoluteQuarterStarts(for: content.measures)
        let quantum = 4.0 / Double(max(1, configuration.quantizationDenominator))
        let keySignature = content.keySignature
        var storedNotes: [StemTranscriptionNote] = []
        var notationItems: [NotationMeasureItem] = []

        for rawNote in result.notes {
            let projectStart = timelineMapping.projectTime(forSourceTime: rawNote.startTimeSeconds)
            let projectEnd = timelineMapping.projectTime(forSourceTime: rawNote.endTimeSeconds)
            guard projectStart.isFinite,
                  projectEnd.isFinite,
                  projectEnd > projectStart,
                  projectEnd > 0,
                  projectStart < projectDuration
            else { continue }

            let clampedStart = min(projectDuration, max(0, projectStart))
            let clampedEnd = min(projectDuration, max(0, projectEnd))
            guard clampedEnd > clampedStart else { continue }

            let rawAbsoluteStart = absoluteQuarter(
                at: clampedStart,
                measures: content.measures,
                measureStarts: measureStarts
            )
            let rawAbsoluteEnd = absoluteQuarter(
                at: clampedEnd,
                measures: content.measures,
                measureStarts: measureStarts
            )
            let quantizedStart = quantize(rawAbsoluteStart, quantum: quantum)
            let quantizedEnd = max(
                quantizedStart + quantum,
                quantize(rawAbsoluteEnd, quantum: quantum)
            )

            let itemIDs = makeNotationItems(
                fromAbsoluteQuarter: quantizedStart,
                toAbsoluteQuarter: quantizedEnd,
                midiPitch: rawNote.midiPitch,
                partID: resolvedPartID,
                measures: content.measures,
                measureStarts: measureStarts,
                keySignature: keySignature
            )
            notationItems.append(contentsOf: itemIDs.items)
            storedNotes.append(StemTranscriptionNote(
                midiPitch: rawNote.midiPitch,
                rawStartTimeSeconds: rawNote.startTimeSeconds,
                rawEndTimeSeconds: rawNote.endTimeSeconds,
                projectStartTimeSeconds: clampedStart,
                projectEndTimeSeconds: clampedEnd,
                confidence: rawNote.confidence,
                pitchBends: rawNote.pitchBends,
                notationItemIDs: itemIDs.ids
            ))
        }

        notationItems = applyingCommonPracticeAccidentals(
            to: notationItems,
            storedNotes: storedNotes,
            measures: content.measures
        )

        let track = StemTranscriptionTrack(
            id: trackID,
            stemType: stemType,
            notationPartID: resolvedPartID,
            sourceFingerprint: sourceFingerprint,
            configuration: configuration,
            notes: storedNotes,
            timings: result.timings,
            warnings: result.warnings
        )
        return StemTranscriptionNotationOutput(track: track, notationItems: notationItems)
    }

    private static func absoluteQuarterStarts(for measures: [ScoreMeasure]) -> [Double] {
        var cursor = 0.0
        return measures.map { measure in
            defer {
                cursor += NotationMeasureTiming.quarterLength(for: measure.attributes.timeSignature)
            }
            return cursor
        }
    }

    private static func absoluteQuarter(
        at time: TimeInterval,
        measures: [ScoreMeasure],
        measureStarts: [Double]
    ) -> Double {
        let index = measures.firstIndex(where: { NotationMeasureTiming.containsEventTime(time, in: $0) })
            ?? max(0, measures.count - 1)
        return measureStarts[index] + NotationMeasureTiming.quarterOffset(for: time, in: measures[index])
    }

    private static func quantize(_ value: Double, quantum: Double) -> Double {
        guard quantum > 0 else { return value }
        return (value / quantum).rounded() * quantum
    }

    private static func makeNotationItems(
        fromAbsoluteQuarter start: Double,
        toAbsoluteQuarter end: Double,
        midiPitch: Int,
        partID: NotationPartID,
        measures: [ScoreMeasure],
        measureStarts: [Double],
        keySignature: KeySignature
    ) -> (items: [NotationMeasureItem], ids: [String]) {
        var chunks: [(measure: ScoreMeasure, offset: Double, duration: Double)] = []
        for (index, measure) in measures.enumerated() {
            let measureStart = measureStarts[index]
            let measureEnd = measureStart
                + NotationMeasureTiming.quarterLength(for: measure.attributes.timeSignature)
            let chunkStart = max(start, measureStart)
            let chunkEnd = min(end, measureEnd)
            if chunkEnd > chunkStart + NotationMeasureTiming.timelineTolerance {
                chunks.append((
                    measure,
                    chunkStart - measureStart,
                    chunkEnd - chunkStart
                ))
            }
        }

        let ids = chunks.map { _ in UUID().uuidString }
        let pitch = NotationPitchMapper.pitch(
            forMIDINoteNumber: midiPitch,
            keySignature: keySignature
        )
        let items = chunks.enumerated().map { index, chunk in
            NotationMeasureItem(
                id: ids[index],
                partID: partID,
                kind: .note,
                pitch: pitch,
                measureNumber: chunk.measure.number,
                measureStartTime: chunk.measure.startTime,
                offsetInQuarterNotes: chunk.offset,
                durationInQuarterNotes: chunk.duration,
                displayDuration: closestDisplayDuration(to: chunk.duration),
                tieTargetItemID: index + 1 < ids.count ? ids[index + 1] : nil
            )
        }
        return (items, ids)
    }

    private static func closestDisplayDuration(to quarterDuration: Double) -> NotationDuration {
        let candidates = NotationDuration.restDecompositionDenominators.flatMap { denominator in
            [
                NotationDuration(denominator: denominator),
                NotationDuration(denominator: denominator, isDotted: true)
            ]
        }
        return candidates.min {
            abs($0.durationInQuarterNotes - quarterDuration)
                < abs($1.durationInQuarterNotes - quarterDuration)
        } ?? NotationDuration()
    }

    private static func applyingCommonPracticeAccidentals(
        to sourceItems: [NotationMeasureItem],
        storedNotes: [StemTranscriptionNote],
        measures: [ScoreMeasure]
    ) -> [NotationMeasureItem] {
        var items = sourceItems
        let itemIndexByID = Dictionary(
            uniqueKeysWithValues: items.indices.map { (items[$0].id, $0) }
        )
        let keySignatureByMeasure = Dictionary(
            uniqueKeysWithValues: measures.map {
                (AccidentalMeasureKey(measure: $0), $0.attributes.keySignature)
            }
        )
        let candidates = storedNotes.enumerated().compactMap {
            sourceOrder,
            storedNote -> TranscribedAccidentalCandidate? in
            guard let rootItemID = storedNote.notationItemIDs.first,
                  let itemIndex = itemIndexByID[rootItemID],
                  let pitch = items[itemIndex].pitch
            else {
                return nil
            }

            let item = items[itemIndex]
            let measureKey = AccidentalMeasureKey(item: item)
            guard let keySignature = keySignatureByMeasure[measureKey] else {
                return nil
            }
            return TranscribedAccidentalCandidate(
                rootItemID: rootItemID,
                sourceOrder: sourceOrder,
                measureKey: measureKey,
                offsetInQuarterNotes: item.offsetInQuarterNotes,
                pitch: pitch,
                keySignature: keySignature
            )
        }
        .sorted(by: accidentalCandidatePrecedes)

        var activeAlters: [AccidentalPitchPosition: Int] = [:]
        var currentMeasureKey: AccidentalMeasureKey?
        var candidateIndex = 0
        while candidateIndex < candidates.count {
            let first = candidates[candidateIndex]
            if currentMeasureKey != first.measureKey {
                currentMeasureKey = first.measureKey
                activeAlters.removeAll(keepingCapacity: true)
            }

            var onsetEndIndex = candidateIndex + 1
            while onsetEndIndex < candidates.count,
                  candidates[onsetEndIndex].measureKey == first.measureKey,
                  candidates[onsetEndIndex].offsetInQuarterNotes == first.offsetInQuarterNotes {
                onsetEndIndex += 1
            }

            applyAccidentals(
                to: candidates[candidateIndex..<onsetEndIndex],
                activeAlters: &activeAlters,
                itemIndexByID: itemIndexByID,
                items: &items
            )
            candidateIndex = onsetEndIndex
        }

        return items
    }

    private static func accidentalCandidatePrecedes(
        _ lhs: TranscribedAccidentalCandidate,
        _ rhs: TranscribedAccidentalCandidate
    ) -> Bool {
        if lhs.measureKey.startTime != rhs.measureKey.startTime {
            return lhs.measureKey.startTime < rhs.measureKey.startTime
        }
        if lhs.measureKey.number != rhs.measureKey.number {
            return lhs.measureKey.number < rhs.measureKey.number
        }
        if lhs.offsetInQuarterNotes != rhs.offsetInQuarterNotes {
            return lhs.offsetInQuarterNotes < rhs.offsetInQuarterNotes
        }
        return lhs.sourceOrder < rhs.sourceOrder
    }

    private static func applyAccidentals(
        to onsetCandidates: ArraySlice<TranscribedAccidentalCandidate>,
        activeAlters: inout [AccidentalPitchPosition: Int],
        itemIndexByID: [String: Int],
        items: inout [NotationMeasureItem]
    ) {
        let candidatesByPosition = Dictionary(
            grouping: onsetCandidates,
            by: \.pitchPosition
        )

        for (position, positionCandidates) in candidatesByPosition {
            let distinctAlters = Set(positionCandidates.map(\.pitch.alter))
            if distinctAlters.count > 1 {
                for candidate in positionCandidates {
                    setExplicitAccidental(
                        for: candidate,
                        itemIndexByID: itemIndexByID,
                        items: &items
                    )
                }
                continue
            }

            guard let first = positionCandidates.first else { continue }
            let currentAlter = activeAlters[position]
                ?? first.keySignature.defaultAlter(for: first.pitch.step)
            if first.pitch.alter != currentAlter {
                setExplicitAccidental(
                    for: first,
                    itemIndexByID: itemIndexByID,
                    items: &items
                )
            }
            activeAlters[position] = first.pitch.alter
        }
    }

    private static func setExplicitAccidental(
        for candidate: TranscribedAccidentalCandidate,
        itemIndexByID: [String: Int],
        items: inout [NotationMeasureItem]
    ) {
        guard let itemIndex = itemIndexByID[candidate.rootItemID],
              items[itemIndex].pitch == candidate.pitch
        else {
            return
        }
        items[itemIndex].explicitAccidental = notationAccidental(forAlter: candidate.pitch.alter)
    }

    private static func notationAccidental(forAlter alter: Int) -> NotationAccidental? {
        switch alter {
        case -1: return .flat
        case 0: return .natural
        case 1: return .sharp
        default: return nil
        }
    }

    private struct TranscribedAccidentalCandidate {
        var rootItemID: String
        var sourceOrder: Int
        var measureKey: AccidentalMeasureKey
        var offsetInQuarterNotes: Double
        var pitch: NotationPitch
        var keySignature: KeySignature

        var pitchPosition: AccidentalPitchPosition {
            AccidentalPitchPosition(
                stepIndex: pitch.step.diatonicIndex,
                octave: pitch.octave
            )
        }
    }

    private struct AccidentalMeasureKey: Hashable {
        var number: Int
        var startTime: TimeInterval

        init(measure: ScoreMeasure) {
            number = measure.number
            startTime = measure.startTime
        }

        init(item: NotationMeasureItem) {
            number = item.measureNumber
            startTime = item.measureStartTime
        }
    }

    private struct AccidentalPitchPosition: Hashable {
        var stepIndex: Int
        var octave: Int
    }
}
