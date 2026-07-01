import SwiftUI

struct ClickToolbarButton: View {
    let isEnabled: Bool
    let isAvailable: Bool
    let volume: Float
    let volumeText: String
    let onToggle: () -> Void
    let onVolumeChanged: (Float) -> Void
    let onPopoverDismiss: () -> Void

    @State private var isVolumePopoverPresented = false
    @Environment(\.appColors) private var appColors

    var body: some View {
        AppControlButton(
            title: "Click",
            systemImage: "metronome",
            isActive: isEnabled,
            action: onToggle
        )
        .controlSize(.small)
        .disabled(!isAvailable)
        .help(ControlHelpText.click)
        .overlay {
            RightClickCaptureView { _ in
                guard isAvailable else { return }
                isVolumePopoverPresented = true
            }
        }
        .popover(isPresented: $isVolumePopoverPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    Label("Click Volume", systemImage: "speaker.wave.2")
                    Spacer()
                    Text(volumeText)
                        .font(AppTheme.Typography.captionMonospaced)
                        .foregroundStyle(appColors.secondaryText)
                }

                JammValueSlider(
                    value: Binding(
                        get: { Double(volume) },
                        set: { onVolumeChanged(Float($0)) }
                    ),
                    minValue: 0,
                    maxValue: 1,
                    defaultValue: Double(AppSliderDefaults.clickVolume),
                    step: 0.01,
                    sensitivity: 1,
                    precision: 0,
                    displayFormatter: { "\(Int(($0 * 100).rounded()))%" },
                    accessibilityLabel: "Click Volume"
                )
                .frame(
                    width: AppTheme.ControlSize.clickVolumeWidth,
                    height: AppTheme.ControlSize.jammValueSliderHeight
                )
                .help(ControlHelpText.clickVolume)
            }
            .padding(AppTheme.Spacing.panelPadding)
            .frame(width: AppTheme.ControlSize.clickVolumeWidth + 96)
        }
        .onAppPopoverDismiss(isPresented: isVolumePopoverPresented, perform: onPopoverDismiss)
    }
}
