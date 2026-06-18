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
                actions.locatePlaybackMarker(viewport.time(forX: value.location.x, width: width))
            }
            .onEnded { value in
                guard state.duration > 0 else { return }
                actions.locatePlaybackMarker(viewport.time(forX: value.location.x, width: width))
            }
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
