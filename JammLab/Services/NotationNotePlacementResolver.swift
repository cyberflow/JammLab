import CoreGraphics
import Foundation

struct NotationNotePlacement: Equatable {
    var measure: ScoreMeasure
    var partID: NotationPartID
    var offsetInQuarterNotes: Double
    var durationInQuarterNotes: Double
    var displayDuration: NotationDuration
    var pitch: NotationPitch
    var explicitAccidental: NotationAccidental?

    var x: CGFloat
    var y: CGFloat

    init(
        measure: ScoreMeasure,
        partID: NotationPartID = .main,
        offsetInQuarterNotes: Double,
        durationInQuarterNotes: Double,
        displayDuration: NotationDuration,
        pitch: NotationPitch,
        explicitAccidental: NotationAccidental? = nil,
        x: CGFloat,
        y: CGFloat
    ) {
        self.measure = measure
        self.partID = partID
        self.offsetInQuarterNotes = offsetInQuarterNotes
        self.durationInQuarterNotes = durationInQuarterNotes
        self.displayDuration = displayDuration
        var resolvedPitch = pitch
        if let explicitAccidental {
            resolvedPitch.alter = explicitAccidental.alter
        }
        self.pitch = resolvedPitch
        self.explicitAccidental = explicitAccidental
        self.x = x
        self.y = y
    }
}

struct NotationRestPlacement: Equatable {
    var measure: ScoreMeasure
    var partID: NotationPartID
    var offsetInQuarterNotes: Double
    var durationInQuarterNotes: Double
    var displayDuration: NotationDuration

    var x: CGFloat

    init(
        measure: ScoreMeasure,
        partID: NotationPartID = .main,
        offsetInQuarterNotes: Double,
        durationInQuarterNotes: Double,
        displayDuration: NotationDuration,
        x: CGFloat
    ) {
        self.measure = measure
        self.partID = partID
        self.offsetInQuarterNotes = offsetInQuarterNotes
        self.durationInQuarterNotes = durationInQuarterNotes
        self.displayDuration = displayDuration
        self.x = x
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
        explicitAccidental: NotationAccidental? = nil,
        selectedDrumInstrumentMIDINoteNumber: Int? = nil,
        lineSpacing: CGFloat = AppTheme.Timeline.notationStaffLineSpacing
    ) -> NotationNotePlacement? {
        guard lineSpacing > 0 else { return nil }
        let pitchPosition: Int
        let pitch: NotationPitch
        if measure.attributes.clef == .drums {
            let instrument = selectedDrumInstrumentMIDINoteNumber
                .flatMap(DrumInstrumentMap.instrument(forMIDINoteNumber:))
                ?? DrumInstrumentMap.defaultInstrument
            pitchPosition = instrument.staffPosition
            pitch = NotationPitchMapper.pitch(
                forMIDINoteNumber: instrument.midiNoteNumber,
                keySignature: .cMajor
            )
        } else {
            guard let resolvedPosition = staffPosition(
                forY: point.y,
                staffTop: staffTop,
                clef: measure.attributes.clef,
                lineSpacing: lineSpacing
            ) else { return nil }
            pitchPosition = resolvedPosition
            pitch = NotationPitchMapper.pitch(
                forStaffPosition: pitchPosition,
                keySignature: measure.attributes.keySignature,
                clef: measure.attributes.clef
            )
        }

        let selectedLength = selectedDuration.durationInQuarterNotes
        guard selectedLength > NotationMeasureTiming.timelineTolerance else { return nil }

        let offset = snappedEntryOffset(in: measure, geometry: geometry, x: point.x)

        let x = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: offset,
            timeSignature: measure.attributes.timeSignature
        )
        let y = yPosition(forStaffPosition: pitchPosition, staffTop: staffTop, lineSpacing: lineSpacing)

        return NotationNotePlacement(
            measure: measure,
            partID: partID,
            offsetInQuarterNotes: offset,
            durationInQuarterNotes: selectedLength,
            displayDuration: selectedDuration,
            pitch: pitch,
            explicitAccidental: measure.attributes.clef == .drums ? nil : explicitAccidental,
            x: x,
            y: y
        )
    }

    static func placement(
        in measure: ScoreMeasure,
        quarterOffset: Double,
        selectedDuration: NotationDuration,
        pitch: NotationPitch,
        partID: NotationPartID,
        x: CGFloat,
        y: CGFloat
    ) -> NotationNotePlacement? {
        guard NotationPitchMapper.isEditable(pitch, in: measure.attributes.clef) else {
            return nil
        }
        let measureLength = NotationMeasureTiming.quarterLength(
            for: measure.attributes.timeSignature
        )
        let clampedOffset = min(max(0, measureLength - NotationRhythmicGrid.subdivisionInQuarterNotes), max(0, quarterOffset))
        let selectedLength = selectedDuration.durationInQuarterNotes
        guard selectedLength > NotationMeasureTiming.timelineTolerance else {
            return nil
        }

        return NotationNotePlacement(
            measure: measure,
            partID: partID,
            offsetInQuarterNotes: clampedOffset,
            durationInQuarterNotes: selectedLength,
            displayDuration: selectedDuration,
            pitch: pitch,
            x: x,
            y: y
        )
    }

    static func restPlacement(
        in measure: ScoreMeasure,
        quarterOffset: Double,
        selectedDuration: NotationDuration,
        partID: NotationPartID,
        x: CGFloat
    ) -> NotationRestPlacement? {
        let measureLength = NotationMeasureTiming.quarterLength(
            for: measure.attributes.timeSignature
        )
        let clampedOffset = min(max(0, measureLength - NotationRhythmicGrid.subdivisionInQuarterNotes), max(0, quarterOffset))
        let selectedLength = selectedDuration.durationInQuarterNotes
        let span = NotationTimeSpan(start: clampedOffset, end: clampedOffset + selectedLength)
        guard selectedLength > NotationMeasureTiming.timelineTolerance,
              span.end <= measureLength + NotationMeasureTiming.timelineTolerance,
              NotationMeasureRhythmRecomposer.isSilent(
                span,
                in: measure,
                partID: partID,
                items: measure.notationItems
              )
        else { return nil }

        return NotationRestPlacement(
            measure: measure,
            partID: partID,
            offsetInQuarterNotes: clampedOffset,
            durationInQuarterNotes: selectedLength,
            displayDuration: selectedDuration,
            x: x
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
        guard isWithinEntryYRange(
            point.y,
            staffTop: staffTop,
            clef: measure.attributes.clef,
            lineSpacing: lineSpacing
        ) else {
            return nil
        }

        let offset = snappedEntryOffset(in: measure, geometry: geometry, x: point.x)

        let x = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: offset,
            timeSignature: measure.attributes.timeSignature
        )

        return restPlacement(
            in: measure,
            quarterOffset: offset,
            selectedDuration: selectedDuration,
            partID: partID,
            x: x
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

    private static func snappedEntryOffset(
        in measure: ScoreMeasure,
        geometry: NotationMeasureCanvasGeometry,
        x: CGFloat
    ) -> Double {
        let measureLength = NotationMeasureTiming.quarterLength(for: measure.attributes.timeSignature)
        let rawProgress = NotationMeasureLayout.notationAnchorProgress(atX: x, geometry: geometry)
        let rawOffset = rawProgress * measureLength
        let step = NotationRhythmicGrid.subdivisionInQuarterNotes
        let snapped = (rawOffset / step).rounded() * step
        return min(max(0, measureLength - step), max(0, snapped))
    }

    static func staffPosition(
        forY y: CGFloat,
        staffTop: CGFloat,
        clef: Clef = .treble,
        lineSpacing: CGFloat = AppTheme.Timeline.notationStaffLineSpacing
    ) -> Int? {
        guard isWithinEntryYRange(
            y,
            staffTop: staffTop,
            clef: clef,
            lineSpacing: lineSpacing
        ) else { return nil }

        return clampedStaffPosition(
            forY: y,
            staffTop: staffTop,
            clef: clef,
            lineSpacing: lineSpacing
        )
    }

    static func clampedStaffPosition(
        forY y: CGFloat,
        staffTop: CGFloat,
        clef: Clef = .treble,
        lineSpacing: CGFloat = AppTheme.Timeline.notationStaffLineSpacing
    ) -> Int? {
        guard lineSpacing > 0 else { return nil }
        let halfSpacing = lineSpacing / 2
        let rawPosition = ((y - staffTop) / halfSpacing).rounded()
        let range = NotationPitchMapper.editableStaffPositionRange(for: clef)
        return min(
            range.upperBound,
            max(range.lowerBound, Int(rawPosition))
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
        clef: Clef = .treble,
        lineSpacing: CGFloat
    ) -> Bool {
        guard lineSpacing > 0 else { return false }
        let halfSpacing = lineSpacing / 2
        let range = NotationPitchMapper.editableStaffPositionRange(for: clef)
        let minimumY = yPosition(
            forStaffPosition: range.lowerBound,
            staffTop: staffTop,
            lineSpacing: lineSpacing
        ) - halfSpacing
        let maximumY = yPosition(
            forStaffPosition: range.upperBound,
            staffTop: staffTop,
            lineSpacing: lineSpacing
        ) + halfSpacing
        return y >= minimumY && y <= maximumY
    }
}
