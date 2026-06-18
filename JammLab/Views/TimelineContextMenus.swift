import AppKit
import SwiftUI

struct NoteContextMenuCaptureView: NSViewRepresentable {
    let note: TimecodedNote
    let onEdit: (TimecodedNote) -> Void
    let onDelete: (TimecodedNote.ID) -> Void
    let onColorChanged: (TimecodedNote.ID, MarkerColor) -> Void
    let onCustomColorChanged: (TimecodedNote.ID, String) -> Void

    func makeNSView(context: Context) -> NoteContextMenuCaptureNSView {
        let view = NoteContextMenuCaptureNSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NoteContextMenuCaptureNSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NoteContextMenuCaptureNSView) {
        view.note = note
        view.onEdit = onEdit
        view.onDelete = onDelete
        view.onColorChanged = onColorChanged
        view.onCustomColorChanged = onCustomColorChanged
    }
}

struct RightClickMenuCaptureView: NSViewRepresentable {
    let title: String
    let action: () -> Void

    func makeNSView(context: Context) -> RightClickMenuCaptureNSView {
        let view = RightClickMenuCaptureNSView()
        view.title = title
        view.action = action
        return view
    }

    func updateNSView(_ nsView: RightClickMenuCaptureNSView, context: Context) {
        nsView.title = title
        nsView.action = action
    }
}

struct RightClickCaptureView: NSViewRepresentable {
    let onAddMarker: (CGPoint) -> Void
    let onAddTempoTimeSignatureMarker: ((CGPoint) -> Void)?

    init(
        _ onAddMarker: @escaping (CGPoint) -> Void,
        onAddTempoTimeSignatureMarker: ((CGPoint) -> Void)? = nil
    ) {
        self.onAddMarker = onAddMarker
        self.onAddTempoTimeSignatureMarker = onAddTempoTimeSignatureMarker
    }

    func makeNSView(context: Context) -> RightClickCaptureNSView {
        let view = RightClickCaptureNSView()
        view.onAddMarker = onAddMarker
        view.onAddTempoTimeSignatureMarker = onAddTempoTimeSignatureMarker
        return view
    }

    func updateNSView(_ nsView: RightClickCaptureNSView, context: Context) {
        nsView.onAddMarker = onAddMarker
        nsView.onAddTempoTimeSignatureMarker = onAddTempoTimeSignatureMarker
    }
}

final class RightClickMenuCaptureNSView: NSView {
    var title = ""
    var action: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        NSApp.currentEvent?.type == .rightMouseDown ? self : nil
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let item = NSMenuItem(title: title, action: #selector(performAction), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func performAction() {
        action?()
    }
}

final class NoteContextMenuCaptureNSView: NSView {
    var note: TimecodedNote?
    var onEdit: ((TimecodedNote) -> Void)?
    var onDelete: ((TimecodedNote.ID) -> Void)?
    var onColorChanged: ((TimecodedNote.ID, MarkerColor) -> Void)?
    var onCustomColorChanged: ((TimecodedNote.ID, String) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        NSApp.currentEvent?.type == .rightMouseDown ? self : nil
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let note else { return }

        let menu = NSMenu()
        addItem(title: "Edit", to: menu) { [weak self] in
            self?.onEdit?(note)
        }

        menu.addItem(.separator())

        let colorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        for preset in NoteColorPreset.presets(for: note) {
            addItem(title: preset.title, to: colorMenu) { [weak self] in
                self?.onColorChanged?(note.id, preset.id)
            }
            colorMenu.items.last?.state = !note.hasCustomColor && note.color == preset.id ? .on : .off
        }

        colorMenu.addItem(.separator())

        addItem(title: "Set Color...", to: colorMenu) { [weak self] in
            guard let self else { return }
            NoteColorPanelPresenter.shared.show(note: note) { hex in
                self.onCustomColorChanged?(note.id, hex)
            }
        }
        colorMenu.items.last?.state = note.hasCustomColor ? .on : .off

        colorItem.submenu = colorMenu
        menu.addItem(colorItem)

        menu.addItem(.separator())

        addItem(title: "Delete", to: menu) { [weak self] in
            self?.onDelete?(note.id)
        }

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func addItem(title: String, to menu: NSMenu, action: @escaping () -> Void) {
        let item = NoteContextMenuActionItem(title: title, action: action)
        menu.addItem(item)
    }
}

private final class NoteContextMenuActionItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(performAction), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func performAction() {
        handler()
    }
}

final class RightClickCaptureNSView: NSView {
    var onAddMarker: ((CGPoint) -> Void)?
    var onAddTempoTimeSignatureMarker: ((CGPoint) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        NSApp.currentEvent?.type == .rightMouseDown ? self : nil
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard onAddTempoTimeSignatureMarker != nil else {
            onAddMarker?(point)
            return
        }

        let menu = NSMenu()
        addItem(title: "Add Marker", to: menu) { [weak self] in
            self?.onAddMarker?(point)
        }
        addItem(title: "Add Tempo / Time Signature Marker", to: menu) { [weak self] in
            self?.onAddTempoTimeSignatureMarker?(point)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func addItem(title: String, to menu: NSMenu, action: @escaping () -> Void) {
        let item = NoteContextMenuActionItem(title: title, action: action)
        menu.addItem(item)
    }
}
