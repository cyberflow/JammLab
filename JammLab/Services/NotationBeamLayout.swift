import CoreGraphics
import Foundation

enum NotationBeamLayout {
    static func groups(
        from layoutItems: [NotationItemLayoutItem],
        staffTop: CGFloat,
        staffSpace: CGFloat = AppTheme.Timeline.notationStaffLineSpacing
    ) -> [NotationBeamGroup] {
        guard staffSpace > 0 else { return [] }
        let metrics = NotationBeamLayoutMetrics(staffSpace: staffSpace)
        let measureGroups = Dictionary(grouping: layoutItems, by: {
            NotationBeamMeasureKey(
                measureNumber: $0.measure.number,
                measureStartTick: tick($0.measure.startTime),
                partID: $0.notationItem.partID
            )
        })

        return measureGroups.values
            .flatMap { measureItems -> [NotationBeamGroup] in
                guard let measure = measureItems.first?.measure else { return [] }
                return beamLanes(from: measureItems).flatMap { lane in
                    let stacks = eventStacks(
                        from: lane.items,
                        staffTop: staffTop,
                        staffSpace: staffSpace
                    )
                    let events = stacks.indices.map { index in
                        NotationBeamGroupingEvent(
                            sourceIndex: index,
                            positionInQuarterNotes: stacks[index]
                                .positionInQuarterNotes,
                            durationInQuarterNotes: stacks[index]
                                .durationInQuarterNotes,
                            beamLevelCount: stacks[index].beamLevelCount,
                            isRest: stacks[index].isRest
                        )
                    }
                    let rhythmicGroups = NotationBeamGrouper.groups(
                        timeSignature: measure.attributes.timeSignature,
                        events: events
                    )
                    return rhythmicGroups.compactMap {
                        NotationBeamGeometryBuilder.group(
                            rhythmicGroup: $0,
                            orderedStacks: stacks,
                            measure: measure,
                            forcedStemDirection: lane.stemDirection,
                            metrics: metrics
                        )
                    }
                }
            }
            .sorted {
                if $0.measure.startTime != $1.measure.startTime {
                    return $0.measure.startTime < $1.measure.startTime
                }
                if abs(
                    $0.startPositionInQuarterNotes
                        - $1.startPositionInQuarterNotes
                ) > NotationMeasureTiming.timelineTolerance {
                    return $0.startPositionInQuarterNotes
                        < $1.startPositionInQuarterNotes
                }
                return beamDirectionSortIndex($0.stemDirection)
                    < beamDirectionSortIndex($1.stemDirection)
            }
    }

    static func beamY(
        at x: CGFloat,
        start: NotationBeamAnchor,
        end: NotationBeamAnchor
    ) -> CGFloat {
        NotationBeamGeometryBuilder.beamY(
            at: x,
            start: start,
            end: end
        )
    }

    private static func beamLanes(
        from items: [NotationItemLayoutItem]
    ) -> [NotationBeamLane] {
        guard let measure = items.first?.measure,
              measure.attributes.clef == .drums
        else {
            return [NotationBeamLane(items: items, stemDirection: nil)]
        }

        let directions = Set(items.compactMap(drumStemDirection(for:)))
        return directions
            .sorted {
                beamDirectionSortIndex($0) < beamDirectionSortIndex($1)
            }
            .map { direction in
                NotationBeamLane(
                    items: items.filter {
                        $0.notationItem.kind == .rest
                            || drumStemDirection(for: $0) == direction
                    },
                    stemDirection: direction
                )
            }
    }

    private static func drumStemDirection(
        for item: NotationItemLayoutItem
    ) -> NotationStemDirection? {
        guard item.notationItem.kind == .note,
              let pitch = item.notationItem.pitch
        else { return nil }
        return item.stemDirectionOverride
            ?? NotationDrumStemLayout.direction(
                forMIDINoteNumber: pitch.midiNoteNumber
            )
    }

    private static func beamDirectionSortIndex(
        _ direction: NotationStemDirection
    ) -> Int {
        direction == .up ? 0 : 1
    }

    private static func eventStacks(
        from layoutItems: [NotationItemLayoutItem],
        staffTop: CGFloat,
        staffSpace: CGFloat
    ) -> [NotationBeamEventStack] {
        let groups = Dictionary(grouping: layoutItems) { item in
            NotationBeamEventKey(
                positionTick: tick(item.notationItem.offsetInQuarterNotes),
                durationTick: tick(item.notationItem.durationInQuarterNotes),
                kind: item.notationItem.kind.rawValue
            )
        }

        return groups.values.compactMap { items in
            guard let first = items.first else { return nil }
            if first.notationItem.kind == .rest {
                return NotationBeamEventStack(
                    members: [],
                    positionInQuarterNotes: first.notationItem
                        .offsetInQuarterNotes,
                    durationInQuarterNotes: first.notationItem
                        .durationInQuarterNotes,
                    beamLevelCount: 0,
                    isRest: true
                )
            }

            let members = items.compactMap { item -> NotationBeamMember? in
                guard let pitch = item.notationItem.pitch else { return nil }
                let presentation = NotationNotePresentationResolver.presentation(
                    for: pitch,
                    clef: item.measure.attributes.clef
                )
                return NotationBeamMember(
                    selection: item.selection,
                    displayDuration: item.notationItem.displayDuration,
                    staffPosition: presentation.staffPosition,
                    noteheadStyle: presentation.noteheadStyle,
                    x: item.x,
                    y: NotationNotePlacementResolver.yPosition(
                        forStaffPosition: presentation.staffPosition,
                        staffTop: staffTop,
                        lineSpacing: staffSpace
                    )
                )
            }
            .sorted {
                if $0.staffPosition != $1.staffPosition {
                    return $0.staffPosition < $1.staffPosition
                }
                return $0.id < $1.id
            }
            guard !members.isEmpty else { return nil }

            return NotationBeamEventStack(
                members: members,
                positionInQuarterNotes: first.notationItem.offsetInQuarterNotes,
                durationInQuarterNotes: first.notationItem
                    .durationInQuarterNotes,
                beamLevelCount: beamLevelCount(
                    for: first.notationItem.displayDuration
                ),
                isRest: false
            )
        }
        .sorted {
            if abs($0.positionInQuarterNotes - $1.positionInQuarterNotes)
                > NotationMeasureTiming.timelineTolerance {
                return $0.positionInQuarterNotes < $1.positionInQuarterNotes
            }
            if $0.isRest != $1.isRest {
                return $0.isRest
            }
            return $0.durationInQuarterNotes > $1.durationInQuarterNotes
        }
    }

    private static func beamLevelCount(for duration: NotationDuration) -> Int {
        switch duration.denominator {
        case 8:
            return 1
        case 16:
            return 2
        default:
            return 0
        }
    }

    private static func tick(_ value: Double) -> Int {
        Int((value * 1_000_000).rounded())
    }
}

private struct NotationBeamLane {
    var items: [NotationItemLayoutItem]
    var stemDirection: NotationStemDirection?
}

private struct NotationBeamMeasureKey: Hashable {
    var measureNumber: Int
    var measureStartTick: Int
    var partID: NotationPartID
}

private struct NotationBeamEventKey: Hashable {
    var positionTick: Int
    var durationTick: Int
    var kind: String
}
