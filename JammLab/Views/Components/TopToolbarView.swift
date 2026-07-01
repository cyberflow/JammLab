import SwiftUI

struct TopToolbarView: View {
    let tempoValue: Double
    let isTempoEditable: Bool
    let timeSignature: TimeSignature
    let keySelection: ProjectKeySelection?
    let keyControlsEnabled: Bool
    let canUseBeatTools: Bool
    let isClickEnabled: Bool
    let clickVolume: Float
    let clickVolumeText: String
    let isSnapEnabled: Bool
    let hasAudio: Bool
    let playbackMode: PlaybackMode
    let canUseStemsPlayback: Bool
    let stemSeparationState: StemSeparationViewState
    let onTempoChanged: (Double) -> Void
    let onTimeSignatureChanged: (Int, Int) -> Void
    let onKeySelectionChanged: (ProjectKeySelection) -> Void
    let onClickToggle: () -> Void
    let onClickVolumeChanged: (Float) -> Void
    let onPopoverDismiss: () -> Void
    let onOpenTuner: () -> Void
    let onSnapToggle: () -> Void
    let onPlaybackModeChanged: (PlaybackMode) -> Void
    let onSeparateStems: (StemSeparationMethod) -> Void
    let onCancelStemSeparation: () -> Void
    let canSetBeatOne: Bool
    let canResetBeatGrid: Bool
    let onSetBeatOne: () -> Void
    let onResetBeatGrid: () -> Void
    let onNudgeBeatGrid: (TimeInterval) -> Void
    @Environment(\.appColors) private var appColors

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xl) {
            projectSettingsGroup

            toolbarDivider

            practiceToolsGroup

            toolbarDivider

            processingGroup

            Spacer(minLength: 0)

            playbackModeGroup
        }
        .padding(.horizontal, AppTheme.Spacing.pagePadding)
        .frame(maxWidth: .infinity, minHeight: AppTheme.ControlSize.toolbarHeight, alignment: .leading)
        .background(appColors.appBackground)
    }

    private var projectSettingsGroup: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            AbletonNumberField(
                value: Binding(
                    get: { tempoValue },
                    set: { onTempoChanged($0) }
                ),
                minValue: 40,
                maxValue: 240,
                defaultValue: AppDefaults.defaultTempoBPM,
                step: 0.01,
                sensitivity: 25,
                precision: 2,
                accessibilityLabel: "Tempo"
            )
                .frame(
                    width: AppTheme.ControlSize.toolbarTempoFieldWidth,
                    height: AppTheme.ControlSize.abletonNumberFieldHeight
                )
                .disabled(!isTempoEditable)
                .help(ControlHelpText.tempo)

            timeSignatureControls
                .help(ControlHelpText.timeSignature)

            keyControls
                .help(ControlHelpText.key)
        }
    }

    private var keyControls: some View {
        HStack(spacing: AppTheme.Spacing.xxs) {
            CompactValuePicker(
                values: ProjectKeyTonic.allCases,
                selection: Binding(
                    get: { displayedKeySelection.tonic },
                    set: { tonic in
                        var updated = displayedKeySelection
                        updated.tonic = tonic
                        onKeySelectionChanged(updated.asUserSelection)
                    }
                ),
                titleForValue: { $0.displayName },
                accessibilityLabel: "Key Tonic"
            )
            .frame(
                width: AppTheme.ControlSize.toolbarKeyTonicFieldWidth,
                height: AppTheme.ControlSize.abletonNumberFieldHeight
            )

            CompactValuePicker(
                values: KeySignature.Mode.allCases,
                selection: Binding(
                    get: { displayedKeySelection.mode },
                    set: { mode in
                        var updated = displayedKeySelection
                        updated.mode = mode
                        onKeySelectionChanged(updated.asUserSelection)
                    }
                ),
                titleForValue: { $0.displayName },
                accessibilityLabel: "Key Mode"
            )
            .frame(
                width: AppTheme.ControlSize.toolbarKeyModeFieldWidth,
                height: AppTheme.ControlSize.abletonNumberFieldHeight
            )
        }
        .disabled(!keyControlsEnabled)
    }

    private var displayedKeySelection: ProjectKeySelection {
        keySelection ?? .defaultSelection()
    }

    private var timeSignatureControls: some View {
        HStack(spacing: AppTheme.Spacing.xxs) {
            AbletonNumberField(
                value: Binding(
                    get: { Double(timeSignature.beatsPerBar) },
                    set: { onTimeSignatureChanged(Int($0.rounded()), timeSignature.beatUnit) }
                ),
                minValue: Double(TimeSignature.minimumBeatsPerBar),
                maxValue: Double(TimeSignature.maximumBeatsPerBar),
                defaultValue: Double(TimeSignature.fourFour.beatsPerBar),
                step: 1,
                precision: 0,
                accessibilityLabel: "Time Signature Beats Per Bar"
            )
            .frame(
                width: AppTheme.ControlSize.toolbarTimeSignatureNumberFieldWidth,
                height: AppTheme.ControlSize.abletonNumberFieldHeight
            )
            .disabled(!canUseBeatTools)

            Text("/")
                .font(AppTheme.Typography.captionMonospaced)
                .foregroundStyle(appColors.secondaryText)

            AbletonNumberField(
                value: Binding(
                    get: { Double(timeSignature.beatUnit) },
                    set: { onTimeSignatureChanged(timeSignature.beatsPerBar, Int($0.rounded())) }
                ),
                minValue: Double(TimeSignature.supportedBeatUnit),
                maxValue: Double(TimeSignature.supportedBeatUnit),
                defaultValue: Double(TimeSignature.supportedBeatUnit),
                step: 1,
                precision: 0,
                accessibilityLabel: "Time Signature Beat Unit"
            )
            .frame(
                width: AppTheme.ControlSize.toolbarTimeSignatureNumberFieldWidth,
                height: AppTheme.ControlSize.abletonNumberFieldHeight
            )
            .disabled(!canUseBeatTools)
        }
    }

    private var practiceToolsGroup: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            ClickToolbarButton(
                isEnabled: isClickEnabled,
                isAvailable: canUseBeatTools,
                volume: clickVolume,
                volumeText: clickVolumeText,
                onToggle: onClickToggle,
                onVolumeChanged: onClickVolumeChanged,
                onPopoverDismiss: onPopoverDismiss
            )

            Button {
                onOpenTuner()
            } label: {
                Label("Tuner", systemImage: "tuningfork")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .focusable(false)
            .focusEffectDisabled(true)
            .help(ControlHelpText.openTuner)
            .accessibilityLabel("Open tuner")

            AppControlButton(
                title: "Snap",
                systemImage: "scope",
                isActive: isSnapEnabled,
                action: onSnapToggle
            )
            .controlSize(.small)
            .disabled(!canUseBeatTools)
            .help(ControlHelpText.snap)

            BeatOneToolbarButton(
                canSetBeatOne: canSetBeatOne,
                canResetBeatGrid: canResetBeatGrid,
                onSetBeatOne: onSetBeatOne,
                onResetBeatGrid: onResetBeatGrid,
                onNudgeBeatGrid: onNudgeBeatGrid,
                onPopoverDismiss: onPopoverDismiss
            )
        }
    }

    private var processingGroup: some View {
        StemSeparationToolbarButton(
            hasAudio: hasAudio,
            separationState: stemSeparationState,
            onSeparate: onSeparateStems,
            onCancel: onCancelStemSeparation
        )
    }

    private var playbackModeGroup: some View {
        JammModeToggleButton(
            playbackMode: Binding(
                get: { playbackMode },
                set: { onPlaybackModeChanged($0) }
            ),
            isEnabled: hasAudio && canUseStemsPlayback,
            accessibilityLabel: "Toggle Stems Mode"
        )
        .help(canUseStemsPlayback ? ControlHelpText.playbackMode : ControlHelpText.playbackModeUnavailable)
    }

    private var toolbarDivider: some View {
        Divider()
            .frame(height: AppTheme.ControlSize.dividerHeight)
    }

    private func readOnlyField(_ value: String, width: CGFloat) -> some View {
        Text(value)
            .font(AppTheme.Typography.bodyMonospaced)
            .foregroundStyle(appColors.secondaryText)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(appColors.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
    }
}

private struct StemSeparationToolbarButton: View {
    let hasAudio: Bool
    let separationState: StemSeparationViewState
    let onSeparate: (StemSeparationMethod) -> Void
    let onCancel: () -> Void
    @State private var isMethodSheetPresented = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if separationState.isProcessing {
                Button(role: .cancel) {
                    onCancel()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .help(ControlHelpText.cancelStemSeparation)

                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    isMethodSheetPresented = true
                } label: {
                    Label("Separate Stems", systemImage: "waveform.badge.magnifyingglass")
                }
                .disabled(!hasAudio)
                .help(ControlHelpText.separateStems)
                .sheet(isPresented: $isMethodSheetPresented) {
                    StemSeparationMethodSelectionSheet { method in
                        isMethodSheetPresented = false
                        onSeparate(method)
                    } onCancel: {
                        isMethodSheetPresented = false
                    }
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

private struct StemSeparationMethodSelectionSheet: View {
    let onSelect: (StemSeparationMethod) -> Void
    let onCancel: () -> Void
    @Environment(\.appColors) private var appColors
    @State private var selectedMethodID = StemSeparationMethod.defaultValue.id

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("Separate Stems")
                .font(AppTheme.Typography.sectionTitle)
                .foregroundStyle(appColors.primaryText)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                ForEach(StemSeparationMethod.allCases) { method in
                    StemSeparationMethodOptionRow(
                        method: method,
                        isSelected: selectedMethodID == method.id
                    ) {
                        selectedMethodID = method.id
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Stem separation method")

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Separate") {
                    onSelect(selectedMethod)
                }
                .keyboardShortcut(.defaultAction)
                .help("Start stem separation with the selected method")
            }
        }
        .padding(AppTheme.Spacing.xl)
        .frame(width: 420)
        .background(appColors.panelBackground)
    }

    private var selectedMethod: StemSeparationMethod {
        StemSeparationMethod.method(forID: selectedMethodID) ?? .defaultValue
    }
}

private struct StemSeparationMethodOptionRow: View {
    let method: StemSeparationMethod
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(\.appColors) private var appColors

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? appColors.accent : appColors.secondaryText)
                    .frame(width: 18, height: 18)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(method.title)
                        .font(AppTheme.Typography.noteTitle)
                        .foregroundStyle(appColors.primaryText)
                    Text(method.optionDescription)
                        .font(.caption)
                        .foregroundStyle(appColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.md)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .background(isSelected ? appColors.controlActive : appColors.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                .stroke(isSelected ? appColors.accent : appColors.border, lineWidth: AppTheme.Stroke.thin)
        }
        .help("Select \(method.title)")
        .accessibilityLabel(method.title)
        .accessibilityValue(isSelected ? "Selected. \(method.optionDescription)" : method.optionDescription)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
