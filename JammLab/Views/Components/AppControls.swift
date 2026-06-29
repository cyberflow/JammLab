import AppKit
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

struct CompactValuePicker<Value: Hashable>: NSViewRepresentable {
    let values: [Value]
    let selection: Binding<Value>
    let titleForValue: (Value) -> String
    let accessibilityLabel: String

    func makeNSView(context: Context) -> CompactValuePickerNSView {
        let view = CompactValuePickerNSView()
        view.popupButton.target = context.coordinator
        view.popupButton.action = #selector(Coordinator.selectionChanged(_:))
        return view
    }

    func updateNSView(_ nsView: CompactValuePickerNSView, context: Context) {
        context.coordinator.parent = self
        let titles = values.map(titleForValue)
        let selectedIndex = values.firstIndex(of: selection.wrappedValue) ?? 0
        nsView.configure(
            titles: titles,
            selectedIndex: selectedIndex,
            colors: context.environment.appColors,
            isEnabled: context.environment.isEnabled,
            accessibilityLabel: accessibilityLabel
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject {
        var parent: CompactValuePicker

        init(parent: CompactValuePicker) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard parent.values.indices.contains(sender.indexOfSelectedItem) else { return }
            parent.selection.wrappedValue = parent.values[sender.indexOfSelectedItem]
        }
    }
}

final class CompactValuePickerNSView: NSView {
    let popupButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private var colors = AppThemeColors.default
    private var isControlEnabled = true

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: AppTheme.ControlSize.abletonNumberFieldHeight)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    override func layout() {
        super.layout()
        popupButton.frame = bounds.insetBy(dx: 1, dy: max(0, (bounds.height - AppTheme.ControlSize.abletonNumberFieldHeight) / 2))
        updateLayerStyle()
    }

    func configure(
        titles: [String],
        selectedIndex: Int,
        colors: AppThemeColors,
        isEnabled: Bool,
        accessibilityLabel: String
    ) {
        self.colors = colors
        isControlEnabled = isEnabled
        popupButton.isEnabled = isEnabled
        popupButton.setAccessibilityLabel(accessibilityLabel)

        if popupButton.itemTitles != titles {
            popupButton.removeAllItems()
            popupButton.addItems(withTitles: titles)
        }

        if popupButton.numberOfItems > 0 {
            popupButton.selectItem(at: max(0, min(selectedIndex, popupButton.numberOfItems - 1)))
        }

        popupButton.setAccessibilityValue(popupButton.titleOfSelectedItem)
        updateLayerStyle()
    }

    private func configureView() {
        wantsLayer = true
        popupButton.isBordered = false
        popupButton.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        popupButton.controlSize = .small
        popupButton.translatesAutoresizingMaskIntoConstraints = true
        addSubview(popupButton)
        configureCompactVerticalControlSizing()
    }

    private func updateLayerStyle() {
        layer?.cornerRadius = AppTheme.Radius.small
        layer?.borderWidth = AppTheme.Stroke.thin
        layer?.borderColor = colors.nsColor(for: .border).cgColor
        layer?.backgroundColor = backgroundColor.cgColor
        popupButton.contentTintColor = textColor
    }

    private var backgroundColor: NSColor {
        isControlEnabled
            ? colors.nsColor(for: .controlBackground)
            : colors.nsColor(for: .controlBackground).withAlphaComponent(0.55)
    }

    private var textColor: NSColor {
        isControlEnabled ? colors.nsColor(for: .primaryText) : colors.nsColor(for: .disabledText)
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
