import Foundation

private struct TiedNotationNoteInput {
    var measures: [ScoreMeasure]
    var sourceItem: NotationMeasureItem
}

private struct NotationAccidentalEditTarget {
    var measureNumber: Int
    var measureStartTime: TimeInterval
    var selectedItemID: String
    var partID: NotationPartID
    var clef: Clef
    var alreadyApplied: Bool
    var updatedItems: [NotationMeasureItem]
}

private enum TiedNotationNoteCommandResolution {
    case unavailable
    case blocked(NotationTieCommandBlockReason)
    case ready(NotationNoteInsertionPlan)

    var status: NotationTieCommandStatus {
        switch self {
        case .unavailable:
            return .unavailable
        case let .blocked(reason):
            return .blocked(reason)
        case .ready:
            return .ready
        }
    }
}

extension AudioPlayerViewModel {
    var canChangeNotationDuration: Bool {
        duration > 0 && (isNotationEntryModeEnabled || canEditSelectedNotationItem)
    }

    var notationDurationIsDotted: Bool {
        selectedNotationItemDuration?.isDotted ?? notationEntryDurationIsDotted
    }

    var canChangeSelectedNotationNotePitch: Bool {
        canChangeSelectedNotationNotePitch(byStaffPositionDelta: -1)
            || canChangeSelectedNotationNotePitch(byStaffPositionDelta: 1)
    }

    func setNotationDurationDenominator(_ denominator: Int) {
        let normalizedDenominator = NotationDuration.normalizedDenominator(denominator)
        guard !isNotationEntryModeEnabled else {
            notationDurationDenominator = normalizedDenominator
            return
        }

        let targetDuration = NotationDuration(
            denominator: normalizedDenominator,
            isDotted: notationDurationIsDotted
        )
        guard selectedNotationItemDuration != targetDuration else {
            notationDurationDenominator = normalizedDenominator
            return
        }
        guard changeSelectedNotationItemDuration(to: targetDuration) else { return }
        notationDurationDenominator = normalizedDenominator
    }

    @discardableResult
    func toggleNotationDurationDot() -> Bool {
        if isNotationEntryModeEnabled {
            notationEntryDurationIsDotted.toggle()
            return true
        }

        guard let selection = selectedNotationItem,
              let match = notationItemMatch(for: selection)
        else {
            return false
        }

        let targetDuration = NotationDuration(
            denominator: match.item.displayDuration.denominator,
            isDotted: !match.item.displayDuration.isDotted
        )
        guard changeSelectedNotationItemDuration(to: targetDuration) else { return false }
        return true
    }

    private var selectedNotationItemDuration: NotationDuration? {
        guard let selection = selectedNotationItem,
              let match = notationItemMatch(for: selection)
        else { return nil }
        return match.item.displayDuration
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

    var tieCommandStatus: NotationTieCommandStatus {
        resolveTiedNotationNoteCommand().status
    }

    var isTieCommandInScope: Bool {
        tieCommandStatus.isInCommandScope
    }

    /// Returns whether the command should consume its input event, including a blocked no-op.
    @discardableResult
    func handleAddTiedNotationNoteCommand() -> Bool {
        switch resolveTiedNotationNoteCommand() {
        case .unavailable:
            return false
        case .blocked:
            return true
        case let .ready(plan):
            performUndoableEdit("Add Tied Notation Note") {
                applyNotationNoteInsertionPlan(plan)
                selectedNotationMeasures = []
                notationMeasureSelectionAnchor = nil
                selectedHarmonySymbolID = nil
                reselectNotationItem(
                    inMeasureNumber: plan.finalMeasureNumber,
                    measureStartTime: plan.finalMeasureStartTime,
                    itemID: plan.finalItemID,
                    partID: plan.partID
                )
            }

            return true
        }
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

        let exitsEntryMode = notationEntryMode != nil && resolvedMode == nil
        notationEntryMode = resolvedMode
        if exitsEntryMode {
            clearPendingNotationAccidental()
        }
        if resolvedMode != nil {
            selectedNotationMeasures = []
            notationMeasureSelectionAnchor = nil
            selectedHarmonySymbolID = nil
            selectedNotationItem = nil
            pendingHarmonyEditorRequest = nil
        }
    }

    /// Applies an accidental to the selected tonal note, or arms it for the next
    /// successfully inserted tonal note while note/rest entry remains enabled.
    @discardableResult
    func handleNotationAccidentalCommand(_ accidental: NotationAccidental) -> Bool {
        if let selection = selectedNotationItem {
            clearPendingNotationAccidental()
            return applyNotationAccidental(accidental, to: selection)
        }

        guard duration > 0, notationEntryMode != nil else { return false }
        pendingNotationAccidental = pendingNotationAccidental == accidental ? nil : accidental
        return true
    }

    func clearPendingNotationAccidental() {
        pendingNotationAccidental = nil
    }

    private func consumePendingNotationAccidental(
        appliedBy placement: NotationNotePlacement
    ) {
        guard placement.measure.attributes.clef != .drums,
              placement.explicitAccidental != nil,
              placement.explicitAccidental == pendingNotationAccidental
        else { return }
        clearPendingNotationAccidental()
    }

    @discardableResult
    private func applyNotationAccidental(
        _ accidental: NotationAccidental,
        to selection: NotationItemSelection
    ) -> Bool {
        guard let target = notationAccidentalEditTarget(for: selection, accidental: accidental) else {
            return false
        }
        guard !target.alreadyApplied else { return true }

        performUndoableEdit("Set \(accidental.displayName) Accidental") {
            notationItems = target.updatedItems
            notationItems = ProjectStateNormalizer.normalizedNotationItems(
                notationItems,
                duration: duration,
                notationPartClefs: notationPartClefs
            )
            sanitizeNotationTieRelationships()
            reselectNotationItem(
                inMeasureNumber: target.measureNumber,
                measureStartTime: target.measureStartTime,
                itemID: target.selectedItemID,
                partID: target.partID
            )
        }

        if let pitch = notationItems.first(where: { $0.id == target.selectedItemID })?.pitch {
            auditionNotationNotePitch(pitch, clef: target.clef)
        }
        return true
    }

    private func notationAccidentalEditTarget(
        for selection: NotationItemSelection,
        accidental: NotationAccidental
    ) -> NotationAccidentalEditTarget? {
        guard let match = notationItemMatch(for: selection),
              let plan = NotationAccidentalPlanner.plan(
                accidental: accidental,
                selectedItem: match.item,
                measure: match.measure,
                allItems: notationItems
              )
        else { return nil }

        return NotationAccidentalEditTarget(
            measureNumber: match.measure.number,
            measureStartTime: match.measure.startTime,
            selectedItemID: match.item.id,
            partID: match.item.partID,
            clef: match.measure.attributes.clef,
            alreadyApplied: plan.alreadyApplied,
            updatedItems: plan.updatedItems
        )
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
        clearPendingNotationAccidental()
        if let placement = harmonyPlacement(for: canonicalSelection) {
            selectedHarmonySymbolID = harmonySymbolID(at: placement.harmonyPlacement.time)
        } else {
            selectedHarmonySymbolID = nil
        }

        if shouldAudition,
           match.item.kind == .note,
           let pitch = match.item.pitch {
            auditionNotationNotePitch(pitch, clef: match.measure.attributes.clef)
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
        clearPendingNotationAccidental()
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
        if let existing = exactNotationNote(matching: placement) {
            selectedNotationMeasures = []
            notationMeasureSelectionAnchor = nil
            selectedHarmonySymbolID = nil
            selectedNotationItem = NotationItemSelection(
                measure: existing.measure,
                item: existing.item,
                partID: placement.partID
            )
            clearPendingNotationAccidental()
            auditionNotationNotePitch(placement.pitch, clef: placement.measure.attributes.clef)
            return true
        }
        guard let plan = notationNoteInsertionPlan(for: placement) else { return false }

        performUndoableEdit("Add Notation Note") {
            applyNotationNoteInsertionPlan(plan)
            selectedNotationMeasures = []
            notationMeasureSelectionAnchor = nil
            selectedHarmonySymbolID = nil
            reselectNotationItem(
                inMeasureNumber: plan.firstMeasureNumber,
                measureStartTime: plan.firstMeasureStartTime,
                itemID: plan.firstItemID,
                partID: plan.partID
            )
        }

        auditionNotationNotePitch(placement.pitch, clef: placement.measure.attributes.clef)
        consumePendingNotationAccidental(appliedBy: placement)
        return true
    }

    func canInsertNotationNote(_ placement: NotationNotePlacement) -> Bool {
        guard duration > 0 else { return false }
        return NotationNoteInsertionPlanner.canPlanInsertion(
            in: currentNotationScoreMeasures(partID: placement.partID),
            placement: placement
        )
    }

    func previewNotationNoteEdit(
        _ request: NotationNoteEditRequest
    ) -> NotationNoteEditPreview? {
        guard duration > 0 else { return nil }
        if let preparedNotationNoteEditSession,
           preparedNotationNoteEditSession.partID == request.partID {
            return preparedNotationNoteEditSession.preview(request)
        }
        return NotationNoteEditPlanner.preview(
            in: currentNotationScoreMeasures(partID: request.partID),
            request: request,
            audioDuration: duration
        )
    }

    func beginNotationNoteEdit(partID: NotationPartID) {
        preparedNotationNoteEditSession = NotationNoteEditPlanner.prepareSession(
            measures: currentNotationScoreMeasures(partID: partID),
            partID: partID,
            audioDuration: duration
        )
    }

    func endNotationNoteEdit() {
        preparedNotationNoteEditSession = nil
    }

    @discardableResult
    func commitNotationNoteEdit(_ request: NotationNoteEditRequest) -> Bool {
        guard let currentPlan = NotationNoteEditPlanner.preview(
            in: currentNotationScoreMeasures(partID: request.partID),
            request: request,
            audioDuration: duration
        )?.plan else { return false }

        performUndoableEdit(currentPlan.actionName) {
            for replacement in currentPlan.replacements {
                notationItems.removeAll { item in
                    item.partID == replacement.partID
                        && item.measureNumber == replacement.measureNumber
                        && abs(item.measureStartTime - replacement.measureStartTime)
                            < NotationMeasureTiming.timelineTolerance
                }
                notationItems.append(contentsOf: replacement.items)
            }
            notationItems = ProjectStateNormalizer.normalizedNotationItems(
                notationItems,
                duration: duration,
                notationPartClefs: notationPartClefs
            )
            sanitizeNotationTieRelationships()
            selectedNotationMeasures = []
            notationMeasureSelectionAnchor = nil
            selectedHarmonySymbolID = nil
            reselectNotationItem(
                inMeasureNumber: currentPlan.rootMeasureNumber,
                measureStartTime: currentPlan.rootMeasureStartTime,
                itemID: currentPlan.rootItemID,
                partID: currentPlan.partID
            )
        }
        return true
    }

    func logicalNotationNoteItemIDs(
        containing itemID: String,
        partID: NotationPartID
    ) -> Set<String> {
        NotationNoteEditPlanner.logicalChainItemIDs(
            in: notationItems,
            containing: itemID,
            partID: partID
        )
    }

    @discardableResult
    func insertNotationRest(_ placement: NotationRestPlacement) -> Bool {
        guard duration > 0,
              let measure = currentNotationScoreMeasures(partID: placement.partID).first(where: {
                  $0.number == placement.measure.number
                      && abs($0.startTime - placement.measure.startTime) < NotationMeasureTiming.timelineTolerance
                      && abs($0.endTime - placement.measure.endTime) < NotationMeasureTiming.timelineTolerance
              })
        else {
            return false
        }

        let restSpan = NotationTimeSpan(
            start: placement.offsetInQuarterNotes,
            end: placement.offsetInQuarterNotes + placement.durationInQuarterNotes
        )
        guard NotationMeasureRhythmRecomposer.isSilent(
            restSpan,
            in: measure,
            partID: placement.partID,
            items: measure.notationItems
        ) else { return false }

        let restItem = NotationMeasureItem(
            partID: placement.partID,
            kind: .rest,
            measureNumber: measure.number,
            measureStartTime: measure.startTime,
            offsetInQuarterNotes: restSpan.start,
            durationInQuarterNotes: placement.durationInQuarterNotes,
            displayDuration: placement.displayDuration
        )

        if let targetRest = measure.notationItems.first(where: {
            !$0.isSynthesized
                && $0.kind == .rest
                && $0.partID == placement.partID
                && abs($0.offsetInQuarterNotes - restItem.offsetInQuarterNotes) < NotationMeasureTiming.timelineTolerance
                && abs($0.durationInQuarterNotes - restItem.durationInQuarterNotes) < NotationMeasureTiming.timelineTolerance
                && $0.displayDuration == restItem.displayDuration
        }) {
            selectedNotationMeasures = []
            notationMeasureSelectionAnchor = nil
            selectedHarmonySymbolID = nil
            selectedNotationItem = NotationItemSelection(measure: measure, item: targetRest, partID: placement.partID)
            return true
        }

        let preferredRests = measure.notationItems.filter { item in
            guard item.kind == .rest, item.partID == placement.partID else { return true }
            let existingSpan = NotationTimeSpan(
                start: item.offsetInQuarterNotes,
                end: item.offsetInQuarterNotes + item.durationInQuarterNotes
            )
            return !existingSpan.overlaps(restSpan)
        } + [restItem]
        let recomposedItems = NotationMeasureRhythmRecomposer.persistedItems(
            in: measure,
            partID: placement.partID,
            notes: measure.notationItems,
            preferredRests: preferredRests
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
        guard measure.attributes.clef != .drums
                || NotationInputPolicy.isEditable(pitch, in: .drums),
              !measure.notationItems.contains(where: {
            $0.id != item.id
                && $0.partID == item.partID
                && $0.kind == .note
                && $0.pitch == pitch
                && abs($0.offsetInQuarterNotes - item.offsetInQuarterNotes)
                    < NotationMeasureTiming.timelineTolerance
                && abs($0.durationInQuarterNotes - item.durationInQuarterNotes)
                    < NotationMeasureTiming.timelineTolerance
        }) else { return false }
        let updatedItem = NotationMeasureItem(
            id: item.id,
            partID: item.partID,
            kind: .note,
            pitch: pitch,
            measureNumber: item.measureNumber,
            measureStartTime: item.measureStartTime,
            offsetInQuarterNotes: item.offsetInQuarterNotes,
            durationInQuarterNotes: item.durationInQuarterNotes,
            displayDuration: item.displayDuration,
            tieTargetItemID: item.tieTargetItemID
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
            auditionNotationNotePitch(pitch, clef: measure.attributes.clef)
        }
        return true
    }

    func auditionNotationNotePitch(_ pitch: NotationPitch, clef: Clef) {
        try? notationNoteAuditioner.audition(pitch: pitch, route: .route(for: clef))
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
    func deleteSelectedNotationMeasureContents() -> Bool {
        guard let measures = validatedSelectedNotationMeasures() else { return false }
        let partID = selectedNotationMeasures.first?.partID ?? .main
        let belongsToSelection: (NotationMeasureItem) -> Bool = { item in
            item.partID == partID
                && measures.contains { measure in
                    item.measureNumber == measure.number
                        && abs(item.measureStartTime - measure.startTime)
                            < NotationMeasureTiming.timelineTolerance
                }
        }
        guard notationItems.contains(where: belongsToSelection) else { return false }

        performUndoableEdit("Delete Measure Contents") {
            notationItems.removeAll(where: belongsToSelection)
            sanitizeNotationTieRelationships()
        }

        return true
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
        let remainingNotes = measure.notationItems.filter {
            $0.kind == .note && !($0.id == item.id && $0.partID == item.partID)
        }
        let replacementItems = NotationMeasureRhythmRecomposer.persistedItems(
            in: measure,
            partID: item.partID,
            notes: remainingNotes,
            preferredRests: measure.notationItems + [replacementRest]
        )

        performUndoableEdit(undoActionName) {
            replaceNotationMeasureItems(in: measure, with: replacementItems)
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
        let copiedNotationItemIDs = Set(measures.flatMap { measure in
            measure.notationItems.filter { !$0.isSynthesized }.map(\.id)
        })

        notationMeasureClipboard = NotationMeasureClipboard(
            measures: measures.map { measure in
                NotationMeasureClipboardMeasure(
                    items: notationClipboardItems(in: measure),
                    notationItems: notationClipboardNotationItems(
                        in: measure,
                        copiedItemIDs: copiedNotationItemIDs
                    )
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
        let targetItemIDs = Set(targetMeasures.flatMap { measure in
            measure.notationItems.filter { !$0.isSynthesized }.map(\.id)
        })
        let currentNotationItemsByMeasure = targetMeasures.map {
            notationClipboardNotationItems(in: $0, copiedItemIDs: targetItemIDs)
        }

        guard currentItemsByMeasure != pastedItemsByMeasure
                || !notationClipboardContentsAreEqual(
                    currentNotationItemsByMeasure,
                    pastedNotationItemsByMeasure
                )
        else {
            selectedHarmonySymbolID = nil
            selectedNotationItem = nil
            selectedNotationMeasures = targetMeasures.map { NotationMeasureSelection(measure: $0, partID: targetPartID) }
            notationMeasureSelectionAnchor = selectedNotationMeasures.first
            return true
        }

        let pastedSourceItemIDs = pastedNotationItemsByMeasure.flatMap { $0.map(\.sourceItemID) }
        let pastedItemIDsBySourceID = pastedSourceItemIDs.reduce(into: [String: String]()) {
            if $0[$1] == nil { $0[$1] = UUID().uuidString }
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
                        id: pastedItemIDsBySourceID[item.sourceItemID] ?? UUID().uuidString,
                        partID: targetPartID,
                        kind: item.kind,
                        pitch: item.kind == .note ? item.pitch : nil,
                        explicitAccidental: item.kind == .note ? item.explicitAccidental : nil,
                        measureNumber: targetMeasure.number,
                        measureStartTime: targetMeasure.startTime,
                        offsetInQuarterNotes: item.offsetInQuarterNotes,
                        durationInQuarterNotes: item.durationInQuarterNotes,
                        displayDuration: item.displayDuration,
                        tieTargetItemID: item.tieTargetItemID.flatMap {
                            pastedItemIDsBySourceID[$0]
                        }
                    )
                })
            }

            harmonySymbols = ProjectStateNormalizer.normalizedHarmonySymbols(harmonySymbols, duration: duration)
            notationItems = ProjectStateNormalizer.normalizedNotationItems(
                notationItems,
                duration: duration,
                notationPartClefs: notationPartClefs
            )
            sanitizeNotationTieRelationships()
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

    @discardableResult
    private func changeSelectedNotationItemDuration(to selectedDuration: NotationDuration) -> Bool {
        guard let selection = selectedNotationItem,
              let match = notationItemMatch(for: selection)
        else { return false }

        let measure = match.measure
        if match.item.kind == .note {
            let measureLength = NotationMeasureTiming.quarterLength(for: measure.attributes.timeSignature)
            let newLength = selectedDuration.durationInQuarterNotes
            guard match.item.offsetInQuarterNotes + newLength
                    <= measureLength + NotationMeasureTiming.timelineTolerance
            else { return false }

            var selectedItem = match.item.persistedCopy()
            selectedItem.durationInQuarterNotes = newLength
            selectedItem.displayDuration = selectedDuration
            guard !measure.notationItems.contains(where: {
                $0.id != selectedItem.id
                    && $0.partID == selectedItem.partID
                    && $0.kind == .note
                    && $0.pitch == selectedItem.pitch
                    && abs($0.offsetInQuarterNotes - selectedItem.offsetInQuarterNotes)
                        < NotationMeasureTiming.timelineTolerance
                    && abs($0.durationInQuarterNotes - selectedItem.durationInQuarterNotes)
                        < NotationMeasureTiming.timelineTolerance
            }) else { return false }

            let notes = measure.notationItems.compactMap { item -> NotationMeasureItem? in
                guard item.kind == .note else { return nil }
                return item.id == selectedItem.id && item.partID == selectedItem.partID
                    ? selectedItem
                    : item
            }
            let items = NotationMeasureRhythmRecomposer.persistedItems(
                in: measure,
                partID: selectedItem.partID,
                notes: notes,
                preferredRests: measure.notationItems
            )
            performUndoableEdit("Change Notation Duration") {
                replaceNotationMeasureItems(in: measure, with: items)
                reselectNotationItem(
                    inMeasureNumber: measure.number,
                    measureStartTime: measure.startTime,
                    itemID: selectedItem.id,
                    partID: selectedItem.partID
                )
            }
            return true
        }

        guard let replacement = NotationDurationEditor.replacement(
            in: measure,
            selectedItem: match.item,
            selectedDuration: selectedDuration
        ) else { return false }

        performUndoableEdit("Change Notation Duration") {
            replaceNotationMeasureItems(in: measure, with: replacement.items)
            reselectNotationItem(
                inMeasureNumber: measure.number,
                measureStartTime: measure.startTime,
                itemID: replacement.selectedItem.id,
                partID: replacement.selectedItem.partID
            )
        }
        return true
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

    private func notationClipboardNotationItems(
        in measure: ScoreMeasure,
        copiedItemIDs: Set<String>
    ) -> [NotationMeasureClipboardNotationItem] {
        measure.notationItems
            .filter { !$0.isSynthesized }
            .map {
                NotationMeasureClipboardNotationItem(
                    sourceItemID: $0.id,
                    kind: $0.kind,
                    pitch: $0.pitch,
                    explicitAccidental: $0.explicitAccidental,
                    offsetInQuarterNotes: $0.offsetInQuarterNotes,
                    durationInQuarterNotes: $0.durationInQuarterNotes,
                    displayDuration: $0.displayDuration,
                    tieTargetItemID: $0.tieTargetItemID.flatMap {
                        copiedItemIDs.contains($0) ? $0 : nil
                    }
                )
            }
            .sorted(by: notationClipboardNotationItemSort)
    }

    private struct NotationClipboardSemanticItem: Equatable {
        var kind: NotationMeasureItem.Kind
        var pitch: NotationPitch?
        var explicitAccidental: NotationAccidental?
        var offsetInQuarterNotes: Double
        var durationInQuarterNotes: Double
        var displayDuration: NotationDuration
        var tieTargetPosition: String?
    }

    private func notationClipboardContentsAreEqual(
        _ lhs: [[NotationMeasureClipboardNotationItem]],
        _ rhs: [[NotationMeasureClipboardNotationItem]]
    ) -> Bool {
        canonicalNotationClipboardContents(lhs) == canonicalNotationClipboardContents(rhs)
    }

    private func canonicalNotationClipboardContents(
        _ contents: [[NotationMeasureClipboardNotationItem]]
    ) -> [[NotationClipboardSemanticItem]] {
        let positionsBySourceID = contents.enumerated().reduce(into: [String: String]()) { output, measure in
            for (itemIndex, item) in measure.element.enumerated() where output[item.sourceItemID] == nil {
                output[item.sourceItemID] = "\(measure.offset):\(itemIndex)"
            }
        }
        return contents.map { measureItems in
            measureItems.map { item in
                NotationClipboardSemanticItem(
                    kind: item.kind,
                    pitch: item.pitch,
                    explicitAccidental: item.explicitAccidental,
                    offsetInQuarterNotes: item.offsetInQuarterNotes,
                    durationInQuarterNotes: item.durationInQuarterNotes,
                    displayDuration: item.displayDuration,
                    tieTargetPosition: item.tieTargetItemID.flatMap { positionsBySourceID[$0] }
                )
            }
        }
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
        let partID = replacementItems.first?.partID ?? measure.notationItems.first?.partID ?? .main
        let canonicalItems = NotationMeasureRhythmRecomposer.persistedItems(
            in: measure,
            partID: partID,
            notes: replacementItems,
            preferredRests: replacementItems
        )
        notationItems.removeAll {
            $0.measureNumber == measure.number
                && $0.partID == partID
                && abs($0.measureStartTime - measure.startTime) < NotationMeasureTiming.timelineTolerance
        }
        notationItems.append(contentsOf: canonicalItems)
        notationItems = ProjectStateNormalizer.normalizedNotationItems(
            notationItems,
            duration: duration,
            notationPartClefs: notationPartClefs
        )
        sanitizeNotationTieRelationships()
    }

    func sanitizeNotationTieRelationships() {
        guard notationItems.contains(where: { $0.tieTargetItemID != nil }) else { return }
        let partIDs = Set(notationItems.map(\.partID))
        let validConnections = partIDs.flatMap { partID in
            NotationTieResolver.connections(in: currentNotationScoreMeasures(partID: partID))
        }
        notationItems = NotationTieResolver.sanitizedPersistedItems(
            notationItems,
            validConnections: validConnections
        )
    }

    private func applyNotationNoteInsertionPlan(_ plan: NotationNoteInsertionPlan) {
        for replacement in plan.replacements {
            notationItems.removeAll { item in
                item.partID == replacement.partID
                    && item.measureNumber == replacement.measureNumber
                    && abs(item.measureStartTime - replacement.measureStartTime)
                        < NotationMeasureTiming.timelineTolerance
            }
            notationItems.append(contentsOf: replacement.items)
        }
        notationItems = ProjectStateNormalizer.normalizedNotationItems(
            notationItems,
            duration: duration,
            notationPartClefs: notationPartClefs
        )
        sanitizeNotationTieRelationships()
    }

    private func notationNoteInsertionPlan(
        for placement: NotationNotePlacement
    ) -> NotationNoteInsertionPlan? {
        guard duration > 0 else { return nil }
        return NotationNoteInsertionPlanner.planInsertion(
            in: currentNotationScoreMeasures(partID: placement.partID),
            placement: placement
        )
    }

    private func exactNotationNote(
        matching placement: NotationNotePlacement
    ) -> (measure: ScoreMeasure, item: NotationMeasureItem)? {
        let measures = currentNotationScoreMeasures(partID: placement.partID).sorted {
            if $0.number != $1.number { return $0.number < $1.number }
            return $0.startTime < $1.startTime
        }
        guard let targetMeasureIndex = measures.firstIndex(where: {
            $0.number == placement.measure.number
                && abs($0.startTime - placement.measure.startTime) < NotationMeasureTiming.timelineTolerance
        }) else { return nil }

        var measureStartOffsets: [Double] = []
        var measureCursor = 0.0
        for measure in measures {
            measureStartOffsets.append(measureCursor)
            measureCursor += NotationMeasureTiming.quarterLength(for: measure.attributes.timeSignature)
        }
        let targetStart = measureStartOffsets[targetMeasureIndex] + placement.offsetInQuarterNotes
        let targetEnd = targetStart + placement.durationInQuarterNotes
        let persistedNotes = measures.flatMap(\.notationItems).filter {
            !$0.isSynthesized && $0.partID == placement.partID && $0.kind == .note
        }
        var visited: Set<String> = []

        for candidate in persistedNotes where !visited.contains(candidate.id) {
            let chainIDs = NotationNoteEditPlanner.logicalChainItemIDs(
                in: persistedNotes,
                containing: candidate.id,
                partID: placement.partID
            )
            visited.formUnion(chainIDs)
            let chain = persistedNotes.filter { chainIDs.contains($0.id) }
            guard chain.first?.pitch == placement.pitch else { continue }

            let spans = chain.compactMap { item -> (ScoreMeasure, Double, Double)? in
                guard let measureIndex = measures.firstIndex(where: {
                    $0.number == item.measureNumber
                        && abs($0.startTime - item.measureStartTime) < NotationMeasureTiming.timelineTolerance
                }) else { return nil }
                let start = measureStartOffsets[measureIndex] + item.offsetInQuarterNotes
                return (measures[measureIndex], start, start + item.durationInQuarterNotes)
            }
            guard let chainStart = spans.map(\.1).min(),
                  let chainEnd = spans.map(\.2).max(),
                  abs(chainStart - targetStart) < NotationMeasureTiming.timelineTolerance,
                  abs(chainEnd - targetEnd) < NotationMeasureTiming.timelineTolerance,
                  let root = chain.first(where: { item in
                      !Set(chain.compactMap(\.tieTargetItemID)).contains(item.id)
                  }),
                  let rootMeasure = measures.first(where: {
                      $0.number == root.measureNumber
                          && abs($0.startTime - root.measureStartTime) < NotationMeasureTiming.timelineTolerance
                  })
            else { continue }
            return (rootMeasure, root)
        }
        return nil
    }

    private func tiedNotationNoteInput() -> TiedNotationNoteInput? {
        guard duration > 0,
              let selection = selectedNotationItem
        else {
            return nil
        }

        let measures = currentNotationScoreMeasures(partID: selection.partID)
        guard let measure = measures.first(where: {
            $0.number == selection.measureNumber
                && abs($0.startTime - selection.measureStartTime) < NotationMeasureTiming.timelineTolerance
        }), let item = measure.notationItems.first(where: {
            $0.id == selection.itemID && $0.partID == selection.partID
        }), item.kind == .note, !item.isSynthesized, item.pitch != nil else {
            return nil
        }

        return TiedNotationNoteInput(
            measures: measures,
            sourceItem: item
        )
    }

    private func resolveTiedNotationNoteCommand() -> TiedNotationNoteCommandResolution {
        guard let input = tiedNotationNoteInput() else {
            return isNotationNoteEntryModeEnabled
                ? .blocked(.selectNote)
                : .unavailable
        }

        guard input.sourceItem.tieTargetItemID == nil else {
            return .blocked(.alreadyTied)
        }

        guard let continuationEndTime = NotationTieContinuationBoundary.endTime(
            in: input.measures,
            sourceItemID: input.sourceItem.id,
            continuationDurationInQuarterNotes: input.sourceItem.displayDuration.durationInQuarterNotes
        ), continuationEndTime <= duration + NotationMeasureTiming.timelineTolerance else {
            return .blocked(.audioBoundary)
        }

        guard let plan = NotationNoteInsertionPlanner.plan(
            in: input.measures,
            sourceItemID: input.sourceItem.id,
            selectedDuration: input.sourceItem.displayDuration
        ) else {
            return .blocked(.audioBoundary)
        }

        return .ready(plan)
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

    func refreshNotationSelections(for partID: NotationPartID) {
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
