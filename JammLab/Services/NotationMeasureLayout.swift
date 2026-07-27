import CoreGraphics
import Foundation

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
    let rhythmicStartX: CGFloat
    let rhythmicEndX: CGFloat
    let rhythmicSpacingMap: NotationRhythmicSpacingMap?

    init(
        measureIndex: Int,
        cellStartX: CGFloat,
        cellEndX: CGFloat,
        contentStartX: CGFloat,
        contentEndX: CGFloat,
        staffStartX: CGFloat,
        staffEndX: CGFloat,
        leadingAnchorInset: CGFloat = AppTheme.Timeline.notationItemAnchorInset,
        trailingAnchorInset: CGFloat = AppTheme.Timeline.notationItemAnchorInset,
        rhythmicSpacingMap: NotationRhythmicSpacingMap? = nil
    ) {
        self.measureIndex = measureIndex
        self.cellStartX = cellStartX
        self.cellEndX = cellEndX
        self.contentStartX = contentStartX
        self.contentEndX = contentEndX
        self.staffStartX = staffStartX
        self.staffEndX = staffEndX
        self.rhythmicSpacingMap = rhythmicSpacingMap

        let visualStartX = max(contentStartX, staffStartX)
        let visualEndX = max(visualStartX, min(contentEndX, staffEndX))
        let proposedStartX = visualStartX + max(0, leadingAnchorInset)
        let proposedEndX = visualEndX - max(0, trailingAnchorInset)
        if proposedStartX <= proposedEndX {
            rhythmicStartX = proposedStartX
            rhythmicEndX = proposedEndX
        } else {
            let midpoint = (visualStartX + visualEndX) / 2
            rhythmicStartX = midpoint
            rhythmicEndX = midpoint
        }
    }

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

struct NotationBarlineHitTarget: Equatable, Identifiable {
    enum Boundary: Equatable {
        case leading
        case trailing
    }

    let measureIndex: Int
    let boundary: Boundary
    let x: CGFloat
    let targetTime: TimeInterval

    var id: String {
        "\(measureIndex)-\(boundary)"
    }
}

struct NotationSelectionOverlayRun: Equatable, Identifiable {
    let startMeasureIndex: Int
    let endMeasureIndex: Int
    let x: CGFloat
    let width: CGFloat

    var id: String {
        "\(startMeasureIndex)-\(endMeasureIndex)"
    }
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

    static func canvasGeometries(
        totalWidth: CGFloat,
        bodyWidths: [CGFloat],
        attributeReserveWidths: [CGFloat],
        leadingAnchorInsets: [CGFloat],
        trailingAnchorInsets: [CGFloat],
        rhythmicSpacingMaps: [NotationRhythmicSpacingMap?]
    ) -> [NotationMeasureCanvasGeometry] {
        let measureCount = bodyWidths.count
        guard measureCount > 0 else { return [] }

        var cursorX: CGFloat = 0
        return bodyWidths.indices.map { index in
            let cellStartX = cursorX
            let reserveWidth = attributeReserveWidths.indices.contains(index)
                ? max(0, attributeReserveWidths[index])
                : 0
            let bodyWidth = max(0, bodyWidths[index])
            let contentStartX = cellStartX + reserveWidth
            let cellEndX = contentStartX + bodyWidth
            cursorX = cellEndX

            return canvasGeometry(
                measureIndex: index,
                measureCount: measureCount,
                cellStartX: cellStartX,
                cellEndX: cellEndX,
                contentStartX: contentStartX,
                totalWidth: totalWidth,
                leadingAnchorInset: leadingAnchorInsets.indices.contains(index)
                    ? leadingAnchorInsets[index]
                    : AppTheme.Timeline.notationItemAnchorInset,
                trailingAnchorInset: trailingAnchorInsets.indices.contains(index)
                    ? trailingAnchorInsets[index]
                    : AppTheme.Timeline.notationItemAnchorInset,
                rhythmicSpacingMap: rhythmicSpacingMaps.indices.contains(index)
                    ? rhythmicSpacingMaps[index]
                    : nil
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

    static func wholeRestVisualCenterY(
        staffTop: CGFloat,
        lineSpacing: CGFloat = AppTheme.Timeline.notationStaffLineSpacing
    ) -> CGFloat {
        staffTop + lineSpacing * 1.5
    }

    static func regionLabelY(
        staffTop: CGFloat,
        labelHeight: CGFloat = AppTheme.Timeline.notationRegionLabelHeight,
        gap: CGFloat = AppTheme.Timeline.notationRegionLabelGap
    ) -> CGFloat {
        let harmonyY = harmonyLabelY(staffTop: staffTop)
        return max(AppTheme.Spacing.xxxs, harmonyY - max(0, labelHeight) - max(0, gap))
    }

    static func regionLabelX(
        geometry: NotationMeasureCanvasGeometry,
        offsetInQuarterNotes: Double,
        timeSignature: TimeSignature,
        labelWidth: CGFloat = AppTheme.Timeline.notationRegionLabelMaxWidth,
        avoidsSystemMeasureNumber: Bool = false,
        measureNumberGap: CGFloat = AppTheme.Spacing.sm
    ) -> CGFloat {
        let bounds = regionLabelXBounds(
            geometry: geometry,
            labelWidth: labelWidth,
            avoidsSystemMeasureNumber: avoidsSystemMeasureNumber,
            measureNumberGap: measureNumberGap
        )
        return regionLabelX(
            geometry: geometry,
            offsetInQuarterNotes: offsetInQuarterNotes,
            timeSignature: timeSignature,
            bounds: bounds
        )
    }

    static func regionLabelX(
        geometry: NotationMeasureCanvasGeometry,
        offsetInQuarterNotes: Double,
        timeSignature: TimeSignature,
        bounds: ClosedRange<CGFloat>
    ) -> CGFloat {
        let anchorX = notationAnchorX(
            geometry: geometry,
            offsetInQuarterNotes: offsetInQuarterNotes,
            timeSignature: timeSignature
        )
        return min(max(anchorX, bounds.lowerBound), bounds.upperBound)
    }

    static func regionLabelXBounds(
        geometry: NotationMeasureCanvasGeometry,
        labelWidth: CGFloat = AppTheme.Timeline.notationRegionLabelMaxWidth,
        avoidsSystemMeasureNumber: Bool = false,
        measureNumberGap: CGFloat = AppTheme.Spacing.sm
    ) -> ClosedRange<CGFloat> {
        let lowerBound = regionLabelLowerBound(
            geometry: geometry,
            avoidsSystemMeasureNumber: avoidsSystemMeasureNumber,
            measureNumberGap: measureNumberGap
        )
        let rawUpperBound = regionLabelUpperBound(
            geometry: geometry,
            labelWidth: labelWidth
        )

        return lowerBound...max(lowerBound, rawUpperBound)
    }

    static func regionLabelLowerBound(
        geometry: NotationMeasureCanvasGeometry,
        avoidsSystemMeasureNumber: Bool,
        measureNumberGap: CGFloat = AppTheme.Spacing.sm
    ) -> CGFloat {
        let baseLowerBound = max(geometry.staffStartX, geometry.cellStartX)
        guard avoidsSystemMeasureNumber else { return baseLowerBound }

        return max(
            baseLowerBound,
            systemMeasureNumberLabelTrailingX(geometry: geometry) + max(0, measureNumberGap)
        )
    }

    static func regionLabelUpperBound(
        geometry: NotationMeasureCanvasGeometry,
        labelWidth: CGFloat = AppTheme.Timeline.notationRegionLabelMaxWidth
    ) -> CGFloat {
        let visualStartX = max(geometry.staffStartX, geometry.cellStartX)
        let visualEndX = max(visualStartX, geometry.staffEndX)
        return max(visualStartX, visualEndX - max(0, labelWidth))
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

    static func barlineHitTargets(
        for geometries: [NotationMeasureCanvasGeometry],
        measures: [ScoreMeasure]
    ) -> [NotationBarlineHitTarget] {
        let measureCount = min(geometries.count, measures.count)
        guard measureCount > 0 else { return [] }

        var targets: [NotationBarlineHitTarget] = []
        for index in 0..<measureCount {
            guard let x = geometries[index].leadingBarlineX else { continue }

            targets.append(NotationBarlineHitTarget(
                measureIndex: index,
                boundary: .leading,
                x: x,
                targetTime: measures[index].startTime
            ))
        }

        let lastIndex = measureCount - 1
        targets.append(NotationBarlineHitTarget(
            measureIndex: lastIndex,
            boundary: .trailing,
            x: geometries[lastIndex].staffEndX,
            targetTime: measures[lastIndex].endTime
        ))
        return targets
    }

    static func selectionOverlayRuns(
        selectedMeasureIndices: [Int],
        geometries: [NotationMeasureCanvasGeometry]
    ) -> [NotationSelectionOverlayRun] {
        let normalizedIndices = Set(selectedMeasureIndices)
            .filter { geometries.indices.contains($0) }
            .sorted()
        guard !normalizedIndices.isEmpty else { return [] }

        var runs: [NotationSelectionOverlayRun] = []
        var runStart = normalizedIndices[0]
        var previousIndex = normalizedIndices[0]

        func appendRun(start: Int, end: Int) {
            guard geometries.indices.contains(start),
                  geometries.indices.contains(end)
            else { return }

            let startGeometry = geometries[start]
            let endGeometry = geometries[end]
            runs.append(NotationSelectionOverlayRun(
                startMeasureIndex: start,
                endMeasureIndex: end,
                x: startGeometry.cellStartX,
                width: max(0, endGeometry.cellEndX - startGeometry.cellStartX)
            ))
        }

        for index in normalizedIndices.dropFirst() {
            if index == previousIndex + 1 {
                previousIndex = index
                continue
            }

            appendRun(start: runStart, end: previousIndex)
            runStart = index
            previousIndex = index
        }

        appendRun(start: runStart, end: previousIndex)
        return runs
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

    static func attributeStaffTopInset(
        for _: MeasureAttributes,
        display: NotationAttributeDisplay
    ) -> CGFloat {
        display.isEmpty ? 0 : AppTheme.Timeline.notationAttributeStaffTopInset
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
        rhythmicX(
            forProgress: Double(max(0, min(progress, 1))),
            geometry: geometry
        )
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

    static func slashBeatCenters(
        geometry: NotationMeasureCanvasGeometry,
        timeSignature: TimeSignature,
        minimumBeatSpacing: CGFloat = AppTheme.Timeline.notationSlashMinimumBeatSpacing
    ) -> [CGFloat] {
        let beatCount = timeSignature.beatsPerBar
        let contentWidth = geometry.rhythmicEndX - geometry.rhythmicStartX
        guard beatCount > 0, contentWidth > 0 else { return [] }

        let beatLength = 4.0 / Double(max(1, timeSignature.beatUnit))
        let centers = (0..<beatCount).map { index in
            notationAnchorX(
                geometry: geometry,
                offsetInQuarterNotes: Double(index) * beatLength,
                timeSignature: timeSignature
            )
        }
        let safeMinimumBeatSpacing = max(0, minimumBeatSpacing)
        guard zip(centers, centers.dropFirst()).allSatisfy({
            $1 - $0 >= safeMinimumBeatSpacing
        }) else {
            return []
        }
        return centers
    }

    static func notationAnchorX(
        geometry: NotationMeasureCanvasGeometry,
        offsetInQuarterNotes: Double,
        timeSignature: TimeSignature
    ) -> CGFloat {
        let quarterLength = quarterLength(for: timeSignature)
        guard quarterLength > 0 else { return geometry.rhythmicStartX }

        let progress = max(0, min(offsetInQuarterNotes / quarterLength, 1))
        return rhythmicX(forProgress: progress, geometry: geometry)
    }

    static func notationAnchorProgress(
        atX x: CGFloat,
        geometry: NotationMeasureCanvasGeometry
    ) -> Double {
        let width = max(0, geometry.rhythmicEndX - geometry.rhythmicStartX)
        guard width > 0 else { return 0 }
        if let spacingMap = geometry.rhythmicSpacingMap {
            return spacingMap.progress(
                atX: x,
                startX: geometry.rhythmicStartX,
                endX: geometry.rhythmicEndX
            )
        }
        let rawProgress = (x - geometry.rhythmicStartX) / width
        return Double(max(0, min(rawProgress, 1)))
    }

    static func harmonyX(
        geometry: NotationMeasureCanvasGeometry,
        offsetInQuarterNotes: Double,
        timeSignature: TimeSignature
    ) -> CGFloat {
        notationAnchorX(
            geometry: geometry,
            offsetInQuarterNotes: offsetInQuarterNotes,
            timeSignature: timeSignature
        )
    }

    private static func rhythmicX(
        forProgress progress: Double,
        geometry: NotationMeasureCanvasGeometry
    ) -> CGFloat {
        if let spacingMap = geometry.rhythmicSpacingMap {
            return spacingMap.x(
                forProgress: progress,
                startX: geometry.rhythmicStartX,
                endX: geometry.rhythmicEndX
            )
        }
        let clampedProgress = max(0, min(progress, 1))
        let width = max(0, geometry.rhythmicEndX - geometry.rhythmicStartX)
        return geometry.rhythmicStartX + CGFloat(clampedProgress) * width
    }

    static func notationItemX(
        geometry: NotationMeasureCanvasGeometry,
        measure: ScoreMeasure,
        item: NotationMeasureItem
    ) -> CGFloat {
        guard centersSingleFullMeasureWholeRest(measure: measure, item: item) else {
            return harmonyX(
                geometry: geometry,
                offsetInQuarterNotes: item.offsetInQuarterNotes,
                timeSignature: measure.attributes.timeSignature
            )
        }

        return (geometry.contentStartX + geometry.contentEndX) / 2
    }

    private static func centersSingleFullMeasureWholeRest(
        measure: ScoreMeasure,
        item: NotationMeasureItem
    ) -> Bool {
        NotationMeasureTiming.isSingleFullMeasureWholeRest(
            measure,
            item: item
        )
    }

    static func harmonyLabelX(
        geometry: NotationMeasureCanvasGeometry,
        offsetInQuarterNotes: Double,
        timeSignature: TimeSignature,
        leadingOffset: CGFloat = AppTheme.Timeline.notationHarmonyAnchorLeadingOffset
    ) -> CGFloat {
        let anchorX = harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: offsetInQuarterNotes,
            timeSignature: timeSignature
        )
        let lowerBound = max(geometry.staffStartX, geometry.contentStartX)
        let upperBound = max(lowerBound, geometry.contentEndX)
        let rawX = anchorX - max(0, leadingOffset)
        return min(max(rawX, lowerBound), upperBound)
    }

    static func time(forHarmonyOffset offset: Double, in measure: ScoreMeasure) -> TimeInterval {
        NotationMeasureTiming.time(forQuarterOffset: offset, in: measure)
    }

    static func quarterLength(for timeSignature: TimeSignature) -> Double {
        NotationMeasureTiming.quarterLength(for: timeSignature)
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
        totalWidth: CGFloat,
        leadingAnchorInset: CGFloat = AppTheme.Timeline.notationItemAnchorInset,
        trailingAnchorInset: CGFloat = AppTheme.Timeline.notationItemAnchorInset,
        rhythmicSpacingMap: NotationRhythmicSpacingMap? = nil
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
            staffEndX: max(staffStartX, staffEndX),
            leadingAnchorInset: leadingAnchorInset,
            trailingAnchorInset: trailingAnchorInset,
            rhythmicSpacingMap: rhythmicSpacingMap
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

}
