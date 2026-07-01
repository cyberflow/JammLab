import AppKit
import SwiftUI

struct HarmonyInlineTextField: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void
    let onNavigate: (HarmonyNavigationDirection) -> Void

    func makeNSView(context: Context) -> HarmonyInlineNSTextField {
        let textField = HarmonyInlineNSTextField(string: text)
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .default
        textField.delegate = context.coordinator
        textField.font = .systemFont(ofSize: 13, weight: .semibold)
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
                parent.onNavigate(.next)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                parent.text = textView.string
                parent.onNavigate(.previous)
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
