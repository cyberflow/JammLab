import Foundation

struct StemTranscriptionNotationOutput: Equatable {
    var track: StemTranscriptionTrack
    var notationItems: [NotationMeasureItem]
}

enum StemTranscriptionNotationMapper {
    static func map(
        result: RawStemTranscriptionResult,
        stemType: StemType,
        sourceFingerprint: StemSourceFingerprint,
        timelineMapping: StemTimelineMapping,
        configuration: StemTranscriptionConfiguration,
        tempoMap: TempoMap,
        projectDuration: TimeInterval,
        keyName: String?
    ) throws -> StemTranscriptionNotationOutput {
        let content = NotationViewportFactory().scoreContent(
            tempoMap: tempoMap,
            duration: projectDuration,
            keyName: keyName,
            partID: .stem(stemType)
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
                partID: .stem(stemType),
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

        let track = StemTranscriptionTrack(
            stemType: stemType,
            sourceFingerprint: sourceFingerprint,
            configuration: configuration,
            notes: storedNotes,
            timings: result.timings
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
}
