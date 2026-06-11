import AppKit
import SwiftUI

struct AbletonNumberFieldConfiguration: Equatable {
    let minValue: Double
    let maxValue: Double
    let defaultValue: Double
    let step: Double
    let sensitivity: Double
    let precision: Int

    init(
        minValue: Double,
        maxValue: Double,
        defaultValue: Double,
        step: Double,
        sensitivity: Double = AppTheme.AbletonNumberField.defaultSensitivity,
        precision: Int
    ) {
        self.minValue = min(minValue, maxValue)
        self.maxValue = max(minValue, maxValue)
        self.defaultValue = defaultValue
        self.step = step > 0 ? step : 1
        self.sensitivity = sensitivity
        self.precision = max(0, precision)
    }
}

enum AbletonNumberFieldLogic {
    static func clamp(_ value: Double, configuration: AbletonNumberFieldConfiguration) -> Double {
        guard value.isFinite else { return configuration.minValue }
        return min(configuration.maxValue, max(configuration.minValue, value))
    }

    static func snapToStep(_ value: Double, configuration: AbletonNumberFieldConfiguration) -> Double {
        let clampedValue = clamp(value, configuration: configuration)
        let steps = ((clampedValue - configuration.minValue) / configuration.step).rounded()
        let snapped = configuration.minValue + steps * configuration.step
        return clamp(snapped, configuration: configuration)
    }

    static func resetValue(configuration: AbletonNumberFieldConfiguration) -> Double {
        snapToStep(configuration.defaultValue, configuration: configuration)
    }

    static func format(_ value: Double, configuration: AbletonNumberFieldConfiguration) -> String {
        let snappedValue = snapToStep(value, configuration: configuration)
        return String(format: "%.\(configuration.precision)f", snappedValue)
    }

    static func parse(_ text: String, configuration: AbletonNumberFieldConfiguration) -> Double? {
        let normalizedText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard !normalizedText.isEmpty else { return nil }
        guard configuration.minValue < 0 || !normalizedText.contains("-") else { return nil }
        guard let value = Double(normalizedText), value.isFinite else { return nil }
        return snapToStep(value, configuration: configuration)
    }
}

struct AbletonNumberField: NSViewRepresentable {
    let value: Binding<Double>
    let configuration: AbletonNumberFieldConfiguration
    let accessibilityLabel: String

    init(
        value: Binding<Double>,
        minValue: Double,
        maxValue: Double,
        defaultValue: Double,
        step: Double,
        sensitivity: Double = AppTheme.AbletonNumberField.defaultSensitivity,
        precision: Int,
        accessibilityLabel: String
    ) {
        self.value = value
        self.configuration = AbletonNumberFieldConfiguration(
            minValue: minValue,
            maxValue: maxValue,
            defaultValue: defaultValue,
            step: step,
            sensitivity: sensitivity,
            precision: precision
        )
        self.accessibilityLabel = accessibilityLabel
    }

    func makeNSView(context: Context) -> AbletonNumberFieldNSView {
        let view = AbletonNumberFieldNSView()
        view.onValueChanged = { [weak coordinator = context.coordinator] newValue in
            coordinator?.setValue(newValue)
        }
        return view
    }

    func updateNSView(_ nsView: AbletonNumberFieldNSView, context: Context) {
        context.coordinator.parent = self
        nsView.onValueChanged = { [weak coordinator = context.coordinator] newValue in
            coordinator?.setValue(newValue)
        }
        nsView.configure(
            value: value.wrappedValue,
            configuration: configuration,
            colors: context.environment.appColors,
            isEnabled: context.environment.isEnabled,
            accessibilityLabel: accessibilityLabel
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator {
        var parent: AbletonNumberField

        init(parent: AbletonNumberField) {
            self.parent = parent
        }

        func setValue(_ value: Double) {
            parent.value.wrappedValue = value
        }
    }
}

final class AbletonNumberFieldNSView: NSView {
    var onValueChanged: ((Double) -> Void)?

    private var value: Double = 0
    private var configuration = AbletonNumberFieldConfiguration(
        minValue: 0,
        maxValue: 1,
        defaultValue: 0,
        step: 1,
        precision: 0
    )
    private var colors = AppThemeColors.default
    private var isFieldEnabled = true
    private var displayText = ""
    private var inputBuffer: String?
    private var valueBeforeEditing: Double = 0
    private var selected = false
    private var hovered = false
    private var dragStartPoint = CGPoint.zero
    private var dragStartValue: Double = 0
    private var isDraggingValue = false
    private var trackingArea: NSTrackingArea?
    private let outsideClickMonitor = AppKitOutsideClickMonitor()

    override var acceptsFirstResponder: Bool { isFieldEnabled }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: AppTheme.ControlSize.abletonNumberFieldHeight)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureCompactVerticalControlSizing()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureCompactVerticalControlSizing()
    }

    deinit {
        outsideClickMonitor.remove()
    }

    func configure(
        value: Double,
        configuration: AbletonNumberFieldConfiguration,
        colors: AppThemeColors,
        isEnabled: Bool,
        accessibilityLabel: String
    ) {
        self.configuration = configuration
        self.colors = colors
        isFieldEnabled = isEnabled
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityRole(.textField)

        if !isEditing {
            self.value = AbletonNumberFieldLogic.snapToStep(value, configuration: configuration)
            displayText = AbletonNumberFieldLogic.format(value, configuration: configuration)
        }

        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let controlHeight = min(bounds.height, AppTheme.ControlSize.abletonNumberFieldHeight)
        let controlRect = NSRect(
            x: 0.5,
            y: (bounds.height - controlHeight) / 2 + 0.5,
            width: max(0, bounds.width - 1),
            height: max(0, controlHeight - 1)
        )
        let path = NSBezierPath(
            roundedRect: controlRect,
            xRadius: AppTheme.AbletonNumberField.cornerRadius,
            yRadius: AppTheme.AbletonNumberField.cornerRadius
        )
        backgroundColor.setFill()
        path.fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        let attributedText = NSAttributedString(string: displayText, attributes: attributes)
        let textSize = attributedText.size()
        let textRect = NSRect(
            x: controlRect.minX + AppTheme.AbletonNumberField.horizontalPadding,
            y: controlRect.midY - textSize.height / 2,
            width: max(0, controlRect.width - AppTheme.AbletonNumberField.horizontalPadding * 2),
            height: textSize.height
        )
        attributedText.draw(in: textRect)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isFieldEnabled else { return }

        window?.makeFirstResponder(self)
        selected = true
        inputBuffer = nil
        valueBeforeEditing = value
        dragStartPoint = event.locationInWindow
        dragStartValue = value
        isDraggingValue = false

        if event.clickCount == 2 {
            setValue(AbletonNumberFieldLogic.resetValue(configuration: configuration))
        }

        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isFieldEnabled else { return }

        let deltaY = event.locationInWindow.y - dragStartPoint.y
        if !isDraggingValue, !AppKitDragThreshold.exceedsVerticalThreshold(
            deltaY: deltaY,
            threshold: AppTheme.AbletonNumberField.dragThreshold
        ) {
            return
        }

        isDraggingValue = true
        inputBuffer = nil
        let rawValue = dragStartValue + deltaY * configuration.sensitivity * configuration.step
        setValue(AbletonNumberFieldLogic.snapToStep(rawValue, configuration: configuration))
    }

    override func mouseUp(with event: NSEvent) {
        guard isFieldEnabled else { return }
        selected = true
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isFieldEnabled else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 36, 76:
            commitInput()
            window?.makeFirstResponder(nil)
        case 53:
            cancelInput()
        case 51, 117:
            beginInputIfNeeded()
            inputBuffer = String((inputBuffer ?? "").dropLast())
            displayText = inputBuffer ?? ""
            needsDisplay = true
        default:
            guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return }
            handleInputCharacters(characters)
        }
    }

    override func becomeFirstResponder() -> Bool {
        selected = true
        installOutsideClickMonitor()
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        commitInput()
        selected = false
        outsideClickMonitor.remove()
        needsDisplay = true
        return true
    }

    private var isEditing: Bool {
        inputBuffer != nil
    }

    private func installOutsideClickMonitor() {
        outsideClickMonitor.install(for: self) { view in
            view.window?.makeFirstResponder(nil)
        }
    }

    private var backgroundColor: NSColor {
        guard isFieldEnabled else { return colors.nsColor(for: .controlBackground).withAlphaComponent(0.55) }
        if selected { return colors.nsColor(for: .controlActive) }
        if hovered { return colors.nsColor(for: .controlHover) }
        return colors.nsColor(for: .controlBackground)
    }

    private var textColor: NSColor {
        isFieldEnabled ? colors.nsColor(for: .primaryText) : colors.nsColor(for: .disabledText)
    }

    private func beginInputIfNeeded() {
        if inputBuffer == nil {
            valueBeforeEditing = value
            inputBuffer = ""
        }
    }

    private func handleInputCharacters(_ characters: String) {
        for character in characters {
            guard isAllowedInputCharacter(character) else { continue }
            beginInputIfNeeded()
            inputBuffer?.append(character)
        }

        displayText = inputBuffer ?? displayText
        needsDisplay = true
    }

    private func isAllowedInputCharacter(_ character: Character) -> Bool {
        if character.isNumber { return true }
        if configuration.precision > 0, character == "." || character == "," {
            return !(inputBuffer ?? "").contains(".") && !(inputBuffer ?? "").contains(",")
        }
        if configuration.minValue < 0, character == "-" {
            return (inputBuffer ?? "").isEmpty
        }
        return false
    }

    private func commitInput() {
        guard let inputBuffer else { return }

        // Invalid input rolls back to the last valid value. This matches the
        // app's existing tempo flow, which restores valid state instead of
        // accepting partial or malformed numeric text.
        if let parsedValue = AbletonNumberFieldLogic.parse(inputBuffer, configuration: configuration) {
            setValue(parsedValue)
        } else {
            setValue(valueBeforeEditing)
        }

        self.inputBuffer = nil
        displayText = AbletonNumberFieldLogic.format(value, configuration: configuration)
        needsDisplay = true
    }

    private func cancelInput() {
        inputBuffer = nil
        setValue(valueBeforeEditing)
        displayText = AbletonNumberFieldLogic.format(value, configuration: configuration)
        needsDisplay = true
    }

    private func setValue(_ newValue: Double) {
        let normalizedValue = AbletonNumberFieldLogic.snapToStep(newValue, configuration: configuration)
        value = normalizedValue
        displayText = AbletonNumberFieldLogic.format(normalizedValue, configuration: configuration)
        onValueChanged?(normalizedValue)
        needsDisplay = true
    }
}
