import AppKit
import SwiftUI

struct RegionTrackView: View {
    let duration: TimeInterval
    let notes: [TimecodedNote]
    let selectedRegionID: TimecodedNote.ID?
    let configuration: BeatGridConfiguration
    let onSelectRegion: (TimecodedNote.ID) -> Void
    let onActivateRegion: (TimecodedNote.ID) -> Void
    let onFocusRegion: (TimecodedNote.ID) -> Void
    let onEditRegion: (TimecodedNote) -> Void
    let onDeleteRegion: (TimecodedNote.ID) -> Void
    let onRegionColorChanged: (TimecodedNote.ID, MarkerColor) -> Void
    let onRegionCustomColorChanged: (TimecodedNote.ID, String) -> Void
    let onRegionRangeChanged: (TimecodedNote.ID, TimeInterval, TimeInterval) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                    .fill(AppTheme.Timeline.regionTrackBackground)

                regionOverlays(width: proxy.size.width)
                    .allowsHitTesting(false)
                regionInteractionOverlays(width: proxy.size.width)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
        }
    }

    private func regionOverlays(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(notes.filter(\.isRegion)) { region in
                regionBody(region, width: width)
            }
        }
    }

    @ViewBuilder
    private func regionBody(_ region: TimecodedNote, width: CGFloat) -> some View {
        if let visibleRange = viewport.intersection(start: region.time, end: region.regionEndTime) {
            let startX = viewport.xPosition(for: visibleRange.lowerBound, width: width)
            let endX = viewport.xPosition(for: visibleRange.upperBound, width: width)
            let isSelected = selectedRegionID == region.id

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(region.resolvedSwiftUIColor)

                Rectangle()
                    .stroke(isSelected ? AppTheme.Timeline.selectedRegionStroke : AppTheme.Timeline.unselectedRegionStroke, lineWidth: isSelected ? AppTheme.Stroke.thick : AppTheme.Stroke.thin)

                if endX - startX > AppTheme.Timeline.regionLabelMinWidth {
                    Text(region.title)
                        .font(AppTheme.Typography.timelineLabel.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(AppTheme.Timeline.regionLabelText)
                        .lineLimit(1)
                        .padding(.horizontal, AppTheme.Spacing.sm)
                }
            }
            .frame(width: max(endX - startX, AppTheme.Timeline.minOverlayWidth))
            .offset(x: startX)
        }
    }

    private func regionInteractionOverlays(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(notes.filter(\.isRegion)) { region in
                RegionInteractionOverlay(
                    note: region,
                    duration: duration,
                    visibleRange: viewport.clampedRange,
                    width: width,
                    isSelected: selectedRegionID == region.id,
                    allowsBodyDrag: true,
                    onSelect: onSelectRegion,
                    onActivate: onActivateRegion,
                    onFocus: onFocusRegion,
                    onEdit: onEditRegion,
                    onDelete: onDeleteRegion,
                    onColorChanged: onRegionColorChanged,
                    onCustomColorChanged: onRegionCustomColorChanged,
                    onRangeChanged: onRegionRangeChanged
                )
            }
        }
    }

    private var viewport: TimelineViewport {
        configuration.viewport(duration: duration)
    }
}

struct MarkerTrackView: View {
    let duration: TimeInterval
    let notes: [TimecodedNote]
    let configuration: BeatGridConfiguration
    let onEditMarker: (TimecodedNote) -> Void
    let onDeleteMarker: (TimecodedNote.ID) -> Void
    let onMarkerColorChanged: (TimecodedNote.ID, MarkerColor) -> Void
    let onMarkerCustomColorChanged: (TimecodedNote.ID, String) -> Void
    let onMarkerTimeChanged: (TimecodedNote.ID, TimeInterval) -> Void

    @State private var dragBaseTime: TimeInterval?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                    .fill(AppTheme.Timeline.markerTrackBackground)

                markerHeads(width: proxy.size.width)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
        }
    }

    private func markerHeads(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(notes.filter(\.isMarker)) { marker in
                markerHead(marker, width: width)
            }
        }
    }

    private func markerHead(_ marker: TimecodedNote, width: CGFloat) -> some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            RoundedRectangle(cornerRadius: AppTheme.Radius.marker)
                .fill(marker.resolvedSwiftUIColor)
                .frame(width: AppTheme.IconSize.markerCapWidth, height: AppTheme.IconSize.markerCapHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.marker)
                        .stroke(AppTheme.Timeline.markerCapStroke, lineWidth: AppTheme.Stroke.thin)
                )

            if marker.isTempoTimeSignatureMarker {
                Text(marker.title)
                    .font(AppTheme.Typography.timelineLabel.weight(.semibold))
                    .foregroundStyle(marker.resolvedSwiftUIColor)
                    .lineLimit(1)
                    .padding(.horizontal, AppTheme.Spacing.xs)
                    .padding(.vertical, AppTheme.Spacing.xxxs)
                    .background(AppTheme.Timeline.markerTrackBackground.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
            }
        }
            .frame(width: marker.isTempoTimeSignatureMarker ? 150 : AppTheme.Timeline.markerHitWidth, height: AppTheme.Timeline.markerTrackHeight, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(viewport.contains(marker.time) ? 1 : 0)
            .allowsHitTesting(viewport.contains(marker.time))
            .offset(x: viewport.xPosition(for: marker.time, width: width) - AppTheme.Timeline.markerHitWidth / 2)
            .cursor(.openHand)
            .overlay(markerContextMenuCapture(marker))
            .gesture(markerDragGesture(marker, width: width))
    }

    private func markerContextMenuCapture(_ marker: TimecodedNote) -> some View {
        NoteContextMenuCaptureView(
            note: marker,
            onEdit: onEditMarker,
            onDelete: onDeleteMarker,
            onColorChanged: onMarkerColorChanged,
            onCustomColorChanged: onMarkerCustomColorChanged
        )
    }

    private func markerDragGesture(_ marker: TimecodedNote, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard duration > 0, width > 0 else { return }

                let base = dragBaseTime ?? marker.time
                dragBaseTime = base
                let delta = TimeInterval(value.translation.width / width) * viewport.visibleDuration
                onMarkerTimeChanged(marker.id, base + delta)
            }
            .onEnded { _ in
                dragBaseTime = nil
            }
    }

    private var viewport: TimelineViewport {
        configuration.viewport(duration: duration)
    }
}

struct TempoTrackView: View {
    let duration: TimeInterval
    let loopStart: TimeInterval
    let loopEnd: TimeInterval
    let playbackMarkerTime: TimeInterval
    let configuration: BeatGridConfiguration
    let onSaveLoopRegion: () -> Void
    let onLoopStartChanged: (TimeInterval) -> Void
    let onLoopEndChanged: (TimeInterval) -> Void
    let onLoopRegionChanged: (TimeInterval, TimeInterval) -> Void

    @State private var dragBaseStartTime: TimeInterval?
    @State private var dragBaseEndTime: TimeInterval?
    @State private var selectionDragStartTime: TimeInterval?
    @Environment(\.appColors) private var appColors

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                    .fill(appColors.controlBackground.opacity(AppTheme.Timeline.tempoTrackOpacity))
                    .contentShape(Rectangle())
                    .gesture(loopSelectionGesture(width: proxy.size.width))

                loopRegionOverlay(width: proxy.size.width, height: proxy.size.height)
                    .allowsHitTesting(false)

                TempoGridRulerView(
                    settings: configuration.settings,
                    tempoMap: configuration.tempoMap,
                    viewport: viewport,
                    playbackMarkerTime: playbackMarkerTime
                )
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                .allowsHitTesting(false)

                loopRegionContextTarget(width: proxy.size.width)
                loopHandle(.start, width: proxy.size.width)
                loopHandle(.end, width: proxy.size.width)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
            .cursor(.iBeam)
        }
    }

    @ViewBuilder
    private func loopRegionOverlay(width: CGFloat, height: CGFloat) -> some View {
        if let visibleRange = viewport.intersection(start: loopStart, end: loopEnd) {
            let startX = viewport.xPosition(for: visibleRange.lowerBound, width: width)
            let endX = viewport.xPosition(for: visibleRange.upperBound, width: width)

            LoopBracketOverlay()
                .frame(width: max(endX - startX, AppTheme.Timeline.minOverlayWidth))
                .frame(height: height)
                .offset(x: startX)
        }
    }

    @ViewBuilder
    private func loopRegionContextTarget(width: CGFloat) -> some View {
        if let visibleRange = viewport.intersection(start: loopStart, end: loopEnd) {
            let startX = viewport.xPosition(for: visibleRange.lowerBound, width: width)
            let endX = viewport.xPosition(for: visibleRange.upperBound, width: width)

            RightClickMenuCaptureView(title: "Save as Region", action: onSaveLoopRegion)
                .frame(width: max(endX - startX, AppTheme.Timeline.minOverlayWidth))
                .frame(maxHeight: .infinity)
                .offset(x: startX)
        }
    }

    private func loopHandle(_ edge: LoopHandleEdge, width: CGFloat) -> some View {
        let handleWidth: CGFloat = AppTheme.Timeline.loopHandleHitWidth
        let time = edge == .start ? loopStart : loopEnd
        let rawX = viewport.xPosition(for: time, width: width)
        let x = rawX - handleWidth / 2

        return Color.clear
            .frame(width: handleWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .opacity(viewport.contains(time) ? 1 : 0)
            .allowsHitTesting(viewport.contains(time))
            .offset(x: max(0, min(x, max(width - handleWidth, 0))))
            .cursor(.resizeLeftRight)
            .gesture(loopHandleDrag(edge, width: width))
    }

    private func loopHandleDrag(_ edge: LoopHandleEdge, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard duration > 0, width > 0 else { return }

                let delta = TimeInterval(value.translation.width / width) * viewport.visibleDuration

                switch edge {
                case .start:
                    let base = dragBaseStartTime ?? loopStart
                    dragBaseStartTime = base
                    onLoopStartChanged(max(0, min(base + delta, duration)))
                case .end:
                    let base = dragBaseEndTime ?? loopEnd
                    dragBaseEndTime = base
                    onLoopEndChanged(max(0, min(base + delta, duration)))
                }
            }
            .onEnded { _ in
                dragBaseStartTime = nil
                dragBaseEndTime = nil
            }
    }

    private func loopSelectionGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard duration > 0, width > 0 else { return }

                let startTime = selectionDragStartTime ?? viewport.time(forX: value.startLocation.x, width: width)
                let currentTime = viewport.time(forX: value.location.x, width: width)
                selectionDragStartTime = startTime
                onLoopRegionChanged(startTime, currentTime)
            }
            .onEnded { value in
                guard duration > 0, width > 0 else {
                    selectionDragStartTime = nil
                    return
                }

                let startTime = selectionDragStartTime ?? viewport.time(forX: value.startLocation.x, width: width)
                let endTime = viewport.time(forX: value.location.x, width: width)
                onLoopRegionChanged(startTime, endTime)
                selectionDragStartTime = nil
            }
    }

    private var viewport: TimelineViewport {
        configuration.viewport(duration: duration)
    }
}

enum LoopHandleEdge {
    case start
    case end
}

private struct LoopBracketOverlay: View {
    private var color: Color {
        AppTheme.Timeline.loopIndicatorColor.opacity(AppTheme.Timeline.loopBracketOpacity)
    }

    var body: some View {
        Canvas { context, size in
            let color = color
            let bracketHeight = AppTheme.Timeline.loopBracketHeight
            let edgeHeight = AppTheme.Timeline.loopBracketEdgeHeight
            let triangleWidth = AppTheme.Timeline.loopHandleTriangleWidth
            let triangleHeight = AppTheme.Timeline.loopHandleTriangleHeight
            let minX = size.width > 0 ? AppTheme.Stroke.thin / 2 : 0
            let maxX = max(minX, size.width - AppTheme.Stroke.thin / 2)
            let bottomY = size.height
            let bracketY = max(0, bottomY - bracketHeight)
            let edgeTopY = max(0, bottomY - edgeHeight)

            context.fill(
                Path(CGRect(x: 0, y: bracketY, width: size.width, height: bracketHeight)),
                with: .color(color)
            )

            var startEdge = Path()
            startEdge.move(to: CGPoint(x: minX, y: bottomY))
            startEdge.addLine(to: CGPoint(x: minX, y: edgeTopY))
            context.stroke(startEdge, with: .color(color), lineWidth: AppTheme.Stroke.thin)

            var endEdge = Path()
            endEdge.move(to: CGPoint(x: maxX, y: bottomY))
            endEdge.addLine(to: CGPoint(x: maxX, y: edgeTopY))
            context.stroke(endEdge, with: .color(color), lineWidth: AppTheme.Stroke.thin)

            var startTriangle = Path()
            startTriangle.move(to: CGPoint(x: 0, y: bottomY))
            startTriangle.addLine(to: CGPoint(x: 0, y: bottomY - triangleHeight))
            startTriangle.addLine(to: CGPoint(x: triangleWidth, y: bottomY))
            startTriangle.closeSubpath()
            context.fill(startTriangle, with: .color(color))

            var endTriangle = Path()
            endTriangle.move(to: CGPoint(x: size.width, y: bottomY))
            endTriangle.addLine(to: CGPoint(x: size.width, y: bottomY - triangleHeight))
            endTriangle.addLine(to: CGPoint(x: max(0, size.width - triangleWidth), y: bottomY))
            endTriangle.closeSubpath()
            context.fill(endTriangle, with: .color(color))
        }
        .allowsHitTesting(false)
    }
}
