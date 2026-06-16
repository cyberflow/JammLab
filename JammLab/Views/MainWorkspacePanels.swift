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
            minHeight: AppTheme.Workspace.bodyMinimumHeight,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    var timelineColumn: some View {
        GeometryReader { proxy in
            let columnHeight = max(proxy.size.height, AppTheme.Workspace.bodyMinimumHeight)
            let timelineHeight = max(
                AppTheme.Timeline.minimumContentHeight,
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
            minHeight: AppTheme.Workspace.bodyMinimumHeight,
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
                    .frame(height: AppTheme.Timeline.tracksMinimumHeight, alignment: .top)

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
        .frame(height: AppTheme.Timeline.tracksMinimumHeight, alignment: .top)
    }

    var timelineViewState: TimelineViewState {
        TimelineViewState(
            peakformData: viewModel.peakformData,
            duration: viewModel.duration,
            currentTime: viewModel.currentTime,
            loopStart: viewModel.loopRegion.start,
            loopEnd: viewModel.loopRegion.end,
            notes: viewModel.notes,
            selectedRegionID: viewModel.selectedRegionID,
            sections: timelineSections,
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
            seek: { viewModel.seek(to: $0) },
            addNote: { viewModel.addNote(at: $0) },
            editNote: { beginEditingMarker($0) },
            deleteNote: { viewModel.deleteNote(id: $0) },
            noteColorChanged: { viewModel.updateNoteColor(id: $0, color: $1) },
            noteCustomColorChanged: { viewModel.updateNoteCustomColor(id: $0, hex: $1) },
            markerTimeChanged: { viewModel.updateMarkerTime(id: $0, time: $1) },
            saveLoopRegion: { viewModel.saveCurrentLoopRegionAsRegion() },
            selectRegion: { viewModel.selectRegion(id: $0) },
            activateRegion: { viewModel.activateRegionAsLoop(id: $0, shouldSeek: true) },
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
            onPlayPause: { viewModel.togglePlayPause() },
            onStop: { viewModel.stop() },
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
            onSelect: { viewModel.seek(to: $0) },
            onEdit: { beginEditingMarker($0) },
            onDelete: { viewModel.deleteNote(id: $0) },
            onColorChanged: { viewModel.updateNoteColor(id: $0, color: $1) },
            onCustomColorChanged: { viewModel.updateNoteCustomColor(id: $0, hex: $1) }
        )
    }

    func beginEditingMarker(_ note: TimecodedNote) {
        editingMarkerID = note.id
        editingMarkerTitle = note.title
        isEditingMarker = true
    }

    var beatGrid: BeatGridConfiguration {
        BeatGridConfiguration(
            settings: viewModel.beatGridSettings,
            visibleRange: viewModel.timelineVisibleRange
        )
    }

    var timelineSections: [TimelineSection] {
        []
    }

}
