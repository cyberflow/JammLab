import AppKit
import SwiftUI

struct NotationTrackActions {
    var selectHarmony: (HarmonySymbol.ID?) -> Void
    var saveHarmony: (HarmonySymbol) -> Void
    var deleteHarmony: (HarmonySymbol.ID) -> Void
    var adjacentHarmonyPlacement: (TimeInterval, HarmonyNavigationDirection) -> HarmonyPlacement?
}

struct NotationTrackView: View {
    let state: NotationViewportState
    let selectedHarmonySymbolID: HarmonySymbol.ID?
    let pendingEditorRequest: HarmonyEditorRequest?
    let inputResolution: HarmonyInputResolution
    let actions: NotationTrackActions

    @Environment(\.appColors) private var appColors
    @FocusState private var isTrackFocused: Bool
    @State private var editingDraft: HarmonyEditorDraft?

    init(
        state: NotationViewportState,
        selectedHarmonySymbolID: HarmonySymbol.ID? = nil,
        pendingEditorRequest: HarmonyEditorRequest? = nil,
        inputResolution: HarmonyInputResolution = HarmonyInputResolution(),
        actions: NotationTrackActions = .noop
    ) {
        self.state = state
        self.selectedHarmonySymbolID = selectedHarmonySymbolID
        self.pendingEditorRequest = pendingEditorRequest
        self.inputResolution = inputResolution
        self.actions = actions
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
                measureNumberLabels(
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
            .simultaneousGesture(
                SpatialTapGesture(count: 2)
                    .onEnded { value in
                        beginEditingHarmony(at: value.location, width: contentWidth)
                    }
            )
            .onTapGesture {
                isTrackFocused = true
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
            .focusable()
            .focused($isTrackFocused)
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
                Path(roundedRect: rect, cornerRadius: AppTheme.Radius.small),
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
                        y: staffTop(in: height) - attributeStaffTopInset(
                            attributes: attributes,
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
                actions.selectHarmony(symbol.id)
            }
            .onTapGesture(count: 2) {
                isTrackFocused = true
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
                width: AppTheme.Timeline.notationHarmonyEditorWidth,
                height: AppTheme.ControlSize.abletonNumberFieldHeight
            )
            .offset(
                x: item.x,
                y: harmonyY
            )
        }
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

    private func attributeStaffTopInset(
        attributes: MeasureAttributes,
        display: NotationAttributeDisplay
    ) -> CGFloat {
        let hasKeySignature = display.showsKeySignature
            && !attributes.keySignature.notationAccidentalGlyphs(for: attributes.clef).isEmpty
        return hasKeySignature ? KeySignatureAccidentalsView.staffTopInset : AppTheme.Spacing.xs
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

    private func harmonyLayoutItems(
        geometries: [NotationMeasureCanvasGeometry]
    ) -> [HarmonyLayoutItem] {
        state.visibleMeasures.indices.flatMap { index -> [HarmonyLayoutItem] in
            guard geometries.indices.contains(index) else { return [] }
            return state.visibleMeasures[index].harmonies.map { symbol in
                HarmonyLayoutItem(
                    symbol: symbol,
                    x: NotationMeasureLayout.harmonyX(
                        geometry: geometries[index],
                        offsetInQuarterNotes: symbol.offsetInQuarterNotes,
                        timeSignature: state.visibleMeasures[index].attributes.timeSignature
                    )
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
            x: NotationMeasureLayout.harmonyX(
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
        let contentWidth = max(1, geometry.contentEndX - geometry.contentStartX)
        let progress = max(0, min((point.x - geometry.contentStartX) / contentWidth, 1))
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

        return "Measures \(first.number) through \(last.number), \(state.keySignature.displayName), \(state.timeSignature.displayText)"
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

    fileprivate static let staffTopInset = AppTheme.Spacing.xxl

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

struct NotationAttributeDisplay: Equatable {
    var showsClef: Bool
    var showsKeySignature: Bool
    var showsTimeSignature: Bool

    static let none = NotationAttributeDisplay(
        showsClef: false,
        showsKeySignature: false,
        showsTimeSignature: false
    )

    static let full = NotationAttributeDisplay(
        showsClef: true,
        showsKeySignature: true,
        showsTimeSignature: true
    )

    var isEmpty: Bool {
        !showsClef && !showsKeySignature && !showsTimeSignature
    }

    static func display(
        for attributes: MeasureAttributes,
        previousAttributes: MeasureAttributes?
    ) -> NotationAttributeDisplay {
        guard let previousAttributes else { return .full }

        return NotationAttributeDisplay(
            showsClef: attributes.clef != previousAttributes.clef,
            showsKeySignature: attributes.keySignature != previousAttributes.keySignature,
            showsTimeSignature: attributes.timeSignature != previousAttributes.timeSignature
        )
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

private struct HarmonyLayoutItem: Equatable {
    var symbol: HarmonySymbol
    var x: CGFloat
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

struct NotationMeasureCanvasGeometry: Equatable {
    let measureIndex: Int
    let cellStartX: CGFloat
    let cellEndX: CGFloat
    let contentStartX: CGFloat
    let contentEndX: CGFloat
    let staffStartX: CGFloat
    let staffEndX: CGFloat

    var includesRawStartBarline: Bool {
        measureIndex > 0 || !contentStartsAfterCellBoundary
    }

    var contentStartsAfterCellBoundary: Bool {
        contentStartX > cellStartX + 0.0001
    }

    var leadingBarlineX: CGFloat? {
        if measureIndex == 0 {
            return staffStartX
        }

        return includesRawStartBarline ? cellStartX : nil
    }
}

struct NotationBarlineGeometry: Equatable {
    let x: CGFloat
    let isOuterBoundary: Bool
}

struct NotationMeasureLayout {
    static var measureNumberLabelWidth: CGFloat {
        AppTheme.Timeline.notationMeasureNumberLabelWidth
    }

    static func canvasWidth(
        measureCount: Int,
        availableWidth: CGFloat,
        attributeReserveWidths: [CGFloat]
    ) -> CGFloat {
        let safeMeasureCount = max(1, measureCount)
        let bodyWidth = baseMeasureBodyWidth(
            measureCount: safeMeasureCount,
            availableWidth: availableWidth
        )
        return bodyWidth * CGFloat(safeMeasureCount) + attributeReserveWidths.reduce(0, +)
    }

    static func minimumCanvasWidth(
        measureCount: Int,
        attributeReserveWidths: [CGFloat]
    ) -> CGFloat {
        AppTheme.Timeline.notationMeasureMinWidth * CGFloat(max(1, measureCount))
            + attributeReserveWidths.reduce(0, +)
    }

    static func baseMeasureBodyWidth(measureCount: Int, availableWidth: CGFloat) -> CGFloat {
        let safeMeasureCount = max(1, measureCount)
        return max(
            AppTheme.Timeline.notationMeasureMinWidth,
            max(0, availableWidth) / CGFloat(safeMeasureCount)
        )
    }

    static func measureBodyWidth(
        measureCount: Int,
        totalWidth: CGFloat,
        attributeReserveWidths: [CGFloat]
    ) -> CGFloat {
        let safeMeasureCount = max(1, measureCount)
        let remainingWidth = max(0, totalWidth - attributeReserveWidths.reduce(0, +))
        return max(
            AppTheme.Timeline.notationMeasureMinWidth,
            remainingWidth / CGFloat(safeMeasureCount)
        )
    }

    static func canvasGeometries(
        measureCount: Int,
        totalWidth: CGFloat,
        attributeReserveWidths: [CGFloat]
    ) -> [NotationMeasureCanvasGeometry] {
        let safeMeasureCount = max(1, measureCount)
        let bodyWidth = measureBodyWidth(
            measureCount: safeMeasureCount,
            totalWidth: totalWidth,
            attributeReserveWidths: attributeReserveWidths
        )
        var cursorX: CGFloat = 0

        return (0..<safeMeasureCount).map { index in
            let cellStartX = cursorX
            let reserveWidth = attributeReserveWidths.indices.contains(index)
                ? max(0, attributeReserveWidths[index])
                : 0
            let contentStartX = cellStartX + reserveWidth
            let cellEndX = contentStartX + bodyWidth
            cursorX = cellEndX

            return canvasGeometry(
                measureIndex: index,
                measureCount: safeMeasureCount,
                cellStartX: cellStartX,
                cellEndX: cellEndX,
                contentStartX: contentStartX,
                totalWidth: totalWidth
            )
        }
    }

    static func systemMeasureNumberLabelX(geometry: NotationMeasureCanvasGeometry) -> CGFloat {
        systemMeasureNumberLabelTrailingX(geometry: geometry) - measureNumberLabelWidth
    }

    static func systemMeasureNumberLabelTrailingX(geometry: NotationMeasureCanvasGeometry) -> CGFloat {
        geometry.staffStartX + AppTheme.Spacing.sm
    }

    static var systemMeasureNumberStaffGap: CGFloat {
        AppTheme.Spacing.headerVertical
    }

    static func systemMeasureNumberLabelY(staffTop: CGFloat) -> CGFloat {
        max(AppTheme.Spacing.xs, staffTop - systemMeasureNumberStaffGap)
    }

    static func harmonyLabelY(
        staffTop: CGFloat,
        elementHeight: CGFloat = AppTheme.ControlSize.abletonNumberFieldHeight,
        gap: CGFloat = AppTheme.Spacing.xs
    ) -> CGFloat {
        max(AppTheme.Spacing.xs, staffTop - max(0, elementHeight) - max(0, gap))
    }

    static func barlineGeometries(for geometries: [NotationMeasureCanvasGeometry]) -> [NotationBarlineGeometry] {
        guard let lastGeometry = geometries.last else { return [] }

        var barlines = geometries.compactMap { geometry -> NotationBarlineGeometry? in
            guard let x = geometry.leadingBarlineX else { return nil }

            return NotationBarlineGeometry(
                x: x,
                isOuterBoundary: geometry.measureIndex == 0
            )
        }
        barlines.append(
            NotationBarlineGeometry(
                x: lastGeometry.staffEndX,
                isOuterBoundary: true
            )
        )
        return barlines
    }

    static func attributeBlockWidth(
        for attributes: MeasureAttributes,
        display: NotationAttributeDisplay,
        cellWidth: CGFloat
    ) -> CGFloat {
        let componentWidths = visibleComponentWidths(for: attributes, display: display)
        guard !componentWidths.isEmpty else { return 0 }

        return componentWidths.reduce(0, +)
            + spacingWidth(forVisibleComponentCount: componentWidths.count)
    }

    static func attributeReserveWidth(
        for attributes: MeasureAttributes,
        display: NotationAttributeDisplay
    ) -> CGFloat {
        let blockWidth = attributeBlockWidth(
            for: attributes,
            display: display,
            cellWidth: AppTheme.Timeline.notationMeasureMinWidth
        )
        guard blockWidth > 0 else { return 0 }
        return AppTheme.Spacing.md + blockWidth + AppTheme.Spacing.xs
    }

    static func keySignatureWidth(for attributes: MeasureAttributes) -> CGFloat {
        let glyphs = attributes.keySignature.notationAccidentalGlyphs(for: attributes.clef)
        return glyphs.isEmpty
            ? 0
            : max(12, CGFloat(glyphs.count) * AppTheme.Timeline.notationAccidentalWidth)
    }

    static func visibleComponentCount(
        for attributes: MeasureAttributes,
        display: NotationAttributeDisplay
    ) -> Int {
        visibleComponentWidths(for: attributes, display: display).count
    }

    static func spacingWidth(forVisibleComponentCount componentCount: Int) -> CGFloat {
        AppTheme.Spacing.xs * CGFloat(max(0, componentCount - 1))
    }

    static func contentStartX(
        measureIndex: Int,
        cellWidth: CGFloat,
        attributes: MeasureAttributes,
        display: NotationAttributeDisplay
    ) -> CGFloat {
        let cellStartX = CGFloat(measureIndex) * cellWidth
        return cellStartX + attributeReserveWidth(for: attributes, display: display)
    }

    static func contentWidth(
        measureIndex: Int,
        cellWidth: CGFloat,
        attributes: MeasureAttributes,
        display: NotationAttributeDisplay
    ) -> CGFloat {
        max(AppTheme.Timeline.notationMinimumMeasureContentWidth, cellWidth)
    }

    static func playheadX(
        measureIndex: Int,
        cellWidth: CGFloat,
        progress: CGFloat,
        attributes: MeasureAttributes,
        display: NotationAttributeDisplay
    ) -> CGFloat {
        let clampedProgress = max(0, min(progress, 1))
        let startX = contentStartX(
            measureIndex: measureIndex,
            cellWidth: cellWidth,
            attributes: attributes,
            display: display
        )
        let width = contentWidth(
            measureIndex: measureIndex,
            cellWidth: cellWidth,
            attributes: attributes,
            display: display
        )
        return startX + clampedProgress * width
    }

    static func playheadX(
        geometry: NotationMeasureCanvasGeometry,
        progress: CGFloat
    ) -> CGFloat {
        let clampedProgress = max(0, min(progress, 1))
        let width = max(0, geometry.contentEndX - geometry.contentStartX)
        return geometry.contentStartX + clampedProgress * width
    }

    static func playheadIndicatorX(
        geometry: NotationMeasureCanvasGeometry,
        progress: CGFloat,
        indicatorWidth: CGFloat
    ) -> CGFloat {
        let rawX = playheadX(geometry: geometry, progress: progress)
        let visualStartX = min(geometry.staffStartX, geometry.staffEndX)
        let visualEndX = max(geometry.staffStartX, geometry.staffEndX)
        let safeIndicatorWidth = max(0, indicatorWidth)
        let maximumX = max(visualStartX, visualEndX - safeIndicatorWidth)
        return min(max(rawX, visualStartX), maximumX)
    }

    static func harmonyX(
        geometry: NotationMeasureCanvasGeometry,
        offsetInQuarterNotes: Double,
        timeSignature: TimeSignature
    ) -> CGFloat {
        let quarterLength = quarterLength(for: timeSignature)
        guard quarterLength > 0 else { return geometry.contentStartX }
        let progress = max(0, min(offsetInQuarterNotes / quarterLength, 1))
        let width = max(0, geometry.contentEndX - geometry.contentStartX)
        return geometry.contentStartX + CGFloat(progress) * width
    }

    static func snappedHarmonyOffset(
        _ offset: Double,
        timeSignature: TimeSignature,
        resolution: HarmonyInputResolution
    ) -> Double {
        let step = resolution.stepInQuarterNotes
        guard step > 0 else { return 0 }
        let maximumOffset = maximumHarmonyOffset(timeSignature: timeSignature, resolution: resolution)
        let snapped = (offset / step).rounded() * step
        return max(0, min(snapped, maximumOffset))
    }

    static func time(forHarmonyOffset offset: Double, in measure: ScoreMeasure) -> TimeInterval {
        let quarterLength = quarterLength(for: measure.attributes.timeSignature)
        guard measure.duration > 0, quarterLength > 0 else { return measure.startTime }
        let progress = max(0, min(offset / quarterLength, 1))
        return measure.startTime + progress * measure.duration
    }

    static func quarterLength(for timeSignature: TimeSignature) -> Double {
        Double(timeSignature.beatsPerBar) * 4.0 / Double(max(1, timeSignature.beatUnit))
    }

    static func canvasGeometry(
        measureIndex: Int,
        measureCount: Int,
        cellWidth: CGFloat,
        attributes: MeasureAttributes,
        display: NotationAttributeDisplay,
        totalWidth: CGFloat
    ) -> NotationMeasureCanvasGeometry {
        let cellStartX = CGFloat(measureIndex) * cellWidth
        let contentStartX = cellStartX + attributeReserveWidth(
            for: attributes,
            display: display
        )

        return canvasGeometry(
            measureIndex: measureIndex,
            measureCount: measureCount,
            cellStartX: cellStartX,
            cellEndX: contentStartX + max(0, cellWidth),
            contentStartX: contentStartX,
            totalWidth: totalWidth
        )
    }

    static func canvasGeometry(
        measureIndex: Int,
        measureCount: Int,
        cellWidth: CGFloat,
        contentStartX: CGFloat,
        totalWidth: CGFloat
    ) -> NotationMeasureCanvasGeometry {
        let cellStartX = CGFloat(measureIndex) * cellWidth
        return canvasGeometry(
            measureIndex: measureIndex,
            measureCount: measureCount,
            cellStartX: cellStartX,
            cellEndX: max(cellStartX + cellWidth, contentStartX + cellWidth),
            contentStartX: contentStartX,
            totalWidth: totalWidth
        )
    }

    static func canvasGeometry(
        measureIndex: Int,
        measureCount: Int,
        cellStartX: CGFloat,
        cellEndX: CGFloat,
        contentStartX: CGFloat,
        totalWidth: CGFloat
    ) -> NotationMeasureCanvasGeometry {
        let safeCellStartX = max(0, cellStartX)
        let safeCellEndX = max(safeCellStartX, cellEndX)
        let clampedContentStartX = min(max(safeCellStartX, contentStartX), safeCellEndX)
        let lastMeasureIndex = max(0, measureCount - 1)
        var staffStartX = safeCellStartX
        var staffEndX = safeCellEndX

        if measureIndex == 0 {
            staffStartX = max(
                safeCellStartX,
                min(safeCellEndX, safeCellStartX + AppTheme.Timeline.notationStaffHorizontalInset)
            )
        }

        if measureIndex == lastMeasureIndex {
            staffEndX = max(
                staffStartX,
                safeCellEndX - AppTheme.Timeline.notationStaffHorizontalInset
            )
        }

        return NotationMeasureCanvasGeometry(
            measureIndex: measureIndex,
            cellStartX: safeCellStartX,
            cellEndX: safeCellEndX,
            contentStartX: clampedContentStartX,
            contentEndX: safeCellEndX,
            staffStartX: staffStartX,
            staffEndX: max(staffStartX, staffEndX)
        )
    }

    static func fallbackCanvasGeometries(
        measureCount: Int,
        totalWidth: CGFloat
    ) -> [NotationMeasureCanvasGeometry] {
        let safeMeasureCount = max(1, measureCount)
        let cellWidth = totalWidth / CGFloat(safeMeasureCount)

        return (0..<safeMeasureCount).map { index in
            canvasGeometry(
                measureIndex: index,
                measureCount: safeMeasureCount,
                cellWidth: cellWidth,
                contentStartX: CGFloat(index) * cellWidth,
                totalWidth: totalWidth
            )
        }
    }

    static func measureIndex(
        atX x: CGFloat,
        in geometries: [NotationMeasureCanvasGeometry]
    ) -> Int? {
        guard !geometries.isEmpty else { return nil }
        let clampedX = max(0, x)

        if let index = geometries.firstIndex(where: { geometry in
            let isLastGeometry = geometry.measureIndex == geometries.last?.measureIndex
            return clampedX >= geometry.cellStartX
                && (clampedX < geometry.cellEndX || (isLastGeometry && clampedX <= geometry.cellEndX))
        }) {
            return index
        }

        return clampedX < geometries[0].cellStartX ? 0 : geometries.indices.last
    }

    private static func visibleComponentWidths(
        for attributes: MeasureAttributes,
        display: NotationAttributeDisplay
    ) -> [CGFloat] {
        var widths: [CGFloat] = []

        if display.showsClef {
            widths.append(AppTheme.Timeline.notationClefWidth)
        }

        let keyWidth = keySignatureWidth(for: attributes)
        if display.showsKeySignature, keyWidth > 0 {
            widths.append(keyWidth)
        }

        if display.showsTimeSignature {
            widths.append(AppTheme.Timeline.notationTimeSignatureWidth)
        }

        return widths
    }

    private static func maximumHarmonyOffset(
        timeSignature: TimeSignature,
        resolution: HarmonyInputResolution
    ) -> Double {
        let length = quarterLength(for: timeSignature)
        let step = resolution.stepInQuarterNotes
        guard length > 0, step > 0 else { return 0 }
        let slots = max(0, Int(floor((length - 0.000_001) / step)))
        return Double(slots) * step
    }
}

private struct HarmonyInlineTextField: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void
    let onNavigate: (HarmonyNavigationDirection) -> Void

    func makeNSView(context: Context) -> HarmonyInlineNSTextField {
        let textField = HarmonyInlineNSTextField(string: text)
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .default
        textField.delegate = context.coordinator
        textField.font = .systemFont(ofSize: 13, weight: .semibold)
        textField.onWindowAttached = { [weak coordinator = context.coordinator, weak textField] in
            guard let textField else { return }
            coordinator?.focusAndSelectIfNeeded(textField)
        }
        return textField
    }

    func updateNSView(_ nsView: HarmonyInlineNSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.focusAndSelectIfNeeded(nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: HarmonyInlineTextField
        private var didAutoSelect = false

        init(parent: HarmonyInlineTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func focusAndSelectIfNeeded(_ textField: NSTextField) {
            guard !didAutoSelect else { return }

            DispatchQueue.main.async { [weak self, weak textField] in
                guard let self, let textField, !self.didAutoSelect else { return }
                guard let window = textField.window else { return }

                window.makeFirstResponder(textField)
                textField.selectText(nil)
                self.didAutoSelect = true
            }
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.text = textView.string
                parent.onCommit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.insertTab(_:)):
                parent.text = textView.string
                parent.onNavigate(.next)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                parent.text = textView.string
                parent.onNavigate(.previous)
                return true
            default:
                return false
            }
        }
    }
}

private final class HarmonyInlineNSTextField: NSTextField {
    var onWindowAttached: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            onWindowAttached?()
        }
    }
}

private extension NotationTrackActions {
    static let noop = NotationTrackActions(
        selectHarmony: { _ in },
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
