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
        HStack(spacing: AppTheme.ControlSize.notationDurationButtonSpacing) {
            ForEach(options) { option in
                durationButton(for: option)
            }
        }
        .frame(height: AppTheme.ControlSize.notationDurationControlHeight)
    }

    private func durationButton(for option: NotationDurationOption) -> some View {
        let isSelected = NotationDuration.normalizedDenominator(denominator) == option.denominator
        let helpText = NotationDurationControlHelpText.tooltip(for: option.duration)

        return Button {
            denominator = option.denominator
        } label: {
            NotationDurationGlyphView(
                symbol: option.symbol,
                color: iconColor(isSelected: isSelected)
            )
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
        .help(Text(helpText))
        .accessibilityLabel(NotationDurationControlHelpText.accessibilityLabel(for: option.duration))
        .accessibilityHint(NotationDurationControlHelpText.accessibilityHint(for: option.duration))
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

struct NotationEntryModeButton: View {
    let mode: NotationEntryMode
    let isActive: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appColors) private var appColors

    var body: some View {
        Button(action: action) {
            ZStack {
                switch mode {
                case .note:
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(iconColor)
                case .rest:
                    NotationRestControlGlyphView(
                        symbol: .restQuarter,
                        color: iconColor
                    )
                }
            }
            .frame(
                width: AppTheme.ControlSize.notationEntryModeButtonWidth,
                height: AppTheme.ControlSize.notationDurationControlHeight
            )
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .stroke(borderColor, lineWidth: AppTheme.Stroke.thin)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var iconColor: Color {
        guard isEnabled else { return appColors.disabledText }
        return isActive ? appColors.primaryText : appColors.secondaryText
    }

    private var backgroundColor: Color {
        isActive ? appColors.accent : appColors.statusButtonFill
    }

    private var borderColor: Color {
        isActive ? appColors.accent : appColors.border
    }
}

private struct NotationDurationGlyphView: View {
    let symbol: NotationDurationControlSymbol
    let color: Color

    var body: some View {
        ZStack {
            if let glyphPath = NotationMusicFontRegistry.glyphPath(
                for: symbol,
                fontSize: AppTheme.ControlSize.notationDurationGlyphSize
            ) {
                Canvas { context, size in
                    context.fill(
                        Path(glyphPath.path).applying(glyphPath.centeredTransform(in: size)),
                        with: .color(color)
                    )
                }
            } else {
                Text(symbol.glyph)
                    .font(.custom(
                        NotationMusicFontRegistry.fontName,
                        size: AppTheme.ControlSize.notationDurationGlyphSize
                    ))
                    .foregroundStyle(color)
            }
        }
    }
}

private struct NotationRestControlGlyphView: View {
    let symbol: NotationSMuFLSymbol
    let color: Color

    var body: some View {
        ZStack {
            if let glyphPath = NotationMusicFontRegistry.glyphPath(
                for: symbol,
                fontSize: AppTheme.ControlSize.notationDurationGlyphSize
            ) {
                Canvas { context, size in
                    context.fill(
                        Path(glyphPath.path).applying(glyphPath.centeredTransform(in: size)),
                        with: .color(color)
                    )
                }
            } else {
                Text(symbol.glyph)
                    .font(.custom(
                        NotationMusicFontRegistry.fontName,
                        size: AppTheme.ControlSize.notationDurationGlyphSize
                    ))
                    .foregroundStyle(color)
            }
        }
    }
}

private struct NotationDurationOption: Identifiable {
    let denominator: Int
    let duration: NotationDuration
    let symbol: NotationDurationControlSymbol

    var id: Int { denominator }

    init?(denominator: Int) {
        let duration = NotationDuration(denominator: denominator)
        guard let symbol = NotationDurationControlSymbol(duration: duration) else {
            return nil
        }

        self.denominator = duration.denominator
        self.duration = duration
        self.symbol = symbol
    }
}

enum NotationDurationControlHelpText {
    static func tooltip(for duration: NotationDuration) -> String {
        let title = title(for: duration)
        let shortcut = AppHotkey.notationDurationShortcutText(for: duration.denominator)
        let firstLine = shortcut.map { "\(title) (\($0))" } ?? title
        return "\(firstLine)\nSet duration: \(lowercaseTitle(for: duration))"
    }

    static func accessibilityLabel(for duration: NotationDuration) -> String {
        "\(duration.capitalizedDisplayName) note duration"
    }

    static func accessibilityHint(for duration: NotationDuration) -> String {
        "Sets notation duration to \(duration.displayName) note"
    }

    private static func title(for duration: NotationDuration) -> String {
        "\(duration.capitalizedDisplayName) (\(traditionalName(for: duration))) note"
    }

    private static func lowercaseTitle(for duration: NotationDuration) -> String {
        "\(duration.displayName) (\(traditionalName(for: duration))) note"
    }

    private static func traditionalName(for duration: NotationDuration) -> String {
        switch duration.denominator {
        case 1:
            return "semibreve"
        case 2:
            return "minim"
        case 4:
            return "crotchet"
        case 8:
            return "quaver"
        case 16:
            return "semiquaver"
        default:
            return duration.displayName
        }
    }
}
