import SwiftUI

struct TimelineSection: Identifiable, Equatable {
    let id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var color: Color
}

struct BeatGridConfiguration: Equatable {
    var settings: BeatGridSettings
    var visibleRange: ClosedRange<TimeInterval>?

    init(settings: BeatGridSettings, visibleRange: ClosedRange<TimeInterval>? = nil) {
        self.settings = settings
        self.visibleRange = visibleRange
    }

    var meterText: String {
        settings.timeSignature.displayText
    }

    func viewport(duration: TimeInterval) -> TimelineViewport {
        TimelineViewport(duration: duration, visibleRange: visibleRange ?? 0...duration)
    }
}

struct WaveformTimelineView: View {
    let peakformData: PeakformData?
    let duration: TimeInterval
    let currentTime: TimeInterval
    let loopStart: TimeInterval
    let loopEnd: TimeInterval
    let notes: [TimecodedNote]
    let selectedRegionID: TimecodedNote.ID?
    let sections: [TimelineSection]
    let beatGrid: BeatGridConfiguration
    let isLoadingPeakform: Bool
    let mainTrackVolume: Float
    let playbackMode: PlaybackMode
    let mixState: StemMixState
    let stemPeakforms: [StemType: PeakformData]
    let isLoadingStemPeakforms: Bool
    let onSeek: (TimeInterval) -> Void
    let onAddNote: (TimeInterval) -> Void
    let onEditNote: (TimecodedNote) -> Void
    let onDeleteNote: (TimecodedNote.ID) -> Void
    let onNoteColorChanged: (TimecodedNote.ID, MarkerColor) -> Void
    let onNoteCustomColorChanged: (TimecodedNote.ID, String) -> Void
    let onMarkerTimeChanged: (TimecodedNote.ID, TimeInterval) -> Void
    let onSaveLoopRegion: () -> Void
    let onSelectRegion: (TimecodedNote.ID) -> Void
    let onActivateRegion: (TimecodedNote.ID) -> Void
    let onFocusRegion: (TimecodedNote.ID) -> Void
    let onRegionRangeChanged: (TimecodedNote.ID, TimeInterval, TimeInterval) -> Void
    let onLoopStartChanged: (TimeInterval) -> Void
    let onLoopEndChanged: (TimeInterval) -> Void
    let onLoopRegionChanged: (TimeInterval, TimeInterval) -> Void
    let onTimelineScroll: (Double, Double, TimeInterval?) -> Void
    let onMainTrackVolumeChanged: (Float) -> Void
    let onStemVolumeChanged: (StemType, Float) -> Void
    let onStemMuteToggled: (StemType) -> Void
    let onStemSoloToggled: (StemType) -> Void

    private let trackControlWidth: CGFloat = AppTheme.Timeline.trackControlWidth
    @Environment(\.appColors) private var appColors

    var body: some View {
        tracksArea
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: AppTheme.Timeline.tracksMinimumHeight, alignment: .topLeading)
    }

    private var tracksArea: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: AppTheme.Timeline.trackSpacing) {
                upperTrackStack
                stemTracksSection
            }

            timelineScrollOverlay
                .frame(height: AppTheme.Timeline.tracksMinimumHeight)
        }
    }

    private var stemTracksSection: some View {
        StemTracksSection(
            playbackMode: playbackMode,
            mixState: mixState,
            stemPeakforms: stemPeakforms,
            isLoadingStemPeakforms: isLoadingStemPeakforms,
            duration: duration,
            viewport: viewport,
            trackControlWidth: trackControlWidth,
            onStemVolumeChanged: onStemVolumeChanged,
            onStemMuteToggled: onStemMuteToggled,
            onStemSoloToggled: onStemSoloToggled
        )
        .frame(height: AppTheme.Timeline.stemTracksHeight, alignment: .top)
    }

    private var upperTrackStack: some View {
        VStack(spacing: AppTheme.Spacing.none) {
            timelineTrackRow(height: AppTheme.Timeline.regionTrackHeight) {
                RegionTrackView(
                    duration: timelineDuration,
                    notes: notes,
                    selectedRegionID: selectedRegionID,
                    configuration: beatGrid,
                    onSelectRegion: onSelectRegion,
                    onActivateRegion: onActivateRegion,
                    onFocusRegion: onFocusRegion,
                    onEditRegion: onEditNote,
                    onDeleteRegion: onDeleteNote,
                    onRegionColorChanged: onNoteColorChanged,
                    onRegionCustomColorChanged: onNoteCustomColorChanged,
                    onRegionRangeChanged: onRegionRangeChanged
                )
            }

            timelineTrackRow(height: AppTheme.Timeline.markerTrackHeight) {
                MarkerTrackView(
                    duration: timelineDuration,
                    notes: notes,
                    configuration: beatGrid,
                    onEditMarker: onEditNote,
                    onDeleteMarker: onDeleteNote,
                    onMarkerColorChanged: onNoteColorChanged,
                    onMarkerCustomColorChanged: onNoteCustomColorChanged,
                    onMarkerTimeChanged: onMarkerTimeChanged
                )
            }

            timelineTrackRow(height: AppTheme.Timeline.tempoTrackHeight) {
                TempoTrackView(
                    duration: timelineDuration,
                    loopStart: loopStart,
                    loopEnd: loopEnd,
                    configuration: beatGrid,
                    onSaveLoopRegion: onSaveLoopRegion,
                    onLoopStartChanged: onLoopStartChanged,
                    onLoopEndChanged: onLoopEndChanged,
                    onLoopRegionChanged: onLoopRegionChanged
                )
            }

            mainTrackRow
                .frame(height: AppTheme.Timeline.waveformTrackHeight)
        }
    }

    private var timelineScrollOverlay: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Color.clear
                .frame(width: trackControlWidth)

            TimelineScrollCaptureView { event in
                let anchorTime = viewport.time(forX: event.locationX, width: event.width)
                onTimelineScroll(event.deltaX, event.deltaY, anchorTime)
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

    private var mainTrackControls: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Main")
                .font(AppTheme.Typography.noteTitle)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            JammValueSlider(
                value: Binding(
                    get: { Double(mainTrackVolume) },
                    set: { onMainTrackVolumeChanged(Float($0)) }
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
            .disabled(duration <= 0)
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
                    peakformData: peakformData,
                    duration: timelineDuration,
                    currentTime: currentTime,
                    loopStart: loopStart,
                    loopEnd: loopEnd,
                    notes: notes,
                    selectedRegionID: selectedRegionID,
                    sections: sections,
                    beatGridSettings: beatGrid.settings,
                    visibleStartTime: visibleRange.lowerBound,
                    visibleEndTime: visibleRange.upperBound,
                    isLoading: isLoadingPeakform,
                    showsImportPlaceholder: duration <= 0,
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
        if duration > 0 {
            return beatGrid.viewport(duration: duration)
        }

        return TimelineViewport(duration: timelineDuration, visibleRange: 0...timelineDuration)
    }

    private var timelineDuration: TimeInterval {
        duration > 0 ? duration : AppDefaults.startupGridDuration
    }

    private var isMainTrackActive: Bool {
        playbackMode == .original
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
    let stemPeakforms: [StemType: PeakformData]
    let isLoadingStemPeakforms: Bool
    let duration: TimeInterval
    let viewport: TimelineViewport
    let trackControlWidth: CGFloat
    let onStemVolumeChanged: (StemType, Float) -> Void
    let onStemMuteToggled: (StemType) -> Void
    let onStemSoloToggled: (StemType) -> Void
    @Environment(\.appColors) private var appColors

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            ForEach(StemType.allCases) { type in
                row(type)
            }
        }
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
                    onStemMuteToggled(type)
                }
                .disabled(!isRowEnabled)
                .help(ControlHelpText.muteTrack(type.title))
                .accessibilityLabel("Mute \(type.title)")
            }

            HStack(spacing: AppTheme.Spacing.md) {
                JammValueSlider(
                    value: Binding(
                        get: { Double(item.volume) },
                        set: { onStemVolumeChanged(type, Float($0)) }
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
                    onStemSoloToggled(type)
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
