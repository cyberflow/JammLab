import SwiftUI

struct JammModeToggleButton: View {
    @Binding var playbackMode: PlaybackMode
    let isEnabled: Bool
    let accessibilityLabel: String

    @State private var isHovered = false
    @Environment(\.appColors) private var appColors

    var body: some View {
        Button {
            playbackMode = playbackMode == .stems ? .original : .stems
        } label: {
            JammModeToggleIcon(color: lineColor)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(JammModeToggleButtonStyle(isHovered: isHovered, isEnabled: isEnabled))
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(playbackMode.title)
    }

    private var lineColor: Color {
        guard isEnabled else { return appColors.disabledText.opacity(0.55) }

        if playbackMode == .stems {
            return isHovered ? appColors.accentHover : appColors.accent
        }

        return isHovered ? appColors.secondaryText : appColors.tertiaryText
    }
}

private struct JammModeToggleIcon: View {
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule()
                    .fill(color)
                    .frame(width: 14, height: 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct JammModeToggleButtonStyle: ButtonStyle {
    let isHovered: Bool
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(opacity(isPressed: configuration.isPressed))
    }

    private func opacity(isPressed: Bool) -> Double {
        guard isEnabled else { return 0.45 }
        if isPressed { return 0.72 }
        return isHovered ? 1 : 0.86
    }
}
