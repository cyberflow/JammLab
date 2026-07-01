import AppKit
import SwiftUI

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
