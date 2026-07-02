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
    var loopStart: TimeInterval
    var loopEnd: TimeInterval
    var notes: [TimecodedNote]
    var selectedHarmonySymbolID: HarmonySymbol.ID?
    var selectedNotationMeasures: [NotationMeasureSelection]
    var selectedNotationBeat: NotationBeatSelection?
    var harmonyInputResolutionDenominator: Int
    var pendingHarmonyEditorRequest: HarmonyEditorRequest?
    var selectedRegionID: TimecodedNote.ID?
    var beatGrid: BeatGridConfiguration
    var notationViewport: NotationViewportState
    var isLoadingPeakform: Bool
    var mainTrackVolume: Float
    var playbackMode: PlaybackMode
    var mixState: StemMixState
    var stemFiles: [StemFile]
    var stemPeakforms: [StemType: PeakformData]
    var isLoadingStemPeakforms: Bool
}

struct TimelineViewActions {
    var locatePlaybackMarker: (TimeInterval) -> Void
    var addNote: (TimeInterval) -> Void
    var harmonyInputResolutionChanged: (Int) -> Void
    var selectHarmony: (HarmonySymbol.ID?) -> Void
    var selectNotationMeasure: (ScoreMeasure?, Bool) -> Void
    var selectNotationBeat: (NotationBeatSelection?) -> Void
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
    var showNotationWindow: () -> Void
}

struct StemTrackActions {
    var volumeChanged: (StemType, Float) -> Void
    var muteToggled: (StemType) -> Void
    var soloToggled: (StemType) -> Void
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
            duration: state.duration,
            viewport: viewport,
            trackControlWidth: trackControlWidth,
            actions: stemActions
        )
        .frame(height: stemTracksHeight, alignment: .top)
    }

    private var visibleStemRowCount: Int {
        state.stemFiles.isEmpty ? StemSeparationMethod.defaultValue.stemTypes.count : state.stemFiles.count
    }

    private var stemTracksHeight: CGFloat {
        AppTheme.Timeline.stemTracksHeight(rowCount: visibleStemRowCount)
    }

    private var tracksHeight: CGFloat {
        AppTheme.Timeline.tracksMinimumHeight(stemRowCount: visibleStemRowCount)
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
                .frame(height: AppTheme.Timeline.notationTrackHeight)
        }
    }

    private var timelineScrollOverlay: some View {
        ZStack(alignment: .topLeading) {
            timelineScrollCaptureArea
                .frame(height: AppTheme.Timeline.zoomableUpperTrackStackHeight)

            timelineScrollCaptureArea
                .frame(height: stemTracksHeight)
                .offset(y: AppTheme.Timeline.upperTrackStackHeight + AppTheme.Timeline.trackSpacing)
        }
        .frame(height: tracksHeight, alignment: .topLeading)
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
        HStack(spacing: AppTheme.Spacing.md) {
            notationTrackControls
                .frame(width: trackControlWidth)
                .frame(height: AppTheme.Timeline.notationTrackHeight)

            NotationTrackView(
                state: state.notationViewport,
                selectedHarmonySymbolID: state.selectedHarmonySymbolID,
                selectedMeasures: state.selectedNotationMeasures,
                selectedBeat: state.selectedNotationBeat,
                pendingEditorRequest: state.pendingHarmonyEditorRequest,
                inputResolution: HarmonyInputResolution(denominator: state.harmonyInputResolutionDenominator),
                actions: NotationTrackActions(
                    selectHarmony: actions.selectHarmony,
                    selectMeasure: actions.selectNotationMeasure,
                    selectBeat: actions.selectNotationBeat,
                    saveHarmony: actions.saveHarmony,
                    deleteHarmony: actions.deleteHarmony,
                    adjacentHarmonyPlacement: actions.adjacentHarmonyPlacement
                )
            )
                .frame(height: AppTheme.Timeline.notationTrackHeight)
        }
        .overlay {
            if state.duration > 0 {
                RightClickMenuCaptureView(
                    title: "Show in the Window",
                    action: actions.showNotationWindow
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var notationTrackControls: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Notation")
                .font(AppTheme.Typography.noteTitle)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: AppTheme.Spacing.xxs) {
                Text("1/")
                    .font(AppTheme.Typography.captionMonospaced)
                    .foregroundStyle(appColors.secondaryText)

                AbletonNumberField(
                    value: Binding(
                        get: { Double(state.harmonyInputResolutionDenominator) },
                        set: { actions.harmonyInputResolutionChanged(Int($0.rounded())) }
                    ),
                    minValue: 1,
                    maxValue: 8,
                    defaultValue: Double(HarmonyInputResolution.defaultDenominator),
                    step: 1,
                    precision: 0,
                    accessibilityLabel: "Harmony Input Resolution"
                )
                .frame(
                    width: AppTheme.ControlSize.toolbarTimeSignatureNumberFieldWidth,
                    height: AppTheme.ControlSize.abletonNumberFieldHeight
                )
                .disabled(!state.notationViewport.isReady)
                .help(ControlHelpText.harmonyInputResolution)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .controlSize(.small)
        .opacity(state.notationViewport.isReady ? 1 : 0.5)
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
    let duration: TimeInterval
    let viewport: TimelineViewport
    let trackControlWidth: CGFloat
    let actions: StemTrackActions
    @Environment(\.appColors) private var appColors

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

        return HStack(spacing: AppTheme.Spacing.md) {
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
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    private var areStemTracksActive: Bool {
        playbackMode == .stems
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
