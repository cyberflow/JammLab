import Foundation

enum NotationNoteResizeEdge: Equatable {
    case leading
    case trailing
}

struct NotationGridPosition: Equatable {
    var measureNumber: Int
    var measureStartTime: TimeInterval
    var offsetInQuarterNotes: Double

    init(measure: ScoreMeasure, offsetInQuarterNotes: Double) {
        measureNumber = measure.number
        measureStartTime = measure.startTime
        self.offsetInQuarterNotes = offsetInQuarterNotes
    }
}

enum NotationNoteEditOperation: Equatable {
    case move(
        grabbedPosition: NotationGridPosition,
        targetPosition: NotationGridPosition,
        semitoneDelta: Int
    )
    case resize(edge: NotationNoteResizeEdge, boundary: NotationGridPosition)
}

private extension NotationNoteEditOperation {
    var actionName: String {
        switch self {
        case .move:
            return "Move MIDI Note"
        case .resize:
            return "Resize MIDI Note"
        }
    }
}

struct NotationNoteEditRequest: Equatable {
    var partID: NotationPartID
    var sourceItemID: String
    var operation: NotationNoteEditOperation
}

enum NotationNoteEditInvalidReason: Equatable {
    case audioBoundary
    case duplicate
    case duration
    case pitch
    case position
}

struct NotationNoteEditPlan: Equatable {
    var replacements: [NotationNoteInsertionMeasureReplacement]
    var rootItemID: String
    var rootMeasureNumber: Int
    var rootMeasureStartTime: TimeInterval
    var partID: NotationPartID
    var actionName: String
}

struct NotationNoteEditPreview: Equatable {
    var request: NotationNoteEditRequest
    var sourceItemIDs: Set<String>
    var rootItemID: String
    var previewItems: [NotationMeasureItem]
    var plan: NotationNoteEditPlan?
    var invalidReason: NotationNoteEditInvalidReason?

    var isValid: Bool {
        plan != nil
    }
}

enum NotationRhythmicGrid {
    static let subdivisionInQuarterNotes = 0.25
    static let ticksPerQuarter = 8
    static let stepTicks = Int(
        (subdivisionInQuarterNotes * Double(ticksPerQuarter)).rounded()
    )
}

enum NotationNoteEditPlanner {
    struct PreparedSession {
        let partID: NotationPartID
        fileprivate let context: Context
        let audioDuration: TimeInterval

        func preview(_ request: NotationNoteEditRequest) -> NotationNoteEditPreview? {
            guard request.partID == partID else { return nil }
            return NotationNoteEditPlanner.preview(
                in: context,
                request: request,
                audioDuration: audioDuration
            )
        }
    }

    static func prepareSession(
        measures: [ScoreMeasure],
        partID: NotationPartID,
        audioDuration: TimeInterval
    ) -> PreparedSession? {
        guard audioDuration > 0, let context = Context(measures: measures) else { return nil }
        return PreparedSession(
            partID: partID,
            context: context,
            audioDuration: audioDuration
        )
    }

    static func preview(
        in measures: [ScoreMeasure],
        request: NotationNoteEditRequest,
        audioDuration: TimeInterval
    ) -> NotationNoteEditPreview? {
        prepareSession(
            measures: measures,
            partID: request.partID,
            audioDuration: audioDuration
        )?.preview(request)
    }

    private static func preview(
        in context: Context,
        request: NotationNoteEditRequest,
        audioDuration: TimeInterval
    ) -> NotationNoteEditPreview? {
        guard let sourceChain = context.logicalChain(
                containing: request.sourceItemID,
                partID: request.partID
              ),
              let rootPitch = sourceChain.locations.first?.item.pitch,
              let sourceStartTick = sourceChain.startTick(in: context),
              let sourceEndTick = sourceChain.endTick(in: context),
              sourceEndTick > sourceStartTick
        else {
            return nil
        }

        let sourceItemIDs = Set(sourceChain.locations.map(\.item.id))
        func invalid(
            _ reason: NotationNoteEditInvalidReason,
            previewItems: [NotationMeasureItem] = []
        ) -> NotationNoteEditPreview {
            NotationNoteEditPreview(
                request: request,
                sourceItemIDs: sourceItemIDs,
                rootItemID: sourceChain.rootItemID,
                previewItems: previewItems,
                plan: nil,
                invalidReason: reason
            )
        }

        let candidate: Candidate
        switch request.operation {
        case .move(let grabbedPosition, let targetPosition, let semitoneDelta):
            guard let grabbedTick = context.globalTick(for: grabbedPosition),
                  let targetTick = context.globalTick(for: targetPosition)
            else {
                return invalid(.position)
            }
            let targetStartTick = sourceStartTick + targetTick - grabbedTick
            let targetPitchNumber = rootPitch.midiNoteNumber + semitoneDelta
            guard (0...127).contains(targetPitchNumber) else {
                return invalid(.pitch)
            }
            candidate = Candidate(
                startTick: targetStartTick,
                endTick: targetStartTick + sourceEndTick - sourceStartTick,
                midiNoteNumber: targetPitchNumber
            )
        case .resize(let edge, let boundary):
            guard let boundaryTick = context.globalTick(for: boundary) else {
                return invalid(.position)
            }
            candidate = Candidate(
                startTick: edge == .leading ? boundaryTick : sourceStartTick,
                endTick: edge == .trailing ? boundaryTick : sourceEndTick,
                midiNoteNumber: rootPitch.midiNoteNumber
            )
        }

        guard candidate.startTick >= 0,
              candidate.endTick <= context.totalTicks,
              candidate.endTick - candidate.startTick >= NotationRhythmicGrid.stepTicks
        else {
            return invalid(candidate.endTick <= candidate.startTick ? .duration : .position)
        }

        guard let previewItems = materializedItems(
            for: candidate,
            rootItemID: sourceChain.rootItemID,
            partID: request.partID,
            context: context,
            preservedPitch: candidate.midiNoteNumber == rootPitch.midiNoteNumber
                ? rootPitch
                : nil,
            preservedExplicitAccidental: candidate.midiNoteNumber == rootPitch.midiNoteNumber
                ? sourceChain.locations.first?.item.explicitAccidental
                : nil
        ) else {
            return invalid(.duration)
        }

        guard let startTime = context.absoluteTime(atGlobalTick: candidate.startTick),
              let endTime = context.absoluteTime(atGlobalTick: candidate.endTick),
              startTime >= -NotationMeasureTiming.timelineTolerance,
              endTime <= audioDuration + NotationMeasureTiming.timelineTolerance
        else {
            return invalid(.audioBoundary, previewItems: previewItems)
        }

        if candidate.startTick == sourceStartTick,
           candidate.endTick == sourceEndTick,
           candidate.midiNoteNumber == rootPitch.midiNoteNumber {
            return NotationNoteEditPreview(
                request: request,
                sourceItemIDs: sourceItemIDs,
                rootItemID: sourceChain.rootItemID,
                previewItems: sourceChain.locations.map(\.item),
                plan: nil,
                invalidReason: nil
            )
        }

        guard previewItems.allSatisfy({ item in
            guard let measure = context.measure(for: item), let pitch = item.pitch else { return false }
            return NotationPitchMapper.isEditable(pitch, in: measure.attributes.clef)
        }) else {
            return invalid(.pitch, previewItems: previewItems)
        }

        guard !context.hasExactDuplicate(
            startTick: candidate.startTick,
            endTick: candidate.endTick,
            midiNoteNumber: candidate.midiNoteNumber,
            excluding: sourceItemIDs,
            partID: request.partID
        ) else {
            return invalid(.duplicate, previewItems: previewItems)
        }

        let affectedMeasureIndices = sourceChain.measureIndices.union(
            previewItems.compactMap(context.measureIndex(for:))
        )
        let replacements = affectedMeasureIndices.sorted().map { measureIndex in
            let measure = context.measures[measureIndex]
            let unrelatedNotes = measure.notationItems.filter { item in
                item.partID == request.partID
                    && item.kind == .note
                    && !item.isSynthesized
                    && !sourceItemIDs.contains(item.id)
            }
            let insertedNotes = previewItems.filter {
                $0.measureNumber == measure.number
                    && abs($0.measureStartTime - measure.startTime)
                        < NotationMeasureTiming.timelineTolerance
            }
            return NotationNoteInsertionMeasureReplacement(
                measureNumber: measure.number,
                measureStartTime: measure.startTime,
                partID: request.partID,
                items: recomposedItems(
                    in: measure,
                    partID: request.partID,
                    notes: unrelatedNotes + insertedNotes
                )
            )
        }

        guard let firstItem = previewItems.first else { return nil }
        let plan = NotationNoteEditPlan(
            replacements: replacements,
            rootItemID: firstItem.id,
            rootMeasureNumber: firstItem.measureNumber,
            rootMeasureStartTime: firstItem.measureStartTime,
            partID: request.partID,
            actionName: request.operation.actionName
        )
        return NotationNoteEditPreview(
            request: request,
            sourceItemIDs: sourceItemIDs,
            rootItemID: sourceChain.rootItemID,
            previewItems: previewItems,
            plan: plan,
            invalidReason: nil
        )
    }

    static func logicalChainItemIDs(
        in items: [NotationMeasureItem],
        containing sourceItemID: String,
        partID: NotationPartID
    ) -> Set<String> {
        let notes = items.filter {
            $0.partID == partID && $0.kind == .note && !$0.isSynthesized
        }
        let itemsByID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        guard itemsByID[sourceItemID] != nil else { return [] }
        var previousByTarget: [String: String] = [:]
        for item in notes {
            if let targetID = item.tieTargetItemID, previousByTarget[targetID] == nil {
                previousByTarget[targetID] = item.id
            }
        }

        var rootID = sourceItemID
        var visited: Set<String> = [rootID]
        while let previousID = previousByTarget[rootID],
              itemsByID[previousID] != nil,
              !visited.contains(previousID) {
            rootID = previousID
            visited.insert(previousID)
        }

        var result: Set<String> = []
        var itemID: String? = rootID
        while let currentID = itemID,
              let item = itemsByID[currentID],
              !result.contains(currentID) {
            result.insert(currentID)
            itemID = item.tieTargetItemID
        }
        return result
    }

    private static func materializedItems(
        for candidate: Candidate,
        rootItemID: String,
        partID: NotationPartID,
        context: Context,
        preservedPitch: NotationPitch?,
        preservedExplicitAccidental: NotationAccidental?
    ) -> [NotationMeasureItem]? {
        var output: [NotationMeasureItem] = []
        guard let pitchMeasureIndex = context.measureIndex(
            containingGlobalTick: candidate.startTick
        ) else { return nil }
        let pitch = preservedPitch ?? NotationPitchMapper.pitch(
            forMIDINoteNumber: candidate.midiNoteNumber,
            keySignature: context.measures[pitchMeasureIndex].attributes.keySignature
        )

        for measureIndex in context.measures.indices {
            let measureStartTick = context.measureStartTicks[measureIndex]
            let measureEndTick = measureStartTick + context.measureTickLengths[measureIndex]
            let spanStart = max(candidate.startTick, measureStartTick)
            let spanEnd = min(candidate.endTick, measureEndTick)
            guard spanEnd > spanStart else { continue }

            let measure = context.measures[measureIndex]
            guard let durations = exactDurations(forTickCount: spanEnd - spanStart) else {
                return nil
            }
            var tickOffset = spanStart - measureStartTick
            for duration in durations {
                let item = NotationMeasureItem(
                    id: output.isEmpty ? rootItemID : UUID().uuidString,
                    partID: partID,
                    kind: .note,
                    pitch: pitch,
                    explicitAccidental: output.isEmpty ? preservedExplicitAccidental : nil,
                    measureNumber: measure.number,
                    measureStartTime: measure.startTime,
                    offsetInQuarterNotes: Double(tickOffset) / Double(NotationRhythmicGrid.ticksPerQuarter),
                    durationInQuarterNotes: duration.durationInQuarterNotes,
                    displayDuration: duration
                )
                output.append(item)
                tickOffset += Int((duration.durationInQuarterNotes * Double(NotationRhythmicGrid.ticksPerQuarter)).rounded())
            }
        }

        guard !output.isEmpty else { return nil }
        for index in output.indices {
            output[index].tieTargetItemID = index < output.index(before: output.endIndex)
                ? output[output.index(after: index)].id
                : nil
        }
        return output
    }

    private static func exactDurations(forTickCount tickCount: Int) -> [NotationDuration]? {
        guard tickCount > 0 else { return nil }
        let candidates = (NotationDuration.entryDenominators + [32])
            .flatMap { denominator -> [NotationDuration] in
                if denominator == 32 {
                    return [NotationDuration(denominator: denominator)]
                }
                if denominator == 1 {
                    return [NotationDuration(denominator: denominator)]
                }
                return [
                    NotationDuration(denominator: denominator, isDotted: true),
                    NotationDuration(denominator: denominator)
                ]
            }
            .compactMap { duration -> (duration: NotationDuration, ticks: Int)? in
                let rawTicks = duration.durationInQuarterNotes * Double(NotationRhythmicGrid.ticksPerQuarter)
                let ticks = Int(rawTicks.rounded())
                guard abs(rawTicks - Double(ticks)) < NotationMeasureTiming.timelineTolerance,
                      ticks > 0,
                      tickCount % NotationRhythmicGrid.stepTicks != 0
                        || ticks % NotationRhythmicGrid.stepTicks == 0
                else { return nil }
                return (duration, ticks)
            }
            .sorted { lhs, rhs in lhs.ticks > rhs.ticks }

        var solutions = Array<[NotationDuration]?>(repeating: nil, count: tickCount + 1)
        solutions[0] = []
        for ticks in 1...tickCount {
            for candidate in candidates where candidate.ticks <= ticks {
                guard let prefix = solutions[ticks - candidate.ticks] else { continue }
                let proposed = prefix + [candidate.duration]
                if solutions[ticks] == nil || proposed.count < solutions[ticks]!.count {
                    solutions[ticks] = proposed
                }
            }
        }
        return solutions[tickCount]?.sorted {
            $0.durationInQuarterNotes > $1.durationInQuarterNotes
        }
    }

    private static func recomposedItems(
        in measure: ScoreMeasure,
        partID: NotationPartID,
        notes: [NotationMeasureItem]
    ) -> [NotationMeasureItem] {
        NotationMeasureRhythmRecomposer.persistedItems(
            in: measure,
            partID: partID,
            notes: notes,
            preferredRests: measure.notationItems
        )
    }

}

private extension NotationNoteEditPlanner {
    struct Candidate {
        var startTick: Int
        var endTick: Int
        var midiNoteNumber: Int
    }

    struct ItemLocation {
        var measureIndex: Int
        var item: NotationMeasureItem
    }

    struct LogicalChain {
        var locations: [ItemLocation]

        var rootItemID: String {
            locations.first?.item.id ?? ""
        }

        var measureIndices: Set<Int> {
            Set(locations.map(\.measureIndex))
        }

        func startTick(in context: Context) -> Int? {
            guard let first = locations.first else { return nil }
            return context.globalTick(measureIndex: first.measureIndex, quarterOffset: first.item.offsetInQuarterNotes)
        }

        func endTick(in context: Context) -> Int? {
            guard let last = locations.last else { return nil }
            return context.globalTick(
                measureIndex: last.measureIndex,
                quarterOffset: last.item.offsetInQuarterNotes + last.item.durationInQuarterNotes
            )
        }
    }

    struct Context {
        var measures: [ScoreMeasure]
        var measureStartTicks: [Int]
        var measureTickLengths: [Int]
        var locationsByItemID: [String: ItemLocation]
        var previousItemIDByTargetID: [String: String]
        var nextItemIDBySourceID: [String: String]

        var totalTicks: Int {
            guard let start = measureStartTicks.last, let length = measureTickLengths.last else { return 0 }
            return start + length
        }

        init?(measures: [ScoreMeasure]) {
            let orderedMeasures = measures.sorted {
                if $0.number != $1.number { return $0.number < $1.number }
                return $0.startTime < $1.startTime
            }
            guard !orderedMeasures.isEmpty else { return nil }

            var starts: [Int] = []
            var lengths: [Int] = []
            var cursor = 0
            for measure in orderedMeasures {
                let rawTicks = NotationMeasureTiming.quarterLength(
                    for: measure.attributes.timeSignature
                ) * Double(NotationRhythmicGrid.ticksPerQuarter)
                let ticks = Int(rawTicks.rounded())
                guard ticks > 0,
                      abs(rawTicks - Double(ticks)) < NotationMeasureTiming.timelineTolerance
                else { return nil }
                starts.append(cursor)
                lengths.append(ticks)
                cursor += ticks
            }

            var locations: [String: ItemLocation] = [:]
            for measureIndex in orderedMeasures.indices {
                for item in orderedMeasures[measureIndex].notationItems where locations[item.id] == nil {
                    locations[item.id] = ItemLocation(measureIndex: measureIndex, item: item)
                }
            }

            let connections = NotationTieResolver.connections(in: orderedMeasures)
            self.measures = orderedMeasures
            measureStartTicks = starts
            measureTickLengths = lengths
            locationsByItemID = locations
            previousItemIDByTargetID = Dictionary(
                uniqueKeysWithValues: connections.map { ($0.target.item.id, $0.source.item.id) }
            )
            nextItemIDBySourceID = Dictionary(
                uniqueKeysWithValues: connections.map { ($0.source.item.id, $0.target.item.id) }
            )
        }

        func logicalChain(containing sourceItemID: String, partID: NotationPartID) -> LogicalChain? {
            guard let source = locationsByItemID[sourceItemID],
                  source.item.partID == partID,
                  source.item.kind == .note,
                  !source.item.isSynthesized,
                  source.item.pitch != nil
            else { return nil }

            var rootID = sourceItemID
            var visited: Set<String> = [rootID]
            while let previousID = previousItemIDByTargetID[rootID], !visited.contains(previousID) {
                rootID = previousID
                visited.insert(previousID)
            }

            var chainIDs: [String] = []
            var itemID: String? = rootID
            visited = []
            while let currentID = itemID, !visited.contains(currentID) {
                guard let location = locationsByItemID[currentID],
                      location.item.partID == partID,
                      location.item.kind == .note,
                      !location.item.isSynthesized,
                      location.item.pitch != nil
                else { return nil }
                chainIDs.append(currentID)
                visited.insert(currentID)
                itemID = nextItemIDBySourceID[currentID]
            }

            let chain = chainIDs.compactMap { locationsByItemID[$0] }
            return chain.isEmpty ? nil : LogicalChain(locations: chain)
        }

        func globalTick(for position: NotationGridPosition) -> Int? {
            guard let measureIndex = measures.firstIndex(where: {
                $0.number == position.measureNumber
                    && abs($0.startTime - position.measureStartTime)
                        < NotationMeasureTiming.timelineTolerance
            }) else { return nil }
            guard let tick = globalTick(
                measureIndex: measureIndex,
                quarterOffset: position.offsetInQuarterNotes
            ), (tick - measureStartTicks[measureIndex]) % NotationRhythmicGrid.stepTicks == 0
            else { return nil }
            return tick
        }

        func globalTick(measureIndex: Int, quarterOffset: Double) -> Int? {
            guard measures.indices.contains(measureIndex) else { return nil }
            let rawTicks = quarterOffset * Double(NotationRhythmicGrid.ticksPerQuarter)
            let ticks = Int(rawTicks.rounded())
            guard abs(rawTicks - Double(ticks)) < NotationMeasureTiming.timelineTolerance,
                  ticks >= 0,
                  ticks <= measureTickLengths[measureIndex]
            else { return nil }
            return measureStartTicks[measureIndex] + ticks
        }

        func absoluteTime(atGlobalTick tick: Int) -> TimeInterval? {
            guard tick >= 0, tick <= totalTicks else { return nil }
            for measureIndex in measures.indices {
                let start = measureStartTicks[measureIndex]
                let end = start + measureTickLengths[measureIndex]
                guard tick <= end else { continue }
                let offset = Double(tick - start) / Double(NotationRhythmicGrid.ticksPerQuarter)
                return NotationMeasureTiming.time(forQuarterOffset: offset, in: measures[measureIndex])
            }
            return measures.last?.endTime
        }

        func measure(for item: NotationMeasureItem) -> ScoreMeasure? {
            measures.first {
                $0.number == item.measureNumber
                    && abs($0.startTime - item.measureStartTime)
                        < NotationMeasureTiming.timelineTolerance
            }
        }

        func measureIndex(for item: NotationMeasureItem) -> Int? {
            measures.firstIndex {
                $0.number == item.measureNumber
                    && abs($0.startTime - item.measureStartTime)
                        < NotationMeasureTiming.timelineTolerance
            }
        }

        func measureIndex(containingGlobalTick tick: Int) -> Int? {
            guard tick >= 0, tick <= totalTicks else { return nil }
            for measureIndex in measures.indices {
                let start = measureStartTicks[measureIndex]
                let end = start + measureTickLengths[measureIndex]
                if tick >= start,
                   tick < end || (measureIndex == measures.index(before: measures.endIndex) && tick == end) {
                    return measureIndex
                }
            }
            return nil
        }

        func hasExactDuplicate(
            startTick: Int,
            endTick: Int,
            midiNoteNumber: Int,
            excluding sourceItemIDs: Set<String>,
            partID: NotationPartID
        ) -> Bool {
            var visitedRoots: Set<String> = []
            for location in locationsByItemID.values {
                let item = location.item
                guard item.partID == partID,
                      item.kind == .note,
                      !item.isSynthesized,
                      !sourceItemIDs.contains(item.id),
                      item.pitch?.midiNoteNumber == midiNoteNumber,
                      let chain = logicalChain(containing: item.id, partID: partID),
                      !visitedRoots.contains(chain.rootItemID)
                else { continue }
                visitedRoots.insert(chain.rootItemID)
                if chain.startTick(in: self) == startTick,
                   chain.endTick(in: self) == endTick {
                    return true
                }
            }
            return false
        }
    }
}
