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

private extension NSColor {
    convenience init?(hexString: String) {
        guard let normalized = TimecodedNote.normalizedColorHex(hexString) else { return nil }

        let digits = String(normalized.dropFirst())
        guard let value = Int(digits, radix: 16) else { return nil }

        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255

        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    var hexString: String? {
        guard let rgbColor = usingColorSpace(.sRGB) else { return nil }

        let red = Int((rgbColor.redComponent * 255).rounded())
        let green = Int((rgbColor.greenComponent * 255).rounded())
        let blue = Int((rgbColor.blueComponent * 255).rounded())

        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
