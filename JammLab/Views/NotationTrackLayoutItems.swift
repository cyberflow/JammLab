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

struct NotationAccidentalLayoutItem: Equatable, Identifiable {
    var itemID: String
    var accidental: NotationAccidental
    var x: CGFloat
    var staffPosition: Int

    var id: String { itemID }
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
            let chordLayout = NotationHorizontalLayoutResolver.chordLayout(in: measure)
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

    static func accidentals(
        from layoutItems: [NotationItemLayoutItem]
    ) -> [NotationAccidentalLayoutItem] {
        let columnsByMeasure = Dictionary(
            uniqueKeysWithValues: Dictionary(
                grouping: layoutItems,
                by: { NotationMeasureIdentity($0.measure) }
            ).compactMap { identity, items -> (NotationMeasureIdentity, [String: Int])? in
                guard let measure = items.first?.measure else { return nil }
                return (
                    identity,
                    NotationHorizontalLayoutResolver.accidentalColumnByItemID(in: measure)
                )
            }
        )

        let candidates = layoutItems.compactMap { item -> AccidentalCandidate? in
            guard item.measure.attributes.clef != .drums,
                  item.notationItem.kind == .note,
                  let pitch = item.notationItem.pitch,
                  let accidental = item.notationItem.explicitAccidental
            else { return nil }
            return AccidentalCandidate(
                itemID: item.notationItem.id,
                accidental: accidental,
                noteX: item.x,
                staffPosition: NotationPitchMapper.staffPosition(
                    for: pitch,
                    clef: item.measure.attributes.clef
                ),
                column: columnsByMeasure[NotationMeasureIdentity(item.measure)]?[
                    item.notationItem.id
                ] ?? 0
            )
        }
        return candidates.map { candidate in
            NotationAccidentalLayoutItem(
                itemID: candidate.itemID,
                accidental: candidate.accidental,
                x: candidate.noteX
                    - AppTheme.Timeline.notationInlineAccidentalNoteOffset
                    - CGFloat(candidate.column)
                        * AppTheme.Timeline.notationInlineAccidentalColumnSpacing,
                staffPosition: candidate.staffPosition
            )
        }
        .sorted { $0.itemID < $1.itemID }
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

private struct AccidentalCandidate {
    var itemID: String
    var accidental: NotationAccidental
    var noteX: CGFloat
    var staffPosition: Int
    var column: Int
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
