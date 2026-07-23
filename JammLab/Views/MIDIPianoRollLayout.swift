import SwiftUI

struct MIDIPianoRollMeasureCell: Equatable {
    var index: Int
    var x: CGFloat
    var width: CGFloat
    var measure: ScoreMeasure
}

struct MIDIPianoRollNoteLayoutItem: Identifiable, Equatable {
    var measure: ScoreMeasure
    var item: NotationMeasureItem
    var selection: NotationItemSelection
    var rect: CGRect

    var id: String { selection.id }
}

enum MIDIPianoRollEditHitMode: Equatable {
    case body
    case leading
    case trailing
}

struct MIDIPianoRollEditHit: Equatable {
    var layoutItem: MIDIPianoRollNoteLayoutItem
    var mode: MIDIPianoRollEditHitMode
}

struct MIDIPianoRollNoteInteractionGeometry: Identifiable, Equatable {
    var layoutItem: MIDIPianoRollNoteLayoutItem
    var hitRect: CGRect
    var canResizeLeading: Bool
    var canResizeTrailing: Bool

    var id: String { layoutItem.id }

    func hitMode(
        at point: CGPoint,
        handleWidth: CGFloat = AppTheme.Timeline.midiResizeHandleHitWidth
    ) -> MIDIPianoRollEditHitMode? {
        guard hitRect.contains(point) else { return nil }
        let leadingDistance = abs(point.x - layoutItem.rect.minX)
        let trailingDistance = abs(point.x - layoutItem.rect.maxX)
        if canResizeLeading,
           leadingDistance <= handleWidth,
           (!canResizeTrailing || leadingDistance <= trailingDistance) {
            return .leading
        }
        if canResizeTrailing, trailingDistance <= handleWidth {
            return .trailing
        }
        return .body
    }
}

enum MIDIPianoRollAutoPageDirection: Equatable {
    case previous
    case next
}

struct MIDIPianoRollAutoPageTarget: Equatable {
    var direction: MIDIPianoRollAutoPageDirection
    var startTime: TimeInterval
}

enum MIDIPianoRollAutoPage {
    typealias Sleep = @Sendable (UInt64) async -> Void

    static func target(
        pointerX: CGFloat,
        width: CGFloat,
        previousPageStartTime: TimeInterval?,
        nextPageStartTime: TimeInterval?,
        pitchLabelWidth: CGFloat = AppTheme.Timeline.midiPitchLabelWidth
    ) -> MIDIPianoRollAutoPageTarget? {
        if pointerX <= pitchLabelWidth
            + AppTheme.Timeline.midiAutoPageEdgeThreshold,
           let previousPageStartTime {
            return MIDIPianoRollAutoPageTarget(
                direction: .previous,
                startTime: previousPageStartTime
            )
        }
        if pointerX >= width - AppTheme.Timeline.midiAutoPageEdgeThreshold,
           let nextPageStartTime {
            return MIDIPianoRollAutoPageTarget(
                direction: .next,
                startTime: nextPageStartTime
            )
        }
        return nil
    }

    static func schedule(
        delayNanoseconds: UInt64,
        sleep: @escaping Sleep = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        },
        action: @escaping @MainActor @Sendable () -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor in
            await sleep(delayNanoseconds)
            guard !Task.isCancelled else { return }
            action()
        }
    }
}

enum MIDIPianoRollLayout {
    static let midiRange = 0...127

    static func isBlackKey(_ midiNoteNumber: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(((midiNoteNumber % 12) + 12) % 12)
    }

    static func pitchName(_ midiNoteNumber: Int, usesFlats: Bool = false) -> String {
        let number = min(127, max(0, midiNoteNumber))
        let names = usesFlats
            ? ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
            : ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[number % 12])\(number / 12 - 1)"
    }

    static func measureCells(
        visibleMeasures: [ScoreMeasure],
        totalWidth: CGFloat,
        pitchLabelWidth: CGFloat = AppTheme.Timeline.midiPitchLabelWidth
    ) -> [MIDIPianoRollMeasureCell] {
        guard !visibleMeasures.isEmpty else { return [] }
        let gridWidth = max(0, totalWidth - pitchLabelWidth)
        let cellWidth = gridWidth / CGFloat(visibleMeasures.count)
        return visibleMeasures.indices.map { index in
            MIDIPianoRollMeasureCell(
                index: index,
                x: pitchLabelWidth + CGFloat(index) * cellWidth,
                width: cellWidth,
                measure: visibleMeasures[index]
            )
        }
    }

    static func cell(
        atX x: CGFloat,
        cells: [MIDIPianoRollMeasureCell]
    ) -> MIDIPianoRollMeasureCell? {
        cells.first { x >= $0.x && x <= $0.x + $0.width }
    }

    static func snappedQuarterOffset(
        atX x: CGFloat,
        cell: MIDIPianoRollMeasureCell,
        subdivision: Double = NotationRhythmicGrid.subdivisionInQuarterNotes,
        allowsMeasureEnd: Bool = false
    ) -> Double {
        let measureLength = NotationMeasureTiming.quarterLength(
            for: cell.measure.attributes.timeSignature
        )
        guard cell.width > 0, measureLength > 0, subdivision > 0 else { return 0 }
        let progress = min(1, max(0, (x - cell.x) / cell.width))
        let snapped = (Double(progress) * measureLength / subdivision).rounded() * subdivision
        let finalGridOffset = allowsMeasureEnd
            ? measureLength
            : max(0, measureLength - subdivision)
        return min(finalGridOffset, max(0, snapped))
    }

    static func gridPosition(
        atX x: CGFloat,
        cells: [MIDIPianoRollMeasureCell],
        allowsMeasureEnd: Bool = false
    ) -> NotationGridPosition? {
        guard let first = cells.first, let last = cells.last else { return nil }
        let clampedX = min(last.x + last.width, max(first.x, x))
        guard let cell = self.cell(atX: clampedX, cells: cells) else { return nil }
        return NotationGridPosition(
            measure: cell.measure,
            offsetInQuarterNotes: snappedQuarterOffset(
                atX: clampedX,
                cell: cell,
                allowsMeasureEnd: allowsMeasureEnd
            )
        )
    }

    static func xPosition(
        quarterOffset: Double,
        cell: MIDIPianoRollMeasureCell
    ) -> CGFloat {
        let measureLength = NotationMeasureTiming.quarterLength(
            for: cell.measure.attributes.timeSignature
        )
        guard measureLength > 0 else { return cell.x }
        let progress = min(1, max(0, quarterOffset / measureLength))
        return cell.x + CGFloat(progress) * cell.width
    }

    static func midiNoteNumber(
        atY y: CGFloat,
        rowHeight: CGFloat = AppTheme.Timeline.midiPitchRowHeight
    ) -> Int? {
        guard rowHeight > 0, y >= 0 else { return nil }
        let row = Int(floor(y / rowHeight))
        let midiNote = 127 - row
        return midiRange.contains(midiNote) ? midiNote : nil
    }

    static func yPosition(
        forMIDINoteNumber midiNoteNumber: Int,
        rowHeight: CGFloat = AppTheme.Timeline.midiPitchRowHeight
    ) -> CGFloat {
        CGFloat(127 - min(127, max(0, midiNoteNumber))) * rowHeight
    }

    static func noteLayoutItems(
        visibleMeasures: [ScoreMeasure],
        totalWidth: CGFloat,
        notationItems: [NotationMeasureItem]? = nil,
        pitchLabelWidth: CGFloat = AppTheme.Timeline.midiPitchLabelWidth,
        noteInset: CGFloat = AppTheme.Timeline.midiNoteInset,
        rowHeight: CGFloat = AppTheme.Timeline.midiPitchRowHeight
    ) -> [MIDIPianoRollNoteLayoutItem] {
        let cells = measureCells(
            visibleMeasures: visibleMeasures,
            totalWidth: totalWidth,
            pitchLabelWidth: pitchLabelWidth
        )
        return cells.flatMap { cell -> [MIDIPianoRollNoteLayoutItem] in
            let measureLength = NotationMeasureTiming.quarterLength(
                for: cell.measure.attributes.timeSignature
            )
            guard measureLength > 0 else { return [] }
            let items = notationItems?.filter {
                $0.measureNumber == cell.measure.number
                    && abs($0.measureStartTime - cell.measure.startTime)
                        < NotationMeasureTiming.timelineTolerance
            } ?? cell.measure.notationItems
            return items.compactMap { item in
                guard item.kind == .note, let pitch = item.pitch else { return nil }
                let startX = xPosition(quarterOffset: item.offsetInQuarterNotes, cell: cell)
                let unclippedEndX = xPosition(
                    quarterOffset: item.offsetInQuarterNotes + item.durationInQuarterNotes,
                    cell: cell
                )
                let endX = min(cell.x + cell.width, max(startX, unclippedEndX))
                let rect = CGRect(
                    x: startX + noteInset,
                    y: yPosition(forMIDINoteNumber: pitch.midiNoteNumber, rowHeight: rowHeight) + noteInset,
                    width: max(AppTheme.Stroke.thick, endX - startX - noteInset * 2),
                    height: max(AppTheme.Stroke.thick, rowHeight - noteInset * 2)
                )
                return MIDIPianoRollNoteLayoutItem(
                    measure: cell.measure,
                    item: item,
                    selection: NotationItemSelection(measure: cell.measure, item: item),
                    rect: rect
                )
            }
        }
    }

    static func noteInteractionGeometries(
        layoutItems: [MIDIPianoRollNoteLayoutItem],
        tieConnections: [NotationTieConnection]
    ) -> [MIDIPianoRollNoteInteractionGeometry] {
        let incomingTargetIDs = Set(tieConnections.map(\.target.item.id))
        return layoutItems.map { layoutItem in
            let hitWidth = max(AppTheme.Timeline.midiMinimumNoteHitWidth, layoutItem.rect.width)
            let hitHeight = max(AppTheme.Timeline.midiMinimumNoteHitHeight, layoutItem.rect.height)
            let hitRect = CGRect(
                x: layoutItem.rect.midX - hitWidth / 2,
                y: layoutItem.rect.midY - hitHeight / 2,
                width: hitWidth,
                height: hitHeight
            )
            return MIDIPianoRollNoteInteractionGeometry(
                layoutItem: layoutItem,
                hitRect: hitRect,
                canResizeLeading: !incomingTargetIDs.contains(layoutItem.item.id),
                canResizeTrailing: layoutItem.item.tieTargetItemID == nil
            )
        }
    }

    static func editHit(
        at point: CGPoint,
        geometries: [MIDIPianoRollNoteInteractionGeometry]
    ) -> MIDIPianoRollEditHit? {
        guard let geometry = geometries.last(where: { $0.hitRect.contains(point) }),
              let mode = geometry.hitMode(at: point)
        else { return nil }
        return MIDIPianoRollEditHit(layoutItem: geometry.layoutItem, mode: mode)
    }

    static func playheadX(
        anchorTime: TimeInterval,
        cells: [MIDIPianoRollMeasureCell]
    ) -> CGFloat? {
        guard let cell = cells.first(where: {
            anchorTime >= $0.measure.startTime
                && anchorTime <= $0.measure.endTime
        }) else { return nil }
        guard cell.measure.duration > 0 else { return cell.x }
        let progress = min(
            1,
            max(0, (anchorTime - cell.measure.startTime) / cell.measure.duration)
        )
        return cell.x + CGFloat(progress) * cell.width
    }
}
