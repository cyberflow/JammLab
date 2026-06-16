import AppKit
import SwiftUI

extension WaveformTimelineView {
    func rightClickNoteTarget(width: CGFloat) -> some View {
        RightClickCaptureView { point in
            actions.addNote(viewport.time(forX: point.x, width: width))
        } onAddTempoTimeSignatureMarker: { point in
            actions.addTempoTimeSignatureMarker(viewport.time(forX: point.x, width: width))
        }
    }

    func noteLines(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(state.notes.filter(\.isMarker)) { note in
                noteLine(note, width: width)
            }
        }
    }

    func noteLine(_ note: TimecodedNote, width: CGFloat) -> some View {
        Rectangle()
            .fill(note.resolvedSwiftUIColor.opacity(AppTheme.Timeline.waveformMarkerLineOpacity))
            .frame(width: AppTheme.IconSize.markerLineWidth)
            .frame(maxHeight: .infinity)
        .opacity(viewport.contains(note.time) ? 1 : 0)
            .offset(x: viewport.xPosition(for: note.time, width: width) - AppTheme.IconSize.markerLineWidth / 2)
    }

    func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard state.duration > 0 else { return }
                actions.seek(viewport.time(forX: value.location.x, width: width))
            }
            .onEnded { value in
                guard state.duration > 0 else { return }
                actions.seek(viewport.time(forX: value.location.x, width: width))
            }
    }
}

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

struct CursorModifier: ViewModifier {
    let cursor: NSCursor
    @State private var isActive = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                if isHovering, !isActive {
                    cursor.push()
                    isActive = true
                } else if !isHovering, isActive {
                    NSCursor.pop()
                    isActive = false
                }
            }
            .onDisappear {
                if isActive {
                    NSCursor.pop()
                    isActive = false
                }
            }
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        modifier(CursorModifier(cursor: cursor))
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

struct RegionInteractionOverlay: View {
    let note: TimecodedNote
    let duration: TimeInterval
    let visibleRange: ClosedRange<TimeInterval>
    let width: CGFloat
    let isSelected: Bool
    let allowsBodyDrag: Bool
    let onSelect: (TimecodedNote.ID) -> Void
    let onActivate: (TimecodedNote.ID) -> Void
    let onFocus: (TimecodedNote.ID) -> Void
    let onEdit: (TimecodedNote) -> Void
    let onDelete: (TimecodedNote.ID) -> Void
    let onColorChanged: (TimecodedNote.ID, MarkerColor) -> Void
    let onCustomColorChanged: (TimecodedNote.ID, String) -> Void
    let onRangeChanged: (TimecodedNote.ID, TimeInterval, TimeInterval) -> Void

    @State private var dragBaseRange: LoopRegion?

    var body: some View {
        GeometryReader { proxy in
            if let frame = regionFrame(height: proxy.size.height) {
                ZStack(alignment: .leading) {
                    if allowsBodyDrag {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(bodyDragGesture)
                            .simultaneousGesture(doubleClickGesture)
                            .overlay(noteContextMenuCapture)
                    } else {
                        Color.clear
                            .allowsHitTesting(false)
                    }

                    HStack(spacing: 0) {
                        edgeHandle(.start)
                        Spacer(minLength: 0)
                        edgeHandle(.end)
                    }
                }
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
            }
        }
    }

    private func edgeHandle(_ edge: LoopHandleEdge) -> some View {
        ZStack {
            Color.clear

            Rectangle()
                .fill(note.resolvedSwiftUIColor.opacity(isSelected ? AppTheme.Timeline.selectedRegionFillOpacity : AppTheme.Timeline.unselectedRegionFillOpacity))
                .frame(width: AppTheme.Stroke.thin)
                .frame(maxWidth: .infinity, alignment: edge == .start ? .leading : .trailing)
        }
        .frame(width: AppTheme.Timeline.regionEdgeHitWidth)
        .contentShape(Rectangle())
        .cursor(.resizeLeftRight)
        .gesture(edgeDragGesture(edge))
        .help(edge == .start ? "Drag region start" : "Drag region end")
    }

    private var noteContextMenuCapture: some View {
        NoteContextMenuCaptureView(
            note: note,
            onEdit: onEdit,
            onDelete: onDelete,
            onColorChanged: onColorChanged,
            onCustomColorChanged: onCustomColorChanged
        )
    }

    private var bodyDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                onFocus(note.id)

                guard abs(value.translation.width) > 2 else { return }
                let baseRange = dragBaseRange ?? currentRange
                dragBaseRange = baseRange
                let updatedRange = baseRange.offset(
                    by: timeDelta(for: value.translation.width),
                    trackDuration: duration
                )
                onRangeChanged(note.id, updatedRange.start, updatedRange.end)
            }
            .onEnded { value in
                if abs(value.translation.width) <= 2 {
                    onSelect(note.id)
                }

                dragBaseRange = nil
            }
    }

    private var doubleClickGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                onActivate(note.id)
            }
    }

    private func edgeDragGesture(_ edge: LoopHandleEdge) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                onFocus(note.id)

                let baseRange = dragBaseRange ?? currentRange
                dragBaseRange = baseRange
                let delta = timeDelta(for: value.translation.width)
                let updatedRange: LoopRegion

                switch edge {
                case .start:
                    updatedRange = baseRange.movingStart(to: baseRange.start + delta, trackDuration: duration)
                case .end:
                    updatedRange = baseRange.movingEnd(to: baseRange.end + delta, trackDuration: duration)
                }

                onRangeChanged(note.id, updatedRange.start, updatedRange.end)
            }
            .onEnded { _ in
                dragBaseRange = nil
            }
    }

    private var currentRange: LoopRegion {
        LoopRegion(start: note.time, end: note.regionEndTime).clamped(to: duration)
    }

    private func regionFrame(height: CGFloat) -> CGRect? {
        let range = currentRange
        let viewport = TimelineViewport(duration: duration, visibleRange: visibleRange)
        guard let visibleRange = viewport.intersection(start: range.start, end: range.end) else { return nil }

        let startX = viewport.xPosition(for: visibleRange.lowerBound, width: width)
        let endX = viewport.xPosition(for: visibleRange.upperBound, width: width)
        return CGRect(x: startX, y: 0, width: max(endX - startX, AppTheme.Timeline.regionMinPixelWidth), height: height)
    }

    private func timeDelta(for xDelta: CGFloat) -> TimeInterval {
        let viewport = TimelineViewport(duration: duration, visibleRange: visibleRange)
        guard width > 0 else { return 0 }
        return TimeInterval(xDelta / width) * viewport.visibleDuration
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

private final class NoteColorPanelPresenter: NSObject {
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
