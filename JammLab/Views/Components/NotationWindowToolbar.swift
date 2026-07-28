import SwiftUI

struct NotationWindowToolbar: View {
    @ObservedObject var viewModel: AudioPlayerViewModel

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            NotationEntryModeButton(
                mode: .note,
                isActive: viewModel.isNotationNoteEntryModeEnabled
            ) {
                viewModel.toggleNotationNoteEntryMode()
            }
            .disabled(viewModel.duration <= 0)
            .help("Add notes to Notation (N)")
            .accessibilityLabel("Notation Note Entry")
            .accessibilityValue(viewModel.isNotationNoteEntryModeEnabled ? "Enabled" : "Disabled")

            NotationDurationControl(
                denominator: Binding(
                    get: { viewModel.notationDurationDenominator },
                    set: { viewModel.setNotationDurationDenominator($0) }
                ),
                isEnabled: viewModel.canChangeNotationDuration
            )

            NotationAugmentationDotButton(
                isActive: viewModel.notationDurationIsDotted
            ) {
                viewModel.toggleNotationDurationDot()
            }
            .disabled(!viewModel.canChangeNotationDuration)

            if hasVisibleTonalPart {
                HStack(spacing: AppTheme.Spacing.xs) {
                    ForEach(NotationAccidental.allCases, id: \.self) { accidental in
                        NotationAccidentalButton(
                            accidental: accidental,
                            isActive: viewModel.pendingNotationAccidental == accidental
                        ) {
                            viewModel.handleNotationAccidentalCommand(accidental)
                        }
                        .disabled(viewModel.duration <= 0)
                    }
                }
            }

            NotationTieButton(status: viewModel.tieCommandStatus) {
                viewModel.handleAddTiedNotationNoteCommand()
            }

            if hasVisibleDrumPart {
                DrumInstrumentPaletteButton(
                    selectedMIDINoteNumber: viewModel.selectedDrumInstrumentMIDINoteNumber,
                    selectInstrument: { viewModel.selectDrumInstrument(midiNoteNumber: $0) }
                )
            }

            NotationEntryModeButton(
                mode: .rest,
                isActive: viewModel.isNotationRestEntryModeEnabled
            ) {
                viewModel.toggleNotationRestEntryMode()
            }
            .disabled(viewModel.duration <= 0)
            .help("Add rests to Notation")
            .accessibilityLabel("Notation Rest Entry")
            .accessibilityValue(viewModel.isNotationRestEntryModeEnabled ? "Enabled" : "Disabled")

            partVisibilityMenu

            Spacer(minLength: AppTheme.Spacing.md)

            AppControlButton(
                title: "Export MusicXML",
                systemImage: "square.and.arrow.up"
            ) {
                Task {
                    await viewModel.exportNotationAsMusicXML()
                }
            }
            .disabled(!viewModel.canExportNotation)
            .help(ControlHelpText.exportNotationMusicXML)
            .accessibilityLabel(ControlHelpText.exportNotationMusicXML)
        }
        .padding(.horizontal, AppTheme.Spacing.panelPadding)
        .padding(.vertical, AppTheme.Spacing.md)
    }

    private var partVisibilityMenu: some View {
        Menu {
            ForEach(viewModel.availableNotationParts) { part in
                Button {
                    viewModel.toggleNotationWindowPartVisibility(part.id)
                } label: {
                    if viewModel.normalizedVisibleNotationPartIDs().contains(part.id) {
                        Label(part.title, systemImage: "checkmark")
                    } else {
                        Text(part.title)
                    }
                }
            }
        } label: {
            Label("Parts", systemImage: "rectangle.stack")
        }
        .disabled(viewModel.availableNotationParts.count <= 1)
        .help("Choose visible Notation parts")
        .accessibilityLabel("Visible Notation Parts")
    }

    private var hasVisibleDrumPart: Bool {
        viewModel.visibleNotationParts.contains {
            viewModel.notationClef(for: $0.id) == .drums
        }
    }

    private var hasVisibleTonalPart: Bool {
        viewModel.visibleNotationParts.contains {
            viewModel.notationClef(for: $0.id) != .drums
        }
    }
}
