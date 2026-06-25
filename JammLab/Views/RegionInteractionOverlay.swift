import SwiftUI

struct RegionInteractionOverlay: View {
    let note: TimecodedNote
    let duration: TimeInterval
    let visibleRange: ClosedRange<TimeInterval>
    let width: CGFloat
    let isSelected: Bool
    let allowsBodyDrag: Bool
    let onSelect: (TimecodedNote.ID) -> Void
    let onActivateRegionAsLoop: (TimecodedNote.ID) -> Void
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
                onActivateRegionAsLoop(note.id)
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
