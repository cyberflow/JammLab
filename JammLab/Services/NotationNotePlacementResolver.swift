import CoreGraphics
import Foundation

struct NotationNotePlacement: Equatable {
    var measure: ScoreMeasure
    var partID: NotationPartID
    var targetRestID: String
    var offsetInQuarterNotes: Double
    var durationInQuarterNotes: Double
    var displayDuration: NotationDuration
    var pitch: NotationPitch

    var x: CGFloat
    var y: CGFloat

    init(
        measure: ScoreMeasure,
        partID: NotationPartID = .main,
        targetRestID: String,
        offsetInQuarterNotes: Double,
        durationInQuarterNotes: Double,
        displayDuration: NotationDuration,
        pitch: NotationPitch,
        x: CGFloat,
        y: CGFloat
    ) {
        self.measure = measure
        self.partID = partID
        self.targetRestID = targetRestID
        self.offsetInQuarterNotes = offsetInQuarterNotes
        self.durationInQuarterNotes = durationInQuarterNotes
        self.displayDuration = displayDuration
        self.pitch = pitch
        self.x = x
        self.y = y
    }
}

struct NotationRestPlacement: Equatable {
    var measure: ScoreMeasure
    var partID: NotationPartID
    var targetRestID: String
    var offsetInQuarterNotes: Double
    var durationInQuarterNotes: Double
    var displayDuration: NotationDuration

    var x: CGFloat

    init(
        measure: ScoreMeasure,
        partID: NotationPartID = .main,
        targetRestID: String,
        offsetInQuarterNotes: Double,
        durationInQuarterNotes: Double,
        displayDuration: NotationDuration,
        x: CGFloat
    ) {
        self.measure = measure
        self.partID = partID
        self.targetRestID = targetRestID
        self.offsetInQuarterNotes = offsetInQuarterNotes
        self.durationInQuarterNotes = durationInQuarterNotes
        self.displayDuration = displayDuration
        self.x = x
    }
}

struct NotationRestSpan: Equatable {
    var rests: [NotationMeasureItem]
    var startOffsetInQuarterNotes: Double
    var endOffsetInQuarterNotes: Double

    var availableDurationInQuarterNotes: Double {
        max(0, endOffsetInQuarterNotes - startOffsetInQuarterNotes)
    }

    func contains(_ item: NotationMeasureItem) -> Bool {
        rests.contains {
            $0.id == item.id
                && abs($0.offsetInQuarterNotes - item.offsetInQuarterNotes) < NotationMeasureTiming.timelineTolerance
        }
    }
}

enum NotationNotePlacementResolver {
    static func placement(
        in measure: ScoreMeasure,
        geometry: NotationMeasureCanvasGeometry,
        point: CGPoint,
        staffTop: CGFloat,
        selectedDuration: NotationDuration,
        partID: NotationPartID = .main,
        lineSpacing: CGFloat = AppTheme.Timeline.notationStaffLineSpacing
    ) -> NotationNotePlacement? {
        guard lineSpacing > 0,
              let pitchPosition = staffPosition(forY: point.y, staffTop: staffTop, lineSpacing: lineSpacing)
        else {
            return nil
        }

        let selectedLength = selectedDuration.durationInQuarterNotes
        guard selectedLength > NotationMeasureTiming.timelineTolerance else { return nil }

        guard let targetRest = targetRest(
            in: measure,
            geometry: geometry,
            x: point.x,
            requiredDurationInQuarterNotes: selectedLength
        ) else { return nil }

        let pitch = NotationPitchMapper.pitch(
            forStaffPosition: pitchPosition,
            keySignature: measure.attributes.keySignature
        )
        let x = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: targetRest.offsetInQuarterNotes,
            timeSignature: measure.attributes.timeSignature
        )
        let y = yPosition(forStaffPosition: pitchPosition, staffTop: staffTop, lineSpacing: lineSpacing)

        return NotationNotePlacement(
            measure: measure,
            partID: partID,
            targetRestID: targetRest.id,
            offsetInQuarterNotes: targetRest.offsetInQuarterNotes,
            durationInQuarterNotes: selectedLength,
            displayDuration: selectedDuration,
            pitch: pitch,
            x: x,
            y: y
        )
    }

    static func restPlacement(
        in measure: ScoreMeasure,
        geometry: NotationMeasureCanvasGeometry,
        point: CGPoint,
        staffTop: CGFloat,
        selectedDuration: NotationDuration,
        partID: NotationPartID = .main,
        lineSpacing: CGFloat = AppTheme.Timeline.notationStaffLineSpacing
    ) -> NotationRestPlacement? {
        guard isWithinEntryYRange(point.y, staffTop: staffTop, lineSpacing: lineSpacing) else {
            return nil
        }

        let selectedLength = selectedDuration.durationInQuarterNotes
        guard selectedLength > NotationMeasureTiming.timelineTolerance else { return nil }
        guard let targetRest = targetRest(
            in: measure,
            geometry: geometry,
            x: point.x,
            requiredDurationInQuarterNotes: selectedLength
        ) else { return nil }

        let x = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: targetRest.offsetInQuarterNotes,
            timeSignature: measure.attributes.timeSignature
        )

        return NotationRestPlacement(
            measure: measure,
            partID: partID,
            targetRestID: targetRest.id,
            offsetInQuarterNotes: targetRest.offsetInQuarterNotes,
            durationInQuarterNotes: selectedLength,
            displayDuration: selectedDuration,
            x: x
        )
    }

    static func singleFullMeasureWholeRest(in measure: ScoreMeasure) -> NotationMeasureItem? {
        guard measure.notationItems.count == 1,
              let item = measure.notationItems.first,
              item.kind == .rest,
              item.displayDuration.denominator == NotationDuration.defaultDenominator,
              abs(item.offsetInQuarterNotes) <= NotationMeasureTiming.timelineTolerance
        else {
            return nil
        }

        let measureLength = NotationMeasureTiming.quarterLength(for: measure.attributes.timeSignature)
        guard abs(item.durationInQuarterNotes - measureLength) <= NotationMeasureTiming.timelineTolerance else {
            return nil
        }
        return item
    }

    static func restSpan(
        in measure: ScoreMeasure,
        from targetRest: NotationMeasureItem,
        requiredDurationInQuarterNotes requiredDuration: Double
    ) -> NotationRestSpan? {
        guard targetRest.kind == .rest,
              requiredDuration > NotationMeasureTiming.timelineTolerance
        else {
            return nil
        }

        let orderedItems = measure.notationItems.sorted(by: notationItemSort)
        guard let targetIndex = orderedItems.firstIndex(where: {
            $0.kind == .rest
                && $0.id == targetRest.id
                && abs($0.offsetInQuarterNotes - targetRest.offsetInQuarterNotes) < NotationMeasureTiming.timelineTolerance
        }) ?? orderedItems.firstIndex(where: {
            $0.kind == .rest
                && abs($0.offsetInQuarterNotes - targetRest.offsetInQuarterNotes) < NotationMeasureTiming.timelineTolerance
        }) else {
            return nil
        }

        var rests: [NotationMeasureItem] = []
        let startOffset = orderedItems[targetIndex].offsetInQuarterNotes
        let requiredEndOffset = startOffset + requiredDuration
        var cursor = startOffset

        for item in orderedItems[targetIndex...] {
            guard item.kind == .rest else { return nil }
            guard abs(item.offsetInQuarterNotes - cursor) <= NotationMeasureTiming.timelineTolerance else {
                return nil
            }

            rests.append(item)
            cursor = item.offsetInQuarterNotes + item.durationInQuarterNotes
            if cursor >= requiredEndOffset - NotationMeasureTiming.timelineTolerance {
                return NotationRestSpan(
                    rests: rests,
                    startOffsetInQuarterNotes: startOffset,
                    endOffsetInQuarterNotes: cursor
                )
            }
        }

        return nil
    }

    static func restSpan(
        in measure: ScoreMeasure,
        matching placement: NotationNotePlacement
    ) -> NotationRestSpan? {
        restSpan(
            in: measure,
            targetRestID: placement.targetRestID,
            offsetInQuarterNotes: placement.offsetInQuarterNotes,
            requiredDurationInQuarterNotes: placement.durationInQuarterNotes
        )
    }

    static func restSpan(
        in measure: ScoreMeasure,
        matching placement: NotationRestPlacement
    ) -> NotationRestSpan? {
        restSpan(
            in: measure,
            targetRestID: placement.targetRestID,
            offsetInQuarterNotes: placement.offsetInQuarterNotes,
            requiredDurationInQuarterNotes: placement.durationInQuarterNotes
        )
    }

    private static func restSpan(
        in measure: ScoreMeasure,
        targetRestID: String,
        offsetInQuarterNotes: Double,
        requiredDurationInQuarterNotes requiredDuration: Double
    ) -> NotationRestSpan? {
        guard let targetRest = measure.notationItems.first(where: {
            $0.kind == .rest
                && $0.id == targetRestID
                && abs($0.offsetInQuarterNotes - offsetInQuarterNotes) < NotationMeasureTiming.timelineTolerance
        }) ?? measure.notationItems.first(where: {
            $0.kind == .rest
                && abs($0.offsetInQuarterNotes - offsetInQuarterNotes) < NotationMeasureTiming.timelineTolerance
        }) else {
            return nil
        }

        return restSpan(
            in: measure,
            from: targetRest,
            requiredDurationInQuarterNotes: requiredDuration
        )
    }

    static func ledgerLineStaffPositions(forStaffPosition staffPosition: Int) -> [Int] {
        if staffPosition < 0 {
            return stride(from: -2, through: staffPosition, by: -2).map { $0 }
        }

        if staffPosition > 8 {
            return stride(from: 10, through: staffPosition, by: 2).map { $0 }
        }

        return []
    }

    private static func targetRest(
        in measure: ScoreMeasure,
        geometry: NotationMeasureCanvasGeometry,
        x: CGFloat,
        requiredDurationInQuarterNotes requiredDuration: Double
    ) -> NotationMeasureItem? {
        if let fullMeasureWholeRest = singleFullMeasureWholeRest(in: measure),
           restSpan(
               in: measure,
               from: fullMeasureWholeRest,
               requiredDurationInQuarterNotes: requiredDuration
           ) != nil {
            return fullMeasureWholeRest
        }

        let rawProgress = NotationMeasureLayout.notationAnchorProgress(
            atX: x,
            geometry: geometry
        )
        let rawOffset = rawProgress * NotationMeasureTiming.quarterLength(for: measure.attributes.timeSignature)
        let eligibleRests = measure.notationItems
            .filter {
                $0.kind == .rest
                    && restSpan(
                        in: measure,
                        from: $0,
                        requiredDurationInQuarterNotes: requiredDuration
                    ) != nil
            }
        guard !eligibleRests.isEmpty else { return nil }

        if let containingRest = eligibleRests.first(where: {
            restContains(rawOffset, in: $0)
        }) {
            return containingRest
        }

        return eligibleRests.min {
            let lhsDistance = abs($0.offsetInQuarterNotes - rawOffset)
            let rhsDistance = abs($1.offsetInQuarterNotes - rawOffset)
            if abs(lhsDistance - rhsDistance) > NotationMeasureTiming.timelineTolerance {
                return lhsDistance < rhsDistance
            }

            return $0.offsetInQuarterNotes < $1.offsetInQuarterNotes
        } ?? eligibleRests[0]
    }

    private static func restContains(
        _ offset: Double,
        in rest: NotationMeasureItem
    ) -> Bool {
        let start = rest.offsetInQuarterNotes
        let end = rest.offsetInQuarterNotes + rest.durationInQuarterNotes
        return offset >= start - NotationMeasureTiming.timelineTolerance
            && offset < end - NotationMeasureTiming.timelineTolerance
    }

    private static func notationItemSort(_ lhs: NotationMeasureItem, _ rhs: NotationMeasureItem) -> Bool {
        if abs(lhs.offsetInQuarterNotes - rhs.offsetInQuarterNotes) > NotationMeasureTiming.timelineTolerance {
            return lhs.offsetInQuarterNotes < rhs.offsetInQuarterNotes
        }

        return lhs.id < rhs.id
    }

    static func staffPosition(
        forY y: CGFloat,
        staffTop: CGFloat,
        lineSpacing: CGFloat = AppTheme.Timeline.notationStaffLineSpacing
    ) -> Int? {
        guard isWithinEntryYRange(y, staffTop: staffTop, lineSpacing: lineSpacing) else { return nil }

        let halfSpacing = lineSpacing / 2
        let rawPosition = ((y - staffTop) / halfSpacing).rounded()
        return min(
            NotationPitchMapper.maximumStaffPosition,
            max(NotationPitchMapper.minimumStaffPosition, Int(rawPosition))
        )
    }

    static func clampedStaffPosition(
        forY y: CGFloat,
        staffTop: CGFloat,
        lineSpacing: CGFloat = AppTheme.Timeline.notationStaffLineSpacing
    ) -> Int? {
        guard lineSpacing > 0 else { return nil }
        let halfSpacing = lineSpacing / 2
        let rawPosition = ((y - staffTop) / halfSpacing).rounded()
        return min(
            NotationPitchMapper.maximumStaffPosition,
            max(NotationPitchMapper.minimumStaffPosition, Int(rawPosition))
        )
    }

    static func yPosition(
        forStaffPosition staffPosition: Int,
        staffTop: CGFloat,
        lineSpacing: CGFloat = AppTheme.Timeline.notationStaffLineSpacing
    ) -> CGFloat {
        staffTop + CGFloat(staffPosition) * lineSpacing / 2
    }

    private static func isWithinEntryYRange(
        _ y: CGFloat,
        staffTop: CGFloat,
        lineSpacing: CGFloat
    ) -> Bool {
        guard lineSpacing > 0 else { return false }
        let halfSpacing = lineSpacing / 2
        let minimumY = yPosition(
            forStaffPosition: NotationPitchMapper.minimumStaffPosition,
            staffTop: staffTop,
            lineSpacing: lineSpacing
        ) - halfSpacing
        let maximumY = yPosition(
            forStaffPosition: NotationPitchMapper.maximumStaffPosition,
            staffTop: staffTop,
            lineSpacing: lineSpacing
        ) + halfSpacing
        return y >= minimumY && y <= maximumY
    }
}

enum NotationEntryRecomposer {
    static func recomposedItems(
        in measure: ScoreMeasure,
        replacing restSpan: NotationRestSpan,
        with insertedItem: NotationMeasureItem
    ) -> [NotationMeasureItem] {
        let orderedItems = measure.notationItems.sorted(by: notationItemSort)

        var output: [NotationMeasureItem] = []
        var didInsertItem = false
        for item in orderedItems {
            if restSpan.contains(item) {
                if !didInsertItem {
                    output.append(insertedItem)
                    let insertedItemEnd = insertedItem.offsetInQuarterNotes + insertedItem.durationInQuarterNotes
                    output.append(contentsOf: metricAwareFillerNotationItems(
                        measure: measure,
                        partID: insertedItem.partID,
                        startOffset: insertedItemEnd,
                        remaining: restSpan.endOffsetInQuarterNotes - insertedItemEnd
                    ))
                    didInsertItem = true
                }
                continue
            }

            output.append(item.persistedCopy())
        }

        return output
    }

    private static func metricAwareFillerNotationItems(
        measure: ScoreMeasure,
        partID: NotationPartID,
        startOffset: Double,
        remaining: Double
    ) -> [NotationMeasureItem] {
        guard remaining > NotationMeasureTiming.timelineTolerance else { return [] }

        var output: [NotationMeasureItem] = []
        var cursor = startOffset
        var rest = remaining
        let nextQuarterBoundary = floor(cursor + NotationMeasureTiming.timelineTolerance) + 1
        let distanceToQuarterBoundary = nextQuarterBoundary - cursor
        let isOnQuarterBoundary = abs(cursor.rounded() - cursor) <= NotationMeasureTiming.timelineTolerance

        if !isOnQuarterBoundary,
           distanceToQuarterBoundary > NotationMeasureTiming.timelineTolerance,
           distanceToQuarterBoundary < rest - NotationMeasureTiming.timelineTolerance,
           let duration = exactNotationDuration(for: distanceToQuarterBoundary) {
            output.append(NotationRestItemFactory.restItem(
                partID: partID,
                measureNumber: measure.number,
                measureStartTime: measure.startTime,
                offsetInQuarterNotes: cursor,
                durationInQuarterNotes: distanceToQuarterBoundary,
                displayDuration: duration
            ))
            cursor += distanceToQuarterBoundary
            rest -= distanceToQuarterBoundary
        }

        output.append(contentsOf: NotationRestItemFactory.restItems(
            measureNumber: measure.number,
            measureStartTime: measure.startTime,
            startOffset: cursor,
            remaining: rest,
            partID: partID
        ))
        return output
    }

    private static func exactNotationDuration(for length: Double) -> NotationDuration? {
        NotationDuration.allowedDenominators
            .map(NotationDuration.init(denominator:))
            .first {
                abs($0.durationInQuarterNotes - length) <= NotationMeasureTiming.timelineTolerance
            }
    }

    private static func notationItemSort(_ lhs: NotationMeasureItem, _ rhs: NotationMeasureItem) -> Bool {
        if abs(lhs.offsetInQuarterNotes - rhs.offsetInQuarterNotes) > NotationMeasureTiming.timelineTolerance {
            return lhs.offsetInQuarterNotes < rhs.offsetInQuarterNotes
        }

        return lhs.id < rhs.id
    }
}
