import CoreGraphics

struct NotationMeasureIdentity: Hashable, Equatable {
    var number: Int
    var startTimeMicroseconds: Int64
    var endTimeMicroseconds: Int64

    init(_ measure: ScoreMeasure) {
        number = measure.number
        startTimeMicroseconds = Int64((measure.startTime * 1_000_000).rounded())
        endTimeMicroseconds = Int64((measure.endTime * 1_000_000).rounded())
    }
}

struct NotationChordHorizontalLayout: Equatable {
    var xOffsetByItemID: [String: CGFloat] = [:]
    var stemDirectionByItemID: [String: NotationStemDirection] = [:]
}

enum NotationHorizontalLayoutResolver {
    static func chordLayout(in measure: ScoreMeasure) -> NotationChordHorizontalLayout {
        let notes = measure.notationItems.filter { $0.kind == .note && $0.pitch != nil }
        let onsetGroups = Dictionary(grouping: notes) {
            Int(($0.offsetInQuarterNotes * 1_000_000).rounded())
        }
        var layout = NotationChordHorizontalLayout()

        for onsetGroup in onsetGroups.values where onsetGroup.count > 1 {
            let durationGroups = Dictionary(grouping: onsetGroup) {
                Int(($0.durationInQuarterNotes * 1_000_000).rounded())
            }.values.sorted {
                let lhsDuration = $0.first?.durationInQuarterNotes ?? 0
                let rhsDuration = $1.first?.durationInQuarterNotes ?? 0
                if abs(lhsDuration - rhsDuration) > NotationMeasureTiming.timelineTolerance {
                    return lhsDuration > rhsDuration
                }
                return ($0.first?.id ?? "") < ($1.first?.id ?? "")
            }

            for (laneIndex, durationGroup) in durationGroups.enumerated() {
                let laneOffset = (CGFloat(laneIndex) - CGFloat(durationGroups.count - 1) / 2)
                    * AppTheme.Timeline.notationPolyphonicLaneSpacing
                let positioned = durationGroup.compactMap { note -> PositionedItem? in
                    guard let pitch = note.pitch else { return nil }
                    return PositionedItem(
                        item: note,
                        staffPosition: NotationPitchMapper.staffPosition(
                            for: pitch,
                            clef: measure.attributes.clef
                        ),
                        drumStemDirection: measure.attributes.clef == .drums
                            ? NotationDrumStemLayout.direction(
                                forMIDINoteNumber: pitch.midiNoteNumber
                            )
                            : nil
                    )
                }
                .sorted {
                    $0.staffPosition == $1.staffPosition
                        ? $0.item.id < $1.item.id
                        : $0.staffPosition < $1.staffPosition
                }

                if measure.attributes.clef == .drums,
                   positioned.allSatisfy({ $0.drumStemDirection != nil }) {
                    for stemDirection in [NotationStemDirection.up, .down] {
                        applyChordLayout(
                            to: positioned.filter { $0.drumStemDirection == stemDirection },
                            laneOffset: laneOffset,
                            stemDirection: stemDirection,
                            layout: &layout
                        )
                    }
                } else {
                    applyChordLayout(
                        to: positioned,
                        laneOffset: laneOffset,
                        stemDirection: averageStemDirection(for: positioned),
                        layout: &layout
                    )
                }
            }
        }
        return layout
    }

    static func accidentalColumnByItemID(in measure: ScoreMeasure) -> [String: Int] {
        let candidates = measure.notationItems.compactMap { item -> AccidentalCandidate? in
            guard item.kind == .note,
                  item.explicitAccidental != nil,
                  let pitch = item.pitch
            else { return nil }
            return AccidentalCandidate(
                itemID: item.id,
                onsetTick: Int((item.offsetInQuarterNotes * 1_000_000).rounded()),
                staffPosition: NotationPitchMapper.staffPosition(
                    for: pitch,
                    clef: measure.attributes.clef
                )
            )
        }
        let groups = Dictionary(grouping: candidates, by: \.onsetTick)
        var result: [String: Int] = [:]

        for group in groups.values {
            var staffPositionsByColumn: [[Int]] = []
            for candidate in group.sorted(by: {
                $0.staffPosition == $1.staffPosition
                    ? $0.itemID < $1.itemID
                    : $0.staffPosition < $1.staffPosition
            }) {
                let column = staffPositionsByColumn.firstIndex { positions in
                    positions.allSatisfy {
                        abs($0 - candidate.staffPosition)
                            >= AppTheme.Timeline.notationInlineAccidentalMinimumStaffPositionDistance
                    }
                } ?? staffPositionsByColumn.count
                if column == staffPositionsByColumn.count {
                    staffPositionsByColumn.append([])
                }
                staffPositionsByColumn[column].append(candidate.staffPosition)
                result[candidate.itemID] = column
            }
        }
        return result
    }

    private static func averageStemDirection(
        for notes: [PositionedItem]
    ) -> NotationStemDirection {
        let staffPositions = notes.map(\.staffPosition)
        let averagePosition = staffPositions.isEmpty
            ? 4
            : Int((Double(staffPositions.reduce(0, +)) / Double(staffPositions.count)).rounded())
        return NotationStemDirection.direction(forStaffPosition: averagePosition)
    }

    private static func applyChordLayout(
        to notes: [PositionedItem],
        laneOffset: CGFloat,
        stemDirection: NotationStemDirection,
        layout: inout NotationChordHorizontalLayout
    ) {
        guard !notes.isEmpty else { return }

        var shiftsRight = stemDirection == .up
        var countsByStaffPosition: [Int: Int] = [:]
        for (noteIndex, note) in notes.enumerated() {
            var noteOffset = laneOffset
            let staffPosition = note.staffPosition
            let duplicateIndex = countsByStaffPosition[staffPosition, default: 0]
            countsByStaffPosition[staffPosition] = duplicateIndex + 1
            if !duplicateIndex.isMultiple(of: 2) {
                noteOffset += AppTheme.Timeline.notationDuplicateNoteOffset
            }
            if noteIndex > 0,
               abs(staffPosition - notes[noteIndex - 1].staffPosition) == 1 {
                noteOffset += shiftsRight
                    ? AppTheme.Timeline.notationChordSecondOffset
                    : -AppTheme.Timeline.notationChordSecondOffset
                shiftsRight.toggle()
            }
            layout.xOffsetByItemID[note.item.id] = noteOffset
            layout.stemDirectionByItemID[note.item.id] = stemDirection
        }
    }

    private struct PositionedItem {
        var item: NotationMeasureItem
        var staffPosition: Int
        var drumStemDirection: NotationStemDirection?
    }

    private struct AccidentalCandidate {
        var itemID: String
        var onsetTick: Int
        var staffPosition: Int
    }
}

struct NotationRhythmicSpacingAnchor: Equatable {
    var progress: Double
    var compactX: CGFloat
}

struct NotationRhythmicSpacingMap: Equatable {
    var anchors: [NotationRhythmicSpacingAnchor]
    var compactSpan: CGFloat

    func x(
        forProgress progress: Double,
        startX: CGFloat,
        endX: CGFloat
    ) -> CGFloat {
        let safeStartX = min(startX, endX)
        let safeEndX = max(startX, endX)
        let width = safeEndX - safeStartX
        guard width > 0 else { return safeStartX }

        let clampedProgress = max(0, min(progress, 1))
        let compactX = compactX(forProgress: clampedProgress)
        let projectedX: CGFloat
        if compactSpan > CGFloat(NotationMeasureTiming.timelineTolerance) {
            if width >= compactSpan {
                projectedX = compactX
                    + (width - compactSpan) * CGFloat(clampedProgress)
            } else {
                projectedX = compactX * (width / compactSpan)
            }
        } else {
            projectedX = width * CGFloat(clampedProgress)
        }
        return safeStartX + min(max(0, projectedX), width)
    }

    func progress(
        atX x: CGFloat,
        startX: CGFloat,
        endX: CGFloat
    ) -> Double {
        let safeStartX = min(startX, endX)
        let safeEndX = max(startX, endX)
        let width = safeEndX - safeStartX
        guard width > 0 else { return 0 }

        let relativeX = min(max(x, safeStartX), safeEndX) - safeStartX
        let projectedAnchors = anchors.map {
            (
                progress: $0.progress,
                x: projectedX(for: $0, width: width)
            )
        }
        guard let first = projectedAnchors.first,
              let last = projectedAnchors.last,
              projectedAnchors.count >= 2
        else {
            return Double(relativeX / width)
        }
        if relativeX <= first.x { return max(0, min(first.progress, 1)) }
        if relativeX >= last.x { return max(0, min(last.progress, 1)) }

        for (lhs, rhs) in zip(projectedAnchors, projectedAnchors.dropFirst())
            where relativeX <= rhs.x {
            let segmentWidth = rhs.x - lhs.x
            guard segmentWidth > CGFloat(NotationMeasureTiming.timelineTolerance) else {
                return max(0, min(rhs.progress, 1))
            }
            let segmentProgress = Double((relativeX - lhs.x) / segmentWidth)
            return max(
                0,
                min(
                    lhs.progress + (rhs.progress - lhs.progress) * segmentProgress,
                    1
                )
            )
        }
        return 1
    }

    private func compactX(forProgress progress: Double) -> CGFloat {
        guard let first = anchors.first,
              let last = anchors.last,
              anchors.count >= 2
        else {
            return compactSpan * CGFloat(progress)
        }
        if progress <= first.progress { return first.compactX }
        if progress >= last.progress { return last.compactX }

        for (lhs, rhs) in zip(anchors, anchors.dropFirst())
            where progress <= rhs.progress {
            let progressSpan = rhs.progress - lhs.progress
            guard progressSpan > NotationMeasureTiming.timelineTolerance else {
                return rhs.compactX
            }
            let interpolation = CGFloat((progress - lhs.progress) / progressSpan)
            return lhs.compactX + (rhs.compactX - lhs.compactX) * interpolation
        }
        return last.compactX
    }

    private func projectedX(
        for anchor: NotationRhythmicSpacingAnchor,
        width: CGFloat
    ) -> CGFloat {
        guard compactSpan > CGFloat(NotationMeasureTiming.timelineTolerance) else {
            return width * CGFloat(anchor.progress)
        }
        if width >= compactSpan {
            return anchor.compactX
                + (width - compactSpan) * CGFloat(anchor.progress)
        }
        return anchor.compactX * (width / compactSpan)
    }
}

struct NotationRhythmicColumn: Equatable {
    var quantizedProgress: Int64
    var progress: Double
    var leftFootprint: CGFloat
    var rightFootprint: CGFloat
}

struct NotationMeasureSpacingRequirements: Equatable {
    var leadingAnchorInset: CGFloat
    var trailingAnchorInset: CGFloat
    var columns: [NotationRhythmicColumn]
}

enum NotationMeasureSpacingAnalyzer {
    static let progressScale: Double = 1_000_000

    static func requirements(for measure: ScoreMeasure) -> NotationMeasureSpacingRequirements {
        let baseInset = AppTheme.Timeline.notationItemAnchorInset
        let gap = AppTheme.Timeline.notationRhythmicColumnGap
        guard !NotationMeasureTiming.isSingleFullMeasureWholeRest(measure) else {
            return NotationMeasureSpacingRequirements(
                leadingAnchorInset: baseInset,
                trailingAnchorInset: baseInset,
                columns: []
            )
        }

        let quarterLength = NotationMeasureTiming.quarterLength(
            for: measure.attributes.timeSignature
        )
        guard quarterLength > NotationMeasureTiming.timelineTolerance else {
            return NotationMeasureSpacingRequirements(
                leadingAnchorInset: baseInset,
                trailingAnchorInset: baseInset,
                columns: []
            )
        }

        let chordLayout = NotationHorizontalLayoutResolver.chordLayout(in: measure)
        let accidentalColumns = NotationHorizontalLayoutResolver.accidentalColumnByItemID(
            in: measure
        )
        let rhythmicItems = measure.notationItems.filter {
            $0.kind == .rest || ($0.kind == .note && $0.pitch != nil)
        }
        let grouped = Dictionary(grouping: rhythmicItems) {
            Int64(($0.offsetInQuarterNotes * progressScale).rounded())
        }
        let columns = grouped.values.compactMap { items -> NotationRhythmicColumn? in
            guard let first = items.first else { return nil }
            var left = AppTheme.Timeline.notationRhythmicGlyphRadius
            var right = AppTheme.Timeline.notationRhythmicGlyphRadius

            for item in items {
                let xOffset = chordLayout.xOffsetByItemID[item.id] ?? 0
                left = max(left, AppTheme.Timeline.notationRhythmicGlyphRadius - xOffset)
                right = max(right, AppTheme.Timeline.notationRhythmicGlyphRadius + xOffset)

                if let accidentalColumn = accidentalColumns[item.id] {
                    let accidentalCenter = xOffset
                        - AppTheme.Timeline.notationInlineAccidentalNoteOffset
                        - CGFloat(accidentalColumn)
                            * AppTheme.Timeline.notationInlineAccidentalColumnSpacing
                    left = max(
                        left,
                        -accidentalCenter + AppTheme.Timeline.notationAccidentalWidth / 2
                    )
                }
                if item.displayDuration.isDotted {
                    right = max(
                        right,
                        xOffset
                            + AppTheme.Timeline.notationStaffLineSpacing
                            + AppTheme.Timeline.notationRhythmicDotRadius
                    )
                }
            }

            let progress = max(0, min(first.offsetInQuarterNotes / quarterLength, 1))
            return NotationRhythmicColumn(
                quantizedProgress: Int64((progress * progressScale).rounded()),
                progress: progress,
                leftFootprint: left,
                rightFootprint: right
            )
        }
        .sorted { $0.quantizedProgress < $1.quantizedProgress }

        guard let first = columns.first, let last = columns.last else {
            return NotationMeasureSpacingRequirements(
                leadingAnchorInset: baseInset,
                trailingAnchorInset: baseInset,
                columns: []
            )
        }

        return NotationMeasureSpacingRequirements(
            leadingAnchorInset: max(baseInset, first.leftFootprint + gap),
            trailingAnchorInset: max(baseInset, last.rightFootprint + gap),
            columns: columns
        )
    }

}

enum NotationRhythmicSpacingMapBuilder {
    static func make(
        rows: [NotationMeasureSpacingRequirements],
        leadingInset: CGFloat,
        trailingInset: CGFloat
    ) -> NotationRhythmicSpacingMap {
        let scale = NotationMeasureSpacingAnalyzer.progressScale
        let endTick = Int64(scale)
        let ticks = Set(
            rows.flatMap { $0.columns.map(\.quantizedProgress) } + [0, endTick]
        ).map {
            min(max(0, $0), endTick)
        }.sorted()
        let safeTicks = ticks.count >= 2 ? ticks : [0, endTick]
        let indexByTick = Dictionary(
            uniqueKeysWithValues: safeTicks.enumerated().map { ($0.element, $0.offset) }
        )
        let baseSpan = max(
            0,
            AppTheme.Timeline.notationMeasureMinWidth
                - max(0, leadingInset)
                - max(0, trailingInset)
        )
        var collisionConstraintsByTarget: [Int: [(source: Int, distance: CGFloat)]] = [:]
        let gap = AppTheme.Timeline.notationRhythmicColumnGap

        for row in rows {
            for (lhs, rhs) in zip(row.columns, row.columns.dropFirst()) {
                guard let source = indexByTick[lhs.quantizedProgress],
                      let target = indexByTick[rhs.quantizedProgress],
                      source < target
                else {
                    continue
                }
                collisionConstraintsByTarget[target, default: []].append(
                    (
                        source: source,
                        distance: lhs.rightFootprint + gap + rhs.leftFootprint
                    )
                )
            }
        }

        var positions = Array(repeating: CGFloat.zero, count: safeTicks.count)
        for target in safeTicks.indices.dropFirst() {
            let progressDelta = Double(safeTicks[target] - safeTicks[target - 1]) / scale
            positions[target] = positions[target - 1]
                + baseSpan * CGFloat(max(0, progressDelta))
            for constraint in collisionConstraintsByTarget[target, default: []] {
                positions[target] = max(
                    positions[target],
                    positions[constraint.source] + constraint.distance
                )
            }
        }

        return NotationRhythmicSpacingMap(
            anchors: safeTicks.indices.map { index in
                NotationRhythmicSpacingAnchor(
                    progress: Double(safeTicks[index]) / scale,
                    compactX: positions[index]
                )
            },
            compactSpan: positions.last ?? baseSpan
        )
    }
}

struct NotationMeasureLayoutSlot: Equatable {
    var identity: NotationMeasureIdentity
    var attributeReserveWidth: CGFloat
    var minimumBodyWidth: CGFloat
    var leadingAnchorInset: CGFloat
    var trailingAnchorInset: CGFloat
    var rhythmicSpacingMap: NotationRhythmicSpacingMap
}

struct NotationSystemMeasureLayout: Equatable {
    var slots: [NotationMeasureLayoutSlot]

    var minimumRequiredWidth: CGFloat {
        slots.map(\.attributeReserveWidth).reduce(0, +)
            + requiredBodyWidths.reduce(0, +)
    }

    static func make(measureRows: [[ScoreMeasure]]) -> NotationSystemMeasureLayout? {
        guard let referenceRow = measureRows.first, !referenceRow.isEmpty else { return nil }
        let identities = referenceRow.map(NotationMeasureIdentity.init)
        guard measureRows.allSatisfy({
            $0.count == referenceRow.count
                && $0.map(NotationMeasureIdentity.init) == identities
        }) else {
            return nil
        }

        let slots = referenceRow.indices.map { index -> NotationMeasureLayoutSlot in
            var reserveWidth: CGFloat = 0
            var spacingRequirements: [NotationMeasureSpacingRequirements] = []

            for row in measureRows {
                let measure = row[index]
                let previousAttributes = index > 0 ? row[index - 1].attributes : nil
                let display = NotationAttributeDisplay.display(
                    for: measure.attributes,
                    previousAttributes: previousAttributes
                )
                reserveWidth = max(
                    reserveWidth,
                    NotationMeasureLayout.attributeReserveWidth(
                        for: measure.attributes,
                        display: display
                    )
                )
                spacingRequirements.append(
                    NotationMeasureSpacingAnalyzer.requirements(for: measure)
                )
            }
            let leadingInset = spacingRequirements
                .map(\.leadingAnchorInset)
                .max() ?? AppTheme.Timeline.notationItemAnchorInset
            let trailingInset = spacingRequirements
                .map(\.trailingAnchorInset)
                .max() ?? AppTheme.Timeline.notationItemAnchorInset
            let rhythmicSpacingMap = NotationRhythmicSpacingMapBuilder.make(
                rows: spacingRequirements,
                leadingInset: leadingInset,
                trailingInset: trailingInset
            )

            return NotationMeasureLayoutSlot(
                identity: identities[index],
                attributeReserveWidth: reserveWidth,
                minimumBodyWidth: max(
                    AppTheme.Timeline.notationMeasureMinWidth,
                    leadingInset + rhythmicSpacingMap.compactSpan + trailingInset
                ),
                leadingAnchorInset: leadingInset,
                trailingAnchorInset: trailingInset,
                rhythmicSpacingMap: rhythmicSpacingMap
            )
        }
        return NotationSystemMeasureLayout(slots: slots)
    }

    static func make(states: [NotationViewportState]) -> NotationSystemMeasureLayout? {
        make(measureRows: states.map(\.visibleMeasures))
    }

    func matches(_ measures: [ScoreMeasure]) -> Bool {
        slots.map(\.identity) == measures.map(NotationMeasureIdentity.init)
    }

    func geometries(totalWidth: CGFloat) -> [NotationMeasureCanvasGeometry] {
        guard !slots.isEmpty else { return [] }
        let safeTotalWidth = max(0, totalWidth)
        var reserveWidths = slots.map(\.attributeReserveWidth)
        let reserveTotal = reserveWidths.reduce(0, +)
        if reserveTotal > safeTotalWidth, reserveTotal > 0 {
            let scale = safeTotalWidth / reserveTotal
            reserveWidths = reserveWidths.map { $0 * scale }
        }

        let availableBodyWidth = max(0, safeTotalWidth - reserveWidths.reduce(0, +))
        let minimumBodyWidths = requiredBodyWidths
        let minimumBodyTotal = minimumBodyWidths.reduce(0, +)
        let bodyWidths: [CGFloat]
        if minimumBodyTotal <= availableBodyWidth {
            let extraPerMeasure = (availableBodyWidth - minimumBodyTotal) / CGFloat(slots.count)
            bodyWidths = minimumBodyWidths.map { $0 + extraPerMeasure }
        } else if minimumBodyTotal > 0 {
            let scale = availableBodyWidth / minimumBodyTotal
            bodyWidths = minimumBodyWidths.map { $0 * scale }
        } else {
            bodyWidths = Array(
                repeating: availableBodyWidth / CGFloat(slots.count),
                count: slots.count
            )
        }

        return NotationMeasureLayout.canvasGeometries(
            totalWidth: safeTotalWidth,
            bodyWidths: bodyWidths,
            attributeReserveWidths: reserveWidths,
            leadingAnchorInsets: slots.map(\.leadingAnchorInset),
            trailingAnchorInsets: slots.map(\.trailingAnchorInset),
            rhythmicSpacingMaps: slots.map { Optional($0.rhythmicSpacingMap) }
        )
    }

    private var requiredBodyWidths: [CGFloat] {
        guard !slots.isEmpty else { return [] }
        var widths = slots.map(\.minimumBodyWidth)
        widths[0] += AppTheme.Timeline.notationStaffHorizontalInset
        widths[widths.count - 1] += AppTheme.Timeline.notationStaffHorizontalInset
        return widths
    }
}

struct NotationVisibleMeasureFitter {
    static let widthTolerance: CGFloat = 0.5

    static func fittedMeasureCount(
        availableWidth: CGFloat,
        maximumMeasureCount: Int,
        stateForMeasureCount: (Int) -> NotationViewportState
    ) -> Int {
        let safeMaximumMeasureCount = max(1, maximumMeasureCount)
        let safeAvailableWidth = max(0, availableWidth)

        for measureCount in stride(from: safeMaximumMeasureCount, through: 1, by: -1) {
            let state = stateForMeasureCount(measureCount)
            let requiredWidth = minimumRequiredWidth(for: state)
            if requiredWidth <= safeAvailableWidth + widthTolerance {
                return measureCount
            }
        }

        return 1
    }

    static func minimumRequiredWidth(for state: NotationViewportState) -> CGFloat {
        if let layout = NotationSystemMeasureLayout.make(states: [state]) {
            return layout.minimumRequiredWidth
        }
        let measureCount = max(
            1,
            state.visibleMeasures.isEmpty ? state.visibleMeasureCount : state.visibleMeasures.count
        )
        let reserveWidths = attributeReserveWidths(for: state, measureCount: measureCount)
        return NotationMeasureLayout.minimumCanvasWidth(
            measureCount: measureCount,
            attributeReserveWidths: reserveWidths
        )
    }

    static func minimumRequiredWidth(for states: [NotationViewportState]) -> CGFloat {
        NotationSystemMeasureLayout.make(states: states)?.minimumRequiredWidth
            ?? states.map(minimumRequiredWidth(for:)).max()
            ?? 0
    }

    static func fittedMeasureCount(
        availableWidth: CGFloat,
        maximumMeasureCount: Int,
        statesForMeasureCount: (Int) -> [NotationViewportState]
    ) -> Int {
        let safeMaximumMeasureCount = max(1, maximumMeasureCount)
        let safeAvailableWidth = max(0, availableWidth)

        for measureCount in stride(from: safeMaximumMeasureCount, through: 1, by: -1) {
            let requiredWidth = minimumRequiredWidth(
                for: statesForMeasureCount(measureCount)
            )
            if requiredWidth <= safeAvailableWidth + widthTolerance {
                return measureCount
            }
        }
        return 1
    }

    static func attributeReserveWidths(
        for state: NotationViewportState,
        measureCount: Int
    ) -> [CGFloat] {
        (0..<max(1, measureCount)).map { index in
            guard state.visibleMeasures.indices.contains(index) else { return 0 }

            let previousAttributes = index > 0 ? state.visibleMeasures[index - 1].attributes : nil
            let display = NotationAttributeDisplay.display(
                for: state.visibleMeasures[index].attributes,
                previousAttributes: previousAttributes
            )
            return NotationMeasureLayout.attributeReserveWidth(
                for: state.visibleMeasures[index].attributes,
                display: display
            )
        }
    }
}
