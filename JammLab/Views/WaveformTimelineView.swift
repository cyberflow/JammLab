import SwiftUI

struct BeatGridConfiguration: Equatable {
    var settings: BeatGridSettings
    var tempoMap: TempoMap
    var visibleRange: ClosedRange<TimeInterval>?

    init(settings: BeatGridSettings, tempoMap: TempoMap? = nil, visibleRange: ClosedRange<TimeInterval>? = nil) {
        self.settings = settings
        self.tempoMap = tempoMap ?? TempoMap(baseSettings: settings, markers: [], duration: visibleRange?.upperBound ?? 0)
        self.visibleRange = visibleRange
    }

    func viewport(duration: TimeInterval) -> TimelineViewport {
        TimelineViewport(duration: duration, visibleRange: visibleRange ?? 0...duration)
    }
}

struct TimelineViewState: Equatable {
    var peakformData: PeakformData?
    var duration: TimeInterval
    var currentTime: TimeInterval
    var playbackMarkerTime: TimeInterval
    var playbackDisplayState: PlaybackDisplayState
    var loopStart: TimeInterval
    var loopEnd: TimeInterval
    var notes: [TimecodedNote]
    var selectedHarmonySymbolID: HarmonySymbol.ID?
    var selectedNotationMeasures: [NotationMeasureSelection]
    var selectedNotationItem: NotationItemSelection?
    var selectedLogicalNotationItemIDs: Set<String> = []
    var pendingHarmonyEditorRequest: HarmonyEditorRequest?
    var selectedRegionID: TimecodedNote.ID?
    var beatGrid: BeatGridConfiguration
    var notationViewport: NotationViewportState
    var stemNotationViewports: [StemType: NotationViewportState]
    var notationMeasureLayout: NotationSystemMeasureLayout?
    var notationDurationDenominator: Int
    var notationDurationIsDotted: Bool
    var pendingNotationAccidental: NotationAccidental?
    var selectedDrumInstrumentMIDINoteNumber: Int = DrumInstrumentMap.defaultMIDINoteNumber
    var canChangeNotationDuration: Bool
    var tieCommandStatus: NotationTieCommandStatus
    var notationEntryMode: NotationEntryMode?
    var isNotationTrackCollapsed: Bool
    var stemNotationTrackCollapsed: [StemType: Bool]
    var stemNoteDisplayModes: [StemType: StemNoteDisplayMode]
    var isLoadingPeakform: Bool
    var mainTrackVolume: Float
    var playbackMode: PlaybackMode
    var mixState: StemMixState
    var stemFiles: [StemFile]
    var stemPeakforms: [StemType: PeakformData]
    var isLoadingStemPeakforms: Bool
    var stemTranscriptionStates: [StemType: StemTranscriptionViewState]
    var stemTypesWithTranscription: Set<StemType>
    var hasPendingStemTranscriptionOverwrite: Bool
}

struct TimelineViewActions {
    var locatePlaybackMarker: (TimeInterval) -> Void
    var locatePlaybackMarkerExactly: (TimeInterval) -> Void
    var addNote: (TimeInterval) -> Void
    var selectHarmony: (HarmonySymbol.ID?) -> Void
    var selectNotationMeasure: (ScoreMeasure?, Bool, NotationPartID) -> Void
    var selectNotationItem: (NotationItemSelection?, Bool) -> Void
    var saveHarmony: (HarmonySymbol) -> Void
    var deleteHarmony: (HarmonySymbol.ID) -> Void
    var adjacentHarmonyPlacement: (TimeInterval, HarmonyNavigationDirection) -> HarmonyPlacement?
    var addTempoTimeSignatureMarker: (TimeInterval) -> Void
    var editNote: (TimecodedNote) -> Void
    var deleteNote: (TimecodedNote.ID) -> Void
    var noteColorChanged: (TimecodedNote.ID, MarkerColor) -> Void
    var noteCustomColorChanged: (TimecodedNote.ID, String) -> Void
    var markerTimeChanged: (TimecodedNote.ID, TimeInterval) -> Void
    var saveLoopRegion: () -> Void
    var selectRegion: (TimecodedNote.ID) -> Void
    var activateRegionAsLoop: (TimecodedNote.ID) -> Void
    var focusRegion: (TimecodedNote.ID) -> Void
    var regionRangeChanged: (TimecodedNote.ID, TimeInterval, TimeInterval) -> Void
    var loopStartChanged: (TimeInterval) -> Void
    var loopEndChanged: (TimeInterval) -> Void
    var loopRegionChanged: (TimeInterval, TimeInterval) -> Void
    var timelineScroll: (Double, Double, TimeInterval?) -> Void
    var mainTrackVolumeChanged: (Float) -> Void
    var notationTrackCollapsedChanged: (Bool) -> Void
    var stemNotationTrackCollapsedChanged: (StemType, Bool) -> Void
    var stemNoteDisplayModeToggled: (StemType) -> Void
    var notationDurationChanged: (Int) -> Void
    var notationDurationDotToggled: () -> Void
    var notationAccidentalSelected: (NotationAccidental) -> Void = { _ in }
    var notationNoteEntryModeToggled: () -> Void
    var notationRestEntryModeToggled: () -> Void
    var addTiedNotationNote: () -> Void
    var canInsertNotationNote: (NotationNotePlacement) -> Bool
    var insertNotationNote: (NotationNotePlacement) -> Bool
    var insertNotationRest: (NotationRestPlacement) -> Bool
    var changeSelectedNotePitch: (NotationPitch, Bool) -> Bool
    var changeNotationClef: (NotationPartID, Clef) -> Void
    var selectDrumInstrument: (Int) -> Void = { _ in }
    var auditionNotePitch: (NotationPitch, Clef) -> Void
    var deleteSelectedNotationMeasureContents: () -> Bool = { false }
    var deleteSelectedNotationNote: () -> Bool
    var showNotationWindow: () -> Void
    var beginNotationNoteEdit: (NotationPartID) -> Void = { _ in }
    var endNotationNoteEdit: () -> Void = {}
    var previewNotationNoteEdit: (NotationNoteEditRequest) -> NotationNoteEditPreview? = { _ in nil }
    var commitNotationNoteEdit: (NotationNoteEditRequest) -> Bool = { _ in false }
    var stemMIDIPageStartChanged: (StemType, TimeInterval) -> Void = { _, _ in }
    var stemMIDIInteractionEnded: (StemType) -> Void = { _ in }
}

extension TimelineViewActions {
    func notationTrackActions(allowsHarmony: Bool) -> NotationTrackActions {
        let selectHarmonyAction: (HarmonySymbol.ID?) -> Void = allowsHarmony
            ? selectHarmony
            : { _ in }
        let saveHarmonyAction: (HarmonySymbol) -> Void = allowsHarmony
            ? saveHarmony
            : { _ in }
        let deleteHarmonyAction: (HarmonySymbol.ID) -> Void = allowsHarmony
            ? deleteHarmony
            : { _ in }
        let adjacentHarmonyAction: (TimeInterval, HarmonyNavigationDirection) -> HarmonyPlacement? = allowsHarmony
            ? adjacentHarmonyPlacement
            : { _, _ in nil }

        return NotationTrackActions(
            selectHarmony: selectHarmonyAction,
            selectMeasure: selectNotationMeasure,
            selectItem: selectNotationItem,
            canInsertNotationNote: canInsertNotationNote,
            insertNotationNote: insertNotationNote,
            insertNotationRest: insertNotationRest,
            changeSelectedNotePitch: changeSelectedNotePitch,
            changeClef: changeNotationClef,
            auditionNotePitch: auditionNotePitch,
            deleteSelectedNotationMeasureContents: deleteSelectedNotationMeasureContents,
            deleteSelectedNotationNote: deleteSelectedNotationNote,
            locatePlaybackMarkerExactly: locatePlaybackMarkerExactly,
            saveHarmony: saveHarmonyAction,
            deleteHarmony: deleteHarmonyAction,
            adjacentHarmonyPlacement: adjacentHarmonyAction
        )
    }

    func midiPianoRollActions() -> MIDIPianoRollActions {
        MIDIPianoRollActions(
            selectItem: selectNotationItem,
            canInsertNotationNote: canInsertNotationNote,
            insertNotationNote: insertNotationNote,
            insertNotationRest: insertNotationRest,
            auditionNotePitch: auditionNotePitch,
            deleteSelectedNotationNote: deleteSelectedNotationNote,
            beginNoteEdit: beginNotationNoteEdit,
            endNoteEdit: endNotationNoteEdit,
            previewNoteEdit: previewNotationNoteEdit,
            commitNoteEdit: commitNotationNoteEdit
        )
    }
}

enum NotationTrackTogglePresentation {
    static func systemName(isCollapsed: Bool) -> String {
        isCollapsed ? "music.note.list" : "music.note"
    }
}

struct StemTrackActions {
    var volumeChanged: (StemType, Float) -> Void
    var muteToggled: (StemType) -> Void
    var soloToggled: (StemType) -> Void
    var transcribe: (StemType) -> Void
    var cancelTranscription: (StemType) -> Void
    var exportTranscriptionMIDI: (StemType) -> Void
}

struct WaveformTimelineView: View {
    let state: TimelineViewState
    let actions: TimelineViewActions
    let stemActions: StemTrackActions

    private let trackControlWidth: CGFloat = AppTheme.Timeline.trackControlWidth
    @Environment(\.appColors) private var appColors

    var body: some View {
        tracksArea
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: tracksHeight, alignment: .topLeading)
    }

    private var tracksArea: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: AppTheme.Timeline.trackSpacing) {
                upperTrackStack
                stemTracksSection
            }

            timelineScrollOverlay
                .frame(height: tracksHeight)
        }
    }

    private var stemTracksSection: some View {
        StemTracksSection(
            playbackMode: state.playbackMode,
            mixState: state.mixState,
            stemFiles: state.stemFiles,
            stemPeakforms: state.stemPeakforms,
            isLoadingStemPeakforms: state.isLoadingStemPeakforms,
            transcriptionStates: state.stemTranscriptionStates,
            stemTypesWithTranscription: state.stemTypesWithTranscription,
            hasPendingTranscriptionOverwrite: state.hasPendingStemTranscriptionOverwrite,
            duration: state.duration,
            viewport: viewport,
            trackControlWidth: trackControlWidth,
            selectedMeasures: state.selectedNotationMeasures,
            selectedItem: state.selectedNotationItem,
            selectedDuration: NotationDuration(
                denominator: state.notationDurationDenominator,
                isDotted: state.notationDurationIsDotted
            ),
            selectedDrumInstrumentMIDINoteNumber: state.selectedDrumInstrumentMIDINoteNumber,
            entryMode: state.notationEntryMode,
            canChangeNotationDuration: state.canChangeNotationDuration,
            tieCommandStatus: state.tieCommandStatus,
            notationDurationDenominator: state.notationDurationDenominator,
            notationDurationIsDotted: state.notationDurationIsDotted,
            pendingNotationAccidental: state.pendingNotationAccidental,
            notationViewports: state.stemNotationViewports,
            measureLayout: state.notationMeasureLayout,
            notationCollapsed: state.stemNotationTrackCollapsed,
            noteDisplayModes: state.stemNoteDisplayModes,
            selectedLogicalItemIDs: state.selectedLogicalNotationItemIDs,
            isPlaying: state.playbackDisplayState.isPlaying,
            notationActions: actions,
            actions: stemActions
        )
        .frame(height: stemTracksHeight, alignment: .top)
    }

    private var visibleStemRowCount: Int {
        state.stemFiles.isEmpty ? StemSeparationMethod.defaultValue.stemTypes.count : state.stemFiles.count
    }

    private var stemTracksHeight: CGFloat {
        AppTheme.Timeline.stemTracksHeight(
            rowCount: visibleStemRowCount,
            expandedStemNotationCount: expandedStemNotationRowCount
        )
    }

    private var expandedStemNotationRowCount: Int {
        state.stemFiles.filter {
            state.stemNotationTrackCollapsed[$0.type] == false
        }.count
    }

    private var tracksHeight: CGFloat {
        AppTheme.Timeline.tracksMinimumHeight(
            stemRowCount: visibleStemRowCount,
            isNotationTrackCollapsed: state.isNotationTrackCollapsed,
            expandedStemNotationCount: expandedStemNotationRowCount
        )
    }

    private var upperTrackStackHeight: CGFloat {
        AppTheme.Timeline.upperTrackStackHeight(
            isNotationTrackCollapsed: state.isNotationTrackCollapsed
        )
    }

    private var notationTrackCurrentHeight: CGFloat {
        AppTheme.Timeline.notationTrackCurrentHeight(
            isCollapsed: state.isNotationTrackCollapsed
        )
    }

    private var isNotationNoteEntryModeEnabled: Bool {
        state.notationEntryMode == .note
    }

    private var isNotationRestEntryModeEnabled: Bool {
        state.notationEntryMode == .rest
    }

    private var upperTrackStack: some View {
        VStack(spacing: AppTheme.Spacing.none) {
            timelineTrackRow(height: AppTheme.Timeline.regionTrackHeight) {
                RegionTrackView(
                    duration: timelineDuration,
                    notes: state.notes,
                    selectedRegionID: state.selectedRegionID,
                    configuration: state.beatGrid,
                    onSelectRegion: actions.selectRegion,
                    onActivateRegionAsLoop: actions.activateRegionAsLoop,
                    onFocusRegion: actions.focusRegion,
                    onEditRegion: actions.editNote,
                    onDeleteRegion: actions.deleteNote,
                    onRegionColorChanged: actions.noteColorChanged,
                    onRegionCustomColorChanged: actions.noteCustomColorChanged,
                    onRegionRangeChanged: actions.regionRangeChanged
                )
            }

            timelineTrackRow(height: AppTheme.Timeline.markerTrackHeight) {
                MarkerTrackView(
                    duration: timelineDuration,
                    notes: state.notes,
                    configuration: state.beatGrid,
                    onEditMarker: actions.editNote,
                    onDeleteMarker: actions.deleteNote,
                    onMarkerColorChanged: actions.noteColorChanged,
                    onMarkerCustomColorChanged: actions.noteCustomColorChanged,
                    onMarkerTimeChanged: actions.markerTimeChanged
                )
            }

            timelineTrackRow(height: AppTheme.Timeline.tempoTrackHeight) {
                TempoTrackView(
                    duration: timelineDuration,
                    loopStart: state.loopStart,
                    loopEnd: state.loopEnd,
                    playbackMarkerTime: state.playbackMarkerTime,
                    configuration: state.beatGrid,
                    onSaveLoopRegion: actions.saveLoopRegion,
                    onLoopStartChanged: actions.loopStartChanged,
                    onLoopEndChanged: actions.loopEndChanged,
                    onLoopRegionChanged: actions.loopRegionChanged
                )
            }

            mainTrackRow
                .frame(height: AppTheme.Timeline.waveformTrackHeight)

            notationTrackRow
                .frame(height: notationTrackCurrentHeight)
        }
    }

    private var timelineScrollOverlay: some View {
        ZStack(alignment: .topLeading) {
            timelineScrollCaptureArea
                .frame(height: AppTheme.Timeline.zoomableUpperTrackStackHeight)

            stemScrollCaptureOverlay
                .frame(height: stemTracksHeight)
                .offset(y: upperTrackStackHeight + AppTheme.Timeline.trackSpacing)
        }
        .frame(height: tracksHeight, alignment: .topLeading)
    }

    private var stemScrollCaptureOverlay: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            ForEach(visibleStemTypes) { type in
                VStack(spacing: AppTheme.Timeline.trackSpacing) {
                    timelineScrollCaptureArea
                        .frame(height: AppTheme.Timeline.stemTrackHeight)

                    if isStemNotationExpanded(type) {
                        if stemNoteDisplayMode(for: type) == .midi {
                            Color.clear
                                .frame(height: AppTheme.Timeline.notationTrackHeight)
                                .allowsHitTesting(false)
                        } else {
                            timelineScrollCaptureArea
                                .frame(height: AppTheme.Timeline.notationTrackHeight)
                        }
                    }
                }
            }
        }
    }

    private var visibleStemTypes: [StemType] {
        state.stemFiles.isEmpty
            ? StemSeparationMethod.defaultValue.stemTypes
            : state.stemFiles.map(\.type)
    }

    private func isStemNotationExpanded(_ type: StemType) -> Bool {
        state.stemFiles.contains(where: { $0.type == type })
            && state.stemNotationTrackCollapsed[type] == false
    }

    private func stemNoteDisplayMode(for type: StemType) -> StemNoteDisplayMode {
        state.stemNoteDisplayModes[type] ?? .notation
    }

    private var timelineScrollCaptureArea: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Color.clear
                .frame(width: trackControlWidth)

            TimelineScrollCaptureView { event in
                let anchorTime = viewport.time(forX: event.locationX, width: event.width)
                actions.timelineScroll(event.deltaX, event.deltaY, anchorTime)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func timelineTrackRow<Content: View>(
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Color.clear
                .frame(width: trackControlWidth)

            content()
        }
        .frame(height: height)
    }

    private var mainTrackRow: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            mainTrackControls
                .frame(width: trackControlWidth)

            audioTrack
        }
    }

    private var notationTrackRow: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            notationTrackControls
                .frame(width: trackControlWidth)
                .frame(height: notationTrackCurrentHeight, alignment: .topLeading)

            notationTrackContent
        }
    }

    @ViewBuilder
    private var notationTrackContent: some View {
        if !state.isNotationTrackCollapsed {
            NotationTrackView(
                state: state.notationViewport,
                measureLayout: state.notationMeasureLayout,
                partID: .main,
                playbackDisplayState: state.playbackDisplayState,
                selectedHarmonySymbolID: state.selectedHarmonySymbolID,
                selectedMeasures: state.selectedNotationMeasures,
                selectedItem: state.selectedNotationItem,
                selectedDuration: NotationDuration(
                    denominator: state.notationDurationDenominator,
                    isDotted: state.notationDurationIsDotted
                ),
                selectedDrumInstrumentMIDINoteNumber: state.selectedDrumInstrumentMIDINoteNumber,
                entryMode: state.notationEntryMode,
                pendingNotationAccidental: state.pendingNotationAccidental,
                pendingEditorRequest: state.pendingHarmonyEditorRequest,
                actions: actions.notationTrackActions(allowsHarmony: true)
            )
            .frame(height: AppTheme.Timeline.notationTrackHeight)
            .overlay {
                if state.duration > 0 {
                    RightClickMenuCaptureView(
                        title: "Show in the Window",
                        action: actions.showNotationWindow
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: notationTrackCurrentHeight)
        }
    }

    private var notationTrackControls: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            notationTrackHeader

            if !state.isNotationTrackCollapsed {
                if state.notationViewport.clef == .drums {
                    DrumInstrumentPaletteButton(
                        selectedMIDINoteNumber: state.selectedDrumInstrumentMIDINoteNumber,
                        selectInstrument: actions.selectDrumInstrument
                    )
                }

                CompactNotationEntryControls(
                    duration: state.duration,
                    entryMode: state.notationEntryMode,
                    notePresentation: .init(
                        help: "Add notes to Notation (N)",
                        accessibilityLabel: "Notation Note Entry",
                        accessibilityValue: isNotationNoteEntryModeEnabled ? "Enabled" : "Disabled"
                    ),
                    restPresentation: .init(
                        help: "Add rests to Notation",
                        accessibilityLabel: "Notation Rest Entry",
                        accessibilityValue: isNotationRestEntryModeEnabled ? "Enabled" : "Disabled"
                    ),
                    notationDurationDenominator: state.notationDurationDenominator,
                    notationDurationIsDotted: state.notationDurationIsDotted,
                    pendingNotationAccidental: state.pendingNotationAccidental,
                    showsAccidental: state.notationViewport.clef != .drums,
                    canChangeNotationDuration: state.canChangeNotationDuration,
                    tieCommandStatus: state.tieCommandStatus,
                    notationNoteEntryModeToggled: actions.notationNoteEntryModeToggled,
                    notationRestEntryModeToggled: actions.notationRestEntryModeToggled,
                    notationDurationChanged: actions.notationDurationChanged,
                    notationDurationDotToggled: actions.notationDurationDotToggled,
                    notationAccidentalSelected: actions.notationAccidentalSelected,
                    addTiedNotationNote: actions.addTiedNotationNote
                )
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .controlSize(.small)
    }

    private var notationTrackHeader: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text("Notation")
                .font(AppTheme.Typography.noteTitle)
                .lineLimit(1)

            Spacer(minLength: AppTheme.Spacing.sm)

            TimelineIconButton(
                systemName: NotationTrackTogglePresentation.systemName(
                    isCollapsed: state.isNotationTrackCollapsed
                ),
                helpText: notationTrackToggleHelpText,
                accessibilityLabel: notationTrackToggleHelpText,
                accessibilityValue: state.isNotationTrackCollapsed ? "Collapsed" : "Expanded"
            ) {
                actions.notationTrackCollapsedChanged(!state.isNotationTrackCollapsed)
            }
        }
    }

    private var notationTrackToggleHelpText: String {
        state.isNotationTrackCollapsed
            ? ControlHelpText.expandNotationTrack
            : ControlHelpText.collapseNotationTrack
    }

    private var mainTrackControls: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Main")
                .font(AppTheme.Typography.noteTitle)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            JammValueSlider(
                value: Binding(
                    get: { Double(state.mainTrackVolume) },
                    set: { actions.mainTrackVolumeChanged(Float($0)) }
                ),
                minValue: 0,
                maxValue: 1,
                defaultValue: Double(AppSliderDefaults.mainTrackVolume),
                step: 0.01,
                sensitivity: 1,
                precision: 0,
                displayFormatter: { "\(Int(($0 * 100).rounded()))%" },
                accessibilityLabel: "Main Volume"
            )
            .frame(
                width: AppTheme.ControlSize.jammValueSliderWidth,
                height: AppTheme.ControlSize.jammValueSliderHeight
            )
            .disabled(state.duration <= 0)
            .help(ControlHelpText.mainTrackVolume)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .controlSize(.small)
        .disabled(!isMainTrackActive)
        .opacity(isMainTrackActive ? 1 : 0.45)
    }

    private var audioTrack: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: AppTheme.Radius.panel)
                    .fill(mainTrackBackgroundColor)

                let visibleRange = viewport.clampedRange
                PeakformTimelineView(
                    peakformData: state.peakformData,
                    duration: timelineDuration,
                    currentTime: state.currentTime,
                    playbackMarkerTime: state.playbackMarkerTime,
                    playbackDisplayState: state.playbackDisplayState,
                    loopStart: state.loopStart,
                    loopEnd: state.loopEnd,
                    notes: state.notes,
                    selectedRegionID: state.selectedRegionID,
                    tempoMap: state.beatGrid.tempoMap,
                    visibleStartTime: visibleRange.lowerBound,
                    visibleEndTime: visibleRange.upperBound,
                    isLoading: state.isLoadingPeakform,
                    showsImportPlaceholder: state.duration <= 0,
                    waveformColor: mainTrackWaveformColor
                )

                rightClickNoteTarget(width: proxy.size.width)
                noteLines(width: proxy.size.width)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.panel))
            .contentShape(Rectangle())
            .gesture(seekGesture(width: proxy.size.width))
        }
    }

    var viewport: TimelineViewport {
        if state.duration > 0 {
            return state.beatGrid.viewport(duration: state.duration)
        }

        return TimelineViewport(duration: timelineDuration, visibleRange: 0...timelineDuration)
    }

    private var timelineDuration: TimeInterval {
        state.duration > 0 ? state.duration : AppDefaults.startupGridDuration
    }

    private var isMainTrackActive: Bool {
        state.playbackMode == .original
    }

    private var mainTrackBackgroundColor: Color {
        isMainTrackActive ? appColors.waveformBackground : appColors.waveformDisabledBackground
    }

    private var mainTrackWaveformColor: Color {
        isMainTrackActive ? appColors.waveformColor : appColors.waveformDisabledColor
    }
}

private struct StemTracksSection: View {
    let playbackMode: PlaybackMode
    let mixState: StemMixState
    let stemFiles: [StemFile]
    let stemPeakforms: [StemType: PeakformData]
    let isLoadingStemPeakforms: Bool
    let transcriptionStates: [StemType: StemTranscriptionViewState]
    let stemTypesWithTranscription: Set<StemType>
    let hasPendingTranscriptionOverwrite: Bool
    let duration: TimeInterval
    let viewport: TimelineViewport
    let trackControlWidth: CGFloat
    let selectedMeasures: [NotationMeasureSelection]
    let selectedItem: NotationItemSelection?
    let selectedDuration: NotationDuration
    let selectedDrumInstrumentMIDINoteNumber: Int
    let entryMode: NotationEntryMode?
    let canChangeNotationDuration: Bool
    let tieCommandStatus: NotationTieCommandStatus
    let notationDurationDenominator: Int
    let notationDurationIsDotted: Bool
    let pendingNotationAccidental: NotationAccidental?
    let notationViewports: [StemType: NotationViewportState]
    let measureLayout: NotationSystemMeasureLayout?
    let notationCollapsed: [StemType: Bool]
    let noteDisplayModes: [StemType: StemNoteDisplayMode]
    let selectedLogicalItemIDs: Set<String>
    let isPlaying: Bool
    let notationActions: TimelineViewActions
    let actions: StemTrackActions
    @Environment(\.appColors) private var appColors
    @State private var midiScrollPitches: [StemType: Int] = [:]

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            ForEach(visibleStemTypes) { type in
                row(type)
            }
        }
    }

    private var visibleStemTypes: [StemType] {
        stemFiles.isEmpty ? StemSeparationMethod.defaultValue.stemTypes : stemFiles.map(\.type)
    }

    private func row(_ type: StemType) -> some View {
        let item = mixState.item(for: type)
        let isRowEnabled = item.isAvailable && areStemTracksActive
        let isLaneActive = isRowEnabled && mixState.isAudible(type)

        return VStack(spacing: AppTheme.Timeline.trackSpacing) {
            HStack(spacing: AppTheme.Spacing.md) {
                controls(type: type, item: item)
                    .frame(width: trackControlWidth)
                    .frame(height: AppTheme.Timeline.stemTrackHeight)

                StemPeakformLaneView(
                    peakformData: stemPeakforms[type],
                    duration: duration,
                    viewport: viewport,
                    isLoading: isLoadingStemPeakforms,
                    isAvailable: item.isAvailable,
                    isActive: isLaneActive
                )
                .frame(height: AppTheme.Timeline.stemTrackHeight)
                .opacity(isRowEnabled ? 1 : 0.45)
            }
            .frame(height: AppTheme.Timeline.stemTrackHeight)

            if item.isAvailable && !isNotationCollapsed(type) {
                stemNotationRow(type)
            }
        }
        .frame(
            height: AppTheme.Timeline.stemRowHeight(
                isNotationExpanded: item.isAvailable && !isNotationCollapsed(type)
            )
        )
        .controlSize(.small)
    }

    private func controls(type: StemType, item: StemMixItem) -> some View {
        let isRowEnabled = item.isAvailable && areStemTracksActive

        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.md) {
                    Circle()
                        .fill(isRowEnabled ? appColors.accent : appColors.disabledText)
                        .frame(width: 7, height: 7)

                    Text(type.title)
                        .font(AppTheme.Typography.noteTitle)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: AppTheme.Spacing.md) {
                    transcriptionControl(type: type, isAvailable: item.isAvailable)

                    AppLetterToggleButton(
                        title: "M",
                        isActive: item.isMuted,
                        activeFillColor: appColors.statusButtonCriticalFill,
                        inactiveTextColor: appColors.statusButtonCriticalFill
                    ) {
                        actions.muteToggled(type)
                    }
                    .disabled(!isRowEnabled)
                    .help(ControlHelpText.muteTrack(type.title))
                    .accessibilityLabel("Mute \(type.title)")

                    TimelineIconButton(
                        systemName: NotationTrackTogglePresentation.systemName(
                            isCollapsed: isNotationCollapsed(type)
                        ),
                        helpText: notationToggleHelpText(type),
                        accessibilityLabel: notationToggleHelpText(type),
                        accessibilityValue: isNotationCollapsed(type) ? "Collapsed" : "Expanded"
                    ) {
                        notationActions.stemNotationTrackCollapsedChanged(type, !isNotationCollapsed(type))
                    }
                    .disabled(!item.isAvailable)
                }
            }

            HStack(spacing: AppTheme.Spacing.md) {
                JammValueSlider(
                    value: Binding(
                        get: { Double(item.volume) },
                        set: { actions.volumeChanged(type, Float($0)) }
                    ),
                    minValue: 0,
                    maxValue: 1,
                    defaultValue: Double(AppSliderDefaults.stemTrackVolume),
                    step: 0.01,
                    sensitivity: 1,
                    precision: 0,
                    displayFormatter: { "\(Int(($0 * 100).rounded()))%" },
                    accessibilityLabel: "\(type.title) Volume"
                )
                .frame(
                    width: AppTheme.ControlSize.jammValueSliderWidth,
                    height: AppTheme.ControlSize.jammValueSliderHeight
                )
                .disabled(!isRowEnabled)
                .help(ControlHelpText.trackVolume(type.title))

                Spacer(minLength: AppTheme.Spacing.none)

                HStack(spacing: AppTheme.Spacing.md) {
                    AppLetterToggleButton(
                        title: "S",
                        isActive: item.isSoloed,
                        activeFillColor: appColors.statusButtonAttentionFill,
                        inactiveTextColor: appColors.statusButtonAttentionFill
                    ) {
                        actions.soloToggled(type)
                    }
                    .disabled(!isRowEnabled)
                    .help(ControlHelpText.soloTrack(type.title))
                    .accessibilityLabel("Solo \(type.title)")

                    TimelineIconButton(
                        systemName: "pianokeys",
                        helpText: displayModeToggleHelpText(type),
                        accessibilityLabel: displayModeToggleHelpText(type),
                        accessibilityValue: noteDisplayMode(for: type) == .midi ? "MIDI" : "Notation",
                        isActive: noteDisplayMode(for: type) == .midi
                    ) {
                        notationActions.stemNoteDisplayModeToggled(type)
                    }
                    .disabled(!item.isAvailable)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    @ViewBuilder
    private func transcriptionControl(type: StemType, isAvailable: Bool) -> some View {
        let state = transcriptionStates[type] ?? StemTranscriptionViewState()
        if type.supportsBasicPitchTranscription, state.isRunning {
            HStack(spacing: AppTheme.Spacing.sm) {
                ProgressView(value: state.progress)
                    .progressViewStyle(.linear)
                    .frame(width: AppTheme.ControlSize.jammValueSliderWidth / 2)
                    .help(state.status)
                    .accessibilityLabel("\(type.title) transcription progress")
                    .accessibilityValue("\(Int((state.progress * 100).rounded())) percent")

                Button {
                    actions.cancelTranscription(type)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .help("Cancel \(type.title) transcription")
                .accessibilityLabel("Cancel \(type.title) transcription")
            }
        } else if type.supportsBasicPitchTranscription {
            Menu {
                Button("Transcribe to Notes") {
                    actions.transcribe(type)
                }
                if stemTypesWithTranscription.contains(type) {
                    Divider()
                    Button("Export Latest Transcription as MIDI…") {
                        actions.exportTranscriptionMIDI(type)
                    }
                }
            } label: {
                Image(systemName: "waveform.badge.plus")
                    .frame(
                        width: AppTheme.Timeline.viewportControlButtonSize,
                        height: AppTheme.Timeline.viewportControlButtonSize
                    )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!isAvailable || hasPendingTranscriptionOverwrite)
            .help("Transcribe \(type.title) to notes")
            .accessibilityLabel("Transcribe \(type.title) to Notes")
        }
    }

    private var areStemTracksActive: Bool {
        playbackMode == .stems
    }

    private func stemNotationRow(_ type: StemType) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            stemNotationControls(type)
                .frame(width: trackControlWidth)
                .frame(height: AppTheme.Timeline.notationTrackHeight, alignment: .topLeading)

            stemNoteContent(type)
                .frame(height: AppTheme.Timeline.notationTrackHeight)
        }
    }

    @ViewBuilder
    private func stemNoteContent(_ type: StemType) -> some View {
        let viewportState = notationViewports[type] ?? .pending(
            visibleMeasureCount: 1,
            keySignature: .cMajor
        )
        if noteDisplayMode(for: type) == .midi {
            MIDIPianoRollView(
                state: viewportState,
                partID: .stem(type),
                partTitle: type.title,
                selectedItem: selectedItem,
                selectedDuration: selectedDuration,
                selectedDrumInstrumentMIDINoteNumber: selectedDrumInstrumentMIDINoteNumber,
                entryMode: entryMode,
                actions: notationActions.midiPianoRollActions(),
                scrollPitch: midiScrollPitchBinding(for: type),
                selectedLogicalItemIDs: selectedLogicalItemIDs,
                isPlaying: isPlaying,
                onPageStartTimeChanged: {
                    notationActions.stemMIDIPageStartChanged(type, $0)
                },
                onInteractionEnded: {
                    notationActions.stemMIDIInteractionEnded(type)
                }
            )
        } else {
            NotationTrackView(
                state: viewportState,
                measureLayout: measureLayout,
                partID: .stem(type),
                playbackDisplayState: nil,
                selectedHarmonySymbolID: nil,
                selectedMeasures: selectedMeasures,
                selectedItem: selectedItem,
                selectedDuration: selectedDuration,
                selectedDrumInstrumentMIDINoteNumber: selectedDrumInstrumentMIDINoteNumber,
                entryMode: entryMode,
                pendingNotationAccidental: pendingNotationAccidental,
                pendingEditorRequest: nil,
                actions: notationActions.notationTrackActions(allowsHarmony: false)
            )
        }
    }

    private func stemNotationControls(_ type: StemType) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(noteDisplayMode(for: type) == .midi ? "MIDI" : "Notation")
                .font(AppTheme.Typography.noteTitle)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if (notationViewports[type]?.clef ?? .treble) == .drums {
                DrumInstrumentPaletteButton(
                    selectedMIDINoteNumber: selectedDrumInstrumentMIDINoteNumber,
                    selectInstrument: notationActions.selectDrumInstrument
                )
            }

            CompactNotationEntryControls(
                duration: duration,
                entryMode: entryMode,
                notePresentation: .init(
                    help: "Add notes to \(type.title) \(noteDisplayTitle(for: type)) (N)",
                    accessibilityLabel: "\(type.title) \(noteDisplayTitle(for: type)) Note Entry"
                ),
                restPresentation: .init(
                    help: "Add rests to \(type.title) \(noteDisplayTitle(for: type))",
                    accessibilityLabel: "\(type.title) \(noteDisplayTitle(for: type)) Rest Entry"
                ),
                notationDurationDenominator: notationDurationDenominator,
                notationDurationIsDotted: notationDurationIsDotted,
                pendingNotationAccidental: pendingNotationAccidental,
                showsAccidental: noteDisplayMode(for: type) == .notation
                    && (notationViewports[type]?.clef ?? .treble) != .drums,
                canChangeNotationDuration: canChangeNotationDuration,
                tieCommandStatus: tieCommandStatus,
                notationNoteEntryModeToggled: notationActions.notationNoteEntryModeToggled,
                notationRestEntryModeToggled: notationActions.notationRestEntryModeToggled,
                notationDurationChanged: notationActions.notationDurationChanged,
                notationDurationDotToggled: notationActions.notationDurationDotToggled,
                notationAccidentalSelected: notationActions.notationAccidentalSelected,
                addTiedNotationNote: notationActions.addTiedNotationNote
            )
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    private func isNotationCollapsed(_ type: StemType) -> Bool {
        notationCollapsed[type] ?? true
    }

    private func notationToggleHelpText(_ type: StemType) -> String {
        isNotationCollapsed(type)
            ? "Expand \(type.title) \(noteDisplayTitle(for: type))"
            : "Collapse \(type.title) \(noteDisplayTitle(for: type))"
    }

    private func noteDisplayMode(for type: StemType) -> StemNoteDisplayMode {
        noteDisplayModes[type] ?? .notation
    }

    private func noteDisplayTitle(for type: StemType) -> String {
        noteDisplayMode(for: type) == .midi ? "MIDI" : "Notation"
    }

    private func displayModeToggleHelpText(_ type: StemType) -> String {
        noteDisplayMode(for: type) == .midi
            ? "Show \(type.title) as Notation"
            : "Show \(type.title) as MIDI"
    }

    private func midiScrollPitchBinding(for type: StemType) -> Binding<Int?> {
        Binding(
            get: { midiScrollPitches[type] },
            set: { newValue in
                if let newValue {
                    midiScrollPitches[type] = newValue
                } else {
                    midiScrollPitches.removeValue(forKey: type)
                }
            }
        )
    }
}

private struct CompactNotationEntryControls: View {
    struct EntryButtonPresentation {
        var help: String
        var accessibilityLabel: String
        var accessibilityValue: String?
    }

    let duration: TimeInterval
    let entryMode: NotationEntryMode?
    let notePresentation: EntryButtonPresentation
    let restPresentation: EntryButtonPresentation
    let notationDurationDenominator: Int
    let notationDurationIsDotted: Bool
    let pendingNotationAccidental: NotationAccidental?
    let showsAccidental: Bool
    let canChangeNotationDuration: Bool
    let tieCommandStatus: NotationTieCommandStatus
    let notationNoteEntryModeToggled: () -> Void
    let notationRestEntryModeToggled: () -> Void
    let notationDurationChanged: (Int) -> Void
    let notationDurationDotToggled: () -> Void
    let notationAccidentalSelected: (NotationAccidental) -> Void
    let addTiedNotationNote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.xs) {
                entryModeButton(
                    mode: .note,
                    isActive: entryMode == .note,
                    presentation: notePresentation,
                    action: notationNoteEntryModeToggled
                )

                entryModeButton(
                    mode: .rest,
                    isActive: entryMode == .rest,
                    presentation: restPresentation,
                    action: notationRestEntryModeToggled
                )

                NotationDurationMenu(
                    denominator: Binding(
                        get: { notationDurationDenominator },
                        set: { notationDurationChanged($0) }
                    ),
                    isEnabled: canChangeNotationDuration
                )
            }

            HStack(spacing: AppTheme.Spacing.xs) {
                NotationAugmentationDotButton(
                    isActive: notationDurationIsDotted,
                    action: notationDurationDotToggled
                )
                .disabled(!canChangeNotationDuration)

                if showsAccidental {
                    NotationAccidentalMenu(
                        pendingAccidental: pendingNotationAccidental,
                        action: notationAccidentalSelected
                    )
                    .disabled(duration <= 0)
                }

                NotationTieButton(
                    status: tieCommandStatus,
                    action: addTiedNotationNote
                )
            }
        }
    }

    @ViewBuilder
    private func entryModeButton(
        mode: NotationEntryMode,
        isActive: Bool,
        presentation: EntryButtonPresentation,
        action: @escaping () -> Void
    ) -> some View {
        let button = NotationEntryModeButton(mode: mode, isActive: isActive, action: action)
            .disabled(duration <= 0)
            .help(presentation.help)
            .accessibilityLabel(presentation.accessibilityLabel)

        if let accessibilityValue = presentation.accessibilityValue {
            button.accessibilityValue(accessibilityValue)
        } else {
            button
        }
    }
}

private struct StemPeakformLaneView: View {
    let peakformData: PeakformData?
    let duration: TimeInterval
    let viewport: TimelineViewport
    let isLoading: Bool
    let isAvailable: Bool
    let isActive: Bool
    @Environment(\.appColors) private var appColors

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(
                Path(roundedRect: rect, cornerRadius: AppTheme.Radius.small),
                with: .color(backgroundColor)
            )

            guard isAvailable && duration > 0 else {
                PeakformRenderer.drawEmpty(in: &context, size: size, colors: appColors, waveformColor: waveformColor)
                return
            }

            PeakformRenderer.draw(
                peakformData: peakformData,
                viewport: viewport,
                in: &context,
                size: size,
                colors: appColors,
                waveformColor: waveformColor
            )
        }
        .overlay {
            if isAvailable && isActive && isLoading && peakformData == nil {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
    }

    private var backgroundColor: Color {
        isActive && isAvailable ? appColors.waveformBackground : appColors.waveformDisabledBackground
    }

    private var waveformColor: Color {
        isActive && isAvailable ? appColors.waveformColor : appColors.waveformDisabledColor
    }
}
