import AppKit
import SwiftUI

struct RenameNoteDialog: View {
    let title: String
    @Binding var text: String
    let onCancel: () -> Void
    let onSave: () -> Void

    @Environment(\.appColors) private var appColors

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.panelPadding) {
            Text(title)
                .font(AppTheme.Typography.sectionTitle)
                .foregroundStyle(appColors.primaryText)

            SelectAllTextField(
                text: $text,
                placeholder: "Name",
                onCommit: onSave,
                onCancel: onCancel
            )
                .frame(height: 26)
                .accessibilityLabel("Name")

            HStack {
                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppTheme.Spacing.panelPadding)
        .frame(width: 340)
        .background(appColors.panelBackground)
    }
}

private struct SelectAllTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> AutoSelectingNSTextField {
        let textField = AutoSelectingNSTextField(string: text)
        textField.placeholderString = placeholder
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .default
        textField.delegate = context.coordinator
        textField.onWindowAttached = { [weak coordinator = context.coordinator, weak textField] in
            guard let textField else { return }
            coordinator?.focusAndSelectIfNeeded(textField)
        }
        return textField
    }

    func updateNSView(_ nsView: AutoSelectingNSTextField, context: Context) {
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
        var parent: SelectAllTextField
        private var didAutoSelect = false

        init(parent: SelectAllTextField) {
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
            default:
                return false
            }
        }
    }
}

private final class AutoSelectingNSTextField: NSTextField {
    var onWindowAttached: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            onWindowAttached?()
        }
    }
}
