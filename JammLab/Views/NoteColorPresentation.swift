import AppKit
import SwiftUI

extension MarkerColor {
    var swiftUIColor: Color {
        switch self {
        case .markerDefault, .markerOrange, .markerYellow, .markerBlue, .markerPurple, .regionDefault:
            return Color(nsColor: nsColor)
        case .regionGreen, .regionAmber, .regionBlue, .regionPlum:
            return Color(nsColor: nsColor)
        }
    }

    var nsColor: NSColor {
        NSColor(hexString: defaultHex) ?? .labelColor
    }
}

extension TimecodedNote {
    var resolvedSwiftUIColor: Color {
        if let normalizedCustomColorHex, let customColor = NSColor(hexString: normalizedCustomColorHex) {
            return Color(nsColor: customColor)
        }

        return color.swiftUIColor
    }

    var resolvedNSColor: NSColor {
        if let normalizedCustomColorHex, let customColor = NSColor(hexString: normalizedCustomColorHex) {
            return customColor
        }

        return color.nsColor
    }
}

final class NoteColorPanelPresenter: NSObject {
    static let shared = NoteColorPanelPresenter()

    private var onColorChanged: ((String) -> Void)?

    func show(note: TimecodedNote, onColorChanged: @escaping (String) -> Void) {
        self.onColorChanged = onColorChanged

        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = note.resolvedNSColor
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorDidChange(_ sender: NSColorPanel) {
        guard let hex = sender.color.hexString else { return }
        onColorChanged?(hex)
    }
}
