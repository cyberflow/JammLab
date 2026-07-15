import Foundation

enum NotationDurationEditor {
    static func replacementSuffix(
        in measure: ScoreMeasure,
        selectedItem: NotationMeasureItem,
        selectedDuration: NotationDuration
    ) -> [NotationMeasureItem]? {
        var items: [NotationMeasureItem] = []
        var cursor = selectedItem.offsetInQuarterNotes
        let measureLength = NotationMeasureTiming.quarterLength(for: measure.attributes.timeSignature)
        var remaining = measureLength - cursor
        guard remaining > NotationMeasureTiming.timelineTolerance else { return nil }

        let selectedLength = selectedDuration.durationInQuarterNotes
        if selectedItem.kind == .note {
            guard selectedLength <= remaining + NotationMeasureTiming.timelineTolerance,
                  let pitch = selectedItem.pitch
            else {
                return nil
            }

            let duration = min(selectedLength, remaining)
            items.append(NotationMeasureItem(
                id: selectedItem.id,
                partID: selectedItem.partID,
                kind: .note,
                pitch: pitch,
                measureNumber: measure.number,
                measureStartTime: measure.startTime,
                offsetInQuarterNotes: cursor,
                durationInQuarterNotes: duration,
                displayDuration: selectedDuration
            ))
            cursor += duration
            remaining -= duration
            items.append(contentsOf: fillerItems(
                in: measure,
                partID: selectedItem.partID,
                startOffset: cursor,
                remaining: remaining
            ))
            return items
        }

        let selectedCount = min(
            2,
            Int(floor((remaining + NotationMeasureTiming.timelineTolerance) / selectedLength))
        )
        if selectedCount > 0 {
            for _ in 0..<selectedCount {
                let duration = min(selectedLength, remaining)
                items.append(NotationRestItemFactory.restItem(
                    partID: selectedItem.partID,
                    measureNumber: measure.number,
                    measureStartTime: measure.startTime,
                    offsetInQuarterNotes: cursor,
                    durationInQuarterNotes: duration,
                    displayDuration: selectedDuration
                ))
                cursor += duration
                remaining -= duration
            }
        } else if let largest = largestDuration(fitting: remaining) {
            let duration = min(largest.durationInQuarterNotes, remaining)
            items.append(NotationRestItemFactory.restItem(
                partID: selectedItem.partID,
                measureNumber: measure.number,
                measureStartTime: measure.startTime,
                offsetInQuarterNotes: cursor,
                durationInQuarterNotes: duration,
                displayDuration: largest
            ))
            cursor += duration
            remaining -= duration
        }

        items.append(contentsOf: fillerItems(
            in: measure,
            partID: selectedItem.partID,
            startOffset: cursor,
            remaining: remaining
        ))
        return items
    }

    private static func fillerItems(
        in measure: ScoreMeasure,
        partID: NotationPartID,
        startOffset: Double,
        remaining: Double
    ) -> [NotationMeasureItem] {
        NotationRestItemFactory.restItems(
            measureNumber: measure.number,
            measureStartTime: measure.startTime,
            startOffset: startOffset,
            remaining: remaining,
            partID: partID
        )
    }

    private static func largestDuration(fitting remaining: Double) -> NotationDuration? {
        NotationRestItemFactory.greedySegments(startOffset: 0, remaining: remaining).first?.displayDuration
    }
}
