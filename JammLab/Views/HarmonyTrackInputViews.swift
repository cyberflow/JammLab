import AppKit
import SwiftUI

struct HarmonyInlineTextField: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void
    let onTab: () -> Void

    func makeNSView(context: Context) -> HarmonyInlineNSTextField {
        let textField = HarmonyInlineNSTextField(string: text)
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = true
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.alignment = .left
        textField.font = HarmonyChordLayout.chordFont
        textField.textColor = NSColor.black.withAlphaComponent(0.86)
        textField.delegate = context.coordinator
        textField.onWindowAttached = { [weak coordinator = context.coordinator, weak textField] in
            guard let textField else { return }
            coordinator?.focusAndSelectIfNeeded(textField)
        }
        return textField
    }

    func updateNSView(_ nsView: HarmonyInlineNSTextField, context: Context) {
        context.coordinator.parent = self

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        context.coordinator.focusAndSelectIfNeeded(nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: HarmonyInlineTextField
        private var didAutoSelect = false

        init(parent: HarmonyInlineTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func focusAndSelectIfNeeded(_ textField: NSTextField) {
            guard !didAutoSelect else { return }

            DispatchQueue.main.async { [weak self, weak textField] in
                guard let self, let textField, !self.didAutoSelect else { return }
                guard let window = textField.window else { return }

                window.makeFirstResponder(textField)
                textField.selectText(nil)
                self.didAutoSelect = true
            }
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.text = textView.string
                parent.onCommit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.insertTab(_:)):
                parent.text = textView.string
                parent.onTab()
                return true
            default:
                return false
            }
        }
    }
}

final class HarmonyInlineNSTextField: NSTextField {
    var onWindowAttached: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            onWindowAttached?()
        }
    }
}

struct HarmonyTrackInputCaptureView: NSViewRepresentable {
    let eventFrames: [CGRect]
    let canDeleteSelection: Bool
    let onBackgroundClick: () -> Void
    let onFocusLost: () -> Void
    let onBackgroundDoubleClick: (CGPoint) -> Void
    let onDeleteSelection: () -> Void

    func makeNSView(context: Context) -> HarmonyTrackInputCaptureNSView {
        let view = HarmonyTrackInputCaptureNSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: HarmonyTrackInputCaptureNSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: HarmonyTrackInputCaptureNSView) {
        view.eventFrames = eventFrames
        view.canDeleteSelection = canDeleteSelection
        view.onBackgroundClick = onBackgroundClick
        view.onFocusLost = onFocusLost
        view.onBackgroundDoubleClick = onBackgroundDoubleClick
        view.onDeleteSelection = onDeleteSelection
    }
}

final class HarmonyTrackInputCaptureNSView: NSView {
    var eventFrames: [CGRect] = []
    var canDeleteSelection = false
    var onBackgroundClick: (() -> Void)?
    var onFocusLost: (() -> Void)?
    var onBackgroundDoubleClick: ((CGPoint) -> Void)?
    var onDeleteSelection: (() -> Void)?
    private var mouseMonitor: Any?
    private var keyMonitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMonitors()
    }

    deinit {
        removeMonitors()
    }

    private func updateMonitors() {
        removeMonitors()
        guard window != nil else { return }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            return self.handleMouseDown(event)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
    }

    private func removeMonitors() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        mouseMonitor = nil
        keyMonitor = nil
    }

    private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        guard
            let window,
            event.window === window,
            bounds.width > 0,
            bounds.height > 0
        else {
            return event
        }

        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else {
            onFocusLost?()
            return event
        }

        if eventFrames.contains(where: { $0.contains(point) }) {
            return event
        }

        if event.clickCount == 2 {
            onBackgroundDoubleClick?(point)
            return nil
        }

        onBackgroundClick?()
        return event
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard canDeleteSelection, event.keyCode == 51 || event.keyCode == 117 else {
            return event
        }

        onDeleteSelection?()
        return nil
    }
}
