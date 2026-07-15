import SwiftUI
import UniformTypeIdentifiers

enum NotesFilter: String, CaseIterable, Identifiable {
    case notes
    case markers
    case regions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes:
            return "All"
        case .markers:
            return "Markers"
        case .regions:
            return "Regions"
        }
    }
}

extension ContentView {
    var scrollableWorkspaceContent: some View {
        GeometryReader { proxy in
            let viewportContentHeight = max(
                0,
                proxy.size.height - AppTheme.Spacing.pagePadding * 2
            )
            let workspaceHeight = max(
                viewportContentHeight,
                timelineColumnMinimumHeight
            )

            ScrollView(.vertical) {
                workspaceContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: workspaceHeight, alignment: .topLeading)
                    .padding(AppTheme.Spacing.pagePadding)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        }
    }

    var workspaceContent: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sectionGap) {
            timelineColumn

            inspectorSidebar
        }
        .frame(
            maxWidth: .infinity,
            minHeight: timelineColumnMinimumHeight,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    var timelineColumn: some View {
        GeometryReader { proxy in
            let columnHeight = max(proxy.size.height, timelineColumnMinimumHeight)
            let timelineHeight = max(
                timelineMinimumContentHeight,
                columnHeight - AppTheme.Spacing.md - AppTheme.ControlSize.transportBarMinHeight
            )
            let notationTrackContentWidth = max(
                1,
                proxy.size.width - AppTheme.Timeline.trackControlWidth - AppTheme.Spacing.md
            )

            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                timelineBlock(
                    height: timelineHeight,
                    notationTrackContentWidth: notationTrackContentWidth
                )

                transportBar
                    .frame(height: AppTheme.ControlSize.transportBarMinHeight)
            }
            .frame(width: proxy.size.width, height: columnHeight, alignment: .topLeading)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: timelineColumnMinimumHeight,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .layoutPriority(2)
    }

    func timelineBlock(
        height: CGFloat,
        notationTrackContentWidth: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            timelineTrackHeadersPanelBackground(height: height)

            VStack(spacing: AppTheme.Spacing.none) {
                timelineSection(notationTrackContentWidth: notationTrackContentWidth)
                    .frame(height: timelineTracksHeight, alignment: .top)

                Spacer(minLength: AppTheme.Timeline.viewportFooterGap)

                timelineViewportControlBar
                    .frame(height: AppTheme.Timeline.viewportControlBarHeight)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height, alignment: .topLeading)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            handleMediaDrop(providers: providers)
        }
    }

    func timelineSection(notationTrackContentWidth: CGFloat) -> some View {
        WaveformTimelineView(
            state: timelineViewState(notationTrackContentWidth: notationTrackContentWidth),
            actions: timelineViewActions,
            stemActions: stemTrackActions
        )
        .frame(height: timelineTracksHeight, alignment: .top)
    }

    var timelineStemRowCount: Int {
        viewModel.stemFiles.isEmpty ? StemSeparationMethod.defaultValue.stemTypes.count : viewModel.stemFiles.count
    }

    var timelineTracksHeight: CGFloat {
        AppTheme.Timeline.tracksMinimumHeight(
            stemRowCount: timelineStemRowCount,
            isNotationTrackCollapsed: viewModel.isNotationTrackCollapsed,
            expandedStemNotationCount: expandedStemNotationRowCount
        )
    }

    var expandedStemNotationRowCount: Int {
        viewModel.stemFiles.filter {
            !viewModel.isStemNotationTrackCollapsed($0.type)
        }.count
    }

    var timelineMinimumContentHeight: CGFloat {
        AppTheme.Timeline.minimumContentHeight(
            stemRowCount: timelineStemRowCount,
            isNotationTrackCollapsed: viewModel.isNotationTrackCollapsed,
            expandedStemNotationCount: expandedStemNotationRowCount
        )
    }

    var timelineColumnMinimumHeight: CGFloat {
        timelineMinimumContentHeight
            + AppTheme.Spacing.md
            + AppTheme.ControlSize.transportBarMinHeight
    }

    func timelineViewState(notationTrackContentWidth: CGFloat) -> TimelineViewState {
        TimelineViewState(
            peakformData: viewModel.peakformData,
            duration: viewModel.duration,
            currentTime: viewModel.currentTime,
            playbackMarkerTime: viewModel.playbackMarkerTime,
            playbackDisplayState: viewModel.playbackDisplayState,
            loopStart: viewModel.loopRegion.start,
            loopEnd: viewModel.loopRegion.end,
            notes: viewModel.notes,
            selectedHarmonySymbolID: viewModel.selectedHarmonySymbolID,
            selectedNotationMeasures: viewModel.selectedNotationMeasures,
            selectedNotationItem: viewModel.selectedNotationItem,
            pendingHarmonyEditorRequest: viewModel.pendingHarmonyEditorRequest,
            selectedRegionID: viewModel.selectedRegionID,
            beatGrid: beatGrid,
            notationViewport: viewModel.isNotationTrackCollapsed
                ? .pending(
                    visibleMeasureCount: 1,
                    keySignature: KeySignature.normalized(from: viewModel.effectiveKeyName)
                )
                : notationViewportState(availableWidth: notationTrackContentWidth, partID: .main),
            stemNotationViewports: stemNotationViewports(availableWidth: notationTrackContentWidth),
            notationDurationDenominator: viewModel.notationDurationDenominator,
            notationDurationIsDotted: viewModel.notationDurationIsDotted,
            canChangeNotationDuration: viewModel.canChangeNotationDuration,
            notationEntryMode: viewModel.notationEntryMode,
            isNotationTrackCollapsed: viewModel.isNotationTrackCollapsed,
            stemNotationTrackCollapsed: viewModel.stemNotationTrackCollapsed,
            isLoadingPeakform: viewModel.isBuildingWaveform,
            mainTrackVolume: viewModel.mainTrackVolume,
            playbackMode: viewModel.playbackMode,
            mixState: viewModel.stemMixState,
            stemFiles: viewModel.stemFiles,
            stemPeakforms: viewModel.stemPeakforms,
            isLoadingStemPeakforms: viewModel.isBuildingStemPeakforms
        )
    }

    func notationViewportState(
        availableWidth: CGFloat,
        partID: NotationPartID
    ) -> NotationViewportState {
        let factory = NotationViewportFactory()
        let content = notationProjectionCache.content(
            tempoMap: viewModel.tempoMap,
            duration: viewModel.duration,
            keyName: viewModel.effectiveKeyName,
            clef: viewModel.notationClef(for: partID),
            partID: partID,
            includesHarmonies: partID.isMain,
            notationItems: viewModel.notationItems,
            harmonySymbols: viewModel.harmonySymbols,
            notes: viewModel.notes
        )
        let maximumMeasureCount = AppTheme.Timeline.notationMaximumVisibleMeasureCount
        let fittedMeasureCount = NotationVisibleMeasureFitter.fittedMeasureCount(
            availableWidth: availableWidth,
            maximumMeasureCount: maximumMeasureCount
        ) { measureCount in
            factory.viewportState(
                content: content,
                duration: viewModel.duration,
                currentTime: viewModel.currentTime,
                playbackMarkerTime: viewModel.playbackMarkerTime,
                isPlaying: viewModel.playbackState == .playing,
                visibleMeasureCount: measureCount
            )
        }

        return factory.viewportState(
            content: content,
            duration: viewModel.duration,
            currentTime: viewModel.currentTime,
            playbackMarkerTime: viewModel.playbackMarkerTime,
            isPlaying: viewModel.playbackState == .playing,
            visibleMeasureCount: fittedMeasureCount
        )
    }

    func stemNotationViewports(availableWidth: CGFloat) -> [StemType: NotationViewportState] {
        Dictionary(uniqueKeysWithValues: viewModel.stemFiles.map { stemFile in
            let isCollapsed = viewModel.isStemNotationTrackCollapsed(stemFile.type)
            let viewport: NotationViewportState = isCollapsed
                ? .pending(
                    visibleMeasureCount: 1,
                    keySignature: KeySignature.normalized(from: viewModel.effectiveKeyName)
                )
                : notationViewportState(
                    availableWidth: availableWidth,
                    partID: .stem(stemFile.type)
                )
            return (stemFile.type, viewport)
        })
    }

    var timelineViewActions: TimelineViewActions {
        TimelineViewActions(
            locatePlaybackMarker: { viewModel.locatePlaybackMarker(to: $0) },
            locatePlaybackMarkerExactly: { viewModel.locatePlaybackMarkerExactly(to: $0) },
            addNote: { viewModel.addNote(at: $0) },
            selectHarmony: { viewModel.selectHarmonySymbol(id: $0) },
            selectNotationMeasure: { viewModel.selectNotationMeasure($0, extendingSelection: $1, partID: $2) },
            selectNotationItem: { viewModel.selectNotationItem($0, shouldAudition: $1) },
            saveHarmony: { viewModel.saveHarmonySymbol($0) },
            deleteHarmony: { viewModel.deleteHarmonySymbol(id: $0) },
            adjacentHarmonyPlacement: { viewModel.adjacentHarmonyPlacement(from: $0, direction: $1) },
            addTempoTimeSignatureMarker: { beginAddingTempoTimeSignatureMarker(at: $0) },
            editNote: { beginEditingMarker($0) },
            deleteNote: { viewModel.deleteNote(id: $0) },
            noteColorChanged: { viewModel.updateNoteColor(id: $0, color: $1) },
            noteCustomColorChanged: { viewModel.updateNoteCustomColor(id: $0, hex: $1) },
            markerTimeChanged: { viewModel.updateMarkerTime(id: $0, time: $1) },
            saveLoopRegion: { viewModel.saveCurrentLoopRegionAsRegion() },
            selectRegion: { viewModel.selectRegion(id: $0) },
            activateRegionAsLoop: { viewModel.activateRegionAsLoopAndMoveMarker(id: $0) },
            focusRegion: { viewModel.focusRegion(id: $0) },
            regionRangeChanged: { viewModel.updateRegionRange(id: $0, start: $1, end: $2) },
            loopStartChanged: { viewModel.updateLoopStart($0) },
            loopEndChanged: { viewModel.updateLoopEnd($0) },
            loopRegionChanged: { viewModel.updateLoopRegion(start: $0, end: $1) },
            timelineScroll: { viewModel.handleTimelineScroll(deltaX: $0, deltaY: $1, anchorTime: $2) },
            mainTrackVolumeChanged: { viewModel.setMainTrackVolume($0) },
            notationTrackCollapsedChanged: { viewModel.setNotationTrackCollapsed($0) },
            stemNotationTrackCollapsedChanged: { viewModel.setStemNotationTrackCollapsed($0, isCollapsed: $1) },
            notationDurationChanged: { viewModel.setNotationDurationDenominator($0) },
            notationDurationDotToggled: { viewModel.toggleNotationDurationDot() },
            notationNoteEntryModeToggled: { viewModel.toggleNotationNoteEntryMode() },
            notationRestEntryModeToggled: { viewModel.toggleNotationRestEntryMode() },
            insertNotationNote: { viewModel.insertNotationNote($0) },
            insertNotationRest: { viewModel.insertNotationRest($0) },
            changeSelectedNotePitch: { viewModel.changeSelectedNotationNotePitch(to: $0, shouldAudition: $1) },
            changeNotationClef: { viewModel.setNotationClef($1, for: $0) },
            auditionNotePitch: { viewModel.auditionNotationNotePitch($0) },
            deleteSelectedNotationNote: { viewModel.deleteSelectedNotationNote() },
            showNotationWindow: { openWindow(id: AppWindowID.notation) }
        )
    }

    var stemTrackActions: StemTrackActions {
        StemTrackActions(
            volumeChanged: { viewModel.setStemVolume($0, volume: $1) },
            muteToggled: { viewModel.toggleStemMute($0) },
            soloToggled: { viewModel.toggleStemSolo($0) }
        )
    }

    var timelineViewportControlBar: some View {
        TimelineViewportControlBar(
            duration: viewModel.duration,
            visibleRange: viewModel.timelineVisibleRange,
            onVisibleRangeChanged: { viewModel.setTimelineVisibleRange($0) },
            onPanLeft: { viewModel.panTimelineLeft() },
            onPanRight: { viewModel.panTimelineRight() },
            onZoomIn: { viewModel.zoomInTimeline() },
            onZoomOut: { viewModel.zoomOutTimeline() }
        )
    }

    private func timelineTrackHeadersPanelBackground(height: CGFloat) -> some View {
        let safeHeight = max(height, AppTheme.Timeline.trackControlsMinimumHeight)

        return HStack(spacing: AppTheme.Spacing.none) {
            RoundedRectangle(cornerRadius: AppTheme.Radius.panel, style: .continuous)
                .fill(appColors.panelBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.panel, style: .continuous)
                        .stroke(appColors.border, lineWidth: AppTheme.Stroke.thin)
                }
                .frame(
                    width: AppTheme.Timeline.trackControlWidth,
                    height: safeHeight
                )

            Spacer(minLength: AppTheme.Spacing.none)
        }
        .frame(height: safeHeight, alignment: .top)
        .allowsHitTesting(false)
    }

    var transportBar: some View {
        TransportBarView(
            playbackState: viewModel.playbackState,
            canPlay: viewModel.canPlay,
            isLooping: viewModel.isLooping,
            statusText: viewModel.transportStatusText,
            transportPositionText: viewModel.transportPositionText,
            playbackRate: viewModel.playbackRate,
            pitchShiftSemitones: viewModel.pitchShiftSemitones,
            onGoToStart: { viewModel.seekToStart() },
            onGoToEnd: { viewModel.seekToEnd() },
            onPlayStop: { viewModel.togglePlayStop() },
            onPause: { viewModel.pause() },
            onLoopChanged: { viewModel.setLooping($0) },
            onPlaybackRateChanged: { viewModel.setPlaybackRate($0) },
            onPitchShiftChanged: { viewModel.setPitchShift(semitones: $0) }
        )
        .frame(height: AppTheme.ControlSize.transportBarMinHeight)
    }

    var inspectorSidebar: some View {
        InspectorSidebarView(
            selectedFilter: $notesFilter,
            notes: viewModel.notes,
            selectedRegionID: viewModel.selectedRegionID,
            onSelect: { viewModel.activateInspectorItem($0) },
            onEdit: { beginEditingMarker($0) },
            onDelete: { viewModel.deleteNote(id: $0) },
            onColorChanged: { viewModel.updateNoteColor(id: $0, color: $1) },
            onCustomColorChanged: { viewModel.updateNoteCustomColor(id: $0, hex: $1) }
        )
    }

    func beginEditingMarker(_ note: TimecodedNote) {
        if note.isTempoTimeSignatureMarker {
            beginEditingTempoTimeSignatureMarker(note)
            return
        }

        editingMarkerID = note.id
        editingMarkerTitle = note.title
        isEditingMarker = true
    }

    func beginAddingTempoTimeSignatureMarker(at time: TimeInterval) {
        guard viewModel.duration > 0 else { return }

        let clampedTime = max(0, min(time, viewModel.duration))
        let settings = viewModel.effectiveBeatGridSettings(at: clampedTime)
        editingTempoTimeSignatureMarkerID = nil
        editingTempoTimeSignatureMarkerTime = clampedTime
        editingTempoTimeSignatureBPM = settings.bpm ?? AppDefaults.defaultTempoBPM
        editingTempoTimeSignatureBeatsPerBar = Double(settings.timeSignature.beatsPerBar)
        editingTempoTimeSignatureSetsNewFirstBeat = false
        isEditingTempoTimeSignatureMarker = true
    }

    func beginEditingTempoTimeSignatureMarker(_ note: TimecodedNote) {
        let settings = viewModel.effectiveBeatGridSettings(at: note.time, excluding: note.id)
        let payload = note.tempoTimeSignaturePayload
        editingTempoTimeSignatureMarkerID = note.id
        editingTempoTimeSignatureMarkerTime = note.time
        editingTempoTimeSignatureBPM = payload?.bpm ?? settings.bpm ?? AppDefaults.defaultTempoBPM
        editingTempoTimeSignatureBeatsPerBar = Double(payload?.beatsPerBar ?? settings.timeSignature.beatsPerBar)
        editingTempoTimeSignatureSetsNewFirstBeat = payload?.setsNewFirstBeat ?? false
        isEditingTempoTimeSignatureMarker = true
    }

    var beatGrid: BeatGridConfiguration {
        BeatGridConfiguration(
            settings: viewModel.beatGridSettings,
            tempoMap: viewModel.tempoMap,
            visibleRange: viewModel.timelineVisibleRange
        )
    }

}
