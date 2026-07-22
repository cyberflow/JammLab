import CoreGraphics
import Foundation

struct RegionLabelLayoutItem: Equatable {
    var label: NotationRegionLabel
    var x: CGFloat
}

struct HarmonyLayoutItem: Equatable {
    var symbol: HarmonySymbol
    var x: CGFloat
}

struct NotationItemLayoutItem: Equatable, Identifiable {
    var measure: ScoreMeasure
    var notationItem: NotationMeasureItem
    var selection: NotationItemSelection
    var x: CGFloat
    var stemDirectionOverride: NotationStemDirection?

    var id: String {
        selection.id
    }

    var effectiveStemDirection: NotationStemDirection? {
        guard notationItem.kind == .note, let pitch = notationItem.pitch else { return nil }
        return stemDirectionOverride ?? NotationStemDirection.direction(
            forStaffPosition: NotationPitchMapper.staffPosition(
                for: pitch,
                clef: measure.attributes.clef
            )
        )
    }
}

struct NotationTieLayoutItem: Equatable, Identifiable {
    var connection: NotationTieConnection
    var start: CGPoint
    var end: CGPoint
    var placement: NotationTiePlacement

    var id: String { connection.id }
}

struct NotationChordRenderGroup: Equatable, Identifiable {
    var measure: ScoreMeasure
    var items: [NotationItemLayoutItem]
    var duration: NotationDuration
    var stemDirection: NotationStemDirection

    var id: String { items.map(\.id).sorted().joined(separator: "|") }
}

enum NotationDrumStemLayout {
    static let emptyStaffPosition = 6

    static func direction(forStaffPosition staffPosition: Int) -> NotationStemDirection? {
        guard staffPosition != emptyStaffPosition else { return nil }
        return staffPosition < emptyStaffPosition ? .up : .down
    }

    static func direction(forMIDINoteNumber midiNoteNumber: Int) -> NotationStemDirection? {
        guard let instrument = DrumInstrumentMap.instrument(forMIDINoteNumber: midiNoteNumber) else {
            return nil
        }
        return direction(forStaffPosition: instrument.staffPosition)
    }
}

enum NotationTrackLayoutItems {
    static func selectedMeasures(
        _ selectedMeasures: [NotationMeasureSelection],
        for partID: NotationPartID
    ) -> [NotationMeasureSelection] {
        selectedMeasures.filter { $0.partID == partID }
    }

    static func selectedMeasureIndices(
        visibleMeasures: [ScoreMeasure],
        selectedMeasures: [NotationMeasureSelection],
        partID: NotationPartID
    ) -> [Int] {
        let partSelections = Self.selectedMeasures(selectedMeasures, for: partID)
        return visibleMeasures.indices.filter { index in
            partSelections.contains(where: {
                $0.matches(visibleMeasures[index], partID: partID)
            })
        }
    }

    static func regionLabels(
        visibleMeasures: [ScoreMeasure],
        geometries: [NotationMeasureCanvasGeometry]
    ) -> [RegionLabelLayoutItem] {
        let candidates = visibleMeasures.indices.flatMap { index -> [RegionLabelLayoutCandidate] in
            guard geometries.indices.contains(index) else { return [] }
            let measure = visibleMeasures[index]
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

    static func harmonies(
        visibleMeasures: [ScoreMeasure],
        geometries: [NotationMeasureCanvasGeometry]
    ) -> [HarmonyLayoutItem] {
        visibleMeasures.indices.flatMap { index -> [HarmonyLayoutItem] in
            guard geometries.indices.contains(index) else { return [] }
            return visibleMeasures[index].harmonies.map { symbol in
                HarmonyLayoutItem(
                    symbol: symbol,
                    x: NotationMeasureLayout.harmonyLabelX(
                        geometry: geometries[index],
                        offsetInQuarterNotes: symbol.offsetInQuarterNotes,
                        timeSignature: visibleMeasures[index].attributes.timeSignature
                    )
                )
            }
        }
    }

    static func notationItems(
        visibleMeasures: [ScoreMeasure],
        geometries: [NotationMeasureCanvasGeometry]
    ) -> [NotationItemLayoutItem] {
        visibleMeasures.indices.flatMap { index -> [NotationItemLayoutItem] in
            guard geometries.indices.contains(index) else { return [] }
            let measure = visibleMeasures[index]
            let baseXByItemID = measure.notationItems.reduce(into: [String: CGFloat]()) { output, notationItem in
                output[notationItem.id] = NotationMeasureLayout.notationItemX(
                    geometry: geometries[index],
                    measure: measure,
                    item: notationItem
                )
            }
            let chordLayout = chordLayout(in: measure)
            return measure.notationItems.map { notationItem in
                NotationItemLayoutItem(
                    measure: measure,
                    notationItem: notationItem,
                    selection: NotationItemSelection(
                        measure: measure,
                        item: notationItem
                    ),
                    x: (baseXByItemID[notationItem.id] ?? 0)
                        + (chordLayout.xOffsetByItemID[notationItem.id] ?? 0),
                    stemDirectionOverride: chordLayout.stemDirectionByItemID[notationItem.id]
                )
            }
        }
    }

    static func chordRenderGroups(
        from layoutItems: [NotationItemLayoutItem]
    ) -> [NotationChordRenderGroup] {
        let notes = layoutItems.filter { $0.notationItem.kind == .note && $0.notationItem.pitch != nil }
        let grouped = Dictionary(grouping: notes) { item in
            NotationChordRenderKey(
                measureNumber: item.measure.number,
                measureStartTick: Int((item.measure.startTime * 1_000_000).rounded()),
                onsetTick: Int((item.notationItem.offsetInQuarterNotes * 1_000_000).rounded()),
                durationTick: Int((item.notationItem.durationInQuarterNotes * 1_000_000).rounded()),
                stemDirection: item.stemDirectionOverride
            )
        }
        return grouped.values.compactMap { items in
            guard items.count > 1,
                  let first = items.first,
                  let direction = first.stemDirectionOverride
            else { return nil }
            return NotationChordRenderGroup(
                measure: first.measure,
                items: items.sorted { $0.notationItem.id < $1.notationItem.id },
                duration: first.notationItem.displayDuration,
                stemDirection: direction
            )
        }.sorted { $0.id < $1.id }
    }

    private static func chordLayout(in measure: ScoreMeasure) -> NotationChordLayout {
        let notes = measure.notationItems.filter { $0.kind == .note && $0.pitch != nil }
        let onsetGroups = Dictionary(grouping: notes) {
            Int(($0.offsetInQuarterNotes * 1_000_000).rounded())
        }
        var layout = NotationChordLayout()

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
                let positioned = durationGroup.compactMap { note -> PositionedNotationItem? in
                    guard let pitch = note.pitch else { return nil }
                    return PositionedNotationItem(
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
                        let stemGroup = positioned.filter {
                            $0.drumStemDirection == stemDirection
                        }
                        applyChordLayout(
                            to: stemGroup,
                            laneOffset: laneOffset,
                            stemDirection: stemDirection,
                            layout: &layout
                        )
                    }
                } else {
                    applyChordLayout(
                        to: positioned,
                        laneOffset: laneOffset,
                        stemDirection: legacyStemDirection(for: positioned),
                        layout: &layout
                    )
                }
            }
        }
        return layout
    }

    private static func legacyStemDirection(
        for notes: [PositionedNotationItem]
    ) -> NotationStemDirection {
        let staffPositions = notes.map(\.staffPosition)
        let averagePosition = staffPositions.isEmpty
            ? 4
            : Int((Double(staffPositions.reduce(0, +)) / Double(staffPositions.count)).rounded())
        return NotationStemDirection.direction(forStaffPosition: averagePosition)
    }

    private static func applyChordLayout(
        to notes: [PositionedNotationItem],
        laneOffset: CGFloat,
        stemDirection: NotationStemDirection,
        layout: inout NotationChordLayout
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

    static func ties(
        visibleMeasures: [ScoreMeasure],
        geometries: [NotationMeasureCanvasGeometry],
        connections: [NotationTieConnection],
        staffTop: CGFloat
    ) -> [NotationTieLayoutItem] {
        guard let firstGeometry = geometries.first,
              let lastGeometry = geometries.last
        else {
            return []
        }

        let visibleItemsByID = notationItems(
                visibleMeasures: visibleMeasures,
                geometries: geometries
            ).reduce(into: [String: NotationItemLayoutItem]()) {
                if $0[$1.notationItem.id] == nil { $0[$1.notationItem.id] = $1 }
            }

        return connections.compactMap { connection in
            let sourceVisible = visibleItemsByID[connection.source.item.id]
            let targetVisible = visibleItemsByID[connection.target.item.id]
            guard sourceVisible != nil || targetVisible != nil,
                  let sourcePitch = connection.source.item.pitch,
                  let targetPitch = connection.target.item.pitch
            else {
                return nil
            }

            let sourceStaffPosition = NotationPitchMapper.staffPosition(
                for: sourcePitch,
                clef: connection.source.measureAttributes.clef
            )
            let targetStaffPosition = NotationPitchMapper.staffPosition(
                for: targetPitch,
                clef: connection.target.measureAttributes.clef
            )
            let stemDirection = sourceVisible?.effectiveStemDirection
                ?? targetVisible?.effectiveStemDirection
                ?? NotationStemDirection.direction(forStaffPosition: sourceStaffPosition)
            let placement: NotationTiePlacement = stemDirection == .up ? .below : .above
            let verticalDirection: CGFloat = placement == .below ? 1 : -1
            let sourceY = NotationNotePlacementResolver.yPosition(
                forStaffPosition: sourceStaffPosition,
                staffTop: staffTop
            ) + verticalDirection * AppTheme.Timeline.notationTieVerticalOffset
            let targetY = NotationNotePlacementResolver.yPosition(
                forStaffPosition: targetStaffPosition,
                staffTop: staffTop
            ) + verticalDirection * AppTheme.Timeline.notationTieVerticalOffset
            let startX = sourceVisible.map {
                $0.x + AppTheme.Timeline.notationTieNoteheadInset
            } ?? firstGeometry.staffStartX
            let endX = targetVisible.map {
                $0.x - AppTheme.Timeline.notationTieNoteheadInset
            } ?? lastGeometry.staffEndX
            guard endX > startX + NotationMeasureTiming.timelineTolerance else { return nil }

            return NotationTieLayoutItem(
                connection: connection,
                start: CGPoint(x: startX, y: sourceY),
                end: CGPoint(x: endX, y: targetY),
                placement: placement
            )
        }
    }
}

private struct NotationChordLayout {
    var xOffsetByItemID: [String: CGFloat] = [:]
    var stemDirectionByItemID: [String: NotationStemDirection] = [:]
}

private struct PositionedNotationItem {
    var item: NotationMeasureItem
    var staffPosition: Int
    var drumStemDirection: NotationStemDirection?
}

private struct NotationChordRenderKey: Hashable {
    var measureNumber: Int
    var measureStartTick: Int
    var onsetTick: Int
    var durationTick: Int
    var stemDirection: NotationStemDirection?
}

enum NotationTrackAccessibility {
    static func value(
        visibleMeasures: [ScoreMeasure],
        keySignature: KeySignature,
        timeSignature: TimeSignature,
        selectedMeasures: [NotationMeasureSelection],
        partID: NotationPartID
    ) -> String {
        guard let first = visibleMeasures.first, let last = visibleMeasures.last else {
            return "Pending tempo"
        }

        let partSelections = NotationTrackLayoutItems.selectedMeasures(
            selectedMeasures,
            for: partID
        )
        let selectedMeasureText: String
        if partSelections.isEmpty {
            selectedMeasureText = ""
        } else if partSelections.count == 1, let selectedMeasure = partSelections.first {
            selectedMeasureText = ", selected measure \(selectedMeasure.number)"
        } else if let firstSelectedMeasure = partSelections.first,
                  let lastSelectedMeasure = partSelections.last {
            selectedMeasureText = ", selected measures \(firstSelectedMeasure.number) through \(lastSelectedMeasure.number)"
        } else {
            selectedMeasureText = ""
        }

        return "Measures \(first.number) through \(last.number), \(keySignature.displayName), \(timeSignature.displayText)\(selectedMeasureText)"
    }
}

private struct RegionLabelLayoutCandidate: Equatable {
    var label: NotationRegionLabel
    var x: CGFloat
    var upperBound: CGFloat
}
