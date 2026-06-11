import AppKit
import SwiftUI

struct JammValueSliderConfiguration: Equatable {
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
        sensitivity: Double = AppTheme.JammValueSlider.defaultSensitivity,
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

enum JammValueSliderLogic {
    static func clamp(_ value: Double, configuration: JammValueSliderConfiguration) -> Double {
        guard value.isFinite else { return configuration.minValue }
        return min(configuration.maxValue, max(configuration.minValue, value))
    }

    static func snapToStep(_ value: Double, configuration: JammValueSliderConfiguration) -> Double {
        let clampedValue = clamp(value, configuration: configuration)
        let steps = ((clampedValue - configuration.minValue) / configuration.step).rounded()
        let snappedValue = configuration.minValue + steps * configuration.step
        return clamp(snappedValue, configuration: configuration)
    }

    static func resetValue(configuration: JammValueSliderConfiguration) -> Double {
        snapToStep(configuration.defaultValue, configuration: configuration)
    }

    static func normalizedValue(_ value: Double, configuration: JammValueSliderConfiguration) -> Double {
        let range = configuration.maxValue - configuration.minValue
        guard range > 0 else { return 0 }
        return min(1, max(0, (clamp(value, configuration: configuration) - configuration.minValue) / range))
    }

    static func format(_ value: Double, configuration: JammValueSliderConfiguration) -> String {
        let snappedValue = snapToStep(value, configuration: configuration)
        return String(format: "%.\(configuration.precision)f", snappedValue)
    }

    static func dragValue(
        startValue: Double,
        deltaX: CGFloat,
        deltaY: CGFloat,
        configuration: JammValueSliderConfiguration
    ) -> Double {
        let dominantDelta = abs(deltaX) >= abs(deltaY) ? Double(deltaX) : Double(deltaY)
        let rawValue = startValue + dominantDelta * configuration.sensitivity * configuration.step
        return snapToStep(rawValue, configuration: configuration)
    }
}

struct JammValueSlider: NSViewRepresentable {
    let value: Binding<Double>
    let configuration: JammValueSliderConfiguration
    let fillColor: Color?
    let displayFormatter: ((Double) -> String)?
    let accessibilityLabel: String

    init(
        value: Binding<Double>,
        minValue: Double,
        maxValue: Double,
        defaultValue: Double,
        step: Double,
        sensitivity: Double = AppTheme.JammValueSlider.defaultSensitivity,
        precision: Int,
        fillColor: Color? = nil,
        displayFormatter: ((Double) -> String)? = nil,
        accessibilityLabel: String
    ) {
        self.value = value
        self.configuration = JammValueSliderConfiguration(
            minValue: minValue,
            maxValue: maxValue,
            defaultValue: defaultValue,
            step: step,
            sensitivity: sensitivity,
            precision: precision
        )
        self.fillColor = fillColor
        self.displayFormatter = displayFormatter
        self.accessibilityLabel = accessibilityLabel
    }

    func makeNSView(context: Context) -> JammValueSliderNSView {
        let view = JammValueSliderNSView()
        view.onValueChanged = { [weak coordinator = context.coordinator] newValue in
            coordinator?.setValue(newValue)
        }
        return view
    }

    func updateNSView(_ nsView: JammValueSliderNSView, context: Context) {
        context.coordinator.parent = self
        nsView.onValueChanged = { [weak coordinator = context.coordinator] newValue in
            coordinator?.setValue(newValue)
        }
        nsView.configure(
            value: value.wrappedValue,
            configuration: configuration,
            colors: context.environment.appColors,
            fillColor: fillColor,
            displayFormatter: displayFormatter,
            isEnabled: context.environment.isEnabled,
            accessibilityLabel: accessibilityLabel
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator {
        var parent: JammValueSlider

        init(parent: JammValueSlider) {
            self.parent = parent
        }

        func setValue(_ value: Double) {
            parent.value.wrappedValue = value
        }
    }
}

final class JammValueSliderNSView: NSView {
    var onValueChanged: ((Double) -> Void)?

    private var value: Double = 0
    private var configuration = JammValueSliderConfiguration(
        minValue: 0,
        maxValue: 1,
        defaultValue: 0,
        step: 1,
        precision: 0
    )
    private var colors = AppThemeColors.default
    private var customFillColor: NSColor?
    private var displayFormatter: ((Double) -> String)?
    private var isControlEnabled = true
    private var selected = false
    private var hovered = false
    private var dragStartPoint = CGPoint.zero
    private var dragStartValue: Double = 0
    private var isDraggingValue = false
    private var trackingArea: NSTrackingArea?
    private var outsideClickMonitor: Any?

    override var acceptsFirstResponder: Bool { isControlEnabled }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: AppTheme.ControlSize.jammValueSliderWidth,
            height: AppTheme.ControlSize.jammValueSliderHeight
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayoutPriorities()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayoutPriorities()
    }

    deinit {
        removeOutsideClickMonitor()
    }

    func configure(
        value: Double,
        configuration: JammValueSliderConfiguration,
        colors: AppThemeColors,
        fillColor: Color?,
        displayFormatter: ((Double) -> String)?,
        isEnabled: Bool,
        accessibilityLabel: String
    ) {
        self.configuration = configuration
        self.colors = colors
        customFillColor = fillColor.map { NSColor($0) }
        self.displayFormatter = displayFormatter
        isControlEnabled = isEnabled
        self.value = JammValueSliderLogic.snapToStep(value, configuration: configuration)
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityRole(.slider)

        if !isEnabled, selected {
            window?.makeFirstResponder(nil)
        }

        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let controlHeight = min(bounds.height, AppTheme.ControlSize.jammValueSliderHeight)
        let controlRect = NSRect(
            x: 0.5,
            y: (bounds.height - controlHeight) / 2 + 0.5,
            width: max(0, bounds.width - 1),
            height: max(0, controlHeight - 1)
        )
        let path = NSBezierPath(
            roundedRect: controlRect,
            xRadius: AppTheme.JammValueSlider.cornerRadius,
            yRadius: AppTheme.JammValueSlider.cornerRadius
        )
        backgroundColor.setFill()
        path.fill()

        let fillWidth = floor(controlRect.width * JammValueSliderLogic.normalizedValue(value, configuration: configuration))
        if fillWidth > 0 {
            let fillRect = NSRect(
                x: controlRect.minX,
                y: controlRect.minY,
                width: fillWidth,
                height: controlRect.height
            )
            let fillPath = NSBezierPath(
                roundedRect: fillRect,
                xRadius: AppTheme.JammValueSlider.cornerRadius,
                yRadius: AppTheme.JammValueSlider.cornerRadius
            )
            fillColor.setFill()
            fillPath.fill()
        }

        borderColor.setStroke()
        path.lineWidth = AppTheme.JammValueSlider.borderWidth
        path.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributedText = NSAttributedString(
            string: valueText,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
                .foregroundColor: textColor,
                .paragraphStyle: paragraph
            ]
        )
        let textSize = attributedText.size()
        let textRect = NSRect(
            x: controlRect.minX + AppTheme.JammValueSlider.horizontalPadding,
            y: controlRect.midY - textSize.height / 2,
            width: max(0, controlRect.width - AppTheme.JammValueSlider.horizontalPadding * 2),
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
        guard isControlEnabled else { return }

        window?.makeFirstResponder(self)
        selected = true
        dragStartPoint = event.locationInWindow
        dragStartValue = value
        isDraggingValue = false

        if event.clickCount == 2 {
            setValue(JammValueSliderLogic.resetValue(configuration: configuration))
        }

        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isControlEnabled else { return }

        let deltaX = event.locationInWindow.x - dragStartPoint.x
        let deltaY = event.locationInWindow.y - dragStartPoint.y
        let dominantDistance = max(abs(deltaX), abs(deltaY))
        if !isDraggingValue, dominantDistance < AppTheme.JammValueSlider.dragThreshold {
            return
        }

        isDraggingValue = true
        setValue(JammValueSliderLogic.dragValue(
            startValue: dragStartValue,
            deltaX: deltaX,
            deltaY: deltaY,
            configuration: configuration
        ))
    }

    override func mouseUp(with event: NSEvent) {
        guard isControlEnabled else { return }
        selected = true
        isDraggingValue = false
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isControlEnabled else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 124, 126:
            setValue(value + configuration.step)
        case 123, 125:
            setValue(value - configuration.step)
        default:
            super.keyDown(with: event)
        }
    }

    override func becomeFirstResponder() -> Bool {
        selected = true
        installOutsideClickMonitor()
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        selected = false
        isDraggingValue = false
        removeOutsideClickMonitor()
        needsDisplay = true
        return true
    }

    private var backgroundColor: NSColor {
        guard isControlEnabled else { return colors.nsColor(for: .controlBackground).withAlphaComponent(0.55) }
        if hovered { return colors.nsColor(for: .controlHover) }
        return colors.nsColor(for: .controlBackground)
    }

    private var fillColor: NSColor {
        customFillColor ?? colors.nsColor(for: .valueSliderFill)
    }

    private var borderColor: NSColor {
        guard isControlEnabled else { return colors.nsColor(for: .border).withAlphaComponent(0.45) }
        return selected || isDraggingValue ? colors.nsColor(for: .controlActive) : colors.nsColor(for: .border)
    }

    private var textColor: NSColor {
        isControlEnabled ? colors.nsColor(for: .primaryText) : colors.nsColor(for: .disabledText)
    }

    private var valueText: String {
        displayFormatter?(value) ?? JammValueSliderLogic.format(value, configuration: configuration)
    }

    private func configureLayoutPriorities() {
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }

        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            guard event.window === self.window else { return event }

            let location = self.convert(event.locationInWindow, from: nil)
            if !self.bounds.contains(location) {
                self.window?.makeFirstResponder(nil)
            }

            return event
        }
    }

    private func removeOutsideClickMonitor() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }

    private func setValue(_ newValue: Double) {
        let normalizedValue = JammValueSliderLogic.snapToStep(newValue, configuration: configuration)
        value = normalizedValue
        onValueChanged?(normalizedValue)
        needsDisplay = true
    }
}
