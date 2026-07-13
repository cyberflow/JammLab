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

    var id: String {
        selection.id
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
            return measure.notationItems.map { notationItem in
                NotationItemLayoutItem(
                    measure: measure,
                    notationItem: notationItem,
                    selection: NotationItemSelection(
                        measure: measure,
                        item: notationItem
                    ),
                    x: NotationMeasureLayout.notationItemX(
                        geometry: geometries[index],
                        measure: measure,
                        item: notationItem
                    )
                )
            }
        }
    }
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
