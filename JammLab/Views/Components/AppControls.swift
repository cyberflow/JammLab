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

struct NotationDurationControl: View {
    @Binding var denominator: Int
    let isEnabled: Bool
    @Environment(\.appColors) private var appColors

    private var options: [NotationDurationOption] {
        NotationDuration.allowedDenominators
            .reversed()
            .compactMap(NotationDurationOption.init)
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            ForEach(options) { option in
                durationButton(for: option)
            }
        }
        .frame(height: AppTheme.ControlSize.notationDurationControlHeight)
    }

    private func durationButton(for option: NotationDurationOption) -> some View {
        let isSelected = NotationDuration.normalizedDenominator(denominator) == option.denominator
        let helpText = "Set \(ControlHelpText.notationDuration.lowercased()) to \(option.durationName)"

        return Button {
            denominator = option.denominator
        } label: {
            Text(option.symbol.glyph)
                .font(.custom(
                    NotationMusicFontRegistry.fontName,
                    size: AppTheme.ControlSize.notationDurationGlyphSize
                ))
                .foregroundStyle(iconColor(isSelected: isSelected))
                .frame(
                    width: AppTheme.ControlSize.notationDurationButtonWidth,
                    height: AppTheme.ControlSize.notationDurationControlHeight
                )
                .background(backgroundColor(isSelected: isSelected))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                        .stroke(borderColor(isSelected: isSelected), lineWidth: AppTheme.Stroke.thin)
                }
                .contentShape(Rectangle())
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(helpText)
        .accessibilityLabel("Notation duration: \(option.durationName)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func iconColor(isSelected: Bool) -> Color {
        guard isEnabled else { return appColors.disabledText }
        return isSelected ? appColors.accent : appColors.secondaryText
    }

    private func backgroundColor(isSelected: Bool) -> Color {
        isEnabled && isSelected ? appColors.controlActive : Color.clear
    }

    private func borderColor(isSelected: Bool) -> Color {
        isEnabled && isSelected ? appColors.accent : Color.clear
    }
}

private struct NotationDurationOption: Identifiable {
    let denominator: Int
    let durationName: String
    let symbol: NotationDurationControlSymbol

    var id: Int { denominator }

    init?(denominator: Int) {
        let duration = NotationDuration(denominator: denominator)
        guard let symbol = NotationDurationControlSymbol(duration: duration) else {
            return nil
        }

        self.denominator = duration.denominator
        self.durationName = duration.pluralDisplayName
        self.symbol = symbol
    }
}
