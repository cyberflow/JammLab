import Foundation

struct NotationTieEndpoint: Equatable {
    var measureNumber: Int
    var measureStartTime: TimeInterval
    var measureAttributes: MeasureAttributes
    var item: NotationMeasureItem
}

struct NotationTieConnection: Equatable, Identifiable {
    var source: NotationTieEndpoint
    var target: NotationTieEndpoint

    var id: String {
        "\(source.item.id)->\(target.item.id)"
    }
}

enum NotationTieCommandBlockReason: Equatable {
    case selectNote
    case alreadyTied
    case audioBoundary
}

enum NotationTieCommandStatus: Equatable {
    case unavailable
    case ready
    case blocked(NotationTieCommandBlockReason)

    var isInCommandScope: Bool {
        self != .unavailable
    }
}

enum NotationTieResolver {
    static func connections(in measures: [ScoreMeasure]) -> [NotationTieConnection] {
        let orderedMeasures = measures.sorted(by: notationTieMeasureSort)
        let flattened = orderedMeasures.flatMap { measure in
            measure.notationItems
                .sorted(by: notationTieItemSort)
                .map { (measure: measure, item: $0) }
        }
        let entriesByID = flattened.reduce(into: [String: (measure: ScoreMeasure, item: NotationMeasureItem)]()) {
            if $0[$1.item.id] == nil { $0[$1.item.id] = $1 }
        }
        var claimedTargetIDs: Set<String> = []
        var output: [NotationTieConnection] = []

        for entry in flattened {
            let source = entry.item
            guard !source.isSynthesized,
                  source.kind == .note,
                  let sourcePitch = source.pitch,
                  let targetID = source.tieTargetItemID,
                  targetID != source.id,
                  let targetEntry = entriesByID[targetID],
                  !claimedTargetIDs.contains(targetID)
            else {
                continue
            }

            let target = targetEntry.item
            guard !target.isSynthesized,
                  target.kind == .note,
                  target.pitch == sourcePitch,
                  target.partID == source.partID,
                  areContiguous(
                    source: source,
                    sourceMeasure: entry.measure,
                    target: target,
                    targetMeasure: targetEntry.measure
                  )
            else {
                continue
            }

            claimedTargetIDs.insert(targetID)
            output.append(NotationTieConnection(
                source: endpoint(measure: entry.measure, item: source),
                target: endpoint(measure: targetEntry.measure, item: target)
            ))
        }

        return output.sorted {
            if $0.source.measureNumber != $1.source.measureNumber {
                return $0.source.measureNumber < $1.source.measureNumber
            }
            if abs($0.source.item.offsetInQuarterNotes - $1.source.item.offsetInQuarterNotes)
                > NotationMeasureTiming.timelineTolerance {
                return $0.source.item.offsetInQuarterNotes < $1.source.item.offsetInQuarterNotes
            }
            return $0.source.item.id < $1.source.item.id
        }
    }

    static func sanitizedPersistedItems(
        _ items: [NotationMeasureItem],
        validConnections: [NotationTieConnection]
    ) -> [NotationMeasureItem] {
        let validTargetsBySource = Dictionary(
            uniqueKeysWithValues: validConnections.map { ($0.source.item.id, $0.target.item.id) }
        )
        return items.map { item in
            var copy = item
            copy.tieTargetItemID = item.kind == .note ? validTargetsBySource[item.id] : nil
            return copy
        }
    }

    static func connections(
        _ connections: [NotationTieConnection],
        visibleIn measures: [ScoreMeasure]
    ) -> [NotationTieConnection] {
        let visibleMeasureIDs = Set(measures.map { measureIdentity($0.number, $0.startTime) })
        return connections.filter { connection in
            visibleMeasureIDs.contains(measureIdentity(
                connection.source.measureNumber,
                connection.source.measureStartTime
            )) || visibleMeasureIDs.contains(measureIdentity(
                connection.target.measureNumber,
                connection.target.measureStartTime
            ))
        }
    }

    private static func endpoint(
        measure: ScoreMeasure,
        item: NotationMeasureItem
    ) -> NotationTieEndpoint {
        NotationTieEndpoint(
            measureNumber: measure.number,
            measureStartTime: measure.startTime,
            measureAttributes: measure.attributes,
            item: item
        )
    }

    private static func measureIdentity(_ number: Int, _ startTime: TimeInterval) -> String {
        "\(number)-\(startTime)"
    }

    private static func areContiguous(
        source: NotationMeasureItem,
        sourceMeasure: ScoreMeasure,
        target: NotationMeasureItem,
        targetMeasure: ScoreMeasure
    ) -> Bool {
        let sourceEnd = source.offsetInQuarterNotes + source.durationInQuarterNotes
        if sourceMeasure.number == targetMeasure.number,
           abs(sourceMeasure.startTime - targetMeasure.startTime) < NotationMeasureTiming.timelineTolerance {
            return abs(sourceEnd - target.offsetInQuarterNotes) < NotationMeasureTiming.timelineTolerance
        }

        let sourceLength = NotationMeasureTiming.quarterLength(for: sourceMeasure.attributes.timeSignature)
        return targetMeasure.number == sourceMeasure.number + 1
            && abs(sourceEnd - sourceLength) < NotationMeasureTiming.timelineTolerance
            && abs(target.offsetInQuarterNotes) < NotationMeasureTiming.timelineTolerance
    }

}

struct NotationNoteInsertionMeasureReplacement: Equatable {
    var measureNumber: Int
    var measureStartTime: TimeInterval
    var partID: NotationPartID
    var items: [NotationMeasureItem]
}

struct NotationNoteInsertionPlan: Equatable {
    var replacements: [NotationNoteInsertionMeasureReplacement]
    var firstItemID: String
    var firstMeasureNumber: Int
    var firstMeasureStartTime: TimeInterval
    var finalItemID: String
    var finalMeasureNumber: Int
    var finalMeasureStartTime: TimeInterval
    var partID: NotationPartID
}

enum NotationNoteInsertionPlanner {
    static func plan(
        in measures: [ScoreMeasure],
        sourceItemID: String,
        selectedDuration: NotationDuration
    ) -> NotationNoteInsertionPlan? {
        guard let context = planningContext(
            in: measures,
            sourceItemID: sourceItemID,
            selectedDuration: selectedDuration
        ) else { return nil }

        return materializedPlan(from: context)
    }

    static func planInsertion(
        in measures: [ScoreMeasure],
        placement: NotationNotePlacement
    ) -> NotationNoteInsertionPlan? {
        guard let context = insertionPlanningContext(
            in: measures,
            placement: placement
        ) else { return nil }

        return materializedPlan(from: context)
    }

    static func canPlanInsertion(
        in measures: [ScoreMeasure],
        placement: NotationNotePlacement
    ) -> Bool {
        insertionPlanningContext(in: measures, placement: placement) != nil
    }

    private static func insertionPlanningContext(
        in measures: [ScoreMeasure],
        placement: NotationNotePlacement
    ) -> PlanningContext? {
        let orderedMeasures = measures.sorted(by: notationTieMeasureSort)
        guard let measureIndex = orderedMeasures.firstIndex(where: {
            $0.number == placement.measure.number
                && abs($0.startTime - placement.measure.startTime) < NotationMeasureTiming.timelineTolerance
                && abs($0.endTime - placement.measure.endTime) < NotationMeasureTiming.timelineTolerance
        }), placement.displayDuration.durationInQuarterNotes > NotationMeasureTiming.timelineTolerance,
           abs(
               placement.durationInQuarterNotes - placement.displayDuration.durationInQuarterNotes
           ) < NotationMeasureTiming.timelineTolerance,
           let consumedSpans = consumedMeasureSpans(
               in: orderedMeasures,
               startMeasureIndex: measureIndex,
               startOffset: placement.offsetInQuarterNotes,
               requiredDuration: placement.durationInQuarterNotes
           )
        else {
            return nil
        }

        return PlanningContext(
            orderedMeasures: orderedMeasures,
            sourceLocation: nil,
            partID: placement.partID,
            pitch: placement.pitch,
            selectedDuration: placement.displayDuration,
            consumedSpans: consumedSpans
        )
    }

    private static func materializedPlan(
        from context: PlanningContext
    ) -> NotationNoteInsertionPlan? {
        let orderedMeasures = context.orderedMeasures
        let consumedSpans = context.consumedSpans

        var insertedByMeasureIndex: [Int: [NotationMeasureItem]] = [:]
        var insertedItems: [NotationMeasureItem] = []
        let usesSelectedDurationDirectly = consumedSpans.count == 1
            && abs(consumedSpans[0].duration - context.selectedDuration.durationInQuarterNotes)
                < NotationMeasureTiming.timelineTolerance

        for span in consumedSpans {
            let durations: [NotationDuration]
            if usesSelectedDurationDirectly {
                durations = [context.selectedDuration]
            } else {
                guard let decomposition = generatedDurations(for: span.duration) else {
                    return nil
                }
                durations = decomposition
            }

            let measure = orderedMeasures[span.measureIndex]
            var offset = span.startOffset
            for duration in durations {
                let item = NotationMeasureItem(
                    partID: context.partID,
                    kind: .note,
                    pitch: context.pitch,
                    measureNumber: measure.number,
                    measureStartTime: measure.startTime,
                    offsetInQuarterNotes: offset,
                    durationInQuarterNotes: duration.durationInQuarterNotes,
                    displayDuration: duration
                )
                insertedByMeasureIndex[span.measureIndex, default: []].append(item)
                insertedItems.append(item)
                offset += duration.durationInQuarterNotes
            }
        }

        guard let firstInserted = insertedItems.first,
              let finalInserted = insertedItems.last
        else {
            return nil
        }

        var linkedItemsByID: [String: NotationMeasureItem] = [:]
        if let sourceLocation = context.sourceLocation {
            var linkedSource = sourceLocation.item.persistedCopy()
            linkedSource.tieTargetItemID = firstInserted.id
            linkedItemsByID[linkedSource.id] = linkedSource
        }
        for index in insertedItems.indices {
            var item = insertedItems[index]
            item.tieTargetItemID = index < insertedItems.index(before: insertedItems.endIndex)
                ? insertedItems[insertedItems.index(after: index)].id
                : nil
            linkedItemsByID[item.id] = item
        }

        var affectedMeasureIndices = Set(consumedSpans.map(\.measureIndex))
        if let sourceLocation = context.sourceLocation {
            affectedMeasureIndices.insert(sourceLocation.measureIndex)
        }
        let replacements = affectedMeasureIndices.sorted().compactMap { measureIndex -> NotationNoteInsertionMeasureReplacement? in
            let measure = orderedMeasures[measureIndex]
            let inserted = insertedByMeasureIndex[measureIndex, default: []].compactMap {
                linkedItemsByID[$0.id]
            }
            let items = replacementItems(
                in: measure,
                partID: context.partID,
                insertedItems: inserted,
                linkedItemsByID: linkedItemsByID
            )
            return NotationNoteInsertionMeasureReplacement(
                measureNumber: measure.number,
                measureStartTime: measure.startTime,
                partID: context.partID,
                items: items
            )
        }

        return NotationNoteInsertionPlan(
            replacements: replacements,
            firstItemID: firstInserted.id,
            firstMeasureNumber: firstInserted.measureNumber,
            firstMeasureStartTime: firstInserted.measureStartTime,
            finalItemID: finalInserted.id,
            finalMeasureNumber: finalInserted.measureNumber,
            finalMeasureStartTime: finalInserted.measureStartTime,
            partID: context.partID
        )
    }

    private struct SourceLocation {
        var measureIndex: Int
        var item: NotationMeasureItem
    }

    private struct PlanningContext {
        var orderedMeasures: [ScoreMeasure]
        var sourceLocation: SourceLocation?
        var partID: NotationPartID
        var pitch: NotationPitch
        var selectedDuration: NotationDuration
        var consumedSpans: [ConsumedSpan]
    }

    private struct ConsumedSpan {
        var measureIndex: Int
        var startOffset: Double
        var duration: Double

        var endOffset: Double { startOffset + duration }
    }

    private static func planningContext(
        in measures: [ScoreMeasure],
        sourceItemID: String,
        selectedDuration: NotationDuration
    ) -> PlanningContext? {
        let orderedMeasures = measures.sorted(by: notationTieMeasureSort)
        guard let sourceLocation = sourceLocation(
            in: orderedMeasures,
            sourceItemID: sourceItemID
        ),
              !sourceLocation.item.isSynthesized,
              sourceLocation.item.kind == .note,
              let pitch = sourceLocation.item.pitch,
              sourceLocation.item.tieTargetItemID == nil,
              selectedDuration.durationInQuarterNotes > NotationMeasureTiming.timelineTolerance,
              let consumedSpans = consumedMeasureSpans(
                in: orderedMeasures,
                startMeasureIndex: sourceLocation.measureIndex,
                startOffset: sourceLocation.item.offsetInQuarterNotes
                    + sourceLocation.item.durationInQuarterNotes,
                requiredDuration: selectedDuration.durationInQuarterNotes
              ),
              !containsExactLogicalNote(
                in: orderedMeasures,
                excluding: sourceLocation.item.id,
                partID: sourceLocation.item.partID,
                pitch: pitch,
                spans: consumedSpans
              )
        else {
            return nil
        }

        return PlanningContext(
            orderedMeasures: orderedMeasures,
            sourceLocation: sourceLocation,
            partID: sourceLocation.item.partID,
            pitch: pitch,
            selectedDuration: selectedDuration,
            consumedSpans: consumedSpans
        )
    }

    private static func sourceLocation(
        in measures: [ScoreMeasure],
        sourceItemID: String
    ) -> SourceLocation? {
        for measureIndex in measures.indices {
            if let item = measures[measureIndex].notationItems.first(where: { $0.id == sourceItemID }) {
                return SourceLocation(measureIndex: measureIndex, item: item)
            }
        }
        return nil
    }

    private static func consumedMeasureSpans(
        in measures: [ScoreMeasure],
        startMeasureIndex: Int,
        startOffset: Double,
        requiredDuration: Double
    ) -> [ConsumedSpan]? {
        var measureIndex = startMeasureIndex
        var cursor = startOffset
        var remaining = requiredDuration
        var spans: [ConsumedSpan] = []

        while remaining > NotationMeasureTiming.timelineTolerance {
            guard measures.indices.contains(measureIndex) else { return nil }
            let measure = measures[measureIndex]
            let measureLength = NotationMeasureTiming.quarterLength(for: measure.attributes.timeSignature)
            if cursor >= measureLength - NotationMeasureTiming.timelineTolerance {
                measureIndex += 1
                cursor = 0
                continue
            }

            let consumed = min(remaining, measureLength - cursor)
            guard consumed > NotationMeasureTiming.timelineTolerance else { return nil }

            if let lastIndex = spans.indices.last, spans[lastIndex].measureIndex == measureIndex {
                guard abs(spans[lastIndex].endOffset - cursor) < NotationMeasureTiming.timelineTolerance else {
                    return nil
                }
                spans[lastIndex].duration += consumed
            } else {
                spans.append(ConsumedSpan(
                    measureIndex: measureIndex,
                    startOffset: cursor,
                    duration: consumed
                ))
            }

            cursor += consumed
            remaining -= consumed
        }

        return spans
    }

    private static func containsExactLogicalNote(
        in measures: [ScoreMeasure],
        excluding sourceItemID: String,
        partID: NotationPartID,
        pitch: NotationPitch,
        spans: [ConsumedSpan]
    ) -> Bool {
        guard let firstSpan = spans.first, let lastSpan = spans.last else { return false }
        var measureStarts: [Double] = []
        var cursor = 0.0
        for measure in measures {
            measureStarts.append(cursor)
            cursor += NotationMeasureTiming.quarterLength(for: measure.attributes.timeSignature)
        }
        let targetStart = measureStarts[firstSpan.measureIndex] + firstSpan.startOffset
        let targetEnd = measureStarts[lastSpan.measureIndex] + lastSpan.endOffset
        let notes = measures.flatMap(\.notationItems).filter {
            !$0.isSynthesized
                && $0.id != sourceItemID
                && $0.partID == partID
                && $0.kind == .note
                && $0.pitch == pitch
        }
        var visited: Set<String> = []

        for note in notes where !visited.contains(note.id) {
            let chainIDs = NotationNoteEditPlanner.logicalChainItemIDs(
                in: notes,
                containing: note.id,
                partID: partID
            )
            visited.formUnion(chainIDs)
            let chainSpans = notes.filter { chainIDs.contains($0.id) }.compactMap { item -> NotationTimeSpan? in
                guard let measureIndex = measures.firstIndex(where: {
                    $0.number == item.measureNumber
                        && abs($0.startTime - item.measureStartTime) < NotationMeasureTiming.timelineTolerance
                }) else { return nil }
                let start = measureStarts[measureIndex] + item.offsetInQuarterNotes
                return NotationTimeSpan(start: start, end: start + item.durationInQuarterNotes)
            }
            guard let chainStart = chainSpans.map(\.start).min(),
                  let chainEnd = chainSpans.map(\.end).max()
            else { continue }
            if abs(chainStart - targetStart) < NotationMeasureTiming.timelineTolerance,
               abs(chainEnd - targetEnd) < NotationMeasureTiming.timelineTolerance {
                return true
            }
        }
        return false
    }

    private static func generatedDurations(for length: Double) -> [NotationDuration]? {
        var candidates = NotationDuration.entryDenominators.flatMap { denominator in
            [
                NotationDuration(denominator: denominator, isDotted: true),
                NotationDuration(denominator: denominator)
            ]
        }
        candidates.append(NotationDuration(denominator: 32))
        candidates.sort { $0.durationInQuarterNotes > $1.durationInQuarterNotes }

        var remaining = length
        var output: [NotationDuration] = []
        for duration in candidates {
            while remaining >= duration.durationInQuarterNotes - NotationMeasureTiming.timelineTolerance {
                output.append(duration)
                remaining -= duration.durationInQuarterNotes
            }
        }

        return abs(remaining) < NotationMeasureTiming.timelineTolerance ? output : nil
    }

    private static func replacementItems(
        in measure: ScoreMeasure,
        partID: NotationPartID,
        insertedItems: [NotationMeasureItem],
        linkedItemsByID: [String: NotationMeasureItem]
    ) -> [NotationMeasureItem] {
        let existingNotes = measure.notationItems.compactMap { item -> NotationMeasureItem? in
            guard item.partID == partID, item.kind == .note, !item.isSynthesized else { return nil }
            return linkedItemsByID[item.id] ?? item.persistedCopy()
        }
        return NotationMeasureRhythmRecomposer.persistedItems(
            in: measure,
            partID: partID,
            notes: existingNotes + insertedItems,
            preferredRests: measure.notationItems
        )
    }

}

enum NotationTieContinuationBoundary {
    static func endTime(
        in measures: [ScoreMeasure],
        sourceItemID: String,
        continuationDurationInQuarterNotes: Double
    ) -> TimeInterval? {
        let orderedMeasures = measures.sorted(by: notationTieMeasureSort)
        guard continuationDurationInQuarterNotes > NotationMeasureTiming.timelineTolerance,
              let sourceMeasureIndex = orderedMeasures.firstIndex(where: { measure in
                  measure.notationItems.contains(where: { $0.id == sourceItemID })
              }),
              let sourceItem = orderedMeasures[sourceMeasureIndex].notationItems.first(where: {
                  $0.id == sourceItemID
              })
        else {
            return nil
        }

        var measureIndex = sourceMeasureIndex
        var cursor = sourceItem.offsetInQuarterNotes + sourceItem.durationInQuarterNotes
        var remaining = continuationDurationInQuarterNotes

        while remaining > NotationMeasureTiming.timelineTolerance {
            guard orderedMeasures.indices.contains(measureIndex) else { return nil }
            let measure = orderedMeasures[measureIndex]
            let measureLength = NotationMeasureTiming.quarterLength(
                for: measure.attributes.timeSignature
            )
            guard cursor <= measureLength + NotationMeasureTiming.timelineTolerance else {
                return nil
            }

            if cursor >= measureLength - NotationMeasureTiming.timelineTolerance {
                measureIndex += 1
                cursor = 0
                continue
            }

            let consumed = min(remaining, measureLength - cursor)
            cursor += consumed
            remaining -= consumed

            if remaining <= NotationMeasureTiming.timelineTolerance {
                return NotationMeasureTiming.time(forQuarterOffset: cursor, in: measure)
            }

            measureIndex += 1
            cursor = 0
        }

        return nil
    }

}

private func notationTieMeasureSort(
    _ lhs: ScoreMeasure,
    _ rhs: ScoreMeasure
) -> Bool {
    if lhs.number != rhs.number { return lhs.number < rhs.number }
    return lhs.startTime < rhs.startTime
}

private func notationTieItemSort(
    _ lhs: NotationMeasureItem,
    _ rhs: NotationMeasureItem
) -> Bool {
    if abs(lhs.offsetInQuarterNotes - rhs.offsetInQuarterNotes) > NotationMeasureTiming.timelineTolerance {
        return lhs.offsetInQuarterNotes < rhs.offsetInQuarterNotes
    }
    return lhs.id < rhs.id
}
