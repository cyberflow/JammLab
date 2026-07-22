import AppKit
import SwiftUI

private let midiPianoRollCoordinateSpaceName = "MIDIPianoRollCoordinateSpace"

struct MIDIPianoRollActions {
    var selectItem: (NotationItemSelection?, Bool) -> Void
    var canInsertNotationNote: (NotationNotePlacement) -> Bool
    var insertNotationNote: (NotationNotePlacement) -> Bool
    var insertNotationRest: (NotationRestPlacement) -> Bool
    var auditionNotePitch: (NotationPitch, Clef) -> Void
    var deleteSelectedNotationNote: () -> Bool
    var beginNoteEdit: (NotationPartID) -> Void
    var endNoteEdit: () -> Void
    var previewNoteEdit: (NotationNoteEditRequest) -> NotationNoteEditPreview?
    var commitNoteEdit: (NotationNoteEditRequest) -> Bool
}

private struct MIDIPianoRollEditInteraction: Equatable {
    var sourceLayoutItem: MIDIPianoRollNoteLayoutItem
    var mode: MIDIPianoRollEditHitMode
    var startPoint: CGPoint
    var grabbedPosition: NotationGridPosition
    var startMIDINoteNumber: Int
    var didMove = false
}

struct MIDIPianoRollView: View {
    let state: NotationViewportState
    let partID: NotationPartID
    let partTitle: String
    let selectedItem: NotationItemSelection?
    let selectedDuration: NotationDuration
    let selectedDrumInstrumentMIDINoteNumber: Int
    let entryMode: NotationEntryMode?
    let actions: MIDIPianoRollActions
    @Binding var scrollPitch: Int?
    let selectedLogicalItemIDs: Set<String>
    let isPlaying: Bool
    let onPageStartTimeChanged: (TimeInterval) -> Void
    let onInteractionEnded: () -> Void

    @Environment(\.appColors) private var appColors
    @FocusState private var isFocused: Bool
    @State private var hoveredPlacement: NotationNotePlacement?
    @State private var editInteraction: MIDIPianoRollEditInteraction?
    @State private var editPreview: NotationNoteEditPreview?
    @State private var lastEditPoint: CGPoint?
    @State private var lastAuditionedMIDINoteNumber: Int?
    @State private var autoPageDirection: MIDIPianoRollAutoPageDirection?
    @State private var autoPageTask: Task<Void, Never>?

    private var rollHeight: CGFloat {
        CGFloat(MIDIPianoRollLayout.midiRange.count) * AppTheme.Timeline.midiPitchRowHeight
    }

    private var pitchLabelWidth: CGFloat {
        state.clef == .drums
            ? AppTheme.Timeline.midiDrumPitchLabelWidth
            : AppTheme.Timeline.midiPitchLabelWidth
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: AppTheme.Spacing.none) {
                ruler(width: proxy.size.width)
                    .frame(height: AppTheme.Timeline.midiRulerHeight)

                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        pitchScrollTargets
                        rollCanvas(width: proxy.size.width)
                        noteInteractionLayer(width: proxy.size.width)
                        entryLayer(width: proxy.size.width)
                    }
                    .coordinateSpace(name: midiPianoRollCoordinateSpaceName)
                    .frame(width: proxy.size.width, height: rollHeight)
                }
                .scrollIndicators(.visible)
                .scrollPosition(id: $scrollPitch, anchor: .center)
            }
            .background(appColors.notationTrackBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.panel))
            .contentShape(Rectangle())
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled(true)
            .onTapGesture { isFocused = true }
            .onDeleteCommand { _ = actions.deleteSelectedNotationNote() }
            .onAppear { initializeScrollPitch() }
            .onChange(of: state.firstVisibleMeasureNumber) { _, _ in
                if scrollPitch == nil { initializeScrollPitch() }
                resumeEditAfterPageChange(width: proxy.size.width)
            }
            .onChange(of: entryMode) { _, mode in
                if mode != nil { cancelEditInteraction() }
            }
            .onChange(of: isPlaying) { _, playing in
                if playing { cancelEditInteraction() }
            }
            .onChange(of: selectedDrumInstrumentMIDINoteNumber) { _, midiNoteNumber in
                if state.clef == .drums { scrollPitch = midiNoteNumber }
            }
            .onDisappear { cancelEditInteraction() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(partTitle) MIDI Track")
            .accessibilityValue(accessibilityValue)
        }
    }

    private var pitchScrollTargets: some View {
        LazyVStack(spacing: AppTheme.Spacing.none) {
            ForEach(Array(MIDIPianoRollLayout.midiRange.reversed()), id: \.self) { pitch in
                Color.clear
                    .frame(height: AppTheme.Timeline.midiPitchRowHeight)
                    .id(pitch)
                    .accessibilityHidden(true)
            }
        }
        .scrollTargetLayout()
        .allowsHitTesting(false)
    }

    private func ruler(width: CGFloat) -> some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(appColors.controlBackground))
            let cells = MIDIPianoRollLayout.measureCells(
                visibleMeasures: state.visibleMeasures,
                totalWidth: width,
                pitchLabelWidth: pitchLabelWidth
            )
            for cell in cells {
                let measureLength = NotationMeasureTiming.quarterLength(
                    for: cell.measure.attributes.timeSignature
                )
                let beatLength = 4.0 / Double(max(1, cell.measure.attributes.timeSignature.beatUnit))
                let beats = max(1, cell.measure.attributes.timeSignature.beatsPerBar)
                for beat in 0..<beats {
                    let offset = Double(beat) * beatLength
                    guard offset < measureLength + NotationMeasureTiming.timelineTolerance else { continue }
                    let x = MIDIPianoRollLayout.xPosition(quarterOffset: offset, cell: cell)
                    let label = beat == 0 ? "\(cell.measure.number)" : "\(cell.measure.number).\(beat + 1)"
                    context.draw(
                        context.resolve(
                            Text(label)
                                .font(.system(
                                    size: AppTheme.Timeline.midiLabelFontSize,
                                    weight: beat == 0 ? .semibold : .regular
                                ))
                                .foregroundStyle(appColors.secondaryText)
                        ),
                        at: CGPoint(x: x + AppTheme.Spacing.xs, y: size.height / 2),
                        anchor: .leading
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func rollCanvas(width: CGFloat) -> some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(Path(bounds), with: .color(appColors.notationTrackBackground))
            drawPitchRows(context: &context, size: size)
            let cells = MIDIPianoRollLayout.measureCells(
                visibleMeasures: state.visibleMeasures,
                totalWidth: width,
                pitchLabelWidth: pitchLabelWidth
            )
            drawTimeGrid(context: &context, size: size, cells: cells)
            drawNotes(context: &context, width: width)
            drawEditPreview(context: &context, width: width)
            drawPlayhead(context: &context, size: size, cells: cells)
            drawHoverPreview(context: &context, width: width)
        }
        .frame(width: width, height: rollHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawPitchRows(context: inout GraphicsContext, size: CGSize) {
        for midiNote in MIDIPianoRollLayout.midiRange {
            let y = MIDIPianoRollLayout.yPosition(forMIDINoteNumber: midiNote)
            let rowRect = CGRect(x: 0, y: y, width: size.width, height: AppTheme.Timeline.midiPitchRowHeight)
            if state.clef == .drums,
               midiNote == selectedDrumInstrumentMIDINoteNumber {
                context.fill(
                    Path(rowRect),
                    with: .color(appColors.accent.opacity(AppTheme.Timeline.midiSelectedPitchRowOpacity))
                )
            }
            if MIDIPianoRollLayout.isBlackKey(midiNote) {
                context.fill(
                    Path(rowRect),
                    with: .color(appColors.notationSymbolsAndLines.opacity(AppTheme.Timeline.midiBlackKeyRowOpacity))
                )
            }
            if !NotationInputPolicy.isEditableMIDINoteNumber(midiNote, in: state.clef) {
                context.fill(
                    Path(rowRect),
                    with: .color(appColors.disabledText.opacity(AppTheme.Timeline.midiDisabledPitchRowOpacity))
                )
            }
            var separator = Path()
            separator.move(to: CGPoint(x: 0, y: y))
            separator.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(
                separator,
                with: .color(appColors.border.opacity(AppTheme.Timeline.midiRowSeparatorOpacity)),
                lineWidth: AppTheme.Stroke.thin
            )

            if let instrument = state.clef == .drums
                ? DrumInstrumentMap.instrument(forMIDINoteNumber: midiNote)
                : nil {
                context.draw(
                    context.resolve(
                        Text("\(instrument.name) · \(instrument.pitchLabel)")
                            .font(.system(size: AppTheme.Timeline.midiLabelFontSize, weight: .medium))
                            .foregroundStyle(appColors.secondaryText)
                    ),
                    at: CGPoint(x: AppTheme.Spacing.xs, y: y + AppTheme.Timeline.midiPitchRowHeight / 2),
                    anchor: .leading
                )
            } else if state.clef != .drums, midiNote % 12 == 0 {
                context.draw(
                    context.resolve(
                        Text(MIDIPianoRollLayout.pitchName(midiNote, usesFlats: state.keySignature.fifths < 0))
                            .font(.system(size: AppTheme.Timeline.midiLabelFontSize, weight: .medium))
                            .foregroundStyle(appColors.secondaryText)
                    ),
                    at: CGPoint(x: AppTheme.Spacing.xs, y: y + AppTheme.Timeline.midiPitchRowHeight / 2),
                    anchor: .leading
                )
            }
        }

        var gutter = Path()
        gutter.move(to: CGPoint(x: pitchLabelWidth, y: 0))
        gutter.addLine(to: CGPoint(x: pitchLabelWidth, y: size.height))
        context.stroke(gutter, with: .color(appColors.border), lineWidth: AppTheme.Stroke.thin)
    }

    private func drawTimeGrid(
        context: inout GraphicsContext,
        size: CGSize,
        cells: [MIDIPianoRollMeasureCell]
    ) {
        for cell in cells {
            let measureLength = NotationMeasureTiming.quarterLength(
                for: cell.measure.attributes.timeSignature
            )
            let beatLength = 4.0 / Double(max(1, cell.measure.attributes.timeSignature.beatUnit))
            var offset = 0.0
            while offset < measureLength - NotationMeasureTiming.timelineTolerance {
                let x = MIDIPianoRollLayout.xPosition(quarterOffset: offset, cell: cell)
                let isBarline = offset <= NotationMeasureTiming.timelineTolerance
                let beatRemainder = beatLength > 0 ? offset.truncatingRemainder(dividingBy: beatLength) : 0
                let isBeat = abs(beatRemainder) < NotationMeasureTiming.timelineTolerance
                    || abs(beatRemainder - beatLength) < NotationMeasureTiming.timelineTolerance
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                let opacity = isBarline
                    ? AppTheme.Timeline.midiBarLineOpacity
                    : (isBeat ? AppTheme.Timeline.midiBeatLineOpacity : AppTheme.Timeline.midiSubdivisionLineOpacity)
                context.stroke(
                    line,
                    with: .color(appColors.notationSymbolsAndLines.opacity(opacity)),
                    lineWidth: isBarline ? AppTheme.Stroke.medium : AppTheme.Stroke.thin
                )
                offset += NotationRhythmicGrid.subdivisionInQuarterNotes
            }
        }

        if let lastCell = cells.last {
            var endLine = Path()
            let x = lastCell.x + lastCell.width
            endLine.move(to: CGPoint(x: x, y: 0))
            endLine.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(
                endLine,
                with: .color(appColors.notationSymbolsAndLines.opacity(AppTheme.Timeline.midiBarLineOpacity)),
                lineWidth: AppTheme.Stroke.medium
            )
        }
    }

    private func drawNotes(context: inout GraphicsContext, width: CGFloat) {
        for layoutItem in MIDIPianoRollLayout.noteLayoutItems(
            visibleMeasures: state.visibleMeasures,
            totalWidth: width,
            pitchLabelWidth: pitchLabelWidth
        ) {
            let isSelected = selectedLogicalItemIDs.contains(layoutItem.item.id)
                || selectedItem?.matches(layoutItem.measure, item: layoutItem.item) == true
            let isEditedSource = editPreview?.sourceItemIDs.contains(layoutItem.item.id) == true
            let path = Path(roundedRect: layoutItem.rect, cornerRadius: AppTheme.Radius.small)
            context.fill(
                path,
                with: .color(appColors.accent.opacity(
                    isEditedSource
                        ? AppTheme.Timeline.midiEditedSourceOpacity
                        : (isSelected ? 1 : AppTheme.Timeline.midiNoteOpacity)
                ))
            )
            if isSelected {
                context.stroke(path, with: .color(appColors.primaryText), lineWidth: AppTheme.Stroke.medium)
            }
        }
    }

    private func drawEditPreview(context: inout GraphicsContext, width: CGFloat) {
        guard let editPreview else { return }
        let color = editPreview.invalidReason == nil
            ? appColors.accent
            : appColors.statusButtonCriticalFill
        for layoutItem in MIDIPianoRollLayout.noteLayoutItems(
            visibleMeasures: state.visibleMeasures,
            totalWidth: width,
            notationItems: editPreview.previewItems,
            pitchLabelWidth: pitchLabelWidth
        ) {
            let path = Path(roundedRect: layoutItem.rect, cornerRadius: AppTheme.Radius.small)
            context.fill(
                path,
                with: .color(color.opacity(AppTheme.Timeline.midiEditPreviewOpacity))
            )
            context.stroke(path, with: .color(color), lineWidth: AppTheme.Stroke.medium)
        }
    }

    private func drawPlayhead(
        context: inout GraphicsContext,
        size: CGSize,
        cells: [MIDIPianoRollMeasureCell]
    ) {
        guard let x = MIDIPianoRollLayout.playheadX(anchorTime: state.anchorTime, cells: cells) else { return }
        var line = Path()
        line.move(to: CGPoint(x: x, y: 0))
        line.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(line, with: .color(appColors.accent), lineWidth: AppTheme.Stroke.thick)
    }

    private func drawHoverPreview(context: inout GraphicsContext, width: CGFloat) {
        guard let hoveredPlacement else { return }
        let cells = MIDIPianoRollLayout.measureCells(
            visibleMeasures: state.visibleMeasures,
            totalWidth: width,
            pitchLabelWidth: pitchLabelWidth
        )
        guard let cell = cells.first(where: { $0.measure.id == hoveredPlacement.measure.id }) else { return }
        let startX = MIDIPianoRollLayout.xPosition(
            quarterOffset: hoveredPlacement.offsetInQuarterNotes,
            cell: cell
        )
        let endX = MIDIPianoRollLayout.xPosition(
            quarterOffset: hoveredPlacement.offsetInQuarterNotes + hoveredPlacement.durationInQuarterNotes,
            cell: cell
        )
        let rect = CGRect(
            x: startX + AppTheme.Timeline.midiNoteInset,
            y: MIDIPianoRollLayout.yPosition(forMIDINoteNumber: hoveredPlacement.pitch.midiNoteNumber)
                + AppTheme.Timeline.midiNoteInset,
            width: max(AppTheme.Stroke.thick, min(cell.x + cell.width, endX) - startX - AppTheme.Timeline.midiNoteInset * 2),
            height: AppTheme.Timeline.midiPitchRowHeight - AppTheme.Timeline.midiNoteInset * 2
        )
        context.fill(
            Path(roundedRect: rect, cornerRadius: AppTheme.Radius.small),
            with: .color(appColors.accent.opacity(AppTheme.Timeline.midiHoverNoteOpacity))
        )
    }

    private func noteInteractionLayer(width: CGFloat) -> some View {
        let layoutItems = MIDIPianoRollLayout.noteLayoutItems(
            visibleMeasures: state.visibleMeasures,
            totalWidth: width,
            pitchLabelWidth: pitchLabelWidth
        )
        let geometries = MIDIPianoRollLayout.noteInteractionGeometries(
            layoutItems: layoutItems,
            tieConnections: state.tieConnections
        )
        return ZStack(alignment: .topLeading) {
            ForEach(geometries) { geometry in
                let layoutItem = geometry.layoutItem
                noteInteractionTarget(geometry)
                    .accessibilityLabel(noteAccessibilityLabel(layoutItem))
                    .accessibilityValue(
                        selectedLogicalItemIDs.contains(layoutItem.item.id)
                            || selectedItem?.matches(layoutItem.measure, item: layoutItem.item) == true
                            ? "Selected"
                            : ""
                    )
                    .accessibilityAction {
                        isFocused = true
                        actions.selectItem(layoutItem.selection, true)
                    }
                    .help("Drag to move this MIDI note; drag either edge to change its duration")
            }
        }
        .gesture(
            DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named(midiPianoRollCoordinateSpaceName)
            )
            .onChanged { value in
                handleEditDragChanged(value, width: width, geometries: geometries)
            }
            .onEnded { value in
                handleEditDragEnded(value)
            }
        )
        .allowsHitTesting(entryMode == nil)
    }

    private func noteInteractionTarget(
        _ geometry: MIDIPianoRollNoteInteractionGeometry
    ) -> some View {
        return ZStack {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .cursor(.openHand)

            if geometry.canResizeLeading {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: min(geometry.hitRect.width, AppTheme.Timeline.midiResizeHandleHitWidth))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cursor(.resizeLeftRight)
            }

            if geometry.canResizeTrailing {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: min(geometry.hitRect.width, AppTheme.Timeline.midiResizeHandleHitWidth))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .cursor(.resizeLeftRight)
            }
        }
        .frame(width: geometry.hitRect.width, height: geometry.hitRect.height)
        .offset(
            x: geometry.hitRect.minX,
            y: geometry.hitRect.minY
        )
    }

    @ViewBuilder
    private func entryLayer(width: CGFloat) -> some View {
        if let entryMode {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: width, height: rollHeight)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        hoveredPlacement = entryMode == .note
                            ? notePlacement(at: point, width: width)
                            : nil
                    case .ended:
                        hoveredPlacement = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            isFocused = true
                            switch entryMode {
                            case .note:
                                guard let placement = notePlacement(at: value.location, width: width) else { return }
                                if actions.insertNotationNote(placement) {
                                    hoveredPlacement = placement
                                }
                            case .rest:
                                guard let placement = restPlacement(at: value.location, width: width) else { return }
                                _ = actions.insertNotationRest(placement)
                                hoveredPlacement = nil
                            }
                        }
                )
                .cursor(.crosshair)
                .help(entryMode == .note ? "Add MIDI note" : "Add MIDI rest")
                .accessibilityLabel(entryMode == .note ? "MIDI note entry area" : "MIDI rest entry area")
        }
    }

    private func notePlacement(at point: CGPoint, width: CGFloat) -> NotationNotePlacement? {
        guard point.x >= pitchLabelWidth,
              let midiNote = MIDIPianoRollLayout.midiNoteNumber(atY: point.y),
              NotationInputPolicy.isEditableMIDINoteNumber(midiNote, in: state.clef)
        else { return nil }
        let cells = MIDIPianoRollLayout.measureCells(
            visibleMeasures: state.visibleMeasures,
            totalWidth: width,
            pitchLabelWidth: pitchLabelWidth
        )
        guard let cell = MIDIPianoRollLayout.cell(atX: point.x, cells: cells) else { return nil }
        let offset = MIDIPianoRollLayout.snappedQuarterOffset(atX: point.x, cell: cell)
        let pitch = NotationPitchMapper.pitch(
            forMIDINoteNumber: midiNote,
            keySignature: cell.measure.attributes.keySignature
        )
        let placement = NotationNotePlacementResolver.placement(
            in: cell.measure,
            quarterOffset: offset,
            selectedDuration: selectedDuration,
            pitch: pitch,
            partID: partID,
            x: MIDIPianoRollLayout.xPosition(quarterOffset: offset, cell: cell),
            y: MIDIPianoRollLayout.yPosition(forMIDINoteNumber: midiNote)
        )
        guard let placement, actions.canInsertNotationNote(placement) else { return nil }
        return placement
    }

    private func restPlacement(at point: CGPoint, width: CGFloat) -> NotationRestPlacement? {
        guard point.x >= pitchLabelWidth else { return nil }
        let cells = MIDIPianoRollLayout.measureCells(
            visibleMeasures: state.visibleMeasures,
            totalWidth: width,
            pitchLabelWidth: pitchLabelWidth
        )
        guard let cell = MIDIPianoRollLayout.cell(atX: point.x, cells: cells) else { return nil }
        let offset = MIDIPianoRollLayout.snappedQuarterOffset(atX: point.x, cell: cell)
        return NotationNotePlacementResolver.restPlacement(
            in: cell.measure,
            quarterOffset: offset,
            selectedDuration: selectedDuration,
            partID: partID,
            x: MIDIPianoRollLayout.xPosition(quarterOffset: offset, cell: cell)
        )
    }

    private func handleEditDragChanged(
        _ value: DragGesture.Value,
        width: CGFloat,
        geometries: [MIDIPianoRollNoteInteractionGeometry]
    ) {
        if editInteraction == nil {
            guard let hit = MIDIPianoRollLayout.editHit(
                at: value.startLocation,
                geometries: geometries
            ) else { return }
            let cells = MIDIPianoRollLayout.measureCells(
                visibleMeasures: state.visibleMeasures,
                totalWidth: width,
                pitchLabelWidth: pitchLabelWidth
            )
            guard let grabbedPosition = MIDIPianoRollLayout.gridPosition(
                atX: value.startLocation.x,
                cells: cells
            ) else { return }

            isFocused = true
            actions.selectItem(hit.layoutItem.selection, true)
            actions.beginNoteEdit(partID)
            lastAuditionedMIDINoteNumber = hit.layoutItem.item.pitch?.midiNoteNumber
            editInteraction = MIDIPianoRollEditInteraction(
                sourceLayoutItem: hit.layoutItem,
                mode: hit.mode,
                startPoint: value.startLocation,
                grabbedPosition: grabbedPosition,
                startMIDINoteNumber: hit.layoutItem.item.pitch?.midiNoteNumber
                    ?? MIDIPianoRollLayout.midiNoteNumber(atY: value.startLocation.y)
                    ?? 60
            )
        }

        guard var interaction = editInteraction else { return }
        let distance = hypot(
            value.location.x - interaction.startPoint.x,
            value.location.y - interaction.startPoint.y
        )
        if distance >= AppTheme.Timeline.midiMinimumDragDistance {
            interaction.didMove = true
        }
        editInteraction = interaction
        lastEditPoint = value.location

        guard interaction.didMove else { return }
        updateEditPreview(at: value.location, width: width)
        updateAutoPage(at: value.location, width: width)
    }

    private func handleEditDragEnded(_ value: DragGesture.Value) {
        guard let interaction = editInteraction else { return }
        if interaction.didMove,
           let preview = editPreview,
           preview.isValid {
            _ = actions.commitNoteEdit(preview.request)
        }
        finishEditInteraction()
    }

    private func updateEditPreview(at point: CGPoint, width: CGFloat) {
        guard let interaction = editInteraction else { return }
        let cells = MIDIPianoRollLayout.measureCells(
            visibleMeasures: state.visibleMeasures,
            totalWidth: width,
            pitchLabelWidth: pitchLabelWidth
        )
        let operation: NotationNoteEditOperation
        switch interaction.mode {
        case .body:
            guard let targetPosition = MIDIPianoRollLayout.gridPosition(
                atX: point.x,
                cells: cells
            ) else { return }
            let clampedY = min(rollHeight.nextDown, max(0, point.y))
            let currentMIDINoteNumber = MIDIPianoRollLayout.midiNoteNumber(atY: clampedY)
                ?? interaction.startMIDINoteNumber
            operation = .move(
                grabbedPosition: interaction.grabbedPosition,
                targetPosition: targetPosition,
                semitoneDelta: currentMIDINoteNumber - interaction.startMIDINoteNumber
            )
        case .leading, .trailing:
            guard let boundary = MIDIPianoRollLayout.gridPosition(
                atX: point.x,
                cells: cells,
                allowsMeasureEnd: true
            ) else { return }
            operation = .resize(
                edge: interaction.mode == .leading ? .leading : .trailing,
                boundary: boundary
            )
        }

        let request = NotationNoteEditRequest(
            partID: partID,
            sourceItemID: interaction.sourceLayoutItem.item.id,
            operation: operation
        )
        editPreview = actions.previewNoteEdit(request)

        if interaction.mode == .body,
           let pitch = editPreview?.previewItems.first?.pitch,
           pitch.midiNoteNumber != lastAuditionedMIDINoteNumber {
            lastAuditionedMIDINoteNumber = pitch.midiNoteNumber
            actions.auditionNotePitch(pitch, state.clef)
        }
    }

    private func updateAutoPage(at point: CGPoint, width: CGFloat) {
        guard editInteraction?.didMove == true else {
            cancelAutoPage()
            return
        }

        guard let target = MIDIPianoRollAutoPage.target(
            pointerX: point.x,
            width: width,
            previousPageStartTime: state.previousPageStartTime,
            nextPageStartTime: state.nextPageStartTime,
            pitchLabelWidth: pitchLabelWidth
        ) else {
            cancelAutoPage()
            return
        }
        guard autoPageDirection != target.direction || autoPageTask == nil else { return }

        cancelAutoPage()
        autoPageDirection = target.direction
        let nanoseconds = UInt64(AppTheme.Timeline.midiAutoPageDelay * 1_000_000_000)
        autoPageTask = MIDIPianoRollAutoPage.schedule(delayNanoseconds: nanoseconds) {
            onPageStartTimeChanged(target.startTime)
            autoPageTask = nil
        }
    }

    private func resumeEditAfterPageChange(width: CGFloat) {
        guard editInteraction?.didMove == true, let lastEditPoint else { return }
        cancelAutoPage()
        updateEditPreview(at: lastEditPoint, width: width)
        updateAutoPage(at: lastEditPoint, width: width)
    }

    private func cancelAutoPage() {
        autoPageTask?.cancel()
        autoPageTask = nil
        autoPageDirection = nil
    }

    private func cancelEditInteraction() {
        guard editInteraction != nil else {
            cancelAutoPage()
            return
        }
        finishEditInteraction()
    }

    private func finishEditInteraction() {
        cancelAutoPage()
        editInteraction = nil
        editPreview = nil
        lastEditPoint = nil
        lastAuditionedMIDINoteNumber = nil
        actions.endNoteEdit()
        onInteractionEnded()
    }

    private func initializeScrollPitch() {
        guard scrollPitch == nil else { return }
        if state.clef == .drums {
            scrollPitch = selectedDrumInstrumentMIDINoteNumber
            return
        }
        if let selectedItem,
           selectedItem.partID == partID,
           let selectedPitch = state.visibleMeasures
               .flatMap(\.notationItems)
               .first(where: { $0.id == selectedItem.itemID })?
               .pitch?
               .midiNoteNumber {
            scrollPitch = selectedPitch
            return
        }
        let visiblePitches = state.visibleMeasures
            .flatMap(\.notationItems)
            .compactMap { $0.kind == .note ? $0.pitch?.midiNoteNumber : nil }
            .sorted()
        scrollPitch = visiblePitches.isEmpty ? 60 : visiblePitches[visiblePitches.count / 2]
    }

    private func noteAccessibilityLabel(_ layoutItem: MIDIPianoRollNoteLayoutItem) -> String {
        guard let pitch = layoutItem.item.pitch else { return "MIDI note" }
        let beat = layoutItem.item.offsetInQuarterNotes + 1
        let pitchName = layoutItem.measure.attributes.clef == .drums
            ? DrumInstrumentMap.instrument(forMIDINoteNumber: pitch.midiNoteNumber)?.name
                ?? MIDIPianoRollLayout.pitchName(pitch.midiNoteNumber)
            : MIDIPianoRollLayout.pitchName(
                pitch.midiNoteNumber,
                usesFlats: layoutItem.measure.attributes.keySignature.fifths < 0
            )
        return "\(pitchName), measure \(layoutItem.measure.number), beat \(beat.formatted(.number.precision(.fractionLength(0...2)))), \(layoutItem.item.displayDuration.humanDisplayName) note"
    }

    private var accessibilityValue: String {
        guard let first = state.visibleMeasures.first,
              let last = state.visibleMeasures.last
        else { return "Pending tempo" }
        return "Measures \(first.number) through \(last.number)"
    }
}
