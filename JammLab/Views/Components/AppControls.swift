import SwiftUI

struct AppControlButton: View {
    let title: String
    let systemImage: String
    var isActive = false
    let action: () -> Void
    @Environment(\.appColors) private var appColors

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(isActive ? appColors.accent : appColors.secondaryText)
        }
        .buttonStyle(.bordered)
    }
}

struct AppLetterToggleButton: View {
    let title: String
    var isActive = false
    let activeFillColor: Color
    let inactiveTextColor: Color
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appColors) private var appColors

    init(
        title: String,
        isActive: Bool = false,
        activeFillColor: Color,
        inactiveTextColor: Color,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isActive = isActive
        self.activeFillColor = activeFillColor
        self.inactiveTextColor = inactiveTextColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .default))
                .foregroundStyle(textColor)
                .frame(
                    width: AppTheme.ControlSize.letterToggleButtonWidth,
                    height: AppTheme.ControlSize.letterToggleButtonHeight
                )
                .background(backgroundColor)
                .overlay {
                    Rectangle()
                        .stroke(borderColor, lineWidth: AppTheme.Stroke.thin)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var backgroundColor: Color {
        isActive ? activeFillColor : appColors.statusButtonFill
    }

    private var textColor: Color {
        if !isEnabled { return appColors.disabledText }
        return isActive ? appColors.primaryText : inactiveTextColor
    }

    private var borderColor: Color {
        isActive ? activeFillColor : appColors.border
    }
}

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

extension View {
    func onAppPopoverDismiss(isPresented: Bool, perform action: @escaping () -> Void) -> some View {
        modifier(AppPopoverDismissModifier(isPresented: isPresented, action: action))
    }
}

private struct AppPopoverDismissModifier: ViewModifier {
    let isPresented: Bool
    let action: () -> Void

    @State private var didPresent = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, newValue in
                if newValue {
                    didPresent = true
                } else if didPresent {
                    didPresent = false
                    DispatchQueue.main.async {
                        action()
                    }
                }
            }
    }
}
