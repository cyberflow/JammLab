import SwiftUI

struct TransportButton: View {
    let type: TransportControlType
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: type.systemImage)
                .font(.system(size: AppTheme.TransportControls.iconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: type.size.width, height: type.size.height)
        }
        .buttonStyle(TransportButtonStyle(type: type, isHovered: isHovered && isEnabled))
        .onHover { isHovered = isEnabled && $0 }
        .help(type.helpText)
        .accessibilityLabel(type.accessibilityLabel)
        .accessibilityValue(type.accessibilityValue)
    }
}

struct TransportButtonStyle: ButtonStyle {
    let type: TransportControlType
    let isHovered: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appColors) private var appColors

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .background {
                buttonFill(isPressed: configuration.isPressed)
            }
            .overlay {
                buttonBorder
            }
            .overlay(alignment: .top) {
                buttonHighlight
            }
            .shadow(
                color: isEnabled ? .black.opacity(0.36) : .clear,
                radius: AppTheme.TransportControls.shadowRadius,
                x: 0,
                y: AppTheme.TransportControls.shadowY
            )
            .opacity(isEnabled ? 1 : 0.56)
            .offset(y: configuration.isPressed ? AppTheme.TransportControls.pressedOffset : 0)
            .animation(.easeOut(duration: AppTheme.Animation.fast), value: isHovered)
            .animation(.easeOut(duration: AppTheme.Animation.fast), value: configuration.isPressed)
            .contentShape(Rectangle())
    }

    private var foregroundColor: Color {
        guard isEnabled else { return appColors.disabledText }
        if type.isActive { return type.activeColor(appColors) }
        return isHovered ? appColors.primaryText : appColors.secondaryText
    }

    @ViewBuilder
    private func buttonFill(isPressed: Bool) -> some View {
        let gradient = LinearGradient(
            colors: buttonGradientColors(isPressed: isPressed),
            startPoint: .top,
            endPoint: .bottom
        )

        if type.isRound {
            Circle().fill(gradient)
        } else {
            TransportButtonShape(corners: type.corners)
                .fill(gradient)
        }
    }

    @ViewBuilder
    private var buttonBorder: some View {
        let color = type.isActive ? type.activeColor(appColors) : appColors.border

        if type.isRound {
            Circle().stroke(color, lineWidth: AppTheme.TransportControls.buttonBorderWidth)
        } else {
            TransportButtonShape(corners: type.corners)
                .stroke(color, lineWidth: AppTheme.TransportControls.buttonBorderWidth)
        }
    }

    @ViewBuilder
    private var buttonHighlight: some View {
        let highlight = appColors.primaryText.opacity(isHovered && isEnabled ? 0.24 : 0.18)

        if type.isRound {
            Circle()
                .trim(from: 0.08, to: 0.43)
                .stroke(highlight, lineWidth: AppTheme.TransportControls.buttonBorderWidth)
                .padding(2)
        } else {
            TransportButtonShape(corners: type.highlightCorners)
                .stroke(highlight, lineWidth: AppTheme.TransportControls.buttonBorderWidth)
                .padding(2)
        }
    }

    private func buttonGradientColors(isPressed: Bool) -> [Color] {
        if isPressed {
            return [
                appColors.accentPressed.opacity(type.isActive ? 0.55 : 0.32),
                appColors.controlBackground
            ]
        }

        let top = (isHovered && isEnabled ? appColors.controlHover : appColors.controlBackground)
        let bottom = type.isActive
            ? type.activeColor(appColors).opacity(0.28)
            : appColors.elevatedSurface

        return [top, bottom]
    }
}

enum TransportControlType {
    case goToStart
    case goToEnd
    case playStop(isPlaying: Bool)
    case pause
    case loop(isActive: Bool)

    var systemImage: String {
        switch self {
        case .goToStart:
            return "backward.end.fill"
        case .goToEnd:
            return "forward.end.fill"
        case .playStop(let isPlaying):
            return isPlaying ? "stop.fill" : "play.fill"
        case .pause:
            return "pause.fill"
        case .loop:
            return "repeat"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .goToStart:
            return "Go to start"
        case .goToEnd:
            return "Go to end"
        case .playStop(let isPlaying):
            return isPlaying ? "Stop" : "Play"
        case .pause:
            return "Pause"
        case .loop:
            return "Loop"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .loop(let isActive):
            return isActive ? "On" : "Off"
        default:
            return ""
        }
    }

    var helpText: String {
        switch self {
        case .goToStart:
            return ControlHelpText.goToStart
        case .goToEnd:
            return ControlHelpText.goToEnd
        case .playStop(let isPlaying):
            return isPlaying ? ControlHelpText.stop : ControlHelpText.play
        case .pause:
            return ControlHelpText.pause
        case .loop(let isActive):
            return isActive ? ControlHelpText.deactivateLoop : ControlHelpText.activateLoop
        }
    }

    var isActive: Bool {
        if case .loop(let isActive) = self {
            return isActive
        }

        return false
    }

    func activeColor(_ colors: AppThemeColors) -> Color {
        switch self {
        case .loop:
            return colors.loopButtonActive
        default:
            return colors.accent
        }
    }

    var isRound: Bool {
        switch self {
        case .playStop, .loop:
            return true
        case .goToStart, .goToEnd, .pause:
            return false
        }
    }

    var size: CGSize {
        switch self {
        case .goToStart, .goToEnd:
            return CGSize(
                width: AppTheme.TransportControls.skipButtonWidth,
                height: AppTheme.TransportControls.skipButtonHeight
            )
        case .playStop, .loop:
            return CGSize(
                width: AppTheme.TransportControls.roundButtonSize,
                height: AppTheme.TransportControls.roundButtonSize
            )
        case .pause:
            return CGSize(
                width: AppTheme.TransportControls.stopButtonSize,
                height: AppTheme.TransportControls.stopButtonSize
            )
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .playStop, .loop:
            return AppTheme.TransportControls.roundButtonSize / 2
        case .goToStart, .goToEnd:
            return AppTheme.TransportControls.skipButtonRadius
        case .pause:
            return AppTheme.TransportControls.stopButtonRadius
        }
    }

    var corners: TransportButtonCorners {
        switch self {
        case .goToStart:
            return TransportButtonCorners(
                topLeft: AppTheme.TransportControls.skipButtonRadius,
                topRight: 0,
                bottomRight: 0,
                bottomLeft: AppTheme.TransportControls.skipButtonRadius
            )
        case .goToEnd:
            return TransportButtonCorners(
                topLeft: 0,
                topRight: AppTheme.TransportControls.skipButtonRadius,
                bottomRight: AppTheme.TransportControls.skipButtonRadius,
                bottomLeft: 0
            )
        case .pause:
            return TransportButtonCorners(radius: AppTheme.TransportControls.stopButtonRadius)
        case .playStop, .loop:
            return TransportButtonCorners(radius: cornerRadius)
        }
    }

    var highlightCorners: TransportButtonCorners {
        let insetRadius = max(1, cornerRadius - 1)

        switch self {
        case .goToStart:
            return TransportButtonCorners(topLeft: insetRadius, topRight: 0, bottomRight: 0, bottomLeft: insetRadius)
        case .goToEnd:
            return TransportButtonCorners(topLeft: 0, topRight: insetRadius, bottomRight: insetRadius, bottomLeft: 0)
        case .pause:
            return TransportButtonCorners(radius: insetRadius)
        case .playStop, .loop:
            return TransportButtonCorners(radius: insetRadius)
        }
    }
}

struct TransportButtonCorners {
    var topLeft: CGFloat
    var topRight: CGFloat
    var bottomRight: CGFloat
    var bottomLeft: CGFloat

    init(topLeft: CGFloat, topRight: CGFloat, bottomRight: CGFloat, bottomLeft: CGFloat) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    init(radius: CGFloat) {
        self.init(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius)
    }
}

struct TransportButtonShape: Shape {
    let corners: TransportButtonCorners

    func path(in rect: CGRect) -> Path {
        let topLeft = min(corners.topLeft, min(rect.width, rect.height) / 2)
        let topRight = min(corners.topRight, min(rect.width, rect.height) / 2)
        let bottomRight = min(corners.bottomRight, min(rect.width, rect.height) / 2)
        let bottomLeft = min(corners.bottomLeft, min(rect.width, rect.height) / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))

        if topRight > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight),
                radius: topRight,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))

        if bottomRight > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight),
                radius: bottomRight,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))

        if bottomLeft > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft),
                radius: bottomLeft,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))

        if topLeft > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + topLeft, y: rect.minY + topLeft),
                radius: topLeft,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        }

        path.closeSubpath()
        return path
    }
}
