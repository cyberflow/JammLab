import Foundation

enum NotationDurationEditor {
    struct Replacement: Equatable {
        let items: [NotationMeasureItem]
        let selectedItem: NotationMeasureItem
    }

    static func replacement(
        in measure: ScoreMeasure,
        selectedItem: NotationMeasureItem,
        selectedDuration: NotationDuration
    ) -> Replacement? {
        let orderedItems = measure.notationItems.sorted(by: itemSort)
        guard let selectedIndex = orderedItems.firstIndex(where: {
            $0.id == selectedItem.id
                && $0.partID == selectedItem.partID
                && abs($0.offsetInQuarterNotes - selectedItem.offsetInQuarterNotes)
                    < NotationMeasureTiming.timelineTolerance
        }) else {
            return nil
        }

        let selected = orderedItems[selectedIndex]
        let startOffset = selected.offsetInQuarterNotes
        let sourceEnd = startOffset + selected.durationInQuarterNotes
        let targetEnd = startOffset + selectedDuration.durationInQuarterNotes
        let measureLength = NotationMeasureTiming.quarterLength(for: measure.attributes.timeSignature)
        guard targetEnd <= measureLength + NotationMeasureTiming.timelineTolerance,
              selected.kind == .rest || selected.pitch != nil
        else {
            return nil
        }

        var consumedEnd = sourceEnd
        var suffixIndex = orderedItems.index(after: selectedIndex)
        while suffixIndex < orderedItems.endIndex {
            let item = orderedItems[suffixIndex]
            guard item.kind == .rest,
                  item.partID == selected.partID,
                  abs(item.offsetInQuarterNotes - consumedEnd) < NotationMeasureTiming.timelineTolerance
            else { break }

            consumedEnd = item.offsetInQuarterNotes + item.durationInQuarterNotes
            suffixIndex = orderedItems.index(after: suffixIndex)
        }

        guard targetEnd <= consumedEnd + NotationMeasureTiming.timelineTolerance else {
            return nil
        }

        let replacement = NotationMeasureItem(
            id: selected.isSynthesized ? UUID().uuidString : selected.id,
            partID: selected.partID,
            kind: selected.kind,
            pitch: selected.pitch,
            measureNumber: measure.number,
            measureStartTime: measure.startTime,
            offsetInQuarterNotes: startOffset,
            durationInQuarterNotes: selectedDuration.durationInQuarterNotes,
            displayDuration: selectedDuration
        )
        let fillerEnd = max(sourceEnd, consumedEnd)
        let fillerItems = NotationRestItemFactory.metricAwareRestItems(
            in: measure,
            partID: selected.partID,
            startOffset: targetEnd,
            remaining: fillerEnd - targetEnd
        )

        let items = Array(orderedItems[..<selectedIndex])
            + [replacement]
            + fillerItems
            + Array(orderedItems[suffixIndex...])
        return Replacement(items: items, selectedItem: replacement)
    }

    private static func itemSort(_ lhs: NotationMeasureItem, _ rhs: NotationMeasureItem) -> Bool {
        if abs(lhs.offsetInQuarterNotes - rhs.offsetInQuarterNotes) > NotationMeasureTiming.timelineTolerance {
            return lhs.offsetInQuarterNotes < rhs.offsetInQuarterNotes
        }
        return lhs.id < rhs.id
    }
}
