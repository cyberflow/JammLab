import SwiftUI

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
