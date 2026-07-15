import AppKit
import SwiftUI

private let notationTrackCoordinateSpaceName = "NotationTrackCoordinateSpace"

struct NotationTrackActions {
    var selectHarmony: (HarmonySymbol.ID?) -> Void
    var selectMeasure: (ScoreMeasure?, Bool, NotationPartID) -> Void
    var selectItem: (NotationItemSelection?, Bool) -> Void
    var insertNotationNote: (NotationNotePlacement) -> Bool
    var insertNotationRest: (NotationRestPlacement) -> Bool
    var changeSelectedNotePitch: (NotationPitch, Bool) -> Bool
    var changeClef: (NotationPartID, Clef) -> Void
    var auditionNotePitch: (NotationPitch) -> Void
    var deleteSelectedNotationNote: () -> Bool
    var locatePlaybackMarkerExactly: (TimeInterval) -> Void
    var saveHarmony: (HarmonySymbol) -> Void
    var deleteHarmony: (HarmonySymbol.ID) -> Void
    var adjacentHarmonyPlacement: (TimeInterval, HarmonyNavigationDirection) -> HarmonyPlacement?
}

struct NotationTrackView: View {
    let state: NotationViewportState
    let partID: NotationPartID
    let playbackDisplayState: PlaybackDisplayState?
    let selectedHarmonySymbolID: HarmonySymbol.ID?
    let selectedMeasures: [NotationMeasureSelection]
    let selectedItem: NotationItemSelection?
    let selectedDuration: NotationDuration
    let entryMode: NotationEntryMode?
    let pendingEditorRequest: HarmonyEditorRequest?
    let showsRegionLabels: Bool
    let actions: NotationTrackActions
    let cornerRadius: CGFloat

    @Environment(\.appColors) private var appColors
    @FocusState private var isTrackFocused: Bool
    @State private var editingDraft: HarmonyEditorDraft?
    @State private var hoveredNotePlacement: NotationNotePlacement?
    @State private var hoveredRestPlacement: NotationRestPlacement?
    @State private var draggedNotePitchPreview: NotationDraggedNotePitchPreview?

    init(
        state: NotationViewportState,
        partID: NotationPartID = .main,
        playbackDisplayState: PlaybackDisplayState? = nil,
        selectedHarmonySymbolID: HarmonySymbol.ID? = nil,
        selectedMeasures: [NotationMeasureSelection] = [],
        selectedItem: NotationItemSelection? = nil,
        selectedDuration: NotationDuration = NotationDuration(),
        entryMode: NotationEntryMode? = nil,
        pendingEditorRequest: HarmonyEditorRequest? = nil,
        showsRegionLabels: Bool = true,
        actions: NotationTrackActions = .noop,
        cornerRadius: CGFloat = AppTheme.Radius.small
    ) {
        self.state = state
        self.partID = partID
        self.playbackDisplayState = playbackDisplayState
        self.selectedHarmonySymbolID = selectedHarmonySymbolID
        self.selectedMeasures = selectedMeasures
        self.selectedItem = selectedItem
        self.selectedDuration = selectedDuration
        self.entryMode = entryMode
        self.pendingEditorRequest = pendingEditorRequest
        self.showsRegionLabels = showsRegionLabels
        self.actions = actions
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        GeometryReader { proxy in
            let attributeDisplays = visibleAttributeDisplays
            let contentWidth = max(1, proxy.size.width)

            ZStack(alignment: .topLeading) {
                notationCanvas(
                    measureCount: renderedMeasureCount,
                    attributeDisplays: attributeDisplays
                )
                selectedMeasureOverlay(
                    width: contentWidth,
                    height: proxy.size.height,
                    attributeDisplays: attributeDisplays
                )
                measureSelectionHitLayer(
                    width: contentWidth,
                    height: proxy.size.height,
                    attributeDisplays: attributeDisplays
                )
                barlineHitLayer(
                    width: contentWidth,
                    height: proxy.size.height,
                    attributeDisplays: attributeDisplays
                )
                notationItemSelectionHitLayer(
                    width: contentWidth,
                    height: proxy.size.height,
                    attributeDisplays: attributeDisplays
                )
                measureNumberLabels(
                    width: contentWidth,
                    height: proxy.size.height,
                    attributeDisplays: attributeDisplays
                )
                if showsRegionLabels {
                    regionLabelsLayer(
                        width: contentWidth,
                        height: proxy.size.height,
                        attributeDisplays: attributeDisplays
                    )
                }
                harmonySymbolsLayer(
                    width: contentWidth,
                    height: proxy.size.height,
                    attributeDisplays: attributeDisplays
                )
                playheadIndicator(
                    width: contentWidth,
                    height: proxy.size.height,
                    attributeDisplays: attributeDisplays
                )
                if partID.isMain {
                    harmonyEditorLayer(
                        width: contentWidth,
                        height: proxy.size.height,
                        attributeDisplays: attributeDisplays
                    )
                }
                notationEntryLayer(
                    width: contentWidth,
                    height: proxy.size.height,
                    attributeDisplays: attributeDisplays
                )
                attributeLabels(
                    width: contentWidth,
                    height: proxy.size.height,
                    attributeDisplays: attributeDisplays
                )
            }
            .coordinateSpace(name: notationTrackCoordinateSpaceName)
            .frame(width: contentWidth, height: proxy.size.height)
            .id(scrollResetIdentity)
            .contentShape(Rectangle())
            .onTapGesture {
                isTrackFocused = true
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .focusable()
            .focused($isTrackFocused)
            .focusEffectDisabled(true)
            .onDeleteCommand {
                deleteSelectedNotationItemOrHarmony()
            }
            .onChange(of: pendingEditorRequest?.id) { _, _ in
                if partID.isMain {
                    handlePendingEditorRequest()
                }
            }
            .onChange(of: entryMode) { _, mode in
                draggedNotePitchPreview = nil
                if mode == nil {
                    hoveredNotePlacement = nil
                    hoveredRestPlacement = nil
                } else if mode == .note {
                    hoveredRestPlacement = nil
                } else {
                    hoveredNotePlacement = nil
                }
            }
            .onChange(of: selectedItem) { _, newSelection in
                if let draggedNotePitchPreview,
                   newSelection != draggedNotePitchPreview.selection {
                    self.draggedNotePitchPreview = nil
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Notation Track")
            .accessibilityValue(accessibilityValue)
        }
    }

    private var renderedMeasureCount: Int {
        max(1, state.visibleMeasures.isEmpty ? state.visibleMeasureCount : state.visibleMeasures.count)
    }

    private var isEntryModeEnabled: Bool {
        entryMode != nil
    }

    private var visibleAttributeDisplays: [NotationAttributeDisplay] {
        state.visibleMeasures.indices.map { index in
            let previousAttributes = index > 0 ? state.visibleMeasures[index - 1].attributes : nil
            return NotationAttributeDisplay.display(
                for: state.visibleMeasures[index].attributes,
                previousAttributes: previousAttributes
            )
        }
    }

    private func measureAttributeReserveWidths(
        attributeDisplays: [NotationAttributeDisplay]
    ) -> [CGFloat] {
        (0..<renderedMeasureCount).map { index in
            guard state.visibleMeasures.indices.contains(index) else { return 0 }

            return NotationMeasureLayout.attributeReserveWidth(
                for: state.visibleMeasures[index].attributes,
                display: attributeDisplay(at: index, in: attributeDisplays)
            )
        }
    }

    private func notationCanvas(
        measureCount: Int,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(
                Path(roundedRect: rect, cornerRadius: cornerRadius),
                with: .color(appColors.notationTrackBackground)
            )

            let staffTop = staffTop(in: size.height)
            let staffBottom = staffTop + AppTheme.Timeline.notationStaffLineSpacing * 4
            let geometries = measureCanvasGeometries(
                measureCount: measureCount,
                width: size.width,
                attributeDisplays: attributeDisplays
            )

            drawStaffLines(
                geometries: geometries,
                staffTop: staffTop,
                in: &context
            )
            drawNotationItems(
                geometries: geometries,
                staffTop: staffTop,
                in: &context
            )
            drawBarlines(
                geometries: geometries,
                staffTop: staffTop,
                staffBottom: staffBottom,
                in: &context
            )
        }
    }

    private func measureCanvasGeometries(
        measureCount: Int,
        width: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> [NotationMeasureCanvasGeometry] {
        let safeMeasureCount = max(1, measureCount)
        return NotationMeasureLayout.canvasGeometries(
            measureCount: safeMeasureCount,
            totalWidth: width,
            attributeReserveWidths: measureAttributeReserveWidths(attributeDisplays: attributeDisplays)
        )
    }

    private func drawStaffLines(
        geometries: [NotationMeasureCanvasGeometry],
        staffTop: CGFloat,
        in context: inout GraphicsContext
    ) {
        for index in 0..<5 {
            let y = staffTop + CGFloat(index) * AppTheme.Timeline.notationStaffLineSpacing
            for geometry in geometries where geometry.staffEndX > geometry.staffStartX {
                var path = Path()
                path.move(to: CGPoint(x: geometry.staffStartX, y: y))
                path.addLine(to: CGPoint(x: geometry.staffEndX, y: y))
                context.stroke(
                    path,
                    with: .color(appColors.notationSymbolsAndLines.opacity(0.56)),
                    lineWidth: AppTheme.Stroke.thin
                )
            }
        }
    }

    private func drawBarlines(
        geometries: [NotationMeasureCanvasGeometry],
        staffTop: CGFloat,
        staffBottom: CGFloat,
        in context: inout GraphicsContext
    ) {
        for barline in NotationMeasureLayout.barlineGeometries(for: geometries) {
            drawBarline(
                x: barline.x,
                isOuterBoundary: barline.isOuterBoundary,
                staffTop: staffTop,
                staffBottom: staffBottom,
                in: &context
            )
        }
    }

    private func drawNotationItems(
        geometries: [NotationMeasureCanvasGeometry],
        staffTop: CGFloat,
        in context: inout GraphicsContext
    ) {
        for item in notationItemLayoutItems(geometries: geometries) {
            let color = selectedItem?.matches(
                item.measure,
                item: item.notationItem
            ) == true
                ? appColors.accent
                : appColors.notationSymbolsAndLines
            switch item.notationItem.kind {
            case .rest:
                guard let symbol = NotationSMuFLSymbol(duration: item.notationItem.displayDuration) else {
                    continue
                }
                drawRestGlyph(
                    symbol: symbol,
                    duration: item.notationItem.displayDuration,
                    x: item.x,
                    staffTop: staffTop,
                    color: color,
                    in: &context
                )
            case .note:
                let pitch = draggedNotePitchPreview?.matches(item.selection) == true
                    ? draggedNotePitchPreview?.pitch
                    : item.notationItem.pitch
                guard let pitch else { continue }
                let staffPosition = NotationPitchMapper.staffPosition(
                    for: pitch,
                    clef: item.measure.attributes.clef
                )
                drawNoteGlyphWithLedgerLines(
                    duration: item.notationItem.displayDuration,
                    x: item.x,
                    staffPosition: staffPosition,
                    staffTop: staffTop,
                    color: color,
                    opacity: 1,
                    in: &context
                )
            }
        }

        if let hoveredNotePlacement {
            let staffPosition = NotationPitchMapper.staffPosition(
                for: hoveredNotePlacement.pitch,
                clef: hoveredNotePlacement.measure.attributes.clef
            )
            drawNoteGlyphWithLedgerLines(
                duration: hoveredNotePlacement.displayDuration,
                x: hoveredNotePlacement.x,
                staffPosition: staffPosition,
                staffTop: staffTop,
                color: appColors.accent,
                opacity: 0.56,
                in: &context
            )
        } else if let hoveredRestPlacement,
                  let symbol = NotationSMuFLSymbol(duration: hoveredRestPlacement.displayDuration) {
            drawRestGlyph(
                symbol: symbol,
                duration: hoveredRestPlacement.displayDuration,
                x: hoveredRestPlacement.x,
                staffTop: staffTop,
                color: appColors.accent.opacity(0.56),
                in: &context
            )
        }
    }

    private func drawNoteGlyphWithLedgerLines(
        duration: NotationDuration,
        x: CGFloat,
        staffPosition: Int,
        staffTop: CGFloat,
        color: Color,
        opacity: Double,
        in context: inout GraphicsContext
    ) {
        drawLedgerLines(
            staffPosition: staffPosition,
            x: x,
            staffTop: staffTop,
            color: color,
            opacity: opacity,
            in: &context
        )
        drawNoteGlyph(
            duration: duration,
            x: x,
            y: NotationNotePlacementResolver.yPosition(
                forStaffPosition: staffPosition,
                staffTop: staffTop
            ),
            stemDirection: NotationStemDirection.direction(forStaffPosition: staffPosition),
            color: color,
            opacity: opacity,
            in: &context
        )
        if duration.isDotted {
            drawAugmentationDot(
                at: NotationAugmentationDotLayout.noteTarget(
                    noteX: x,
                    noteStaffPosition: staffPosition,
                    staffTop: staffTop
                ),
                color: color,
                opacity: opacity,
                in: &context
            )
        }
    }

    private func drawLedgerLines(
        staffPosition: Int,
        x: CGFloat,
        staffTop: CGFloat,
        color: Color,
        opacity: Double,
        in context: inout GraphicsContext
    ) {
        let spacing = AppTheme.Timeline.notationStaffLineSpacing
        let halfWidth = spacing * 1.28
        for ledgerPosition in NotationNotePlacementResolver.ledgerLineStaffPositions(forStaffPosition: staffPosition) {
            let y = NotationNotePlacementResolver.yPosition(
                forStaffPosition: ledgerPosition,
                staffTop: staffTop
            )
            var path = Path()
            path.move(to: CGPoint(x: x - halfWidth, y: y))
            path.addLine(to: CGPoint(x: x + halfWidth, y: y))
            context.stroke(
                path,
                with: .color(color.opacity(opacity)),
                lineWidth: AppTheme.Stroke.thin
            )
        }
    }

    private func drawNoteGlyph(
        duration: NotationDuration,
        x: CGFloat,
        y: CGFloat,
        stemDirection: NotationStemDirection,
        color: Color,
        opacity: Double,
        in context: inout GraphicsContext
    ) {
        let spacing = AppTheme.Timeline.notationStaffLineSpacing
        let fontSize = spacing * 3.25
        guard let symbol = NotationStaffNoteSymbol(
            duration: duration,
            stemDirection: stemDirection
        ),
              let glyphPath = NotationMusicFontRegistry.glyphPath(for: symbol, fontSize: fontSize),
              let anchor = NotationMusicFontRegistry.noteheadAnchor(for: symbol, fontSize: fontSize)
        else {
            return
        }

        let transform = glyphPath.anchoredTransform(
            anchor: anchor,
            target: CGPoint(x: x, y: y)
        )
        context.fill(
            Path(glyphPath.path).applying(transform),
            with: .color(color.opacity(opacity))
        )
    }

    private func drawRestGlyph(
        symbol: NotationSMuFLSymbol,
        duration: NotationDuration,
        x: CGFloat,
        staffTop: CGFloat,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let spacing = AppTheme.Timeline.notationStaffLineSpacing
        let fontSize = spacing * 3.25
        if symbol == .restWhole,
           let glyphPath = NotationMusicFontRegistry.glyphPath(for: symbol, fontSize: fontSize) {
            let targetY = wholeRestVisualCenterY(staffTop: staffTop)
            let transform = CGAffineTransform(
                translationX: x - glyphPath.bounds.midX,
                y: targetY - glyphPath.bounds.midY
            )
            context.fill(
                Path(glyphPath.path).applying(transform),
                with: .color(color)
            )
        } else {
            let text = Text(symbol.glyph)
                .font(.custom(NotationMusicFontRegistry.fontName, size: fontSize))
                .foregroundStyle(color)
            context.draw(
                text,
                at: CGPoint(x: x, y: restGlyphY(symbol: symbol, staffTop: staffTop)),
                anchor: .center
            )
        }

        if duration.isDotted {
            drawAugmentationDot(
                at: NotationAugmentationDotLayout.restTarget(restX: x, staffTop: staffTop),
                color: color,
                opacity: 1,
                in: &context
            )
        }
    }

    private func drawAugmentationDot(
        at target: CGPoint,
        color: Color,
        opacity: Double,
        in context: inout GraphicsContext
    ) {
        let fontSize = AppTheme.Timeline.notationStaffLineSpacing * 3.25
        guard let glyphPath = NotationMusicFontRegistry.glyphPath(
            for: NotationAugmentationDotSymbol.augmentationDot,
            fontSize: fontSize
        ) else { return }
        let anchor = CGPoint(x: glyphPath.bounds.midX, y: glyphPath.bounds.midY)
        context.fill(
            Path(glyphPath.path).applying(glyphPath.anchoredTransform(anchor: anchor, target: target)),
            with: .color(color.opacity(opacity))
        )
    }

    private func restGlyphY(symbol: NotationSMuFLSymbol, staffTop: CGFloat) -> CGFloat {
        let spacing = AppTheme.Timeline.notationStaffLineSpacing
        let line3Y = staffTop + spacing * 2

        switch symbol {
        case .restWhole:
            return wholeRestVisualCenterY(staffTop: staffTop)
        case .restHalf:
            return line3Y - spacing * 0.08
        case .restQuarter:
            return line3Y + spacing * 0.06
        case .rest8th, .rest16th, .rest32nd:
            return line3Y - spacing * 0.12
        }
    }

    private func wholeRestVisualCenterY(staffTop: CGFloat) -> CGFloat {
        NotationMeasureLayout.wholeRestVisualCenterY(staffTop: staffTop)
    }

    private func drawBarline(
        x: CGFloat,
        isOuterBoundary: Bool,
        staffTop: CGFloat,
        staffBottom: CGFloat,
        in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: CGPoint(x: x, y: staffTop))
        path.addLine(to: CGPoint(x: x, y: staffBottom))
        context.stroke(
            path,
            with: .color(appColors.notationSymbolsAndLines),
            lineWidth: isOuterBoundary ? AppTheme.Stroke.medium : AppTheme.Stroke.thin
        )
    }

    private func measureNumberLabels(
        width: CGFloat,
        height: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> some View {
        let geometries = measureCanvasGeometries(
            measureCount: renderedMeasureCount,
            width: width,
            attributeDisplays: attributeDisplays
        )
        let labelY = NotationMeasureLayout.systemMeasureNumberLabelY(
            staffTop: staffTop(in: height)
        )

        return ZStack(alignment: .topLeading) {
            if let firstMeasure = state.visibleMeasures.first {
                let labelX = geometries.first.map {
                    NotationMeasureLayout.systemMeasureNumberLabelX(geometry: $0)
                } ?? AppTheme.Spacing.xs

                Text("\(firstMeasure.number)")
                    .font(AppTheme.Typography.timelineLabel.weight(.medium))
                    .foregroundStyle(appColors.secondaryText)
                    .lineLimit(1)
                    .frame(width: NotationMeasureLayout.measureNumberLabelWidth, alignment: .trailing)
                    .offset(
                        x: labelX,
                        y: labelY
                    )
                    .accessibilityLabel("Measure \(firstMeasure.number)")
            }
        }
    }

    private func selectedMeasureOverlay(
        width: CGFloat,
        height: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> some View {
        let geometries = measureCanvasGeometries(
            measureCount: renderedMeasureCount,
            width: width,
            attributeDisplays: attributeDisplays
        )
        let staffTop = staffTop(in: height)
        let overlayY = max(AppTheme.Spacing.xs, staffTop - AppTheme.Spacing.xxl)
        let overlayBottom = staffTop
            + AppTheme.Timeline.notationStaffLineSpacing * 4
            + AppTheme.Spacing.lg
        let overlayHeight = max(1, overlayBottom - overlayY)
        let selectedMeasureIndices = NotationTrackLayoutItems.selectedMeasureIndices(
            visibleMeasures: state.visibleMeasures,
            selectedMeasures: selectedMeasures,
            partID: partID
        )
        let selectionRuns = NotationMeasureLayout.selectionOverlayRuns(
            selectedMeasureIndices: selectedMeasureIndices,
            geometries: geometries
        )

        return ZStack(alignment: .topLeading) {
            ForEach(selectionRuns) { run in
                RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                    .fill(appColors.accent.opacity(0.16))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                            .stroke(appColors.accent, lineWidth: AppTheme.Stroke.thick)
                    }
                    .frame(
                        width: max(1, run.width),
                        height: overlayHeight
                    )
                    .offset(x: run.x, y: overlayY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private func measureSelectionHitLayer(
        width: CGFloat,
        height: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> some View {
        let geometries = measureCanvasGeometries(
            measureCount: renderedMeasureCount,
            width: width,
            attributeDisplays: attributeDisplays
        )

        return ZStack(alignment: .topLeading) {
            ForEach(state.visibleMeasures.indices, id: \.self) { index in
                if geometries.indices.contains(index) {
                    let geometry = geometries[index]
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .frame(
                            width: max(1, geometry.cellEndX - geometry.cellStartX),
                            height: height
                        )
                        .offset(x: geometry.cellStartX, y: 0)
                        .onTapGesture {
                            isTrackFocused = true
                            editingDraft = nil
                            actions.selectMeasure(state.visibleMeasures[index], isShiftClickActive, partID)
                        }
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func notationItemSelectionHitLayer(
        width: CGFloat,
        height: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> some View {
        let geometries = measureCanvasGeometries(
            measureCount: renderedMeasureCount,
            width: width,
            attributeDisplays: attributeDisplays
        )
        let staffTop = staffTop(in: height)
        let hitHeight = AppTheme.Timeline.notationStaffLineSpacing * 4 + AppTheme.Spacing.md
        let hitWidth = max(
            AppTheme.ControlSize.abletonNumberFieldHeight,
            AppTheme.Timeline.notationSlashWidth + AppTheme.Spacing.lg
        )

        return ZStack(alignment: .topLeading) {
            ForEach(notationItemLayoutItems(geometries: geometries), id: \.id) { item in
                let hitCenterY = notationItemHitCenterY(item, staffTop: staffTop)
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: hitWidth, height: hitHeight)
                    .offset(
                        x: item.x - hitWidth / 2,
                        y: max(0, hitCenterY - hitHeight / 2)
                    )
                    .onTapGesture {
                        isTrackFocused = true
                        editingDraft = nil
                        actions.selectItem(item.selection, true)
                    }
                    .simultaneousGesture(notePitchDragGesture(
                        item: item,
                        staffTop: staffTop
                    ))
                    .accessibilityLabel(notationItemAccessibilityLabel(item))
                    .accessibilityValue(
                        selectedItem?.matches(
                            item.measure,
                            item: item.notationItem
                        ) == true ? "Selected" : ""
                    )
            }
        }
    }

    private func notationItemHitCenterY(
        _ item: NotationItemLayoutItem,
        staffTop: CGFloat
    ) -> CGFloat {
        if item.notationItem.kind == .note,
           let pitch = item.notationItem.pitch {
            let staffPosition = NotationPitchMapper.staffPosition(
                for: pitch,
                clef: item.measure.attributes.clef
            )
            return NotationNotePlacementResolver.yPosition(
                forStaffPosition: staffPosition,
                staffTop: staffTop
            )
        }

        return restGlyphY(
            symbol: NotationSMuFLSymbol(duration: item.notationItem.displayDuration) ?? .restQuarter,
            staffTop: staffTop
        )
    }

    @ViewBuilder
    private func notationEntryLayer(
        width: CGFloat,
        height: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> some View {
        if let entryMode {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: width, height: height)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        updateHoveredEntryPlacement(
                            mode: entryMode,
                            point: point,
                            width: width,
                            height: height,
                            attributeDisplays: attributeDisplays
                        )
                    case .ended:
                        hoveredNotePlacement = nil
                        hoveredRestPlacement = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            isTrackFocused = true
                            editingDraft = nil
                            switch entryMode {
                            case .note:
                                guard let placement = notePlacement(
                                    at: value.location,
                                    width: width,
                                    height: height,
                                    attributeDisplays: attributeDisplays
                                ) else { return }
                                if actions.insertNotationNote(placement) {
                                    hoveredNotePlacement = placement
                                    hoveredRestPlacement = nil
                                }
                            case .rest:
                                guard let placement = restPlacement(
                                    at: value.location,
                                    width: width,
                                    height: height,
                                    attributeDisplays: attributeDisplays
                                ) else { return }
                                if actions.insertNotationRest(placement) {
                                    hoveredNotePlacement = nil
                                    hoveredRestPlacement = placement
                                }
                            }
                        }
                )
                .cursor(.crosshair)
                .help(entryMode == .note ? "Add notation note" : "Add notation rest")
                .accessibilityLabel(entryMode == .note ? "Notation note entry area" : "Notation rest entry area")
        }
    }

    private func updateHoveredEntryPlacement(
        mode: NotationEntryMode,
        point: CGPoint,
        width: CGFloat,
        height: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) {
        switch mode {
        case .note:
            hoveredNotePlacement = notePlacement(
                at: point,
                width: width,
                height: height,
                attributeDisplays: attributeDisplays
            )
            hoveredRestPlacement = nil
        case .rest:
            hoveredNotePlacement = nil
            hoveredRestPlacement = restPlacement(
                at: point,
                width: width,
                height: height,
                attributeDisplays: attributeDisplays
            )
        }
    }

    private func notePitchDragGesture(
        item: NotationItemLayoutItem,
        staffTop: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(notationTrackCoordinateSpaceName))
            .onChanged { value in
                guard !isEntryModeEnabled,
                      item.notationItem.kind == .note,
                      let pitch = notePitch(
                          forDragY: value.location.y,
                          measure: item.measure,
                          staffTop: staffTop
                      )
                else {
                    return
                }

                isTrackFocused = true
                editingDraft = nil
                if draggedNotePitchPreview?.matches(item.selection) != true {
                    actions.selectItem(item.selection, false)
                }

                let didAudition: Bool
                if draggedNotePitchPreview?.matches(item.selection) == true,
                   draggedNotePitchPreview?.pitch == pitch {
                    didAudition = draggedNotePitchPreview?.didAudition == true
                } else if item.notationItem.pitch != pitch {
                    actions.auditionNotePitch(pitch)
                    didAudition = true
                } else {
                    didAudition = false
                }

                draggedNotePitchPreview = NotationDraggedNotePitchPreview(
                    selection: item.selection,
                    pitch: pitch,
                    didAudition: didAudition
                )
            }
            .onEnded { _ in
                guard let preview = draggedNotePitchPreview,
                      preview.matches(item.selection)
                else {
                    draggedNotePitchPreview = nil
                    return
                }

                _ = actions.changeSelectedNotePitch(preview.pitch, !preview.didAudition)
                draggedNotePitchPreview = nil
            }
    }

    private func notePitch(
        forDragY y: CGFloat,
        measure: ScoreMeasure,
        staffTop: CGFloat
    ) -> NotationPitch? {
        guard let staffPosition = NotationNotePlacementResolver.clampedStaffPosition(
            forY: y,
            staffTop: staffTop,
            clef: measure.attributes.clef
        ) else {
            return nil
        }

        return NotationPitchMapper.pitch(
            forStaffPosition: staffPosition,
            keySignature: measure.attributes.keySignature,
            clef: measure.attributes.clef
        )
    }

    private func barlineHitLayer(
        width: CGFloat,
        height: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> some View {
        let geometries = measureCanvasGeometries(
            measureCount: renderedMeasureCount,
            width: width,
            attributeDisplays: attributeDisplays
        )
        let targets = NotationMeasureLayout.barlineHitTargets(
            for: geometries,
            measures: state.visibleMeasures
        )
        let staffTop = staffTop(in: height)
        let hitY = max(0, staffTop - AppTheme.Spacing.xs)
        let hitHeight = AppTheme.Timeline.notationStaffLineSpacing * 4 + AppTheme.Spacing.sm
        let hitWidth = AppTheme.Timeline.notationBarlineHitWidth

        return ZStack(alignment: .topLeading) {
            ForEach(targets) { target in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: hitWidth, height: hitHeight)
                    .offset(
                        x: target.x - hitWidth / 2,
                        y: hitY
                    )
                    .onTapGesture {
                        isTrackFocused = true
                        editingDraft = nil
                        actions.locatePlaybackMarkerExactly(target.targetTime)
                    }
                    .accessibilityLabel(barlineAccessibilityLabel(for: target))
                    .help(barlineAccessibilityLabel(for: target))
            }
        }
    }

    private func regionLabelsLayer(
        width: CGFloat,
        height: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> some View {
        let geometries = measureCanvasGeometries(
            measureCount: renderedMeasureCount,
            width: width,
            attributeDisplays: attributeDisplays
        )
        let labelY = NotationMeasureLayout.regionLabelY(staffTop: staffTop(in: height))

        return ZStack(alignment: .topLeading) {
            ForEach(regionLabelLayoutItems(geometries: geometries), id: \.label.id) { item in
                regionLabelView(item.label)
                    .offset(
                        x: item.x,
                        y: labelY
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private func regionLabelView(_ label: NotationRegionLabel) -> some View {
        Text(label.title.uppercased())
            .font(.system(size: AppTheme.Timeline.notationRegionLabelFontSize, weight: .bold))
            .foregroundStyle(appColors.notationSymbolsAndLines)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, AppTheme.Spacing.xxs)
            .frame(
                maxWidth: AppTheme.Timeline.notationRegionLabelMaxWidth,
                minHeight: AppTheme.Timeline.notationRegionLabelHeight,
                maxHeight: AppTheme.Timeline.notationRegionLabelHeight,
                alignment: .center
            )
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Timeline.notationRegionLabelCornerRadius)
                    .fill(appColors.notationTrackBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Timeline.notationRegionLabelCornerRadius)
                    .stroke(appColors.notationSymbolsAndLines, lineWidth: AppTheme.Stroke.thin)
            )
    }

    private func attributeLabels(
        width: CGFloat,
        height: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> some View {
        let geometries = measureCanvasGeometries(
            measureCount: renderedMeasureCount,
            width: width,
            attributeDisplays: attributeDisplays
        )

        return ZStack(alignment: .topLeading) {
            ForEach(state.visibleMeasures.indices, id: \.self) { index in
                let display = attributeDisplay(at: index, in: attributeDisplays)
                if !display.isEmpty, geometries.indices.contains(index) {
                    let attributes = state.visibleMeasures[index].attributes
                    let attributeBlockWidth = NotationMeasureLayout.attributeBlockWidth(
                        for: attributes,
                        display: display,
                        cellWidth: geometries[index].contentEndX - geometries[index].contentStartX
                    )

                    measureAttributes(
                        attributes,
                        display: display,
                        blockWidth: attributeBlockWidth
                    )
                    .offset(
                        x: geometries[index].cellStartX + AppTheme.Spacing.md,
                        y: staffTop(in: height) - NotationMeasureLayout.attributeStaffTopInset(
                            for: attributes,
                            display: display
                        )
                    )
                }
            }
        }
    }

    private func harmonySymbolsLayer(
        width: CGFloat,
        height: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> some View {
        let geometries = measureCanvasGeometries(
            measureCount: renderedMeasureCount,
            width: width,
            attributeDisplays: attributeDisplays
        )
        let staffTop = staffTop(in: height)
        let harmonyY = NotationMeasureLayout.harmonyLabelY(staffTop: staffTop)

        return ZStack(alignment: .topLeading) {
            ForEach(harmonyLayoutItems(geometries: geometries), id: \.symbol.id) { item in
                harmonySymbolView(item.symbol)
                    .frame(width: AppTheme.Timeline.notationHarmonySymbolWidth, alignment: .leading)
                    .offset(
                        x: item.x,
                        y: harmonyY
                    )
            }
        }
    }

    private func harmonySymbolView(_ symbol: HarmonySymbol) -> some View {
        let isSelected = symbol.id == selectedHarmonySymbolID

        return Text(symbol.rawText)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(appColors.notationSymbolsAndLines)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, AppTheme.Spacing.xs)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                    .fill(isSelected ? appColors.accent.opacity(0.24) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                isTrackFocused = true
                actions.selectItem(itemSelection(for: symbol), false)
                if !isShiftClickActive {
                    actions.selectHarmony(symbol.id)
                }
            }
            .onTapGesture(count: 2) {
                isTrackFocused = true
                actions.selectItem(itemSelection(for: symbol), false)
                beginEditingHarmony(symbol)
            }
            .accessibilityLabel("Harmony \(symbol.rawText)")
    }

    @ViewBuilder
    private func harmonyEditorLayer(
        width: CGFloat,
        height: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> some View {
        if let editingDraft,
           let item = harmonyLayoutItem(
            for: editingDraft.time,
            width: width,
            attributeDisplays: attributeDisplays
           ) {
            let staffTop = staffTop(in: height)
            let harmonyY = NotationMeasureLayout.harmonyLabelY(staffTop: staffTop)

            HarmonyInlineTextField(
                text: Binding(
                    get: { self.editingDraft?.text ?? "" },
                    set: { self.editingDraft?.text = $0 }
                ),
                onCommit: { commitEditingDraft() },
                onCancel: { cancelEditingDraft() },
                onNavigate: { commitEditingDraft(navigation: $0) }
            )
            .frame(
                width: harmonyEditorWidth(for: editingDraft.text),
                height: AppTheme.ControlSize.abletonNumberFieldHeight
            )
            .offset(
                x: item.x,
                y: harmonyY
            )
        }
    }

    private func harmonyEditorWidth(for text: String) -> CGFloat {
        let measuredText = text.isEmpty ? "M" : text
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let textWidth = (measuredText as NSString).size(withAttributes: [.font: font]).width
        let paddedWidth = ceil(textWidth) + AppTheme.Spacing.md
        return min(
            AppTheme.Timeline.notationHarmonyEditorMaxWidth,
            max(AppTheme.Timeline.notationHarmonyEditorMinWidth, paddedWidth)
        )
    }

    private func measureAttributes(
        _ attributes: MeasureAttributes,
        display: NotationAttributeDisplay,
        blockWidth: CGFloat
    ) -> some View {
        let visibleComponentCount = NotationMeasureLayout.visibleComponentCount(
            for: attributes,
            display: display
        )
        let visibleSpacingWidth = NotationMeasureLayout.spacingWidth(forVisibleComponentCount: visibleComponentCount)
        let fixedComponentWidth = (display.showsClef ? NotationClefLayout.frameSize.width : 0)
            + (display.showsTimeSignature ? AppTheme.Timeline.notationTimeSignatureWidth : 0)
        let availableAccidentalWidth = max(
            0,
            blockWidth
                - fixedComponentWidth
                - visibleSpacingWidth
        )
        let keySignatureGlyphs = attributes.keySignature.notationAccidentalGlyphs(for: attributes.clef)

        return HStack(alignment: .center, spacing: AppTheme.Spacing.xs) {
            if display.showsClef {
                ClefGlyphView(
                    clef: attributes.clef,
                    color: appColors.notationSymbolsAndLines
                )
                    .contentShape(Rectangle())
                    .contextMenu {
                        ForEach(Clef.allCases) { clef in
                            Button {
                                actions.changeClef(partID, clef)
                            } label: {
                                Label(
                                    clef.displayName,
                                    systemImage: clef == attributes.clef ? "checkmark" : "music.note"
                                )
                            }
                            .disabled(clef == attributes.clef)
                        }
                    }
                    .menuOrder(.fixed)
                    .help("Change clef")
                    .accessibilityLabel("Notation clef")
                    .accessibilityValue(attributes.clef.displayName)
            }

            if display.showsKeySignature && !keySignatureGlyphs.isEmpty {
                KeySignatureAccidentalsView(
                    glyphs: keySignatureGlyphs,
                    color: appColors.notationSymbolsAndLines
                )
                .frame(
                    width: min(
                        NotationMeasureLayout.keySignatureWidth(for: attributes),
                        availableAccidentalWidth
                    ),
                    alignment: .leading
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(attributes.keySignature.displayName) key signature")
                .allowsHitTesting(false)
            }

            if display.showsTimeSignature {
                VStack(spacing: AppTheme.Spacing.none) {
                    Text("\(attributes.timeSignature.beatsPerBar)")
                    Text("\(attributes.timeSignature.beatUnit)")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(appColors.notationSymbolsAndLines)
                .lineLimit(1)
                .frame(width: AppTheme.Timeline.notationTimeSignatureWidth)
                .accessibilityLabel("Time signature \(attributes.timeSignature.displayText)")
                .allowsHitTesting(false)
            }
        }
        .frame(width: max(0, blockWidth), alignment: .leading)
        .clipped()
    }

    @ViewBuilder
    private func playheadIndicator(
        width: CGFloat,
        height: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> some View {
        if let playbackDisplayState {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playbackDisplayState.isPlaying)) { context in
                playheadIndicator(
                    anchorTime: playbackDisplayState.displayTime(at: context.date),
                    width: width,
                    height: height,
                    attributeDisplays: attributeDisplays
                )
            }
        } else {
            playheadIndicator(
                anchorTime: state.anchorTime,
                width: width,
                height: height,
                attributeDisplays: attributeDisplays
            )
        }
    }

    @ViewBuilder
    private func playheadIndicator(
        anchorTime: TimeInterval,
        width: CGFloat,
        height: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> some View {
        if let activeMeasureIndex = activeMeasureIndex(for: anchorTime) {
            let geometries = measureCanvasGeometries(
                measureCount: renderedMeasureCount,
                width: width,
                attributeDisplays: attributeDisplays
            )
            let measure = state.visibleMeasures[activeMeasureIndex]
            let progress = measure.duration > 0
                ? max(0, min((anchorTime - measure.startTime) / measure.duration, 1))
                : 0
            let geometry = geometries.indices.contains(activeMeasureIndex)
                ? geometries[activeMeasureIndex]
                : nil
            let x = geometry.map {
                NotationMeasureLayout.playheadIndicatorX(
                    geometry: $0,
                    progress: CGFloat(progress),
                    indicatorWidth: AppTheme.Stroke.thick
                )
            } ?? 0
            let staffTop = staffTop(in: height)
            let indicatorHeight = AppTheme.Timeline.notationStaffLineSpacing * 4

            Rectangle()
                .fill(appColors.accent)
                .frame(width: AppTheme.Stroke.thick, height: indicatorHeight + AppTheme.Spacing.sm)
                .offset(x: x, y: staffTop - AppTheme.Spacing.xs)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func activeMeasureIndex(for anchorTime: TimeInterval) -> Int? {
        state.visibleMeasures.indices.first { index in
            let measure = state.visibleMeasures[index]
            let isLastVisibleMeasure = index == state.visibleMeasures.indices.upperBound - 1
            return state.anchorTime >= measure.startTime
                && (state.anchorTime < measure.endTime || (isLastVisibleMeasure && state.anchorTime <= measure.endTime))
        }
    }

    private func attributeDisplay(
        at index: Int,
        in attributeDisplays: [NotationAttributeDisplay]
    ) -> NotationAttributeDisplay {
        guard attributeDisplays.indices.contains(index) else { return .none }
        return attributeDisplays[index]
    }

    private func staffTop(in height: CGFloat) -> CGFloat {
        max(AppTheme.Spacing.xxl, (height - AppTheme.Timeline.notationStaffLineSpacing * 4) / 2 + AppTheme.Spacing.xs)
    }

    private func regionLabelLayoutItems(
        geometries: [NotationMeasureCanvasGeometry]
    ) -> [RegionLabelLayoutItem] {
        NotationTrackLayoutItems.regionLabels(
            visibleMeasures: state.visibleMeasures,
            geometries: geometries
        )
    }

    private func harmonyLayoutItems(
        geometries: [NotationMeasureCanvasGeometry]
    ) -> [HarmonyLayoutItem] {
        NotationTrackLayoutItems.harmonies(
            visibleMeasures: state.visibleMeasures,
            geometries: geometries
        )
    }

    private func notationItemLayoutItems(
        geometries: [NotationMeasureCanvasGeometry]
    ) -> [NotationItemLayoutItem] {
        NotationTrackLayoutItems.notationItems(
            visibleMeasures: state.visibleMeasures,
            geometries: geometries
        )
    }

    private func harmonyLayoutItem(
        for time: TimeInterval,
        width: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> HarmonyLayoutItem? {
        guard let placement = harmonyPlacement(for: time) else { return nil }
        let geometries = measureCanvasGeometries(
            measureCount: renderedMeasureCount,
            width: width,
            attributeDisplays: attributeDisplays
        )
        guard geometries.indices.contains(placement.measureIndex) else { return nil }

        return HarmonyLayoutItem(
            symbol: HarmonySymbol(
                time: placement.time,
                measureNumber: placement.measureNumber,
                offsetInQuarterNotes: placement.offsetInQuarterNotes,
                rawText: editingDraft?.text ?? ""
            ),
            x: NotationMeasureLayout.harmonyLabelX(
                geometry: geometries[placement.measureIndex],
                offsetInQuarterNotes: placement.offsetInQuarterNotes,
                timeSignature: state.visibleMeasures[placement.measureIndex].attributes.timeSignature
            )
        )
    }

    private func beginEditingHarmony(at point: CGPoint, width: CGFloat) {
        isTrackFocused = true
        guard let placement = harmonyPlacement(for: point, width: width) else { return }

        if let existing = harmonySymbol(at: placement.time) {
            beginEditingHarmony(existing)
            return
        }

        editingDraft = HarmonyEditorDraft(
            id: UUID(),
            time: placement.time,
            measureNumber: placement.measureNumber,
            offsetInQuarterNotes: placement.offsetInQuarterNotes,
            text: "",
            isNew: true
        )
        actions.selectHarmony(nil)
    }

    private func beginEditingHarmony(_ symbol: HarmonySymbol) {
        editingDraft = HarmonyEditorDraft(
            id: symbol.id,
            time: symbol.time,
            measureNumber: symbol.measureNumber,
            offsetInQuarterNotes: symbol.offsetInQuarterNotes,
            text: symbol.rawText,
            isNew: false
        )
        actions.selectHarmony(symbol.id)
    }

    private func beginEditingHarmony(at placement: HarmonyPlacement) {
        if let existing = harmonySymbol(at: placement.time) {
            beginEditingHarmony(existing)
            return
        }

        editingDraft = HarmonyEditorDraft(
            id: UUID(),
            time: placement.time,
            measureNumber: placement.measureNumber,
            offsetInQuarterNotes: placement.offsetInQuarterNotes,
            text: "",
            isNew: true
        )
        actions.selectHarmony(nil)
    }

    private func commitEditingDraft(navigation: HarmonyNavigationDirection? = nil) {
        guard let draft = editingDraft else { return }
        let trimmedText = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedText.isEmpty {
            if !draft.isNew {
                actions.deleteHarmony(draft.id)
            }
        } else {
            actions.saveHarmony(HarmonySymbol(
                id: draft.id,
                time: draft.time,
                measureNumber: draft.measureNumber,
                offsetInQuarterNotes: draft.offsetInQuarterNotes,
                rawText: draft.text
            ))
        }

        editingDraft = nil

        if let navigation,
           let nextPlacement = actions.adjacentHarmonyPlacement(draft.time, navigation) {
            beginEditingHarmony(at: nextPlacement)
        }
    }

    private func cancelEditingDraft() {
        editingDraft = nil
    }

    private func deleteSelectedNotationItemOrHarmony() {
        if actions.deleteSelectedNotationNote() {
            editingDraft = nil
            draggedNotePitchPreview = nil
            return
        }

        deleteSelectedHarmony()
    }

    private func deleteSelectedHarmony() {
        guard let selectedHarmonySymbolID else { return }
        editingDraft = nil
        actions.deleteHarmony(selectedHarmonySymbolID)
    }

    private func handlePendingEditorRequest() {
        guard let pendingEditorRequest,
              let placement = harmonyPlacement(for: pendingEditorRequest.time)
        else {
            return
        }

        beginEditingHarmony(at: placement.harmonyPlacement)
    }

    private func harmonySymbol(at time: TimeInterval) -> HarmonySymbol? {
        state.visibleMeasures
            .flatMap(\.harmonies)
            .first { abs($0.time - time) < 0.000_001 }
    }

    private func measure(containing symbol: HarmonySymbol) -> ScoreMeasure? {
        state.visibleMeasures.first {
            NotationMeasureTiming.containsEventTime(symbol.time, in: $0)
        }
    }

    private func itemSelection(for symbol: HarmonySymbol) -> NotationItemSelection? {
        guard let measure = measure(containing: symbol) else { return nil }
        let matchingItem = measure.notationItems.first {
            abs($0.offsetInQuarterNotes - symbol.offsetInQuarterNotes) < 0.000_001
        } ?? measure.notationItems.first

        return matchingItem.map { NotationItemSelection(measure: measure, item: $0) }
    }

    private func harmonyPlacement(for time: TimeInterval) -> NotationHarmonyPlacement? {
        guard let measureIndex = state.visibleMeasures.indices.first(where: { index in
            let measure = state.visibleMeasures[index]
            return time >= measure.startTime - 0.000_001
                && (
                    time < measure.endTime - 0.000_001
                        || abs(time - measure.startTime) < 0.000_001
                )
        }) else {
            return nil
        }

        let measure = state.visibleMeasures[measureIndex]
        let snappedOffset = NotationMeasureTiming.quarterOffset(for: time, in: measure)
        let resolvedTime = NotationMeasureLayout.time(
            forHarmonyOffset: snappedOffset,
            in: measure
        )

        return NotationHarmonyPlacement(
            measureIndex: measureIndex,
            time: resolvedTime,
            measureNumber: measure.number,
            offsetInQuarterNotes: snappedOffset
        )
    }

    private func harmonyPlacement(for point: CGPoint, width: CGFloat) -> NotationHarmonyPlacement? {
        guard renderedMeasureCount > 0, !state.visibleMeasures.isEmpty else { return nil }
        let attributeDisplays = visibleAttributeDisplays
        let geometries = measureCanvasGeometries(
            measureCount: renderedMeasureCount,
            width: width,
            attributeDisplays: attributeDisplays
        )
        guard let geometryIndex = NotationMeasureLayout.measureIndex(
            atX: point.x,
            in: geometries
        ) else { return nil }

        let measureIndex = min(max(0, geometryIndex), state.visibleMeasures.count - 1)
        let measure = state.visibleMeasures[measureIndex]
        guard geometries.indices.contains(measureIndex) else { return nil }
        let geometry = geometries[measureIndex]
        let progress = NotationMeasureLayout.notationAnchorProgress(
            atX: point.x,
            geometry: geometry
        )
        let rawOffset = progress * NotationMeasureLayout.quarterLength(for: measure.attributes.timeSignature)
        let matchingItem = measure.notationItems.min { lhs, rhs in
            abs(lhs.offsetInQuarterNotes - rawOffset) < abs(rhs.offsetInQuarterNotes - rawOffset)
        }
        let offset = matchingItem?.offsetInQuarterNotes ?? rawOffset
        let resolvedTime = NotationMeasureLayout.time(forHarmonyOffset: offset, in: measure)

        return NotationHarmonyPlacement(
            measureIndex: measureIndex,
            time: resolvedTime,
            measureNumber: measure.number,
            offsetInQuarterNotes: offset
        )
    }

    private func notePlacement(
        at point: CGPoint,
        width: CGFloat,
        height: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> NotationNotePlacement? {
        guard let target = notationEntryTarget(
            at: point,
            width: width,
            attributeDisplays: attributeDisplays
        ) else { return nil }

        return NotationNotePlacementResolver.placement(
            in: target.measure,
            geometry: target.geometry,
            point: point,
            staffTop: staffTop(in: height),
            selectedDuration: selectedDuration,
            partID: partID
        )
    }

    private func restPlacement(
        at point: CGPoint,
        width: CGFloat,
        height: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> NotationRestPlacement? {
        guard let target = notationEntryTarget(
            at: point,
            width: width,
            attributeDisplays: attributeDisplays
        ) else { return nil }

        return NotationNotePlacementResolver.restPlacement(
            in: target.measure,
            geometry: target.geometry,
            point: point,
            staffTop: staffTop(in: height),
            selectedDuration: selectedDuration,
            partID: partID
        )
    }

    private func notationEntryTarget(
        at point: CGPoint,
        width: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> (measure: ScoreMeasure, geometry: NotationMeasureCanvasGeometry)? {
        guard renderedMeasureCount > 0, !state.visibleMeasures.isEmpty else { return nil }
        let geometries = measureCanvasGeometries(
            measureCount: renderedMeasureCount,
            width: width,
            attributeDisplays: attributeDisplays
        )
        guard let geometryIndex = NotationMeasureLayout.measureIndex(
            atX: point.x,
            in: geometries
        ) else {
            return nil
        }

        let measureIndex = min(max(0, geometryIndex), state.visibleMeasures.count - 1)
        guard geometries.indices.contains(measureIndex) else { return nil }

        return (measure: state.visibleMeasures[measureIndex], geometry: geometries[measureIndex])
    }

    private var accessibilityValue: String {
        NotationTrackAccessibility.value(
            visibleMeasures: state.visibleMeasures,
            keySignature: state.keySignature,
            timeSignature: state.timeSignature,
            selectedMeasures: selectedMeasures,
            partID: partID
        )
    }

    private func barlineAccessibilityLabel(for target: NotationBarlineHitTarget) -> String {
        switch target.boundary {
        case .leading:
            guard state.visibleMeasures.indices.contains(target.measureIndex) else {
                return "Move position marker to measure start"
            }
            return "Move position marker to measure \(state.visibleMeasures[target.measureIndex].number)"
        case .trailing:
            return "Move position marker to end of measure"
        }
    }

    private func notationItemAccessibilityLabel(_ item: NotationItemLayoutItem) -> String {
        switch item.notationItem.kind {
        case .rest:
            return "\(item.notationItem.displayDuration.capitalizedDisplayName) rest in measure \(item.selection.measureNumber)"
        case .note:
            let pitchText = item.notationItem.pitch.map {
                "\($0.step.rawValue)\($0.alter == 1 ? " sharp" : $0.alter == -1 ? " flat" : "")\($0.octave)"
            } ?? "note"
            return "\(item.notationItem.displayDuration.capitalizedDisplayName) \(pitchText) in measure \(item.selection.measureNumber)"
        }
    }

    private var isShiftClickActive: Bool {
        NSApp.currentEvent?.modifierFlags.contains(.shift) == true
    }

    private var scrollResetIdentity: String {
        guard let first = state.visibleMeasures.first else {
            return "pending-\(state.visibleMeasureCount)"
        }

        return "\(first.number)-\(first.startTime)"
    }
}

private struct ClefGlyphView: View {
    let clef: Clef
    let color: Color

    var body: some View {
        Canvas { context, size in
            let symbol = NotationClefSymbol(clef)
            guard let glyphPath = NotationMusicFontRegistry.glyphPath(
                for: symbol,
                fontSize: AppTheme.Timeline.notationClefFontSize
            ) else {
                return
            }

            let transform = NotationClefLayout.transform(
                for: glyphPath,
                symbol: symbol,
                in: size
            )
            context.fill(Path(glyphPath.path).applying(transform), with: .color(color))
        }
        .frame(
            width: NotationClefLayout.frameSize.width,
            height: NotationClefLayout.frameSize.height
        )
    }
}

private struct KeySignatureAccidentalsView: View {
    let glyphs: [KeySignatureAccidental]
    let color: Color

    fileprivate static let staffTopInset = AppTheme.Timeline.notationAttributeStaffTopInset

    private let fontSize: CGFloat = 20

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 0)
            let advance = glyphs.isEmpty ? 0 : width / CGFloat(glyphs.count)
            let lineSpacing = AppTheme.Timeline.notationStaffLineSpacing
            let staffTop = Self.staffTopInset

            ZStack(alignment: .topLeading) {
                ForEach(Array(glyphs.enumerated()), id: \.offset) { index, glyph in
                    Text(glyph.symbol)
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                        .position(
                            x: CGFloat(index) * advance + advance / 2,
                            y: staffTop + CGFloat(glyph.staffPositionFromTopLine) * lineSpacing / 2
                        )
                }
            }
        }
        .frame(height: Self.staffTopInset * 2 + AppTheme.Timeline.notationStaffLineSpacing * 4)
    }
}

private struct HarmonyEditorDraft: Equatable {
    var id: HarmonySymbol.ID
    var time: TimeInterval
    var measureNumber: Int
    var offsetInQuarterNotes: Double
    var text: String
    var isNew: Bool
}

private struct NotationHarmonyPlacement: Equatable {
    var measureIndex: Int
    var time: TimeInterval
    var measureNumber: Int
    var offsetInQuarterNotes: Double

    var harmonyPlacement: HarmonyPlacement {
        HarmonyPlacement(
            time: time,
            measureNumber: measureNumber,
            offsetInQuarterNotes: offsetInQuarterNotes
        )
    }
}

private struct NotationDraggedNotePitchPreview: Equatable {
    var selection: NotationItemSelection
    var pitch: NotationPitch
    var didAudition: Bool

    func matches(_ selection: NotationItemSelection) -> Bool {
        self.selection == selection
    }
}

private extension NotationTrackActions {
    static let noop = NotationTrackActions(
        selectHarmony: { _ in },
        selectMeasure: { _, _, _ in },
        selectItem: { _, _ in },
        insertNotationNote: { _ in false },
        insertNotationRest: { _ in false },
        changeSelectedNotePitch: { _, _ in false },
        changeClef: { _, _ in },
        auditionNotePitch: { _ in },
        deleteSelectedNotationNote: { false },
        locatePlaybackMarkerExactly: { _ in },
        saveHarmony: { _ in },
        deleteHarmony: { _ in },
        adjacentHarmonyPlacement: { _, _ in nil }
    )
}

#Preview {
    let settings = BeatGridSettings(bpm: 120, timeSignature: .fourFour)
    let tempoMap = TempoMap(baseSettings: settings, markers: [], duration: 120)
    let state = NotationViewportFactory().viewportState(
        tempoMap: tempoMap,
        duration: 120,
        currentTime: 40,
        playbackMarkerTime: 40,
        isPlaying: true,
        keyName: "D major",
        visibleMeasureCount: AppTheme.Timeline.notationMaximumVisibleMeasureCount
    )

    NotationTrackView(state: state)
        .frame(height: AppTheme.Timeline.notationTrackHeight)
        .padding()
}
