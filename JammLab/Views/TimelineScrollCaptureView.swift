import AppKit
import SwiftUI

struct TimelineScrollEvent {
    let deltaX: Double
    let deltaY: Double
    let locationX: CGFloat
    let width: CGFloat
}

struct TimelineScrollCaptureView: NSViewRepresentable {
    let onScroll: (TimelineScrollEvent) -> Void

    func makeNSView(context: Context) -> TimelineScrollCaptureNSView {
        let view = TimelineScrollCaptureNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: TimelineScrollCaptureNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

final class TimelineScrollCaptureNSView: NSView {
    var onScroll: ((TimelineScrollEvent) -> Void)?
    private var scrollMonitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScrollMonitor()
    }

    deinit {
        removeScrollMonitor()
    }

    private func updateScrollMonitor() {
        removeScrollMonitor()

        guard window != nil else { return }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.capture(event) else {
                return event
            }

            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }

        scrollMonitor = nil
    }

    private func capture(_ event: NSEvent) -> Bool {
        guard
            let window,
            event.window === window,
            bounds.width > 0,
            bounds.height > 0
        else {
            return false
        }

        let localPoint = convert(event.locationInWindow, from: nil)
        guard bounds.contains(localPoint) else { return false }

        onScroll?(
            TimelineScrollEvent(
                deltaX: Double(event.scrollingDeltaX),
                deltaY: Double(event.scrollingDeltaY),
                locationX: localPoint.x,
                width: bounds.width
            )
        )

        return true
    }
}
