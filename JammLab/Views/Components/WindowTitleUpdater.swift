import AppKit
import SwiftUI

struct WindowTitleUpdater: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> TitleUpdatingNSView {
        let view = TitleUpdatingNSView(frame: .zero)
        view.title = title
        return view
    }

    func updateNSView(_ nsView: TitleUpdatingNSView, context: Context) {
        nsView.title = title
    }
}

final class TitleUpdatingNSView: NSView {
    var title = "" {
        didSet {
            updateTitle()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTitle()
    }

    private func updateTitle() {
        DispatchQueue.main.async {
            self.window?.title = self.title
        }
    }
}

struct WindowMinimumSizeEnforcer: NSViewRepresentable {
    let contentSize: CGSize

    func makeNSView(context: Context) -> MinimumSizeEnforcingNSView {
        let view = MinimumSizeEnforcingNSView(frame: .zero)
        view.contentSize = contentSize
        return view
    }

    func updateNSView(_ nsView: MinimumSizeEnforcingNSView, context: Context) {
        nsView.contentSize = contentSize
    }
}

final class MinimumSizeEnforcingNSView: NSView {
    var contentSize = CGSize.zero {
        didSet {
            updateMinimumSize()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMinimumSize()
    }

    private func updateMinimumSize() {
        DispatchQueue.main.async {
            guard let window = self.window else { return }

            let contentRect = NSRect(origin: .zero, size: self.contentSize)
            let frameSize = window.frameRect(forContentRect: contentRect).size
            window.contentMinSize = self.contentSize
            window.minSize = frameSize

            let currentFrame = window.frame
            let correctedWidth = max(currentFrame.width, frameSize.width)
            let correctedHeight = max(currentFrame.height, frameSize.height)
            let needsCorrection = correctedWidth > currentFrame.width || correctedHeight > currentFrame.height

            guard needsCorrection else { return }

            let correctedFrame = NSRect(
                x: currentFrame.minX,
                y: currentFrame.maxY - correctedHeight,
                width: correctedWidth,
                height: correctedHeight
            )
            window.setFrame(correctedFrame, display: true)
        }
    }
}
