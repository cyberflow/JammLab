import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: AudioPlayerViewModel
    @State var isEditingMarker = false
    @State var editingMarkerID: TimecodedNote.ID?
    @State var editingMarkerTitle = ""
    @State var isEditingTempoTimeSignatureMarker = false
    @State var editingTempoTimeSignatureMarkerID: TimecodedNote.ID?
    @State var editingTempoTimeSignatureMarkerTime: TimeInterval = 0
    @State var editingTempoTimeSignatureBPM: Double = AppDefaults.defaultTempoBPM
    @State var editingTempoTimeSignatureBeatsPerBar: Double = Double(TimeSignature.fourFour.beatsPerBar)
    @State var editingTempoTimeSignatureSetsNewFirstBeat = false
    @State var notesFilter: NotesFilter = .notes
    @Environment(\.appColors) var appColors
    @Environment(\.openWindow) var openWindow
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(spacing: 0) {
            topToolbar

            Divider()

            workspaceContent
                .padding(AppTheme.Spacing.pagePadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(appColors.appBackground)
        }
        .background(WindowTitleUpdater(title: viewModel.windowTitle))
        .background(
            WindowMinimumSizeEnforcer(
                contentSize: CGSize(
                    width: AppTheme.Window.minWidth,
                    height: AppTheme.Window.minHeight
                )
            )
        )
        .background(WindowCloseGuard())
        .background(
            AppHotkeyMonitorView(
                allowedHotkeys: Set(AppHotkey.allCases),
                onHotkey: handleHotkey
            )
        )
        .task {
            viewModel.startPlaybackClock()
        }
        .onAppear {
            viewModel.undoManager = undoManager
            clearKeyboardFocus()
        }
        .onDisappear {
            viewModel.stopPlaybackClock()
        }
        .sheet(isPresented: $isEditingMarker) {
            RenameNoteDialog(
                title: "Edit Note",
                text: $editingMarkerTitle,
                onCancel: cancelMarkerEditing,
                onSave: saveMarkerEditing
            )
        }
        .sheet(isPresented: $isEditingTempoTimeSignatureMarker) {
            TempoTimeSignatureMarkerDialog(
                bpm: $editingTempoTimeSignatureBPM,
                beatsPerBar: $editingTempoTimeSignatureBeatsPerBar,
                setsNewFirstBeat: $editingTempoTimeSignatureSetsNewFirstBeat,
                onCancel: cancelTempoTimeSignatureMarkerEditing,
                onSet: saveTempoTimeSignatureMarkerEditing
            )
        }
        .sheet(isPresented: errorAlertBinding) {
            ErrorDialogView(message: viewModel.errorMessage ?? "") {
                viewModel.clearError()
            }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.clearError()
                }
            }
        )
    }

    private func cancelMarkerEditing() {
        isEditingMarker = false
        editingMarkerID = nil
        editingMarkerTitle = ""
    }

    private func saveMarkerEditing() {
        if let editingMarkerID {
            viewModel.updateNoteTitle(id: editingMarkerID, title: editingMarkerTitle)
        }

        cancelMarkerEditing()
    }

    private func cancelTempoTimeSignatureMarkerEditing() {
        isEditingTempoTimeSignatureMarker = false
        editingTempoTimeSignatureMarkerID = nil
        editingTempoTimeSignatureMarkerTime = 0
        editingTempoTimeSignatureBPM = AppDefaults.defaultTempoBPM
        editingTempoTimeSignatureBeatsPerBar = Double(TimeSignature.fourFour.beatsPerBar)
        editingTempoTimeSignatureSetsNewFirstBeat = false
    }

    private func saveTempoTimeSignatureMarkerEditing() {
        if let editingTempoTimeSignatureMarkerID {
            viewModel.updateTempoTimeSignatureMarker(
                id: editingTempoTimeSignatureMarkerID,
                bpm: editingTempoTimeSignatureBPM,
                beatsPerBar: Int(editingTempoTimeSignatureBeatsPerBar.rounded()),
                setsNewFirstBeat: editingTempoTimeSignatureSetsNewFirstBeat
            )
        } else {
            viewModel.addTempoTimeSignatureMarker(
                at: editingTempoTimeSignatureMarkerTime,
                bpm: editingTempoTimeSignatureBPM,
                beatsPerBar: Int(editingTempoTimeSignatureBeatsPerBar.rounded()),
                setsNewFirstBeat: editingTempoTimeSignatureSetsNewFirstBeat
            )
        }

        cancelTempoTimeSignatureMarkerEditing()
    }

    private var topToolbar: some View {
        TopToolbarView(
            tempoValue: viewModel.tempoBPM ?? AppDefaults.defaultTempoBPM,
            isTempoEditable: viewModel.importedFile != nil,
            timeSignature: viewModel.beatGridSettings.timeSignature,
            keySelection: viewModel.projectKeySelection,
            keyControlsEnabled: viewModel.importedFile != nil,
            canUseBeatTools: viewModel.canPlay && viewModel.tempoBPM != nil,
            isClickEnabled: viewModel.isClickEnabled,
            clickVolume: viewModel.clickVolume,
            clickVolumeText: viewModel.clickVolumeText,
            isSnapEnabled: viewModel.isSnapEnabled,
            hasAudio: viewModel.importedFile != nil,
            playbackMode: viewModel.playbackMode,
            canUseStemsPlayback: viewModel.canUseStemsPlayback,
            stemSeparationState: viewModel.stemSeparationState,
            onTempoChanged: { viewModel.setTempoBPM($0) },
            onTimeSignatureChanged: { viewModel.setTimeSignature(beatsPerBar: $0, beatUnit: $1) },
            onKeySelectionChanged: { viewModel.setProjectKeySelection($0) },
            onClickToggle: { viewModel.toggleClick() },
            onClickVolumeChanged: { viewModel.setClickVolume($0) },
            onPopoverDismiss: { clearKeyboardFocus() },
            onOpenTuner: { openWindow(id: "tuner") },
            onSnapToggle: { viewModel.toggleSnap() },
            onPlaybackModeChanged: { viewModel.setPlaybackMode($0) },
            onSeparateStems: { viewModel.separateStems(method: $0) },
            onCancelStemSeparation: { viewModel.cancelStemSeparation() },
            canSetBeatOne: viewModel.canPlay && viewModel.tempoBPM != nil,
            canResetBeatGrid: viewModel.canPlay && viewModel.beatGridSettings.isManuallyAligned,
            onSetBeatOne: { viewModel.setCurrentTimeAsBeatOne() },
            onResetBeatGrid: { viewModel.resetBeatGridAlignment() },
            onNudgeBeatGrid: { viewModel.nudgeBeatGrid(by: $0) }
        )
    }

    func clearKeyboardFocus() {
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private func handleHotkey(_ hotkey: AppHotkey) {
        // AppHotkey is the single source of truth for handled shortcuts.
        // Add new hotkeys there first so Help > Keyboard Shortcuts updates
        // together with this dispatch switch.
        switch hotkey {
        case .playPause:
            viewModel.togglePlayStop()
        case .toggleLoop:
            viewModel.toggleLooping()
        case .setLoopStart:
            viewModel.setLoopStartAtCurrentTime()
        case .setLoopEnd:
            viewModel.setLoopEndAtCurrentTime()
        case .addNote:
            viewModel.addNoteAtCurrentTime()
        case .addHarmonyAtPlaybackMarker:
            viewModel.requestAddHarmonyAtPlaybackMarker()
        case .addTempoTimeSignatureMarker:
            beginAddingTempoTimeSignatureMarker(at: viewModel.currentTime)
        case .setBeatOne:
            viewModel.setCurrentTimeAsBeatOne()
        case .toggleClick:
            viewModel.toggleClick()
        case .toggleSnap:
            viewModel.toggleSnap()
        case .togglePlaybackMode:
            viewModel.togglePlaybackMode()
        case .toggleVideoWindow:
            viewModel.toggleVideoWindow()
        }
    }

    func handleMediaDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?

            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let itemURL = item as? URL {
                url = itemURL
            } else {
                url = nil
            }

            guard let url else { return }

            Task { @MainActor in
                await viewModel.importAudio(from: url)
            }
        }

        return true
    }
}

private struct ErrorDialogView: View {
    let message: String
    let onDismiss: () -> Void
    @Environment(\.appColors) private var appColors

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            Text("Error")
                .font(.headline)
                .foregroundStyle(appColors.primaryText)

            ScrollView {
                Text(message)
                    .font(AppTheme.Typography.captionMonospaced)
                    .foregroundStyle(appColors.secondaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppTheme.Spacing.md)
            }
            .frame(minHeight: 160, maxHeight: 340)
            .background(appColors.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))

            HStack {
                Spacer()
                Button("OK") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppTheme.Spacing.panelPadding)
        .frame(width: 680)
        .background(appColors.panelBackground)
    }
}

#Preview {
    ContentView(viewModel: AudioPlayerViewModel())
}
