import SwiftUI

struct NotationTrackView: View {
    let state: NotationViewportState

    @Environment(\.appColors) private var appColors

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(
                proxy.size.width,
                CGFloat(renderedMeasureCount) * AppTheme.Timeline.notationMeasureMinWidth
            )
            let attributeDisplays = visibleAttributeDisplays

            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    notationCanvas(
                        measureCount: renderedMeasureCount,
                        attributeDisplays: attributeDisplays
                    )
                    measureNumberLabels(width: contentWidth)
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
                }
                .frame(width: contentWidth, height: proxy.size.height)
                .id(scrollResetIdentity)
            }
            .scrollIndicators(.visible)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
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
        let cellWidth = width / CGFloat(safeMeasureCount)

        guard !state.visibleMeasures.isEmpty else {
            return NotationMeasureLayout.fallbackCanvasGeometries(
                measureCount: safeMeasureCount,
                totalWidth: width
            )
        }

        return (0..<safeMeasureCount).map { index in
            guard state.visibleMeasures.indices.contains(index) else {
                return NotationMeasureLayout.canvasGeometry(
                    measureIndex: index,
                    measureCount: safeMeasureCount,
                    cellWidth: cellWidth,
                    contentStartX: CGFloat(index) * cellWidth,
                    totalWidth: width
                )
            }

            return NotationMeasureLayout.canvasGeometry(
                measureIndex: index,
                measureCount: safeMeasureCount,
                cellWidth: cellWidth,
                attributes: state.visibleMeasures[index].attributes,
                display: attributeDisplay(at: index, in: attributeDisplays),
                totalWidth: width
            )
        }
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

    private func measureNumberLabels(width: CGFloat) -> some View {
        let cellWidth = width / CGFloat(renderedMeasureCount)

        return ZStack(alignment: .topLeading) {
            ForEach(state.visibleMeasures.indices, id: \.self) { index in
                Text("\(state.visibleMeasures[index].number)")
                    .font(AppTheme.Typography.timelineLabel.weight(.medium))
                    .foregroundStyle(appColors.secondaryText)
                    .lineLimit(1)
                    .frame(width: cellWidth - AppTheme.Spacing.md * 2, alignment: .leading)
                    .offset(
                        x: CGFloat(index) * cellWidth + AppTheme.Spacing.md,
                        y: AppTheme.Spacing.xs
                    )
                    .accessibilityLabel("Measure \(state.visibleMeasures[index].number)")
            }
        }
    }

    private func attributeLabels(
        width: CGFloat,
        height: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> some View {
        let cellWidth = width / CGFloat(renderedMeasureCount)

        return ZStack(alignment: .topLeading) {
            ForEach(state.visibleMeasures.indices, id: \.self) { index in
                let display = attributeDisplay(at: index, in: attributeDisplays)
                if !display.isEmpty {
                    let attributes = state.visibleMeasures[index].attributes
                    let attributeBlockWidth = NotationMeasureLayout.attributeBlockWidth(
                        for: attributes,
                        display: display,
                        cellWidth: cellWidth
                    )

                    measureAttributes(
                        attributes,
                        display: display,
                        blockWidth: attributeBlockWidth
                    )
                    .offset(
                        x: CGFloat(index) * cellWidth + AppTheme.Spacing.md,
                        y: staffTop(in: height) - AppTheme.Spacing.xs
                    )
                }
            }
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

        return HStack(alignment: .center, spacing: AppTheme.Spacing.xs) {
            if display.showsClef {
                Text(attributes.clef.displaySymbol)
                    .font(.system(size: 42))
                    .foregroundStyle(appColors.notationSymbolsAndLines)
                    .frame(width: AppTheme.Timeline.notationClefWidth, alignment: .center)
                    .accessibilityLabel("Treble clef")
            }

            if display.showsKeySignature && !attributes.keySignature.notationAccidentals.isEmpty {
                Text(attributes.keySignature.notationAccidentals)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(appColors.notationSymbolsAndLines)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(
                        width: min(
                            NotationMeasureLayout.keySignatureWidth(for: attributes),
                            availableAccidentalWidth
                        ),
                        alignment: .leading
                    )
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

    @ViewBuilder
    private func playheadIndicator(
        width: CGFloat,
        height: CGFloat,
        attributeDisplays: [NotationAttributeDisplay]
    ) -> some View {
        if let activeMeasureIndex {
            let measure = state.visibleMeasures[activeMeasureIndex]
            let progress = measure.duration > 0
                ? max(0, min((state.anchorTime - measure.startTime) / measure.duration, 1))
                : 0
            let cellWidth = width / CGFloat(renderedMeasureCount)
            let x = NotationMeasureLayout.playheadX(
                measureIndex: activeMeasureIndex,
                cellWidth: cellWidth,
                progress: CGFloat(progress),
                attributes: measure.attributes,
                display: attributeDisplay(at: activeMeasureIndex, in: attributeDisplays)
            )
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
}

struct NotationBarlineGeometry: Equatable {
    let x: CGFloat
    let isOuterBoundary: Bool
}

struct NotationMeasureLayout {
    static func barlineGeometries(for geometries: [NotationMeasureCanvasGeometry]) -> [NotationBarlineGeometry] {
        guard let lastGeometry = geometries.last else { return [] }

        var barlines = geometries.compactMap { geometry -> NotationBarlineGeometry? in
            guard geometry.includesRawStartBarline else { return nil }

            return NotationBarlineGeometry(
                x: geometry.cellStartX,
                isOuterBoundary: geometry.measureIndex == 0
            )
        }
        barlines.append(
            NotationBarlineGeometry(
                x: lastGeometry.cellEndX,
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

        let desiredWidth = componentWidths.reduce(0, +)
            + spacingWidth(forVisibleComponentCount: componentWidths.count)
        let maximumWidth = max(
            0,
            cellWidth - AppTheme.Timeline.notationMinimumMeasureContentWidth - AppTheme.Spacing.md
        )

        return min(desiredWidth, maximumWidth)
    }

    static func keySignatureWidth(for attributes: MeasureAttributes) -> CGFloat {
        attributes.keySignature.notationAccidentals.isEmpty
            ? 0
            : max(12, CGFloat(attributes.keySignature.accidentalCount) * AppTheme.Timeline.notationAccidentalWidth)
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
        guard !display.isEmpty else { return cellStartX }

        let attributeWidth = attributeBlockWidth(
            for: attributes,
            display: display,
            cellWidth: cellWidth
        )
        guard attributeWidth > 0 else { return cellStartX }

        let desiredStartX = cellStartX + AppTheme.Spacing.md + attributeWidth + AppTheme.Spacing.xs
        let maximumStartX = cellStartX + max(0, cellWidth - AppTheme.Timeline.notationMinimumMeasureContentWidth)
        return min(desiredStartX, maximumStartX)
    }

    static func contentWidth(
        measureIndex: Int,
        cellWidth: CGFloat,
        attributes: MeasureAttributes,
        display: NotationAttributeDisplay
    ) -> CGFloat {
        let cellEndX = CGFloat(measureIndex + 1) * cellWidth
        let startX = contentStartX(
            measureIndex: measureIndex,
            cellWidth: cellWidth,
            attributes: attributes,
            display: display
        )
        return max(AppTheme.Timeline.notationMinimumMeasureContentWidth, cellEndX - startX)
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

    static func canvasGeometry(
        measureIndex: Int,
        measureCount: Int,
        cellWidth: CGFloat,
        attributes: MeasureAttributes,
        display: NotationAttributeDisplay,
        totalWidth: CGFloat
    ) -> NotationMeasureCanvasGeometry {
        canvasGeometry(
            measureIndex: measureIndex,
            measureCount: measureCount,
            cellWidth: cellWidth,
            contentStartX: contentStartX(
                measureIndex: measureIndex,
                cellWidth: cellWidth,
                attributes: attributes,
                display: display
            ),
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
        let safeMeasureCount = max(1, measureCount)
        let cellStartX = CGFloat(measureIndex) * cellWidth
        let cellEndX = CGFloat(measureIndex + 1) * cellWidth
        let clampedContentStartX = min(max(cellStartX, contentStartX), cellEndX)
        var staffStartX = cellStartX
        var staffEndX = cellEndX

        if measureIndex == 0 {
            staffStartX = max(staffStartX, min(cellEndX, AppTheme.Timeline.notationStaffHorizontalInset))
        }

        if measureIndex == safeMeasureCount - 1 {
            staffEndX = min(
                staffEndX,
                max(staffStartX, totalWidth - AppTheme.Timeline.notationStaffHorizontalInset)
            )
        }

        return NotationMeasureCanvasGeometry(
            measureIndex: measureIndex,
            cellStartX: cellStartX,
            cellEndX: cellEndX,
            contentStartX: clampedContentStartX,
            contentEndX: cellEndX,
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
        visibleMeasureCount: AppTheme.Timeline.notationVisibleMeasureCount
    )

    NotationTrackView(state: state)
        .frame(height: AppTheme.Timeline.notationTrackHeight)
        .padding()
}
