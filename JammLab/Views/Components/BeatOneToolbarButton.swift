import SwiftUI

struct BeatOneToolbarButton: View {
    let canSetBeatOne: Bool
    let canResetBeatGrid: Bool
    let onSetBeatOne: () -> Void
    let onResetBeatGrid: () -> Void
    let onNudgeBeatGrid: (TimeInterval) -> Void
    let onPopoverDismiss: () -> Void

    @State private var isPopoverPresented = false

    var body: some View {
        Button(action: onSetBeatOne) {
            Label("Beat 1", systemImage: "flag.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!canSetBeatOne)
        .help(ControlHelpText.setBeatOne)
        .overlay {
            RightClickCaptureView { _ in
                guard canSetBeatOne else { return }
                isPopoverPresented = true
            }
        }
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                Button {
                    onResetBeatGrid()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .disabled(!canResetBeatGrid)
                .help(ControlHelpText.resetBeatGrid)

                Divider()

                HStack(spacing: AppTheme.Spacing.md) {
                    beatGridNudgeButton("-50 ms", systemImage: "backward.end.fill", delta: -0.05)
                    beatGridNudgeButton("-10 ms", systemImage: "chevron.left", delta: -0.01)
                    beatGridNudgeButton("+10 ms", systemImage: "chevron.right", delta: 0.01)
                    beatGridNudgeButton("+50 ms", systemImage: "forward.end.fill", delta: 0.05)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(AppTheme.Spacing.panelPadding)
        }
        .onAppPopoverDismiss(isPresented: isPopoverPresented, perform: onPopoverDismiss)
    }

    private func beatGridNudgeButton(_ title: String, systemImage: String, delta: TimeInterval) -> some View {
        Button {
            onNudgeBeatGrid(delta)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .help(ControlHelpText.beatGridNudge(title))
    }
}
