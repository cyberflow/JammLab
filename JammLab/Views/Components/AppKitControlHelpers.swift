import AppKit

final class AppKitOutsideClickMonitor {
    private var monitor: Any?

    deinit {
        remove()
    }

    func install(for view: NSView, onOutsideClick: @escaping (NSView) -> Void) {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak view] event in
            guard let view else { return event }
            guard let window = view.window, event.window === window else { return event }

            let location = view.convert(event.locationInWindow, from: nil)
            if !view.bounds.contains(location) {
                onOutsideClick(view)
            }

            return event
        }
    }

    func remove() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}

enum AppKitDragThreshold {
    static func exceedsVerticalThreshold(deltaY: CGFloat, threshold: CGFloat) -> Bool {
        abs(deltaY) >= threshold
    }

    static func exceedsDominantAxisThreshold(deltaX: CGFloat, deltaY: CGFloat, threshold: CGFloat) -> Bool {
        max(abs(deltaX), abs(deltaY)) >= threshold
    }
}

enum NumericControlLogic {
    static func clamp(_ value: Double, minValue: Double, maxValue: Double) -> Double {
        guard value.isFinite else { return minValue }
        return min(maxValue, max(minValue, value))
    }

    static func snapToStep(_ value: Double, minValue: Double, maxValue: Double, step: Double) -> Double {
        let clampedValue = clamp(value, minValue: minValue, maxValue: maxValue)
        let steps = ((clampedValue - minValue) / step).rounded()
        let snappedValue = minValue + steps * step
        return clamp(snappedValue, minValue: minValue, maxValue: maxValue)
    }

    static func format(_ value: Double, precision: Int) -> String {
        String(format: "%.\(precision)f", value)
    }
}

extension NSView {
    func configureCompactVerticalControlSizing() {
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }
}
