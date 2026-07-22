import SwiftUI

struct DrumInstrumentPaletteButton: View {
    let selectedMIDINoteNumber: Int
    let selectInstrument: (Int) -> Void

    @Environment(\.appColors) private var appColors
    @State private var isPresented = false

    private var selectedInstrument: DrumInstrumentDefinition {
        DrumInstrumentMap.instrument(forMIDINoteNumber: selectedMIDINoteNumber)
            ?? DrumInstrumentMap.defaultInstrument
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "music.note")
                Text(selectedInstrument.name)
                    .lineLimit(1)
                Spacer(minLength: AppTheme.Spacing.xs)
                Text(selectedInstrument.pitchLabel)
                    .foregroundStyle(appColors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .frame(width: AppTheme.ControlSize.drumInstrumentSelectorWidth)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(AppTheme.ControlSize.drumInstrumentPadWidth)),
                    count: 8
                ),
                spacing: AppTheme.Spacing.md
            ) {
                ForEach(DrumInstrumentMap.instruments) { instrument in
                    drumPad(instrument)
                }
            }
            .padding(AppTheme.Spacing.panelPadding)
            .background(appColors.elevatedSurface)
        }
        .help("Choose the drum sound used when adding notes")
        .accessibilityLabel("Drum instrument")
        .accessibilityValue("\(selectedInstrument.name), \(selectedInstrument.pitchLabel)")
    }

    private func drumPad(_ instrument: DrumInstrumentDefinition) -> some View {
        let isSelected = instrument.midiNoteNumber == selectedInstrument.midiNoteNumber
        return Button {
            selectInstrument(instrument.midiNoteNumber)
            isPresented = false
        } label: {
            VStack(spacing: AppTheme.Spacing.xs) {
                Text(instrument.name)
                    .font(AppTheme.Typography.noteTitle)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(instrument.pitchLabel)
                    .font(AppTheme.Typography.timelineLabel)
                    .foregroundStyle(isSelected ? appColors.primaryText : appColors.secondaryText)
            }
            .frame(
                width: AppTheme.ControlSize.drumInstrumentPadWidth,
                height: AppTheme.ControlSize.drumInstrumentPadHeight
            )
            .background(isSelected ? appColors.controlActive : appColors.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .stroke(isSelected ? appColors.accent : appColors.border, lineWidth: AppTheme.Stroke.thin)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(instrument.name), \(instrument.pitchLabel), MIDI \(instrument.midiNoteNumber)")
        .accessibilityLabel(instrument.name)
        .accessibilityValue("\(instrument.pitchLabel), MIDI \(instrument.midiNoteNumber)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct NotationDurationControl: View {
    @Binding var denominator: Int
    let isEnabled: Bool
    @Environment(\.appColors) private var appColors

    private var options: [NotationDurationOption] {
        NotationDuration.entryDenominators
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

    var body: some View {
        NotationSelectableButton(isActive: isActive, action: action) { iconColor in
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
        }
    }
}

struct NotationAugmentationDotButton: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        NotationSelectableButton(isActive: isActive, action: action) { iconColor in
            NotationAugmentationDotGlyphView(color: iconColor)
                .accessibilityHidden(true)
        }
        .help(Text(NotationAugmentationDotHelpText.tooltip))
        .accessibilityLabel(NotationAugmentationDotHelpText.accessibilityLabel)
        .accessibilityHint(NotationAugmentationDotHelpText.accessibilityHint)
        .accessibilityValue(isActive ? "Enabled" : "Disabled")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

struct NotationTieButton: View {
    let status: NotationTieCommandStatus
    let action: () -> Void

    var body: some View {
        NotationSelectableButton(isActive: false, action: action) { iconColor in
            NotationTieControlGlyphView(color: iconColor)
                .accessibilityHidden(true)
        }
        .disabled(!status.isInCommandScope)
        .help(Text(NotationTieHelpText.tooltip(for: status)))
        .accessibilityLabel(NotationTieHelpText.accessibilityLabel)
        .accessibilityHint(Text(NotationTieHelpText.accessibilityHint(for: status)))
    }
}

private struct NotationSelectableButton<Label: View>: View {
    let isActive: Bool
    let action: () -> Void
    private let label: (Color) -> Label
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appColors) private var appColors

    init(
        isActive: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping (Color) -> Label
    ) {
        self.isActive = isActive
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            label(iconColor)
                .frame(
                    width: AppTheme.ControlSize.notationModeButtonWidth,
                    height: AppTheme.ControlSize.notationDurationControlHeight
                )
                .background(isActive ? appColors.accent : appColors.statusButtonFill)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                        .stroke(isActive ? appColors.accent : appColors.border, lineWidth: AppTheme.Stroke.thin)
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
}

enum NotationAugmentationDotHelpText {
    static let tooltip = [
        "\(AppHotkey.toggleNotationDurationDot.title) (\(AppHotkey.toggleNotationDurationDot.key))",
        AppHotkey.toggleNotationDurationDot.detail
    ].joined(separator: "\n")
    static let accessibilityLabel = AppHotkey.toggleNotationDurationDot.title
    static let accessibilityHint = AppHotkey.toggleNotationDurationDot.detail
}

enum NotationTieHelpText {
    private static let defaultTooltip = [
        "\(AppHotkey.addTiedNotationNote.title) (\(AppHotkey.addTiedNotationNote.key))",
        AppHotkey.addTiedNotationNote.detail
    ].joined(separator: "\n")
    static let accessibilityLabel = AppHotkey.addTiedNotationNote.title

    static func tooltip(for status: NotationTieCommandStatus) -> String {
        guard let blockedExplanation = blockedExplanation(for: status) else {
            return defaultTooltip
        }
        return [defaultTooltip, blockedExplanation].joined(separator: "\n")
    }

    static func accessibilityHint(for status: NotationTieCommandStatus) -> String {
        blockedExplanation(for: status) ?? AppHotkey.addTiedNotationNote.detail
    }

    private static func blockedExplanation(
        for status: NotationTieCommandStatus
    ) -> String? {
        guard case let .blocked(reason) = status else { return nil }
        switch reason {
        case .selectNote:
            return "Select a note to add a tie."
        case .alreadyTied:
            return "The selected note already starts a tie."
        case .audioBoundary:
            return "There is not enough audio time after the selected note."
        }
    }
}

private struct NotationTieControlGlyphView: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let fontSize = AppTheme.ControlSize.notationDurationGlyphSize
            if let notePath = NotationMusicFontRegistry.glyphPath(
                for: NotationDurationControlSymbol.quarter,
                fontSize: fontSize
            ) {
                for direction in [-1.0, 1.0] {
                    let transform = notePath.centeredTransform(in: size)
                        .translatedBy(
                            x: CGFloat(direction) * AppTheme.ControlSize.notationTieNoteOffsetX,
                            y: 0
                        )
                    context.fill(Path(notePath.path).applying(transform), with: .color(color))
                }
            }

            let centerY = size.height / 2 + AppTheme.ControlSize.notationTieArcOffsetY
            let tiePath = NotationTiePath.path(
                start: CGPoint(x: size.width / 2 - AppTheme.ControlSize.notationTieNoteOffsetX, y: centerY),
                end: CGPoint(x: size.width / 2 + AppTheme.ControlSize.notationTieNoteOffsetX, y: centerY),
                placement: .below,
                arcHeight: AppTheme.ControlSize.notationTieArcHeight,
                endpointThickness: AppTheme.ControlSize.notationTieEndpointThickness,
                midpointThickness: AppTheme.ControlSize.notationTieMidpointThickness
            )
            context.fill(Path(tiePath), with: .color(color))
        }
    }
}

private struct NotationAugmentationDotGlyphView: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let fontSize = AppTheme.ControlSize.notationDurationGlyphSize
            if let notePath = NotationMusicFontRegistry.glyphPath(
                for: NotationDurationControlSymbol.quarter,
                fontSize: fontSize
            ) {
                let transform = notePath.centeredTransform(in: size)
                    .translatedBy(
                        x: AppTheme.ControlSize.notationAugmentationDotNoteOffsetX,
                        y: 0
                    )
                context.fill(Path(notePath.path).applying(transform), with: .color(color))
            }

            if let dotPath = NotationMusicFontRegistry.glyphPath(
                for: NotationAugmentationDotSymbol.augmentationDot,
                fontSize: fontSize
            ) {
                let target = CGPoint(
                    x: size.width / 2 + AppTheme.ControlSize.notationAugmentationDotGlyphOffsetX,
                    y: size.height / 2 + AppTheme.ControlSize.notationAugmentationDotGlyphOffsetY
                )
                let anchor = CGPoint(x: dotPath.bounds.midX, y: dotPath.bounds.midY)
                context.fill(
                    Path(dotPath.path).applying(dotPath.anchoredTransform(anchor: anchor, target: target)),
                    with: .color(color)
                )
            }
        }
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
