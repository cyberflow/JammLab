import Foundation

extension AudioPlayerViewModel {
    var canShowNotationWindow: Bool {
        duration > 0
    }

    var availableNotationParts: [NotationPartDescriptor] {
        [.main] + knownStemNotationPartTypes().map(NotationPartDescriptor.stem)
    }

    var visibleNotationParts: [NotationPartDescriptor] {
        let visibleIDs = normalizedVisibleNotationPartIDs()
        return availableNotationParts.filter { visibleIDs.contains($0.id) }
    }

    func isStemNotationTrackCollapsed(_ stemType: StemType) -> Bool {
        stemNotationTrackCollapsed[stemType] ?? true
    }

    func toggleNotationWindowPartVisibility(_ partID: NotationPartID) {
        var next = normalizedVisibleNotationPartIDs()
        if next.contains(partID) {
            next.remove(partID)
        } else {
            next.insert(partID)
        }

        let normalized = normalizedVisibleNotationPartIDs(from: next)
        guard normalized != visibleNotationPartIDs else { return }
        visibleNotationPartIDs = normalized
        refreshProjectModifiedState()
    }

    func normalizedVisibleNotationPartIDs(from rawPartIDs: Set<NotationPartID>? = nil) -> Set<NotationPartID> {
        let allowedPartIDs = Set(availableNotationParts.map(\.id))
        var normalized = (rawPartIDs ?? visibleNotationPartIDs).intersection(allowedPartIDs)
        if normalized.isEmpty {
            normalized = allowedPartIDs.contains(.main) ? [.main] : Set(allowedPartIDs.prefix(1))
        }
        return normalized
    }

    func notationClef(for partID: NotationPartID) -> Clef {
        NotationPartClefOverrides.clef(for: partID, in: notationPartClefs)
    }

    func setNotationClef(_ clef: Clef, for partID: NotationPartID) {
        let sourceClef = notationClef(for: partID)
        guard sourceClef != clef else { return }

        let octaveDelta = clef.notationMetrics.storedPitchOctaveOffset
            - sourceClef.notationMetrics.storedPitchOctaveOffset
        performUndoableEdit("Change Notation Clef") {
            if clef == .treble {
                notationPartClefs.removeValue(forKey: partID)
            } else {
                notationPartClefs[partID] = clef
            }

            notationItems = notationItems.map { item in
                guard item.partID == partID,
                      !item.isSynthesized,
                      item.kind == .note,
                      var pitch = item.pitch
                else {
                    return item
                }

                pitch.octave += octaveDelta
                var transposed = item
                transposed.pitch = pitch
                return transposed
            }
            notationItems = ProjectStateNormalizer.normalizedNotationItems(
                notationItems,
                duration: duration
            )
            refreshNotationSelections(for: partID)
        }
    }

    private func knownStemNotationPartTypes() -> [StemType] {
        let stemTypes = Set(stemFiles.map(\.type))
        let notationStemTypes = Set(notationItems.compactMap(\.partID.stemType))
        let collapsedStemTypes = Set(stemNotationTrackCollapsed.keys)
        let visibleStemTypes = Set(visibleNotationPartIDs.compactMap(\.stemType))
        let knownTypes = stemTypes
            .union(notationStemTypes)
            .union(collapsedStemTypes)
            .union(visibleStemTypes)

        return StemType.allCases.filter { knownTypes.contains($0) }
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
        setNotationRestEntryModeEnabled(!isNotationRestEntryModeEnabled)
    }

    func setNotationRestEntryModeEnabled(_ isEnabled: Bool) {
        if isEnabled, duration > 0 {
            _ = replaceSelectedNotationNoteWithRest(
                undoActionName: "Convert Notation Note to Rest"
            )
        }
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
              let selection = selectedNotationItem
        else {
            clearNotationItemSelection()
            return false
        }
        guard selection.partID.isMain else { return false }
        guard let placement = harmonyPlacement(for: selection) else {
            clearNotationItemSelection()
            return false
        }

        selectedNotationItem = NotationItemSelection(measure: placement.measure, item: placement.item, partID: selection.partID)
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

        let canonicalSelection = NotationItemSelection(measure: match.measure, item: match.item, partID: selection.partID)
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

    var canEditHarmonyAtSelectedNotationItem: Bool {
        guard duration > 0,
              let selection = selectedNotationItem,
              selection.partID.isMain
        else { return false }

        return harmonyPlacement(for: selection) != nil
    }

    func selectNotationMeasure(
        _ measure: ScoreMeasure?,
        extendingSelection: Bool = false,
        partID: NotationPartID = .main
    ) {
        guard let measure else {
            clearNotationMeasureSelection()
            return
        }

        if extendingSelection, let anchor = notationMeasureSelectionAnchor {
            let scoreMeasures = currentNotationScoreMeasures(partID: partID)
            if anchor.partID == partID,
               let anchorIndex = scoreMeasures.firstIndex(where: { anchor.matches($0, partID: partID) }),
               let measureIndex = scoreMeasures.firstIndex(where: { NotationMeasureSelection(measure: measure, partID: partID).matches($0, partID: partID) }) {
                let range = min(anchorIndex, measureIndex)...max(anchorIndex, measureIndex)
                selectedNotationMeasures = range.map { NotationMeasureSelection(measure: scoreMeasures[$0], partID: partID) }
            } else {
                selectedNotationMeasures = [NotationMeasureSelection(measure: measure, partID: partID)]
                notationMeasureSelectionAnchor = NotationMeasureSelection(measure: measure, partID: partID)
            }
        } else {
            selectedNotationMeasures = [NotationMeasureSelection(measure: measure, partID: partID)]
            notationMeasureSelectionAnchor = NotationMeasureSelection(measure: measure, partID: partID)
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
              let measure = currentNotationScoreMeasures(partID: placement.partID).first(where: {
                  $0.number == placement.measure.number
                      && abs($0.startTime - placement.measure.startTime) < NotationMeasureTiming.timelineTolerance
                      && abs($0.endTime - placement.measure.endTime) < NotationMeasureTiming.timelineTolerance
              }),
              let restSpan = NotationNotePlacementResolver.restSpan(in: measure, matching: placement)
        else {
            return false
        }

        let noteItem = NotationMeasureItem(
            partID: placement.partID,
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
                itemID: noteItem.id,
                partID: placement.partID
            )
        }

        try? notationNoteAuditioner.audition(pitch: placement.pitch)
        return true
    }

    @discardableResult
    func insertNotationRest(_ placement: NotationRestPlacement) -> Bool {
        guard duration > 0,
              let measure = currentNotationScoreMeasures(partID: placement.partID).first(where: {
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
            partID: placement.partID,
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
            selectedNotationItem = NotationItemSelection(measure: measure, item: targetRest, partID: placement.partID)
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
                itemID: restItem.id,
                partID: placement.partID
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
            partID: item.partID,
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
                itemID: updatedItem.id,
                partID: item.partID
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
        replaceSelectedNotationNoteWithRest(
            undoActionName: "Delete Notation Note"
        )
    }

    @discardableResult
    private func replaceSelectedNotationNoteWithRest(
        undoActionName: String
    ) -> Bool {
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
            partID: item.partID,
            kind: .rest,
            pitch: nil,
            measureNumber: item.measureNumber,
            measureStartTime: item.measureStartTime,
            offsetInQuarterNotes: item.offsetInQuarterNotes,
            durationInQuarterNotes: item.durationInQuarterNotes,
            displayDuration: item.displayDuration
        )

        performUndoableEdit(undoActionName) {
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
        let targetPartID = selectedNotationMeasures.first?.partID ?? .main

        let pastedItemsByMeasure: [[NotationMeasureClipboardItem]] = zip(targetMeasures, clipboard.measures).map { targetMeasure, sourceMeasure in
            guard targetPartID == .main else { return [] as [NotationMeasureClipboardItem] }
            return sourceMeasure.items
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
            selectedNotationMeasures = targetMeasures.map { NotationMeasureSelection(measure: $0, partID: targetPartID) }
            notationMeasureSelectionAnchor = selectedNotationMeasures.first
            return true
        }

        performUndoableEdit(targetMeasures.count == 1 ? "Paste Measure" : "Paste Measures") {
            harmonySymbols.removeAll { symbol in
                guard targetPartID == .main else { return false }
                return targetMeasures.contains { targetMeasure in
                    NotationMeasureTiming.containsEventTime(symbol.time, in: targetMeasure)
                }
            }
            notationItems.removeAll { item in
                targetMeasures.contains { targetMeasure in
                    item.measureNumber == targetMeasure.number
                        && item.partID == targetPartID
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
                        partID: targetPartID,
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
            selectedNotationMeasures = targetMeasures.map { NotationMeasureSelection(measure: $0, partID: targetPartID) }
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
        guard selection.partID == .main,
              let match = notationItemMatch(for: selection)
        else { return nil }
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
        for measure in currentNotationScoreMeasures(partID: selection.partID) {
            guard measure.number == selection.measureNumber else { continue }
            if let exact = measure.notationItems.first(where: { selection.matches(measure, item: $0) }) {
                return (measure, exact)
            }
            if let byOffset = measure.notationItems.first(where: {
                $0.partID == selection.partID
                    && abs($0.offsetInQuarterNotes - selection.offsetInQuarterNotes) < NotationMeasureTiming.timelineTolerance
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
            rest -= duration
            items.append(contentsOf: fillerNotationItems(
                measure: measure,
                partID: selectedItem.partID,
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
                    partID: selectedItem.partID,
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
                partID: selectedItem.partID,
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
            partID: selectedItem.partID,
            startOffset: cursor,
            remaining: rest
        ))
        return items
    }

    private func fillerNotationItems(
        measure: ScoreMeasure,
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
        guard measure.notationItems.allSatisfy({ $0.partID == .main }) else { return [] }

        return harmonySymbols
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

        let partID = selectedNotationMeasures.first?.partID ?? .main
        selectedNotationMeasures = measures.map { NotationMeasureSelection(measure: $0, partID: partID) }
        if let anchor = notationMeasureSelectionAnchor,
           anchor.partID == partID,
           measures.contains(where: { anchor.matches($0, partID: partID) }) {
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

        let partID = selectedNotationMeasures.first?.partID ?? .main
        selectedNotationMeasures = targetMeasures.map { NotationMeasureSelection(measure: $0, partID: partID) }
        notationMeasureSelectionAnchor = selectedNotationMeasures.first
        return targetMeasures
    }

    private func currentSelectedNotationMeasures() -> [ScoreMeasure] {
        guard !selectedNotationMeasures.isEmpty else { return [] }
        let partID = selectedNotationMeasures[0].partID
        guard selectedNotationMeasures.allSatisfy({ $0.partID == partID }) else { return [] }

        let scoreMeasures = currentNotationScoreMeasures(partID: partID)
        guard let firstIndex = scoreMeasures.firstIndex(where: { selectedNotationMeasures[0].matches($0, partID: partID) }) else { return [] }
        let expectedRange = firstIndex..<(firstIndex + selectedNotationMeasures.count)
        guard expectedRange.upperBound <= scoreMeasures.endIndex else { return [] }
        let expectedMeasures = expectedRange.map { scoreMeasures[$0] }

        return zip(expectedMeasures, selectedNotationMeasures).allSatisfy { measure, selection in
            selection.matches(measure, partID: partID)
        } ? expectedMeasures : []
    }

    private func currentPasteTargetMeasures(forClipboardMeasureCount clipboardMeasureCount: Int) -> [ScoreMeasure]? {
        guard clipboardMeasureCount > 0 else { return nil }
        let selectedMeasures = currentSelectedNotationMeasures()
        guard let firstSelectedMeasure = selectedMeasures.first else { return nil }

        let partID = selectedNotationMeasures.first?.partID ?? .main
        let scoreMeasures = currentNotationScoreMeasures(partID: partID)
        let firstSelection = NotationMeasureSelection(measure: firstSelectedMeasure, partID: partID)
        guard let startIndex = scoreMeasures.firstIndex(where: { firstSelection.matches($0, partID: partID) }) else {
            return nil
        }

        let targetCount = min(clipboardMeasureCount, scoreMeasures.count - startIndex)
        guard targetCount > 0 else { return nil }
        return (startIndex..<(startIndex + targetCount)).map { scoreMeasures[$0] }
    }

    private func currentNotationScoreMeasures(
        partID: NotationPartID = .main
    ) -> [ScoreMeasure] {
        NotationViewportFactory().scoreState(
            tempoMap: tempoMap,
            duration: duration,
            currentTime: currentTime,
            playbackMarkerTime: playbackMarkerTime,
            isPlaying: playbackState == .playing,
            keyName: effectiveKeyName,
            clef: notationClef(for: partID),
            partID: partID,
            includesHarmonies: partID.isMain,
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
        let updatedItems = measure.notationItems.compactMap { item in
            if item.id == targetItem.id && item.partID == targetItem.partID {
                return replacementItem
            }
            return item.isSynthesized ? nil : item.persistedCopy()
        }
        replaceNotationMeasureItems(in: measure, with: updatedItems)
    }

    private func replaceNotationMeasureItems(
        in measure: ScoreMeasure,
        with replacementItems: [NotationMeasureItem]
    ) {
        notationItems.removeAll {
            $0.measureNumber == measure.number
                && $0.partID == (replacementItems.first?.partID ?? measure.notationItems.first?.partID ?? .main)
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
            keySignature: match.measure.attributes.keySignature,
            clef: match.measure.attributes.clef
        )
    }

    private func refreshNotationSelections(for partID: NotationPartID) {
        let measures = currentNotationScoreMeasures(partID: partID)

        if let selection = selectedNotationItem, selection.partID == partID {
            if let measure = measures.first(where: {
                $0.number == selection.measureNumber
                    && abs($0.startTime - selection.measureStartTime) < NotationMeasureTiming.timelineTolerance
            }), let item = measure.notationItems.first(where: {
                $0.id == selection.itemID && $0.partID == partID
            }) {
                selectedNotationItem = NotationItemSelection(measure: measure, item: item, partID: partID)
            } else {
                selectedNotationItem = nil
            }
        }

        selectedNotationMeasures = selectedNotationMeasures.compactMap { selection in
            guard selection.partID == partID else { return selection }
            guard let measure = measures.first(where: {
                $0.number == selection.number
                    && abs($0.startTime - selection.startTime) < NotationMeasureTiming.timelineTolerance
            }) else {
                return nil
            }
            return NotationMeasureSelection(measure: measure, partID: partID)
        }

        if let anchor = notationMeasureSelectionAnchor, anchor.partID == partID {
            notationMeasureSelectionAnchor = measures.first(where: {
                $0.number == anchor.number
                    && abs($0.startTime - anchor.startTime) < NotationMeasureTiming.timelineTolerance
            }).map { NotationMeasureSelection(measure: $0, partID: partID) }
        }
    }

    private func reselectNotationItem(
        inMeasureNumber measureNumber: Int,
        measureStartTime: TimeInterval,
        itemID: String,
        partID: NotationPartID
    ) {
        guard let updatedMeasure = currentNotationScoreMeasures(partID: partID).first(where: {
            $0.number == measureNumber
                && abs($0.startTime - measureStartTime) < NotationMeasureTiming.timelineTolerance
        }), let selected = updatedMeasure.notationItems.first(where: { $0.id == itemID && $0.partID == partID }) else {
            selectedNotationItem = nil
            return
        }

        selectedNotationItem = NotationItemSelection(measure: updatedMeasure, item: selected, partID: partID)
    }

    private func locatePlaybackMarkerAtFirstSelectedNotationMeasure() {
        guard let firstSelectedMeasure = currentSelectedNotationMeasures().first else { return }
        locatePlaybackMarkerExactly(to: firstSelectedMeasure.startTime)
    }

}
