import Foundation

extension AudioPlayerViewModel {
    var canShowNotationWindow: Bool {
        duration > 0
    }

    var canChangeNotationDuration: Bool {
        duration > 0 && (isNotationEntryModeEnabled || canEditSelectedNotationItem)
    }

    var canChangeSelectedNotationNotePitch: Bool {
        canChangeSelectedNotationNotePitch(byStaffPositionDelta: -1)
            || canChangeSelectedNotationNotePitch(byStaffPositionDelta: 1)
    }

    func setNotationDurationDenominator(_ denominator: Int) {
        notationDurationDenominator = NotationDuration.normalizedDenominator(denominator)
        guard !isNotationEntryModeEnabled else { return }
        changeSelectedNotationItemDuration(to: NotationDuration(denominator: notationDurationDenominator))
    }

    var isNotationEntryModeEnabled: Bool {
        notationEntryMode != nil
    }

    var isNotationNoteEntryModeEnabled: Bool {
        notationEntryMode == .note
    }

    var isNotationRestEntryModeEnabled: Bool {
        notationEntryMode == .rest
    }

    func toggleNotationNoteEntryMode() {
        setNotationNoteEntryModeEnabled(!isNotationNoteEntryModeEnabled)
    }

    func setNotationNoteEntryModeEnabled(_ isEnabled: Bool) {
        setNotationEntryMode(isEnabled ? .note : nil)
    }

    func toggleNotationRestEntryMode() {
        setNotationEntryMode(isNotationRestEntryModeEnabled ? nil : .rest)
    }

    func setNotationRestEntryModeEnabled(_ isEnabled: Bool) {
        setNotationEntryMode(isEnabled ? .rest : nil)
    }

    func clearNotationEntryMode() {
        setNotationEntryMode(nil)
    }

    private func setNotationEntryMode(_ mode: NotationEntryMode?) {
        let resolvedMode = duration > 0 ? mode : nil
        guard notationEntryMode != resolvedMode else { return }

        notationEntryMode = resolvedMode
        if resolvedMode != nil {
            selectedNotationMeasures = []
            notationMeasureSelectionAnchor = nil
            selectedHarmonySymbolID = nil
            selectedNotationItem = nil
            pendingHarmonyEditorRequest = nil
        }
    }

    func clearNotationNoteEntryMode() {
        clearNotationEntryMode()
    }

    @discardableResult
    func requestEditSelectedNotationItem() -> Bool {
        guard duration > 0,
              let selection = selectedNotationItem,
              let placement = harmonyPlacement(for: selection)
        else {
            clearNotationItemSelection()
            return false
        }

        selectedNotationItem = NotationItemSelection(measure: placement.measure, item: placement.item)
        selectedHarmonySymbolID = harmonySymbolID(at: placement.harmonyPlacement.time)
        pendingHarmonyEditorRequest = HarmonyEditorRequest(time: placement.harmonyPlacement.time)
        return true
    }

    func selectHarmonySymbol(id: HarmonySymbol.ID?) {
        selectedHarmonySymbolID = availableHarmonySymbolID(id)
    }

    func selectNotationItem(
        _ selection: NotationItemSelection?,
        shouldAudition: Bool = false
    ) {
        guard let selection else {
            clearNotationItemSelection()
            return
        }

        guard let match = notationItemMatch(for: selection) else {
            clearNotationItemSelection()
            return
        }

        let canonicalSelection = NotationItemSelection(measure: match.measure, item: match.item)
        selectedNotationItem = canonicalSelection
        selectedNotationMeasures = []
        notationMeasureSelectionAnchor = nil
        notationEntryMode = nil
        if let placement = harmonyPlacement(for: canonicalSelection) {
            selectedHarmonySymbolID = harmonySymbolID(at: placement.harmonyPlacement.time)
        } else {
            selectedHarmonySymbolID = nil
        }

        if shouldAudition,
           match.item.kind == .note,
           let pitch = match.item.pitch {
            try? notationNoteAuditioner.audition(pitch: pitch)
        }
    }

    func clearNotationItemSelection() {
        selectedNotationItem = nil
    }

    var canCopySelectedNotationMeasure: Bool {
        !currentSelectedNotationMeasures().isEmpty
    }

    var canPasteNotationMeasureClipboard: Bool {
        guard let clipboard = notationMeasureClipboard, !clipboard.measures.isEmpty else { return false }
        return currentPasteTargetMeasures(forClipboardMeasureCount: clipboard.measures.count) != nil
    }

    var hasSelectedNotationMeasures: Bool {
        !selectedNotationMeasures.isEmpty
    }

    var canEditSelectedNotationItem: Bool {
        duration > 0 && selectedNotationItem != nil
    }

    func selectNotationMeasure(_ measure: ScoreMeasure?, extendingSelection: Bool = false) {
        guard let measure else {
            clearNotationMeasureSelection()
            return
        }

        if extendingSelection, let anchor = notationMeasureSelectionAnchor {
            let scoreMeasures = currentNotationScoreMeasures()
            if let anchorIndex = scoreMeasures.firstIndex(where: anchor.matches),
               let measureIndex = scoreMeasures.firstIndex(where: { NotationMeasureSelection(measure: measure).matches($0) }) {
                let range = min(anchorIndex, measureIndex)...max(anchorIndex, measureIndex)
                selectedNotationMeasures = range.map { NotationMeasureSelection(measure: scoreMeasures[$0]) }
            } else {
                selectedNotationMeasures = [NotationMeasureSelection(measure: measure)]
                notationMeasureSelectionAnchor = NotationMeasureSelection(measure: measure)
            }
        } else {
            selectedNotationMeasures = [NotationMeasureSelection(measure: measure)]
            notationMeasureSelectionAnchor = NotationMeasureSelection(measure: measure)
        }
        selectedHarmonySymbolID = nil
        selectedNotationItem = nil
        notationEntryMode = nil
        locatePlaybackMarkerAtFirstSelectedNotationMeasure()
    }

    func clearNotationMeasureSelection() {
        selectedNotationMeasures = []
        notationMeasureSelectionAnchor = nil
        selectedHarmonySymbolID = nil
        selectedNotationItem = nil
    }

    @discardableResult
    func insertNotationNote(_ placement: NotationNotePlacement) -> Bool {
        guard duration > 0,
              let measure = currentNotationScoreMeasures().first(where: {
                  $0.number == placement.measure.number
                      && abs($0.startTime - placement.measure.startTime) < NotationMeasureTiming.timelineTolerance
                      && abs($0.endTime - placement.measure.endTime) < NotationMeasureTiming.timelineTolerance
              }),
              let restSpan = NotationNotePlacementResolver.restSpan(in: measure, matching: placement)
        else {
            return false
        }

        let noteItem = NotationMeasureItem(
            kind: .note,
            pitch: placement.pitch,
            measureNumber: measure.number,
            measureStartTime: measure.startTime,
            offsetInQuarterNotes: restSpan.startOffsetInQuarterNotes,
            durationInQuarterNotes: placement.durationInQuarterNotes,
            displayDuration: placement.displayDuration
        )
        let recomposedItems = NotationEntryRecomposer.recomposedItems(
            in: measure,
            replacing: restSpan,
            with: noteItem
        )

        performUndoableEdit("Add Notation Note") {
            replaceNotationMeasureItems(in: measure, with: recomposedItems)
            selectedNotationMeasures = []
            notationMeasureSelectionAnchor = nil
            selectedHarmonySymbolID = nil
            reselectNotationItem(
                inMeasureNumber: measure.number,
                measureStartTime: measure.startTime,
                itemID: noteItem.id
            )
        }

        try? notationNoteAuditioner.audition(pitch: placement.pitch)
        return true
    }

    @discardableResult
    func insertNotationRest(_ placement: NotationRestPlacement) -> Bool {
        guard duration > 0,
              let measure = currentNotationScoreMeasures().first(where: {
                  $0.number == placement.measure.number
                      && abs($0.startTime - placement.measure.startTime) < NotationMeasureTiming.timelineTolerance
                      && abs($0.endTime - placement.measure.endTime) < NotationMeasureTiming.timelineTolerance
              }),
              let restSpan = NotationNotePlacementResolver.restSpan(in: measure, matching: placement),
              let targetRest = restSpan.rests.first
        else {
            return false
        }

        let restItem = NotationMeasureItem(
            kind: .rest,
            measureNumber: measure.number,
            measureStartTime: measure.startTime,
            offsetInQuarterNotes: restSpan.startOffsetInQuarterNotes,
            durationInQuarterNotes: placement.durationInQuarterNotes,
            displayDuration: placement.displayDuration
        )

        if !targetRest.isSynthesized,
           abs(targetRest.offsetInQuarterNotes - restItem.offsetInQuarterNotes) < NotationMeasureTiming.timelineTolerance,
           abs(targetRest.durationInQuarterNotes - restItem.durationInQuarterNotes) < NotationMeasureTiming.timelineTolerance,
           targetRest.displayDuration == restItem.displayDuration {
            selectedNotationMeasures = []
            notationMeasureSelectionAnchor = nil
            selectedHarmonySymbolID = nil
            selectedNotationItem = NotationItemSelection(measure: measure, item: targetRest)
            return true
        }

        let recomposedItems = NotationEntryRecomposer.recomposedItems(
            in: measure,
            replacing: restSpan,
            with: restItem
        )

        performUndoableEdit("Add Notation Rest") {
            replaceNotationMeasureItems(in: measure, with: recomposedItems)
            selectedNotationMeasures = []
            notationMeasureSelectionAnchor = nil
            selectedHarmonySymbolID = nil
            reselectNotationItem(
                inMeasureNumber: measure.number,
                measureStartTime: measure.startTime,
                itemID: restItem.id
            )
        }

        return true
    }

    @discardableResult
    func changeSelectedNotationNotePitch(
        to pitch: NotationPitch,
        shouldAudition: Bool = true
    ) -> Bool {
        guard let selection = selectedNotationItem,
              let match = notationItemMatch(for: selection),
              match.item.kind == .note,
              match.item.pitch != nil,
              match.item.pitch != pitch
        else {
            return false
        }

        let measure = match.measure
        let item = match.item
        let updatedItem = NotationMeasureItem(
            id: item.id,
            kind: .note,
            pitch: pitch,
            measureNumber: item.measureNumber,
            measureStartTime: item.measureStartTime,
            offsetInQuarterNotes: item.offsetInQuarterNotes,
            durationInQuarterNotes: item.durationInQuarterNotes,
            displayDuration: item.displayDuration
        )

        performUndoableEdit("Change Notation Note Pitch") {
            replaceNotationItem(
                in: measure,
                matching: item,
                with: updatedItem
            )
            reselectNotationItem(
                inMeasureNumber: measure.number,
                measureStartTime: measure.startTime,
                itemID: updatedItem.id
            )
        }

        if shouldAudition {
            try? notationNoteAuditioner.audition(pitch: pitch)
        }
        return true
    }

    func auditionNotationNotePitch(_ pitch: NotationPitch) {
        try? notationNoteAuditioner.audition(pitch: pitch)
    }

    func canChangeSelectedNotationNotePitch(byStaffPositionDelta staffPositionDelta: Int) -> Bool {
        selectedNotationNotePitchChange(byStaffPositionDelta: staffPositionDelta) != nil
    }

    @discardableResult
    func changeSelectedNotationNotePitch(byStaffPositionDelta staffPositionDelta: Int) -> Bool {
        guard let pitch = selectedNotationNotePitchChange(byStaffPositionDelta: staffPositionDelta) else {
            return false
        }

        return changeSelectedNotationNotePitch(to: pitch)
    }

    @discardableResult
    func deleteSelectedNotationNote() -> Bool {
        guard let selection = selectedNotationItem,
              let match = notationItemMatch(for: selection),
              match.item.kind == .note
        else {
            return false
        }

        let measure = match.measure
        let item = match.item
        let replacementRest = NotationMeasureItem(
            id: item.id,
            kind: .rest,
            pitch: nil,
            measureNumber: item.measureNumber,
            measureStartTime: item.measureStartTime,
            offsetInQuarterNotes: item.offsetInQuarterNotes,
            durationInQuarterNotes: item.durationInQuarterNotes,
            displayDuration: item.displayDuration
        )

        performUndoableEdit("Delete Notation Note") {
            replaceNotationItem(
                in: measure,
                matching: item,
                with: replacementRest
            )
            selectedNotationItem = nil
        }

        return true
    }

    func clearNotationMeasureSelectionAndClipboard() {
        clearNotationMeasureSelection()
        notationMeasureClipboard = nil
    }

    @discardableResult
    func copySelectedNotationMeasure() -> Bool {
        guard let measures = validatedSelectedNotationMeasures() else { return false }

        notationMeasureClipboard = NotationMeasureClipboard(
            measures: measures.map { measure in
                NotationMeasureClipboardMeasure(
                    items: notationClipboardItems(in: measure),
                    notationItems: notationClipboardNotationItems(in: measure)
                )
            }
        )
        return true
    }

    @discardableResult
    func pasteNotationMeasureClipboard() -> Bool {
        guard let clipboard = notationMeasureClipboard,
              let targetMeasures = validatedPasteTargetMeasures(forClipboardMeasureCount: clipboard.measures.count)
        else {
            return false
        }

        let pastedItemsByMeasure = zip(targetMeasures, clipboard.measures).map { targetMeasure, sourceMeasure in
            sourceMeasure.items
                .filter {
                    NotationMeasureTiming.isValidHarmonyOffset(
                        $0.offsetInQuarterNotes,
                        in: targetMeasure.attributes.timeSignature
                    )
                }
                .sorted(by: notationClipboardItemSort)
        }
        let pastedNotationItemsByMeasure = zip(targetMeasures, clipboard.measures).map { targetMeasure, sourceMeasure in
            sourceMeasure.notationItems
                .filter {
                    NotationMeasureTiming.isValidHarmonyOffset(
                        $0.offsetInQuarterNotes,
                        in: targetMeasure.attributes.timeSignature
                    )
                    && ($0.kind == .rest || $0.pitch != nil)
                }
                .sorted(by: notationClipboardNotationItemSort)
        }
        let currentItemsByMeasure = targetMeasures.map { notationClipboardItems(in: $0) }
        let currentNotationItemsByMeasure = targetMeasures.map { notationClipboardNotationItems(in: $0) }

        guard currentItemsByMeasure != pastedItemsByMeasure
                || currentNotationItemsByMeasure != pastedNotationItemsByMeasure
        else {
            selectedHarmonySymbolID = nil
            selectedNotationItem = nil
            selectedNotationMeasures = targetMeasures.map(NotationMeasureSelection.init)
            notationMeasureSelectionAnchor = selectedNotationMeasures.first
            return true
        }

        performUndoableEdit(targetMeasures.count == 1 ? "Paste Measure" : "Paste Measures") {
            harmonySymbols.removeAll { symbol in
                targetMeasures.contains { targetMeasure in
                    NotationMeasureTiming.containsEventTime(symbol.time, in: targetMeasure)
                }
            }
            notationItems.removeAll { item in
                targetMeasures.contains { targetMeasure in
                    item.measureNumber == targetMeasure.number
                        && abs(item.measureStartTime - targetMeasure.startTime) < NotationMeasureTiming.timelineTolerance
                }
            }

            for ((targetMeasure, pastedItems), pastedNotationItems) in zip(zip(targetMeasures, pastedItemsByMeasure), pastedNotationItemsByMeasure) {
                harmonySymbols.append(contentsOf: pastedItems.map { item in
                    HarmonySymbol(
                        time: NotationMeasureTiming.time(
                            forQuarterOffset: item.offsetInQuarterNotes,
                            in: targetMeasure
                        ),
                        measureNumber: targetMeasure.number,
                        offsetInQuarterNotes: item.offsetInQuarterNotes,
                        rawText: item.rawText
                    )
                })
                notationItems.append(contentsOf: pastedNotationItems.map { item in
                    NotationMeasureItem(
                        kind: item.kind,
                        pitch: item.kind == .note ? item.pitch : nil,
                        measureNumber: targetMeasure.number,
                        measureStartTime: targetMeasure.startTime,
                        offsetInQuarterNotes: item.offsetInQuarterNotes,
                        durationInQuarterNotes: item.durationInQuarterNotes,
                        displayDuration: item.displayDuration
                    )
                })
            }

            harmonySymbols = ProjectStateNormalizer.normalizedHarmonySymbols(harmonySymbols, duration: duration)
            notationItems = ProjectStateNormalizer.normalizedNotationItems(notationItems, duration: duration)
            selectedHarmonySymbolID = nil
            selectedNotationItem = nil
            selectedNotationMeasures = targetMeasures.map(NotationMeasureSelection.init)
            notationMeasureSelectionAnchor = selectedNotationMeasures.first
        }

        return true
    }

    func saveHarmonySymbol(_ symbol: HarmonySymbol) {
        guard duration > 0,
              let placement = harmonyPlacement(for: symbol.time)
        else {
            return
        }

        let trimmedText = symbol.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            deleteHarmonySymbol(id: symbol.id)
            return
        }

        let existingIndex = harmonySymbols.firstIndex { $0.id == symbol.id }
        let duplicateIndex = harmonySymbols.firstIndex {
            $0.id != symbol.id && sameHarmonyPosition($0.time, placement.time)
        }
        let actionName = existingIndex == nil && duplicateIndex == nil ? "Add Harmony" : "Edit Harmony"

        performUndoableEdit(actionName) {
            let normalizedSymbol = HarmonySymbol(
                id: duplicateIndex.map { harmonySymbols[$0].id } ?? symbol.id,
                time: placement.time,
                measureNumber: placement.measureNumber,
                offsetInQuarterNotes: placement.offsetInQuarterNotes,
                rawText: symbol.rawText
            )

            if let existingIndex, let duplicateIndex {
                harmonySymbols[duplicateIndex] = normalizedSymbol
                harmonySymbols.remove(at: existingIndex)
            } else if let existingIndex {
                harmonySymbols[existingIndex] = normalizedSymbol
            } else if let duplicateIndex {
                harmonySymbols[duplicateIndex] = normalizedSymbol
            } else {
                harmonySymbols.append(normalizedSymbol)
            }

            harmonySymbols = ProjectStateNormalizer.normalizedHarmonySymbols(harmonySymbols, duration: duration)
            selectedHarmonySymbolID = normalizedSymbol.id
        }
    }

    func deleteHarmonySymbol(id: HarmonySymbol.ID) {
        performUndoableEdit("Delete Harmony") {
            harmonySymbols.removeAll { $0.id == id }
            if selectedHarmonySymbolID == id {
                selectedHarmonySymbolID = nil
            }
        }
    }

    func adjacentHarmonyPlacement(
        from time: TimeInterval,
        direction: HarmonyNavigationDirection
    ) -> HarmonyPlacement? {
        NotationViewportFactory().adjacentHarmonyPlacement(
            from: time,
            direction: direction,
            tempoMap: tempoMap,
            duration: duration,
            notationItems: notationItems
        )
    }

    private func harmonyPlacement(
        for time: TimeInterval
    ) -> HarmonyPlacement? {
        NotationViewportFactory().harmonyPlacement(
            for: time,
            tempoMap: tempoMap,
            duration: duration
        )
    }

    private func harmonyPlacement(
        for selection: NotationItemSelection
    ) -> (measure: ScoreMeasure, item: NotationMeasureItem, harmonyPlacement: HarmonyPlacement)? {
        guard let match = notationItemMatch(for: selection) else { return nil }
        guard NotationMeasureTiming.isValidHarmonyOffset(
            selection.offsetInQuarterNotes,
            in: match.measure.attributes.timeSignature
        ) else {
            return nil
        }

        let time = NotationMeasureTiming.time(forQuarterOffset: match.item.offsetInQuarterNotes, in: match.measure)
        return (
            match.measure,
            match.item,
            HarmonyPlacement(
                time: max(0, min(time, max(0, duration.nextDown))),
                measureNumber: match.measure.number,
                offsetInQuarterNotes: match.item.offsetInQuarterNotes
            )
        )
    }

    private func notationItemMatch(
        for selection: NotationItemSelection
    ) -> (measure: ScoreMeasure, item: NotationMeasureItem)? {
        for measure in currentNotationScoreMeasures() {
            guard measure.number == selection.measureNumber else { continue }
            if let exact = measure.notationItems.first(where: { selection.matches(measure, item: $0) }) {
                return (measure, exact)
            }
            if let byOffset = measure.notationItems.first(where: {
                abs($0.offsetInQuarterNotes - selection.offsetInQuarterNotes) < NotationMeasureTiming.timelineTolerance
            }) {
                return (measure, byOffset)
            }
        }
        return nil
    }

    private func changeSelectedNotationItemDuration(to selectedDuration: NotationDuration) {
        guard let selection = selectedNotationItem,
              let match = notationItemMatch(for: selection)
        else { return }

        let measure = match.measure
        let measureLength = NotationMeasureTiming.quarterLength(for: measure.attributes.timeSignature)
        let startOffset = match.item.offsetInQuarterNotes
        let remaining = measureLength - startOffset
        guard remaining > NotationMeasureTiming.timelineTolerance else { return }

        performUndoableEdit("Change Notation Duration") {
            let prefix = measure.notationItems
                .filter { $0.offsetInQuarterNotes < startOffset - NotationMeasureTiming.timelineTolerance }
                .filter { !$0.isSynthesized }

            let suffix = notationDurationSuffix(
                measure: measure,
                selectedItem: match.item,
                startOffset: startOffset,
                remaining: remaining,
                selectedDuration: selectedDuration
            )
            replaceNotationMeasureItems(in: measure, with: prefix + suffix)

            if let selected = suffix.first {
                selectedNotationItem = NotationItemSelection(measure: measure, item: selected)
            }
        }
    }

    private func notationDurationSuffix(
        measure: ScoreMeasure,
        selectedItem: NotationMeasureItem,
        startOffset: Double,
        remaining: Double,
        selectedDuration: NotationDuration
    ) -> [NotationMeasureItem] {
        var items: [NotationMeasureItem] = []
        var cursor = startOffset
        var rest = remaining
        let selectedLength = selectedDuration.durationInQuarterNotes

        if selectedItem.kind == .note {
            guard selectedLength <= rest + NotationMeasureTiming.timelineTolerance,
                  let pitch = selectedItem.pitch
            else {
                return [selectedItem.persistedCopy()]
            }

            let duration = min(selectedLength, rest)
            items.append(NotationMeasureItem(
                id: selectedItem.id,
                kind: .note,
                pitch: pitch,
                measureNumber: measure.number,
                measureStartTime: measure.startTime,
                offsetInQuarterNotes: cursor,
                durationInQuarterNotes: duration,
                displayDuration: selectedDuration
            ))
            cursor += duration
            rest -= duration
            items.append(contentsOf: fillerNotationItems(
                measure: measure,
                startOffset: cursor,
                remaining: rest
            ))
            return items
        }

        let selectedCount = min(2, Int(floor((rest + NotationMeasureTiming.timelineTolerance) / selectedLength)))

        if selectedCount > 0 {
            for _ in 0..<selectedCount {
                let duration = min(selectedLength, rest)
                items.append(NotationRestItemFactory.restItem(
                    measureNumber: measure.number,
                    measureStartTime: measure.startTime,
                    offsetInQuarterNotes: cursor,
                    durationInQuarterNotes: duration,
                    displayDuration: selectedDuration
                ))
                cursor += duration
                rest -= duration
            }
        } else if let largest = largestNotationDuration(fitting: rest) {
            let duration = min(largest.durationInQuarterNotes, rest)
            items.append(NotationRestItemFactory.restItem(
                measureNumber: measure.number,
                measureStartTime: measure.startTime,
                offsetInQuarterNotes: cursor,
                durationInQuarterNotes: duration,
                displayDuration: largest
            ))
            cursor += duration
            rest -= duration
        }

        items.append(contentsOf: fillerNotationItems(
            measure: measure,
            startOffset: cursor,
            remaining: rest
        ))
        return items
    }

    private func fillerNotationItems(
        measure: ScoreMeasure,
        startOffset: Double,
        remaining: Double
    ) -> [NotationMeasureItem] {
        NotationRestItemFactory.restItems(
            measureNumber: measure.number,
            measureStartTime: measure.startTime,
            startOffset: startOffset,
            remaining: remaining
        )
    }

    private func largestNotationDuration(fitting remaining: Double) -> NotationDuration? {
        NotationRestItemFactory.greedySegments(startOffset: 0, remaining: remaining).first?.displayDuration
    }

    private func harmonySymbolID(at time: TimeInterval) -> HarmonySymbol.ID? {
        harmonySymbols.first { sameHarmonyPosition($0.time, time) }?.id
    }

    private func sameHarmonyPosition(_ lhs: TimeInterval, _ rhs: TimeInterval) -> Bool {
        abs(lhs - rhs) < 0.000_001
    }

    private func notationClipboardItemSort(
        _ lhs: NotationMeasureClipboardItem,
        _ rhs: NotationMeasureClipboardItem
    ) -> Bool {
        if abs(lhs.offsetInQuarterNotes - rhs.offsetInQuarterNotes) > NotationMeasureTiming.timelineTolerance {
            return lhs.offsetInQuarterNotes < rhs.offsetInQuarterNotes
        }

        return lhs.rawText < rhs.rawText
    }

    private func notationClipboardNotationItemSort(
        _ lhs: NotationMeasureClipboardNotationItem,
        _ rhs: NotationMeasureClipboardNotationItem
    ) -> Bool {
        if abs(lhs.offsetInQuarterNotes - rhs.offsetInQuarterNotes) > NotationMeasureTiming.timelineTolerance {
            return lhs.offsetInQuarterNotes < rhs.offsetInQuarterNotes
        }

        return lhs.displayDuration.denominator < rhs.displayDuration.denominator
    }

    private func notationClipboardItems(in measure: ScoreMeasure) -> [NotationMeasureClipboardItem] {
        harmonySymbols
            .compactMap { symbol -> (HarmonySymbol, Double)? in
                guard NotationMeasureTiming.containsEventTime(symbol.time, in: measure) else {
                    return nil
                }

                return (symbol, NotationMeasureTiming.quarterOffset(for: symbol.time, in: measure))
            }
            .sorted {
                if abs($0.1 - $1.1) > NotationMeasureTiming.timelineTolerance {
                    return $0.1 < $1.1
                }

                return $0.0.id.uuidString < $1.0.id.uuidString
            }
            .map { symbol, offset in
                NotationMeasureClipboardItem(
                    offsetInQuarterNotes: offset,
                    rawText: symbol.rawText
                )
            }
    }

    private func notationClipboardNotationItems(in measure: ScoreMeasure) -> [NotationMeasureClipboardNotationItem] {
        measure.notationItems
            .filter { !$0.isSynthesized }
            .map {
                NotationMeasureClipboardNotationItem(
                    kind: $0.kind,
                    pitch: $0.pitch,
                    offsetInQuarterNotes: $0.offsetInQuarterNotes,
                    durationInQuarterNotes: $0.durationInQuarterNotes,
                    displayDuration: $0.displayDuration
                )
            }
            .sorted(by: notationClipboardNotationItemSort)
    }

    private func validatedSelectedNotationMeasures() -> [ScoreMeasure]? {
        let measures = currentSelectedNotationMeasures()
        guard !measures.isEmpty else {
            clearNotationMeasureSelection()
            return nil
        }

        selectedNotationMeasures = measures.map(NotationMeasureSelection.init)
        if let anchor = notationMeasureSelectionAnchor,
           measures.contains(where: anchor.matches) {
            notationMeasureSelectionAnchor = anchor
        } else {
            notationMeasureSelectionAnchor = selectedNotationMeasures.first
        }
        return measures
    }

    private func validatedPasteTargetMeasures(forClipboardMeasureCount clipboardMeasureCount: Int) -> [ScoreMeasure]? {
        guard let targetMeasures = currentPasteTargetMeasures(forClipboardMeasureCount: clipboardMeasureCount) else {
            clearNotationMeasureSelection()
            return nil
        }

        selectedNotationMeasures = targetMeasures.map(NotationMeasureSelection.init)
        notationMeasureSelectionAnchor = selectedNotationMeasures.first
        return targetMeasures
    }

    private func currentSelectedNotationMeasures() -> [ScoreMeasure] {
        guard !selectedNotationMeasures.isEmpty else { return [] }

        let scoreMeasures = currentNotationScoreMeasures()
        guard let firstIndex = scoreMeasures.firstIndex(where: selectedNotationMeasures[0].matches) else { return [] }
        let expectedRange = firstIndex..<(firstIndex + selectedNotationMeasures.count)
        guard expectedRange.upperBound <= scoreMeasures.endIndex else { return [] }
        let expectedMeasures = expectedRange.map { scoreMeasures[$0] }

        return zip(expectedMeasures, selectedNotationMeasures).allSatisfy { measure, selection in
            selection.matches(measure)
        } ? expectedMeasures : []
    }

    private func currentPasteTargetMeasures(forClipboardMeasureCount clipboardMeasureCount: Int) -> [ScoreMeasure]? {
        guard clipboardMeasureCount > 0 else { return nil }
        let selectedMeasures = currentSelectedNotationMeasures()
        guard let firstSelectedMeasure = selectedMeasures.first else { return nil }

        let scoreMeasures = currentNotationScoreMeasures()
        let firstSelection = NotationMeasureSelection(measure: firstSelectedMeasure)
        guard let startIndex = scoreMeasures.firstIndex(where: { firstSelection.matches($0) }) else {
            return nil
        }

        let targetCount = min(clipboardMeasureCount, scoreMeasures.count - startIndex)
        guard targetCount > 0 else { return nil }
        return (startIndex..<(startIndex + targetCount)).map { scoreMeasures[$0] }
    }

    private func currentNotationScoreMeasures() -> [ScoreMeasure] {
        NotationViewportFactory().scoreState(
            tempoMap: tempoMap,
            duration: duration,
            currentTime: currentTime,
            playbackMarkerTime: playbackMarkerTime,
            isPlaying: playbackState == .playing,
            keyName: effectiveKeyName,
            notationItems: notationItems,
            harmonySymbols: harmonySymbols,
            notes: notes
        ).measures
    }

    private func replaceNotationItem(
        in measure: ScoreMeasure,
        matching targetItem: NotationMeasureItem,
        with replacementItem: NotationMeasureItem
    ) {
        let updatedItems = measure.notationItems.map { item in
            item.id == targetItem.id ? replacementItem : item.persistedCopy()
        }
        replaceNotationMeasureItems(in: measure, with: updatedItems)
    }

    private func replaceNotationMeasureItems(
        in measure: ScoreMeasure,
        with replacementItems: [NotationMeasureItem]
    ) {
        notationItems.removeAll {
            $0.measureNumber == measure.number
                && abs($0.measureStartTime - measure.startTime) < NotationMeasureTiming.timelineTolerance
        }
        notationItems.append(contentsOf: replacementItems)
        notationItems = ProjectStateNormalizer.normalizedNotationItems(notationItems, duration: duration)
    }

    private func selectedNotationNotePitchChange(byStaffPositionDelta staffPositionDelta: Int) -> NotationPitch? {
        guard let selection = selectedNotationItem,
              let match = notationItemMatch(for: selection),
              match.item.kind == .note,
              let pitch = match.item.pitch
        else {
            return nil
        }

        return NotationPitchMapper.adjacentPitch(
            from: pitch,
            staffPositionDelta: staffPositionDelta,
            keySignature: match.measure.attributes.keySignature
        )
    }

    private func reselectNotationItem(
        inMeasureNumber measureNumber: Int,
        measureStartTime: TimeInterval,
        itemID: String
    ) {
        guard let updatedMeasure = currentNotationScoreMeasures().first(where: {
            $0.number == measureNumber
                && abs($0.startTime - measureStartTime) < NotationMeasureTiming.timelineTolerance
        }), let selected = updatedMeasure.notationItems.first(where: { $0.id == itemID }) else {
            selectedNotationItem = nil
            return
        }

        selectedNotationItem = NotationItemSelection(measure: updatedMeasure, item: selected)
    }

    private func locatePlaybackMarkerAtFirstSelectedNotationMeasure() {
        guard let firstSelectedMeasure = currentSelectedNotationMeasures().first else { return }
        locatePlaybackMarkerExactly(to: firstSelectedMeasure.startTime)
    }

}
