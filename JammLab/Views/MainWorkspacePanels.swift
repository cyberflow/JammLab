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

            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                timelineBlock(height: timelineHeight)

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

    func timelineBlock(height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            timelineTrackHeadersPanelBackground(height: height)

            VStack(spacing: AppTheme.Spacing.none) {
                timelineSection
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

    var timelineSection: some View {
        WaveformTimelineView(
            state: timelineViewState,
            actions: timelineViewActions,
            stemActions: stemTrackActions
        )
        .frame(height: timelineTracksHeight, alignment: .top)
    }

    var timelineStemRowCount: Int {
        viewModel.stemFiles.isEmpty ? StemSeparationMethod.defaultValue.stemTypes.count : viewModel.stemFiles.count
    }

    var timelineTracksHeight: CGFloat {
        AppTheme.Timeline.tracksMinimumHeight(stemRowCount: timelineStemRowCount)
    }

    var timelineMinimumContentHeight: CGFloat {
        AppTheme.Timeline.minimumContentHeight(stemRowCount: timelineStemRowCount)
    }

    var timelineColumnMinimumHeight: CGFloat {
        timelineMinimumContentHeight
            + AppTheme.Spacing.md
            + AppTheme.ControlSize.transportBarMinHeight
    }

    var timelineViewState: TimelineViewState {
        TimelineViewState(
            peakformData: viewModel.peakformData,
            duration: viewModel.duration,
            currentTime: viewModel.currentTime,
            playbackMarkerTime: viewModel.playbackMarkerTime,
            loopStart: viewModel.loopRegion.start,
            loopEnd: viewModel.loopRegion.end,
            notes: viewModel.notes,
            harmonyEvents: viewModel.harmonyEvents,
            selectedRegionID: viewModel.selectedRegionID,
            selectedHarmonyEventID: viewModel.selectedHarmonyEventID,
            beatGrid: beatGrid,
            isLoadingPeakform: viewModel.isBuildingWaveform,
            mainTrackVolume: viewModel.mainTrackVolume,
            playbackMode: viewModel.playbackMode,
            mixState: viewModel.stemMixState,
            stemFiles: viewModel.stemFiles,
            stemPeakforms: viewModel.stemPeakforms,
            isLoadingStemPeakforms: viewModel.isBuildingStemPeakforms
        )
    }

    var timelineViewActions: TimelineViewActions {
        TimelineViewActions(
            locatePlaybackMarker: { viewModel.locatePlaybackMarker(to: $0) },
            addNote: { viewModel.addNote(at: $0) },
            addTempoTimeSignatureMarker: { beginAddingTempoTimeSignatureMarker(at: $0) },
            editNote: { beginEditingMarker($0) },
            deleteNote: { viewModel.deleteNote(id: $0) },
            noteColorChanged: { viewModel.updateNoteColor(id: $0, color: $1) },
            noteCustomColorChanged: { viewModel.updateNoteCustomColor(id: $0, hex: $1) },
            markerTimeChanged: { viewModel.updateMarkerTime(id: $0, time: $1) },
            createHarmonyEvent: { viewModel.createHarmonyEvent(at: $0) },
            selectHarmonyEvent: { viewModel.selectHarmonyEvent(id: $0) },
            updateHarmonyEventSymbol: { viewModel.updateHarmonyEventSymbol(id: $0, symbol: $1) },
            commitHarmonyEventAndCreateNext: { viewModel.commitHarmonyEventAndCreateNext(id: $0, symbol: $1) },
            harmonyEventTimeChanged: { viewModel.moveHarmonyEvent(id: $0, to: $1) },
            deleteHarmonyEvent: { viewModel.deleteHarmonyEvent(id: $0) },
            saveLoopRegion: { viewModel.saveCurrentLoopRegionAsRegion() },
            selectRegion: { viewModel.selectRegion(id: $0) },
            activateRegionAsLoop: { viewModel.activateRegionAsLoopAndMoveMarker(id: $0) },
            focusRegion: { viewModel.focusRegion(id: $0) },
            regionRangeChanged: { viewModel.updateRegionRange(id: $0, start: $1, end: $2) },
            loopStartChanged: { viewModel.updateLoopStart($0) },
            loopEndChanged: { viewModel.updateLoopEnd($0) },
            loopRegionChanged: { viewModel.updateLoopRegion(start: $0, end: $1) },
            timelineScroll: { viewModel.handleTimelineScroll(deltaX: $0, deltaY: $1, anchorTime: $2) },
            mainTrackVolumeChanged: { viewModel.setMainTrackVolume($0) }
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
            currentTime: viewModel.currentTime,
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
