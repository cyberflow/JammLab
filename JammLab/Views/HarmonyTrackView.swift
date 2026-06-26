import SwiftUI

struct HarmonyTrackView: View {
    let duration: TimeInterval
    let events: [HarmonyEvent]
    let selectedEventID: HarmonyEvent.ID?
    let configuration: BeatGridConfiguration
    let onCreateEvent: (TimeInterval) -> HarmonyEvent.ID?
    let onSelectEvent: (HarmonyEvent.ID?) -> Void
    let onUpdateSymbol: (HarmonyEvent.ID, String) -> Bool
    let onCommitAndCreateNext: (HarmonyEvent.ID, String) -> HarmonyEvent.ID?
    let onMoveEvent: (HarmonyEvent.ID, TimeInterval) -> Void
    let onDeleteEvent: (HarmonyEvent.ID) -> Void

    @State private var editingEventID: HarmonyEvent.ID?
    @State private var editingText = ""
    @State private var dragBaseBeat: Double?
    @State private var hasSelectionFocus = false
    @State private var hoveredEventID: HarmonyEvent.ID?
    @Environment(\.appColors) private var appColors

    var body: some View {
        GeometryReader { proxy in
            let renderItems = renderItems(width: proxy.size.width)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                    .fill(appColors.harmonyTrackBackground)

                HarmonyTrackGridOverlay(
                    tempoMap: configuration.tempoMap,
                    viewport: viewport
                )

                eventMarkers(renderItems, width: proxy.size.width)

                HarmonyTrackInputCaptureView(
                    eventFrames: renderItems.map(\.hitFrame),
                    canDeleteSelection: selectedEventID != nil && editingEventID == nil && hasSelectionFocus,
                    onBackgroundClick: {
                        hasSelectionFocus = true
                        onSelectEvent(nil)
                    },
                    onFocusLost: {
                        hasSelectionFocus = false
                    },
                    onBackgroundDoubleClick: { point in
                        guard duration > 0, proxy.size.width > 0 else { return }
                        hasSelectionFocus = true
                        let time = viewport.time(forX: point.x, width: proxy.size.width)
                        if let id = onCreateEvent(time) {
                            beginEditing(id)
                        }
                    },
                    onDeleteSelection: {
                        guard let selectedEventID else { return }
                        onDeleteEvent(selectedEventID)
                        editingEventID = nil
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
            .opacity(duration > 0 ? 1 : 0.55)
            .accessibilityLabel("Chords Track")
            .help("Double-click to add a chord marker.")
        }
    }

    private func eventMarkers(_ renderItems: [HarmonyChordRenderItem], width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(renderItems) { item in
                eventMarker(item, width: width)
            }
        }
    }

    private func eventMarker(_ item: HarmonyChordRenderItem, width: CGFloat) -> some View {
        let event = item.event
        let layout = item.layout
        let isSelected = selectedEventID == event.id
        let isHovered = hoveredEventID == event.id
        let isEditing = editingEventID == event.id

        return ZStack(alignment: .topLeading) {
            if let labelFrame = item.labelFrame, item.mode == .label {
                ChordSymbolFrame(
                    layout: layout,
                    frameWidth: labelFrame.width,
                    anchorOffsetX: item.anchorX - labelFrame.minX,
                    isSelected: isSelected,
                    isHovered: isHovered,
                    isEditing: isEditing
                ) {
                    if isEditing {
                        HarmonyInlineTextField(
                            text: $editingText,
                            onCommit: { commitEditing(event.id) },
                            onCancel: { cancelEditing() },
                            onTab: { commitAndCreateNext(event.id) }
                        )
                        .frame(
                            width: max(0, labelFrame.width - AppTheme.Timeline.chordSymbolHorizontalInset),
                            height: AppTheme.Timeline.chordSymbolLineHeight
                        )
                        .offset(x: AppTheme.Timeline.chordSymbolHorizontalInset)
                    } else {
                        Text(event.symbol)
                            .font(.system(
                                size: AppTheme.Timeline.chordSymbolFontSize,
                                weight: .semibold,
                                design: .default
                            ))
                            .foregroundStyle(AppTheme.Timeline.chordSymbolText)
                            .lineLimit(1)
                            .opacity(isSelected || isHovered ? AppTheme.Timeline.chordSymbolHoverOpacity : AppTheme.Timeline.chordSymbolNormalOpacity)
                            .frame(
                                width: max(0, labelFrame.width - AppTheme.Timeline.chordSymbolHorizontalInset),
                                height: AppTheme.Timeline.chordSymbolLineHeight,
                                alignment: .leading
                            )
                            .offset(x: AppTheme.Timeline.chordSymbolHorizontalInset)
                    }
                }
                .frame(width: labelFrame.width, height: labelFrame.height)
                .offset(x: labelFrame.minX - item.hitFrame.minX, y: labelFrame.minY - item.hitFrame.minY)
            } else {
                ChordTickView(isSelected: isSelected, isHovered: isHovered)
                    .frame(width: item.tickFrame.width, height: item.tickFrame.height)
                    .offset(x: item.tickFrame.minX - item.hitFrame.minX, y: item.tickFrame.minY - item.hitFrame.minY)
            }
        }
        .frame(width: item.hitFrame.width, height: item.hitFrame.height)
        .contentShape(Rectangle())
        .offset(x: item.hitFrame.minX, y: item.hitFrame.minY)
        .zIndex(zIndex(for: item))
        .cursor(.openHand)
        .onHover { isHovered in
            if isHovered {
                hoveredEventID = event.id
            } else if hoveredEventID == event.id {
                hoveredEventID = nil
            }
        }
        .overlay {
            RightClickMenuCaptureView(title: "Delete Chord", action: {
                onDeleteEvent(event.id)
            })
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    hasSelectionFocus = true
                    onSelectEvent(event.id)
                    beginEditing(event.id)
                }
        )
        .gesture(markerDragGesture(event, width: width))
        .accessibilityLabel("Chord \(event.symbol)")
        .accessibilityValue("Beat \(event.beatKey.value)")
        .help(item.mode == .tick ? event.symbol : "Double-click to edit chord.")
    }

    private func markerDragGesture(_ event: HarmonyEvent, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard duration > 0, width > 0, editingEventID == nil else { return }

                hasSelectionFocus = true
                onSelectEvent(event.id)
                let baseBeat = dragBaseBeat ?? event.startBeat
                dragBaseBeat = baseBeat
                let baseTime = mapper.time(for: baseBeat)
                let delta = TimeInterval(value.translation.width / width) * viewport.visibleDuration
                onMoveEvent(event.id, baseTime + delta)
            }
            .onEnded { _ in
                dragBaseBeat = nil
            }
    }

    private func beginEditing(_ id: HarmonyEvent.ID) {
        guard let event = events.first(where: { $0.id == id }) else { return }
        editingEventID = id
        editingText = event.symbol
        onSelectEvent(id)
    }

    private func commitEditing(_ id: HarmonyEvent.ID) {
        if onUpdateSymbol(id, editingText) {
            editingEventID = nil
        }
    }

    private func commitAndCreateNext(_ id: HarmonyEvent.ID) {
        guard let nextID = onCommitAndCreateNext(id, editingText) else { return }
        editingEventID = nil
        DispatchQueue.main.async {
            beginEditing(nextID)
        }
    }

    private func cancelEditing() {
        editingEventID = nil
    }

    private func renderItems(width: CGFloat) -> [HarmonyChordRenderItem] {
        HarmonyChordCollisionLayout.renderItems(
            events: events,
            tempoMap: configuration.tempoMap,
            viewport: viewport,
            width: width,
            selectedEventID: selectedEventID,
            hoveredEventID: hoveredEventID,
            editingEventID: editingEventID
        )
    }

    private func zIndex(for item: HarmonyChordRenderItem) -> Double {
        if editingEventID == item.id {
            return 4
        }
        if selectedEventID == item.id || hoveredEventID == item.id {
            return 3
        }
        if item.mode == .tick {
            return 2
        }
        if item.mode == .label {
            return 1
        }
        return 0
    }

    private var viewport: TimelineViewport {
        configuration.viewport(duration: duration)
    }

    private var mapper: BeatCoordinateMapper {
        BeatCoordinateMapper(tempoMap: configuration.tempoMap)
    }
}

private struct ChordSymbolFrame<Content: View>: View {
    let layout: HarmonyChordLayout
    let frameWidth: CGFloat
    let anchorOffsetX: CGFloat
    let isSelected: Bool
    let isHovered: Bool
    let isEditing: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            content()
                .offset(y: AppTheme.Timeline.chordSymbolHitVerticalPadding)

            if showsUnderline {
                Rectangle()
                    .fill(AppTheme.Timeline.chordSymbolSelected.opacity(underlineOpacity))
                    .frame(
                        width: underlineWidth,
                        height: AppTheme.Timeline.chordSymbolUnderlineHeight
                    )
                    .offset(
                        x: AppTheme.Timeline.chordSymbolHorizontalInset,
                        y: AppTheme.Timeline.chordSymbolHitVerticalPadding
                            + AppTheme.Timeline.chordSymbolLineHeight
                            - AppTheme.Timeline.chordSymbolUnderlineHeight
                    )
            }

            if showsCaret {
                Rectangle()
                    .fill(AppTheme.Timeline.chordSymbolSelected.opacity(AppTheme.Timeline.chordSymbolCaretOpacity))
                    .frame(
                        width: AppTheme.Timeline.chordSymbolCaretWidth,
                        height: AppTheme.Timeline.chordSymbolCaretHeight
                    )
                    .offset(
                        x: caretOffsetX,
                        y: AppTheme.Timeline.chordSymbolHitVerticalPadding
                            + max(0, (AppTheme.Timeline.chordSymbolLineHeight - AppTheme.Timeline.chordSymbolCaretHeight) / 2)
                    )
            }
        }
    }

    private var showsUnderline: Bool {
        isSelected || isHovered || isEditing
    }

    private var showsCaret: Bool {
        isSelected || isEditing
    }

    private var underlineWidth: CGFloat {
        min(
            layout.textWidth,
            max(0, frameWidth - AppTheme.Timeline.chordSymbolHorizontalInset)
        )
    }

    private var underlineOpacity: Double {
        isSelected || isEditing ? AppTheme.Timeline.chordSymbolUnderlineOpacity : 0.3
    }

    private var caretOffsetX: CGFloat {
        let centered = anchorOffsetX - AppTheme.Timeline.chordSymbolCaretWidth / 2
        return min(max(0, centered), max(0, frameWidth - AppTheme.Timeline.chordSymbolCaretWidth))
    }
}

private struct ChordTickView: View {
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        DiamondShape()
            .fill(color.opacity(opacity))
    }

    private var color: Color {
        isSelected ? AppTheme.Timeline.chordTickSelectedColor : AppTheme.Timeline.chordTickColor
    }

    private var opacity: Double {
        isSelected || isHovered ? AppTheme.Timeline.chordTickHoverOpacity : AppTheme.Timeline.chordTickNormalOpacity
    }
}

private struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private struct HarmonyTrackGridOverlay: View {
    let tempoMap: TempoMap
    let viewport: TimelineViewport

    @Environment(\.appColors) private var appColors

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let markers = TempoGridCalculator().grid(
                    tempoMap: tempoMap,
                    viewport: viewport,
                    width: proxy.size.width,
                    minimumLabelSpacing: AppTheme.Timeline.rulerMinimumLabelSpacing
                ).markers

                for marker in markers {
                    let style = lineStyle(for: marker.kind)
                    var path = Path()
                    path.move(to: CGPoint(x: marker.xPosition, y: 0))
                    path.addLine(to: CGPoint(x: marker.xPosition, y: size.height))
                    context.stroke(path, with: .color(style.color), lineWidth: style.width)
                }
            }
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func lineStyle(for kind: TempoGridMarkerKind) -> (color: Color, width: CGFloat) {
        switch kind {
        case .majorLabeled:
            return (
                appColors.waveformAccentBeatLine.opacity(AppTheme.Timeline.harmonyGridLabeledBarOpacity),
                AppTheme.Stroke.medium
            )
        case .minorBar:
            return (
                appColors.waveformAccentBeatLine.opacity(AppTheme.Timeline.harmonyGridBarOpacity),
                AppTheme.Stroke.thin
            )
        case .beat:
            return (
                appColors.waveformBeatLine.opacity(AppTheme.Timeline.harmonyGridBeatOpacity),
                AppTheme.Stroke.thin
            )
        }
    }
}
