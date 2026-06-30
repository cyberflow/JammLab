import AppKit
import SwiftUI

struct AppHotkeyMonitorView: NSViewRepresentable {
    let allowedHotkeys: Set<AppHotkey>
    let onHotkey: (AppHotkey) -> Void

    func makeNSView(context: Context) -> AppHotkeyMonitorNSView {
        let view = AppHotkeyMonitorNSView(frame: .zero)
        view.allowedHotkeys = allowedHotkeys
        view.onHotkey = onHotkey
        return view
    }

    func updateNSView(_ nsView: AppHotkeyMonitorNSView, context: Context) {
        nsView.allowedHotkeys = allowedHotkeys
        nsView.onHotkey = onHotkey
        nsView.installIfNeeded()
    }

    static func dismantleNSView(_ nsView: AppHotkeyMonitorNSView, coordinator: ()) {
        nsView.removeMonitor()
    }
}

final class AppHotkeyMonitorNSView: NSView {
    var allowedHotkeys: Set<AppHotkey> = []
    var onHotkey: ((AppHotkey) -> Void)?

    private var monitor: Any?

    deinit {
        removeMonitor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            removeMonitor()
            return
        }

        installIfNeeded()
    }

    func installIfNeeded() {
        guard window != nil else { return }
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard let hotkey = self.hotkey(for: event) else { return event }

            self.onHotkey?(hotkey)
            return nil
        }
    }

    func removeMonitor() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func hotkey(for event: NSEvent) -> AppHotkey? {
        guard let window else { return nil }
        return AppHotkeyEventFilter.hotkey(
            for: event,
            attachedWindowNumber: window.windowNumber,
            firstResponder: window.firstResponder,
            allowedHotkeys: allowedHotkeys
        )
    }
}

enum AppHotkeyEventFilter {
    static func hotkey(
        for event: NSEvent,
        attachedWindowNumber: Int,
        firstResponder: NSResponder?,
        allowedHotkeys: Set<AppHotkey>
    ) -> AppHotkey? {
        guard event.windowNumber == attachedWindowNumber else { return nil }
        guard !event.isARepeat else { return nil }
        guard !(firstResponder is NSTextView) else { return nil }
        guard !(firstResponder is AbletonNumberFieldNSView) else { return nil }
        guard let hotkey = AppHotkey(event: event) else { return nil }
        guard allowedHotkeys.contains(hotkey) else { return nil }
        return hotkey
    }
}
