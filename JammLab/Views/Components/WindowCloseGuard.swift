import AppKit
import SwiftUI

struct WindowCloseGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowCloseGuardNSView {
        WindowCloseGuardNSView(frame: .zero)
    }

    func updateNSView(_ nsView: WindowCloseGuardNSView, context: Context) {
        nsView.installIfNeeded()
    }
}

final class WindowCloseGuardNSView: NSView {
    private var closeDelegate: MainWindowCloseDelegate?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installIfNeeded()
    }

    func installIfNeeded() {
        guard let window, closeDelegate == nil else { return }

        let delegate = MainWindowCloseDelegate(previousDelegate: window.delegate)
        closeDelegate = delegate
        window.delegate = delegate
    }
}

final class MainWindowCloseDelegate: NSObject, NSWindowDelegate {
    private weak var previousDelegate: NSWindowDelegate?

    init(previousDelegate: NSWindowDelegate?) {
        self.previousDelegate = previousDelegate
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if previousDelegate?.windowShouldClose?(sender) == false {
            return false
        }

        NSApp.terminate(nil)
        return false
    }
}
