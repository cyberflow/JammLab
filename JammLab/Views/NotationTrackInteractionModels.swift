import Foundation

struct NotationTrackActions {
    var selectHarmony: (HarmonySymbol.ID?) -> Void
    var selectMeasure: (ScoreMeasure?, Bool, NotationPartID) -> Void
    var selectItem: (NotationItemSelection?, Bool) -> Void
    var canInsertNotationNote: (NotationNotePlacement) -> Bool
    var insertNotationNote: (NotationNotePlacement) -> Bool
    var insertNotationRest: (NotationRestPlacement) -> Bool
    var changeSelectedNotePitch: (NotationPitch, Bool) -> Bool
    var changeClef: (NotationPartID, Clef) -> Void
    var auditionNotePitch: (NotationPitch, Clef) -> Void
    var deleteSelectedNotationMeasureContents: () -> Bool
    var deleteSelectedNotationNote: () -> Bool
    var locatePlaybackMarkerExactly: (TimeInterval) -> Void
    var saveHarmony: (HarmonySymbol) -> Void
    var deleteHarmony: (HarmonySymbol.ID) -> Void
    var adjacentHarmonyPlacement: (TimeInterval, HarmonyNavigationDirection) -> HarmonyPlacement?

    static var noop: NotationTrackActions {
        NotationTrackActions(
            selectHarmony: { _ in },
            selectMeasure: { _, _, _ in },
            selectItem: { _, _ in },
            canInsertNotationNote: { _ in false },
            insertNotationNote: { _ in false },
            insertNotationRest: { _ in false },
            changeSelectedNotePitch: { _, _ in false },
            changeClef: { _, _ in },
            auditionNotePitch: { _, _ in },
            deleteSelectedNotationMeasureContents: { false },
            deleteSelectedNotationNote: { false },
            locatePlaybackMarkerExactly: { _ in },
            saveHarmony: { _ in },
            deleteHarmony: { _ in },
            adjacentHarmonyPlacement: { _, _ in nil }
        )
    }
}

struct HarmonyEditorDraft: Equatable {
    var id: HarmonySymbol.ID
    var time: TimeInterval
    var measureNumber: Int
    var offsetInQuarterNotes: Double
    var text: String
    var isNew: Bool
}

struct NotationHarmonyPlacement: Equatable {
    var measureIndex: Int
    var time: TimeInterval
    var measureNumber: Int
    var offsetInQuarterNotes: Double

    var harmonyPlacement: HarmonyPlacement {
        HarmonyPlacement(
            time: time,
            measureNumber: measureNumber,
            offsetInQuarterNotes: offsetInQuarterNotes
        )
    }
}

struct NotationDraggedNotePitchPreview: Equatable {
    var selection: NotationItemSelection
    var pitch: NotationPitch
    var didAudition: Bool

    func matches(_ selection: NotationItemSelection) -> Bool {
        self.selection == selection
    }
}
