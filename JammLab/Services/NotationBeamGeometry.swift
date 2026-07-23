import CoreGraphics
import Foundation

enum NotationBeamVoiceRole: Equatable {
    case single
    case upper
    case lower
}

enum NotationBeamStemDirectionResolver {
    static func direction(
        staffPositions: [Int],
        explicitDirections: [NotationStemDirection] = [],
        voiceRole: NotationBeamVoiceRole = .single,
        middleStaffPosition: Int = 4
    ) -> NotationStemDirection {
        if let explicitDirection = explicitDirections.first {
            return explicitDirection
        }

        switch voiceRole {
        case .upper:
            return .up
        case .lower:
            return .down
        case .single:
            break
        }

        guard let firstPosition = staffPositions.first else {
            return .up
        }
        let highestPosition = staffPositions.min() ?? middleStaffPosition
        let lowestPosition = staffPositions.max() ?? middleStaffPosition
        let distanceAbove = max(0, middleStaffPosition - highestPosition)
        let distanceBelow = max(0, lowestPosition - middleStaffPosition)

        if distanceBelow > distanceAbove {
            return .up
        }
        if distanceAbove > distanceBelow {
            return .down
        }
        return NotationStemDirection.direction(forStaffPosition: firstPosition)
    }
}

enum NotationBeamSelectionResolver {
    static func containsMatch(
        _ selection: NotationItemSelection?,
        in group: NotationBeamGroup
    ) -> Bool {
        guard let selection else { return false }
        return group.notes.contains { note in
            note.members.contains {
                selection.matches($0.selection)
            }
        }
    }
}

struct NotationBeamMember: Equatable, Identifiable {
    var selection: NotationItemSelection
    var displayDuration: NotationDuration
    var staffPosition: Int
    var noteheadStyle: DrumNoteheadStyle
    var x: CGFloat
    var y: CGFloat

    var id: String { selection.id }
    var itemID: String { selection.itemID }
}

struct NotationBeamNote: Equatable, Identifiable {
    var members: [NotationBeamMember]
    var positionInQuarterNotes: Double
    var durationInQuarterNotes: Double
    var beamLevelCount: Int
    var stemX: CGFloat
    var stemAttachmentY: CGFloat
    var stemEndY: CGFloat

    var id: String {
        members.map(\.id).sorted().joined(separator: "|")
    }
}

struct NotationBeamAnchor: Equatable {
    var x: CGFloat
    var y: CGFloat
}

struct NotationBeamSegment: Equatable, Identifiable {
    var level: Int
    var start: CGPoint
    var end: CGPoint
    var thickness: CGFloat
    var isBeamlet: Bool

    var id: String {
        "\(level)-\(start.x)-\(start.y)-\(end.x)-\(end.y)-\(isBeamlet)"
    }

    var polygonPoints: [CGPoint] {
        let halfThickness = thickness / 2
        return [
            CGPoint(x: start.x, y: start.y - halfThickness),
            CGPoint(x: end.x, y: end.y - halfThickness),
            CGPoint(x: end.x, y: end.y + halfThickness),
            CGPoint(x: start.x, y: start.y + halfThickness)
        ]
    }
}

struct NotationBeamGroup: Equatable, Identifiable {
    var measure: ScoreMeasure
    var voiceIndex: Int
    var notes: [NotationBeamNote]
    var startPositionInQuarterNotes: Double
    var endPositionInQuarterNotes: Double
    var stemDirection: NotationStemDirection
    var beamLevelCount: Int
    var primaryStartAnchor: NotationBeamAnchor
    var primaryEndAnchor: NotationBeamAnchor
    var primarySegment: NotationBeamSegment
    var secondarySegments: [NotationBeamSegment]

    var id: String {
        "\(measure.id)-\(voiceIndex)-\(notes.map(\.id).joined(separator: "|"))"
    }

    var notationItemIDs: Set<String> {
        Set(notes.flatMap { $0.members.map(\.itemID) })
    }
}

struct NotationBeamLayoutMetrics: Equatable {
    var staffSpace: CGFloat
    var beamThickness: CGFloat
    var beamGap: CGFloat
    var minimumStemLength: CGFloat
    var stemXOffset: CGFloat
    var maximumSlopeRatio: CGFloat
    var maximumSlopeDelta: CGFloat
    var quantizationStep: CGFloat
    var maximumBeamletLength: CGFloat

    init(staffSpace: CGFloat) {
        self.staffSpace = staffSpace
        beamThickness = staffSpace
            * AppTheme.Timeline.notationBeamThicknessInStaffSpaces
        beamGap = staffSpace
            * AppTheme.Timeline.notationBeamGapInStaffSpaces
        minimumStemLength = staffSpace
            * AppTheme.Timeline.notationStemMinimumLengthInStaffSpaces
        stemXOffset = staffSpace
            * AppTheme.Timeline.notationStemXOffsetInStaffSpaces
        maximumSlopeRatio = AppTheme.Timeline.notationBeamMaximumSlopeRatio
        maximumSlopeDelta = staffSpace
            * AppTheme.Timeline.notationBeamMaximumSlopeInStaffSpaces
        quantizationStep = staffSpace
            * AppTheme.Timeline.notationBeamQuantizationInStaffSpaces
        maximumBeamletLength = staffSpace
            * AppTheme.Timeline.notationBeamletMaximumLengthInStaffSpaces
    }
}

struct NotationBeamEventStack {
    var members: [NotationBeamMember]
    var positionInQuarterNotes: Double
    var durationInQuarterNotes: Double
    var beamLevelCount: Int
    var isRest: Bool
}

enum NotationBeamGeometryBuilder {
    static func group(
        rhythmicGroup: NotationBeamRhythmicGroup,
        orderedStacks stacks: [NotationBeamEventStack],
        measure: ScoreMeasure,
        forcedStemDirection: NotationStemDirection?,
        metrics: NotationBeamLayoutMetrics
    ) -> NotationBeamGroup? {
        let groupStacks = rhythmicGroup.eventIndices.compactMap {
            stacks.indices.contains($0) ? stacks[$0] : nil
        }
        guard groupStacks.count >= 2 else { return nil }

        let staffPositions = groupStacks.flatMap { $0.members.map(\.staffPosition) }
        let stemDirection = NotationBeamStemDirectionResolver.direction(
            staffPositions: staffPositions,
            explicitDirections: forcedStemDirection.map { [$0] } ?? []
        )
        var notes = groupStacks.map {
            makeBeamNote(stack: $0, direction: stemDirection, metrics: metrics)
        }
        guard !notes.isEmpty else {
            return nil
        }

        let primaryAnchors = primaryAnchors(
            notes: notes,
            direction: stemDirection,
            metrics: metrics
        )
        let primarySegment = NotationBeamSegment(
            level: 0,
            start: CGPoint(
                x: primaryAnchors.start.x,
                y: primaryAnchors.start.y
            ),
            end: CGPoint(
                x: primaryAnchors.end.x,
                y: primaryAnchors.end.y
            ),
            thickness: metrics.beamThickness,
            isBeamlet: false
        )
        let levelCount = notes.map(\.beamLevelCount).max() ?? 1
        let secondaryContext = SecondaryBeamLayoutContext(
            notes: notes,
            direction: stemDirection,
            primaryStart: primaryAnchors.start,
            primaryEnd: primaryAnchors.end,
            rules: NotationBeamMeterRules.rules(
                for: measure.attributes.timeSignature
            ),
            metrics: metrics
        )
        let secondarySegments = makeSecondarySegments(
            levelCount: levelCount,
            context: secondaryContext
        )

        for index in notes.indices {
            let primaryY = beamY(
                at: notes[index].stemX,
                start: primaryAnchors.start,
                end: primaryAnchors.end
            )
            let outermostLevel = max(0, notes[index].beamLevelCount - 1)
            let levelOffset = CGFloat(outermostLevel)
                * (metrics.beamThickness + metrics.beamGap)
            switch stemDirection {
            case .up:
                notes[index].stemEndY = primaryY - levelOffset
                    - metrics.beamThickness / 2
            case .down:
                notes[index].stemEndY = primaryY + levelOffset
                    + metrics.beamThickness / 2
            }
        }

        return NotationBeamGroup(
            measure: measure,
            voiceIndex: 0,
            notes: notes,
            startPositionInQuarterNotes: rhythmicGroup.startPositionInQuarterNotes,
            endPositionInQuarterNotes: rhythmicGroup.endPositionInQuarterNotes,
            stemDirection: stemDirection,
            beamLevelCount: levelCount,
            primaryStartAnchor: primaryAnchors.start,
            primaryEndAnchor: primaryAnchors.end,
            primarySegment: primarySegment,
            secondarySegments: secondarySegments
        )
    }

    static func beamY(
        at x: CGFloat,
        start: NotationBeamAnchor,
        end: NotationBeamAnchor
    ) -> CGFloat {
        let width = end.x - start.x
        guard abs(width) > .ulpOfOne else { return start.y }
        let progress = (x - start.x) / width
        return start.y + (end.y - start.y) * progress
    }

    private static func makeBeamNote(
        stack: NotationBeamEventStack,
        direction: NotationStemDirection,
        metrics: NotationBeamLayoutMetrics
    ) -> NotationBeamNote {
        let memberXs = stack.members.map(\.x)
        let memberYs = stack.members.map(\.y)
        let stemX: CGFloat
        let attachmentY: CGFloat
        switch direction {
        case .up:
            stemX = (memberXs.max() ?? 0) + metrics.stemXOffset
            attachmentY = memberYs.max() ?? 0
        case .down:
            stemX = (memberXs.min() ?? 0) - metrics.stemXOffset
            attachmentY = memberYs.min() ?? 0
        }
        return NotationBeamNote(
            members: stack.members,
            positionInQuarterNotes: stack.positionInQuarterNotes,
            durationInQuarterNotes: stack.durationInQuarterNotes,
            beamLevelCount: stack.beamLevelCount,
            stemX: stemX,
            stemAttachmentY: attachmentY,
            stemEndY: attachmentY
        )
    }

    private static func primaryAnchors(
        notes: [NotationBeamNote],
        direction: NotationStemDirection,
        metrics: NotationBeamLayoutMetrics
    ) -> (start: NotationBeamAnchor, end: NotationBeamAnchor) {
        let beamSideYs = notes.map { note -> CGFloat in
            let ys = note.members.map(\.y)
            switch direction {
            case .up:
                return ys.min() ?? note.stemAttachmentY
            case .down:
                return ys.max() ?? note.stemAttachmentY
            }
        }
        let startX = notes.first?.stemX ?? 0
        let endX = notes.last?.stemX ?? startX
        let horizontalDistance = abs(endX - startX)
        let desiredDelta = (beamSideYs.last ?? 0) - (beamSideYs.first ?? 0)
        let maximumDelta = min(
            metrics.maximumSlopeDelta,
            horizontalDistance * metrics.maximumSlopeRatio
        )
        var slopeDelta = min(maximumDelta, max(-maximumDelta, desiredDelta))
        slopeDelta = quantized(slopeDelta, step: metrics.quantizationStep)
        if abs(desiredDelta) < metrics.quantizationStep / 2 {
            slopeDelta = 0
        }

        let halfThickness = metrics.beamThickness / 2
        var startY: CGFloat
        switch direction {
        case .up:
            startY = (beamSideYs.first ?? 0)
                - metrics.minimumStemLength
                - halfThickness
        case .down:
            startY = (beamSideYs.first ?? 0)
                + metrics.minimumStemLength
                + halfThickness
        }
        startY = quantized(startY, step: metrics.quantizationStep)
        var endY = startY + slopeDelta

        var requiredParallelShift: CGFloat = 0
        for (index, note) in notes.enumerated() {
            let progress = horizontalDistance > .ulpOfOne
                ? (note.stemX - startX) / (endX - startX)
                : 0
            let lineY = startY + (endY - startY) * progress
            switch direction {
            case .up:
                let maximumAllowedY = beamSideYs[index]
                    - metrics.minimumStemLength
                    - halfThickness
                requiredParallelShift = max(
                    requiredParallelShift,
                    lineY - maximumAllowedY
                )
            case .down:
                let minimumAllowedY = beamSideYs[index]
                    + metrics.minimumStemLength
                    + halfThickness
                requiredParallelShift = max(
                    requiredParallelShift,
                    minimumAllowedY - lineY
                )
            }
        }

        if requiredParallelShift > 0 {
            let quantizedShift = quantizedAwayFromZero(
                requiredParallelShift,
                step: metrics.quantizationStep
            )
            switch direction {
            case .up:
                startY -= quantizedShift
                endY -= quantizedShift
            case .down:
                startY += quantizedShift
                endY += quantizedShift
            }
        }

        return (
            NotationBeamAnchor(x: startX, y: startY),
            NotationBeamAnchor(x: endX, y: endY)
        )
    }

    private static func makeSecondarySegments(
        levelCount: Int,
        context: SecondaryBeamLayoutContext
    ) -> [NotationBeamSegment] {
        guard levelCount > 1 else { return [] }
        var output: [NotationBeamSegment] = []

        for level in 1..<levelCount {
            var run: [Int] = []

            func appendRun() {
                guard let firstIndex = run.first, let lastIndex = run.last else {
                    run.removeAll(keepingCapacity: true)
                    return
                }
                if run.count >= 2 {
                    output.append(segment(
                        level: level,
                        startX: context.notes[firstIndex].stemX,
                        endX: context.notes[lastIndex].stemX,
                        context: context,
                        isBeamlet: false
                    ))
                } else {
                    output.append(beamlet(
                        level: level,
                        noteIndex: firstIndex,
                        context: context
                    ))
                }
                run.removeAll(keepingCapacity: true)
            }

            for index in context.notes.indices {
                guard context.notes[index].beamLevelCount > level else {
                    appendRun()
                    continue
                }
                if let previousIndex = run.last,
                   hasSecondaryBreak(
                       from: context.notes[previousIndex].positionInQuarterNotes,
                       to: context.notes[index].positionInQuarterNotes,
                       rules: context.rules
                   ) {
                    appendRun()
                }
                run.append(index)
            }
            appendRun()
        }

        return output
    }

    private static func segment(
        level: Int,
        startX: CGFloat,
        endX: CGFloat,
        context: SecondaryBeamLayoutContext,
        isBeamlet: Bool
    ) -> NotationBeamSegment {
        let offset = CGFloat(level)
            * (context.metrics.beamThickness + context.metrics.beamGap)
        let signedOffset = context.direction == .up ? -offset : offset
        return NotationBeamSegment(
            level: level,
            start: CGPoint(
                x: startX,
                y: beamY(
                    at: startX,
                    start: context.primaryStart,
                    end: context.primaryEnd
                ) + signedOffset
            ),
            end: CGPoint(
                x: endX,
                y: beamY(
                    at: endX,
                    start: context.primaryStart,
                    end: context.primaryEnd
                ) + signedOffset
            ),
            thickness: context.metrics.beamThickness,
            isBeamlet: isBeamlet
        )
    }

    private static func beamlet(
        level: Int,
        noteIndex: Int,
        context: SecondaryBeamLayoutContext
    ) -> NotationBeamSegment {
        let pointsRight = beamletPointsRight(
            noteIndex: noteIndex,
            level: level,
            notes: context.notes,
            rules: context.rules
        )
        let adjacentIndex = pointsRight ? noteIndex + 1 : noteIndex - 1
        let adjacentDistance: CGFloat
        if context.notes.indices.contains(adjacentIndex) {
            adjacentDistance = abs(
                context.notes[adjacentIndex].stemX
                    - context.notes[noteIndex].stemX
            )
        } else if context.notes.count >= 2 {
            let fallbackIndex = noteIndex == 0 ? 1 : noteIndex - 1
            adjacentDistance = abs(
                context.notes[fallbackIndex].stemX
                    - context.notes[noteIndex].stemX
            )
        } else {
            adjacentDistance = context.metrics.maximumBeamletLength * 2
        }
        let length = min(
            context.metrics.maximumBeamletLength,
            max(
                context.metrics.beamThickness * 2,
                adjacentDistance * 0.5
            )
        )
        let startX = context.notes[noteIndex].stemX
        let endX = startX + (pointsRight ? length : -length)
        return segment(
            level: level,
            startX: startX,
            endX: endX,
            context: context,
            isBeamlet: true
        )
    }

    private static func beamletPointsRight(
        noteIndex: Int,
        level: Int,
        notes: [NotationBeamNote],
        rules: NotationBeamMeterRules?
    ) -> Bool {
        if noteIndex == 0 {
            return true
        }
        if noteIndex == notes.indices.last {
            return false
        }

        let notePosition = notes[noteIndex].positionInQuarterNotes
        let leftIndex = notes.indices.reversed().first {
            $0 < noteIndex
                && notes[$0].beamLevelCount > level
                && !hasSecondaryBreak(
                    from: notes[$0].positionInQuarterNotes,
                    to: notePosition,
                    rules: rules
                )
        }
        let rightIndex = notes.indices.first {
            $0 > noteIndex
                && notes[$0].beamLevelCount > level
                && !hasSecondaryBreak(
                    from: notePosition,
                    to: notes[$0].positionInQuarterNotes,
                    rules: rules
                )
        }

        switch (leftIndex, rightIndex) {
        case let (.some(left), .some(right)):
            let leftDistance = notePosition
                - notes[left].positionInQuarterNotes
            let rightDistance = notes[right].positionInQuarterNotes
                - notePosition
            if abs(leftDistance - rightDistance)
                > NotationMeasureTiming.timelineTolerance {
                return rightDistance < leftDistance
            }
        case (.none, .some):
            return true
        case (.some, .none):
            return false
        case (.none, .none):
            break
        }

        if let interval = rules?.secondaryBreakIntervalInQuarterNotes {
            let subgroupStart = floor(
                (notePosition + NotationMeasureTiming.timelineTolerance)
                    / interval
            ) * interval
            return notePosition < subgroupStart + interval / 2
        }
        return noteIndex < notes.count / 2
    }

    private static func hasSecondaryBreak(
        from start: Double,
        to end: Double,
        rules: NotationBeamMeterRules?
    ) -> Bool {
        guard let interval = rules?.secondaryBreakIntervalInQuarterNotes else {
            return false
        }
        let startGroup = Int(floor(
            (start + NotationMeasureTiming.timelineTolerance) / interval
        ))
        let endGroup = Int(floor(
            (end + NotationMeasureTiming.timelineTolerance) / interval
        ))
        return startGroup != endGroup
    }

    private static func quantized(_ value: CGFloat, step: CGFloat) -> CGFloat {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

    private static func quantizedAwayFromZero(
        _ value: CGFloat,
        step: CGFloat
    ) -> CGFloat {
        guard step > 0 else { return value }
        return ceil(value / step) * step
    }
}

private struct SecondaryBeamLayoutContext {
    var notes: [NotationBeamNote]
    var direction: NotationStemDirection
    var primaryStart: NotationBeamAnchor
    var primaryEnd: NotationBeamAnchor
    var rules: NotationBeamMeterRules?
    var metrics: NotationBeamLayoutMetrics
}
