import AppKit
import SwiftUI

struct NotationTrackActions {
    var selectHarmony: (HarmonySymbol.ID?) -> Void
    var selectMeasure: (ScoreMeasure?, Bool) -> Void
    var selectBeat: (NotationBeatSelection?) -> Void
    var saveHarmony: (HarmonySymbol) -> Void
    var deleteHarmony: (HarmonySymbol.ID) -> Void
    var adjacentHarmonyPlacement: (TimeInterval, HarmonyNavigationDirection) -> HarmonyPlacement?
}

struct NotationTrackView: View {
    let state: NotationViewportState
    let selectedHarmonySymbolID: HarmonySymbol.ID?
    let selectedMeasures: [NotationMeasureSelection]
    let selectedBeat: NotationBeatSelection?
    let pendingEditorRequest: HarmonyEditorRequest?
    let inputResolution: HarmonyInputResolution
    let actions: NotationTrackActions
    let cornerRadius: CGFloat

    @Environment(\.appColors) private var appColors
    @FocusState private var isTrackFocused: Bool
    @State private var editingDraft: HarmonyEditorDraft?

    init(
        state: NotationViewportState,
        selectedHarmonySymbolID: HarmonySymbol.ID? = nil,
        selectedMeasures: [NotationMeasureSelection] = [],
        selectedBeat: NotationBeatSelection? = nil,
        pendingEditorRequest: HarmonyEditorRequest? = nil,
        inputResolution: HarmonyInputResolution = HarmonyInputResolution(),
        actions: NotationTrackActions = .noop,
        cornerRadius: CGFloat = AppTheme.Radius.small
    ) {
        self.state = state
        self.selectedHarmonySymbolID = selectedHarmonySymbolID
        self.selectedMeasures = selectedMeasures
        self.selectedBeat = selectedBeat
        self.pendingEditorRequest = pendingEditorRequest
        self.inputResolution = inputResolution
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
                beatSelectionHitLayer(
                    width: contentWidth,
                    height: proxy.size.height,
                    attributeDisplays: attributeDisplays
                )
                measureNumberLabels(
                    width: contentWidth,
                    height: proxy.size.height,
                    attributeDisplays: attributeDisplays
                )
                regionLabelsLayer(
                    width: contentWidth,
                    height: proxy.size.height,
                    attributeDisplays: attributeDisplays
                )
                harmonySymbolsLayer(
                    width: contentWidth,
                    height: proxy.size.height,
                    attributeDisplays: attributeDisplays
                )
                attributeLabels(
                    width: contentWidth,
                    height: proxy.size.height,
                    attributeDisplays: attributeDisplays
                )
                playheadIndicator(
                    width: contentWidth,
                    height: proxy.size.height,
                    attributeDisplays: attributeDisplays
                )
                harmonyEditorLayer(
                    width: contentWidth,
                    height: proxy.size.height,
                    attributeDisplays: attributeDisplays
                )
            }
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
                deleteSelectedHarmony()
            }
            .onChange(of: pendingEditorRequest?.id) { _, _ in
                handlePendingEditorRequest()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Notation Track")
            .accessibilityValue(accessibilityValue)
        }
    }

    private var renderedMeasureCount: Int {
        max(1, state.visibleMeasures.isEmpty ? state.visibleMeasureCount : state.visibleMeasures.count)
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
            drawSlashNotation(
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

    private func drawSlashNotation(
        geometries: [NotationMeasureCanvasGeometry],
        staffTop: CGFloat,
        in context: inout GraphicsContext
    ) {
        let centerY = staffTop + AppTheme.Timeline.notationStaffLineSpacing * 2
        let slashWidth = AppTheme.Timeline.notationSlashWidth
        let slashHeight = AppTheme.Timeline.notationSlashHeight
        let style = StrokeStyle(
            lineWidth: AppTheme.Timeline.notationSlashLineWidth,
            lineCap: .round,
            lineJoin: .round
        )

        for item in beatLayoutItems(geometries: geometries) {
            let color = selectedBeat?.matches(
                item.measure,
                offsetInQuarterNotes: item.selection.offsetInQuarterNotes
            ) == true
                ? appColors.accent
                : appColors.notationSymbolsAndLines
            var path = Path()
            path.move(to: CGPoint(
                x: item.x - slashWidth / 2,
                y: centerY + slashHeight / 2
            ))
            path.addLine(to: CGPoint(
                x: item.x + slashWidth / 2,
                y: centerY - slashHeight / 2
            ))
            context.stroke(
                path,
                with: .color(color),
                style: style
            )
        }
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
        let selectedMeasureIndices = state.visibleMeasures.indices.filter { index in
            selectedMeasures.contains(where: { $0.matches(state.visibleMeasures[index]) })
        }
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
                            actions.selectMeasure(state.visibleMeasures[index], isShiftClickActive)
                        }
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func beatSelectionHitLayer(
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
        let hitY = max(0, staffTop - AppTheme.Spacing.sm)
        let hitHeight = AppTheme.Timeline.notationStaffLineSpacing * 4 + AppTheme.Spacing.md
        let hitWidth = max(
            AppTheme.ControlSize.abletonNumberFieldHeight,
            AppTheme.Timeline.notationSlashWidth + AppTheme.Spacing.lg
        )

        return ZStack(alignment: .topLeading) {
            ForEach(beatLayoutItems(geometries: geometries), id: \.id) { item in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: hitWidth, height: hitHeight)
                    .offset(
                        x: item.x - hitWidth / 2,
                        y: hitY
                    )
                    .onTapGesture {
                        isTrackFocused = true
                        editingDraft = nil
                        actions.selectBeat(item.selection)
                    }
                    .accessibilityLabel("Beat \(item.beatNumber) in measure \(item.selection.measureNumber)")
                    .accessibilityValue(
                        selectedBeat?.matches(
                            item.measure,
                            offsetInQuarterNotes: item.selection.offsetInQuarterNotes
                        ) == true ? "Selected" : ""
                    )
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
                actions.selectBeat(beatSelection(for: symbol))
                if !isShiftClickActive {
                    actions.selectHarmony(symbol.id)
                }
            }
            .onTapGesture(count: 2) {
                isTrackFocused = true
                actions.selectBeat(beatSelection(for: symbol))
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
        let fixedComponentWidth = (display.showsClef ? AppTheme.Timeline.notationClefWidth : 0)
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
                Text(attributes.clef.displaySymbol)
                    .font(.system(size: AppTheme.Timeline.notationClefFontSize))
                    .foregroundStyle(appColors.notationSymbolsAndLines)
                    .frame(width: AppTheme.Timeline.notationClefWidth, alignment: .center)
                    .offset(y: clefVerticalOffset(for: attributes.clef))
                    .accessibilityLabel("Treble clef")
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
            }
        }
        .frame(width: max(0, blockWidth), alignment: .leading)
        .clipped()
    }

    private func clefVerticalOffset(for clef: Clef) -> CGFloat {
        switch clef {
        case .treble:
            return AppTheme.Timeline.notationTrebleClefVerticalOffset
        }
    }

    @ViewBuilder
    private func playheadIndicator(
        width: CGFloat,
        height: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> some View {
        if let activeMeasureIndex {
            let geometries = measureCanvasGeometries(
                measureCount: renderedMeasureCount,
                width: width,
                attributeDisplays: attributeDisplays
            )
            let measure = state.visibleMeasures[activeMeasureIndex]
            let progress = measure.duration > 0
                ? max(0, min((state.anchorTime - measure.startTime) / measure.duration, 1))
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

    private var activeMeasureIndex: Int? {
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
        let candidates = state.visibleMeasures.indices.flatMap { index -> [RegionLabelLayoutCandidate] in
            guard geometries.indices.contains(index) else { return [] }
            let measure = state.visibleMeasures[index]
            return measure.regionLabels.map { label in
                let avoidsMeasureNumber = index == 0
                let bounds = NotationMeasureLayout.regionLabelXBounds(
                    geometry: geometries[index],
                    labelWidth: AppTheme.Timeline.notationRegionLabelMaxWidth,
                    avoidsSystemMeasureNumber: avoidsMeasureNumber
                )
                let x = NotationMeasureLayout.regionLabelX(
                    geometry: geometries[index],
                    offsetInQuarterNotes: label.offsetInQuarterNotes,
                    timeSignature: measure.attributes.timeSignature,
                    bounds: bounds
                )
                return RegionLabelLayoutCandidate(
                    label: label,
                    x: x,
                    upperBound: bounds.upperBound
                )
            }
        }
        .sorted {
            if abs($0.x - $1.x) > 0.0001 {
                return $0.x < $1.x
            }

            return $0.label.id.uuidString < $1.label.id.uuidString
        }

        var previousEnd: CGFloat?
        return candidates.map { candidate in
            let minimumX = previousEnd.map {
                $0 + AppTheme.Timeline.notationRegionLabelGap
            } ?? candidate.x
            let adjustedX = min(max(candidate.x, minimumX), candidate.upperBound)
            previousEnd = adjustedX + AppTheme.Timeline.notationRegionLabelMaxWidth
            return RegionLabelLayoutItem(label: candidate.label, x: adjustedX)
        }
    }

    private func harmonyLayoutItems(
        geometries: [NotationMeasureCanvasGeometry]
    ) -> [HarmonyLayoutItem] {
        state.visibleMeasures.indices.flatMap { index -> [HarmonyLayoutItem] in
            guard geometries.indices.contains(index) else { return [] }
            return state.visibleMeasures[index].harmonies.map { symbol in
                HarmonyLayoutItem(
                    symbol: symbol,
                    x: NotationMeasureLayout.harmonyLabelX(
                        geometry: geometries[index],
                        offsetInQuarterNotes: symbol.offsetInQuarterNotes,
                        timeSignature: state.visibleMeasures[index].attributes.timeSignature
                    )
                )
            }
        }
    }

    private func beatLayoutItems(
        geometries: [NotationMeasureCanvasGeometry]
    ) -> [BeatLayoutItem] {
        state.visibleMeasures.indices.flatMap { index -> [BeatLayoutItem] in
            guard geometries.indices.contains(index) else { return [] }
            let measure = state.visibleMeasures[index]
            let centers = NotationMeasureLayout.slashBeatCenters(
                geometry: geometries[index],
                timeSignature: measure.attributes.timeSignature
            )
            let beatLength = 4.0 / Double(max(1, measure.attributes.timeSignature.beatUnit))

            return centers.enumerated().map { beatIndex, x in
                let offset = Double(beatIndex) * beatLength
                return BeatLayoutItem(
                    measure: measure,
                    selection: NotationBeatSelection(
                        measure: measure,
                        offsetInQuarterNotes: offset
                    ),
                    beatNumber: beatIndex + 1,
                    x: x
                )
            }
        }
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

    private func beatSelection(for symbol: HarmonySymbol) -> NotationBeatSelection? {
        guard let measure = measure(containing: symbol) else { return nil }

        return NotationBeatSelection(
            measure: measure,
            offsetInQuarterNotes: symbol.offsetInQuarterNotes
        )
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
        let quarterLength = NotationMeasureLayout.quarterLength(for: measure.attributes.timeSignature)
        let progress = measure.duration > 0
            ? max(0, min((time - measure.startTime) / measure.duration, 1))
            : 0
        let snappedOffset = NotationMeasureLayout.snappedHarmonyOffset(
            progress * quarterLength,
            timeSignature: measure.attributes.timeSignature,
            resolution: inputResolution
        )
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
        let snappedOffset = NotationMeasureLayout.snappedHarmonyOffset(
            rawOffset,
            timeSignature: measure.attributes.timeSignature,
            resolution: inputResolution
        )
        let resolvedTime = NotationMeasureLayout.time(forHarmonyOffset: snappedOffset, in: measure)

        return NotationHarmonyPlacement(
            measureIndex: measureIndex,
            time: resolvedTime,
            measureNumber: measure.number,
            offsetInQuarterNotes: snappedOffset
        )
    }

    private var accessibilityValue: String {
        guard let first = state.visibleMeasures.first, let last = state.visibleMeasures.last else {
            return "Pending tempo"
        }

        let selectedMeasureText: String
        if selectedMeasures.isEmpty {
            selectedMeasureText = ""
        } else if selectedMeasures.count == 1, let selectedMeasure = selectedMeasures.first {
            selectedMeasureText = ", selected measure \(selectedMeasure.number)"
        } else if let firstSelectedMeasure = selectedMeasures.first,
                  let lastSelectedMeasure = selectedMeasures.last {
            selectedMeasureText = ", selected measures \(firstSelectedMeasure.number) through \(lastSelectedMeasure.number)"
        } else {
            selectedMeasureText = ""
        }
        return "Measures \(first.number) through \(last.number), \(state.keySignature.displayName), \(state.timeSignature.displayText)\(selectedMeasureText)"
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

private struct RegionLabelLayoutCandidate: Equatable {
    var label: NotationRegionLabel
    var x: CGFloat
    var upperBound: CGFloat
}

private struct RegionLabelLayoutItem: Equatable {
    var label: NotationRegionLabel
    var x: CGFloat
}

private struct HarmonyLayoutItem: Equatable {
    var symbol: HarmonySymbol
    var x: CGFloat
}

private struct BeatLayoutItem: Equatable, Identifiable {
    var measure: ScoreMeasure
    var selection: NotationBeatSelection
    var beatNumber: Int
    var x: CGFloat

    var id: String {
        selection.id
    }
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

private extension NotationTrackActions {
    static let noop = NotationTrackActions(
        selectHarmony: { _ in },
        selectMeasure: { _, _ in },
        selectBeat: { _ in },
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
