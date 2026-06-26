import AppKit

struct HarmonyChordLayout: Equatable {
    var textWidth: CGFloat
    var hitWidth: CGFloat

    var textFrameWidth: CGFloat {
        max(0, hitWidth - AppTheme.Timeline.chordSymbolHorizontalInset)
    }

    static func layout(symbol: String) -> HarmonyChordLayout {
        let measuredTextWidth = ceil(textWidth(symbol: symbol))
        let paddedHitWidth = measuredTextWidth
            + AppTheme.Timeline.chordSymbolHorizontalInset
            + AppTheme.Timeline.chordSymbolHitHorizontalPadding * 2
        let hitWidth = min(
            AppTheme.Timeline.chordSymbolMaxHitWidth,
            max(AppTheme.Timeline.chordSymbolMinHitWidth, paddedHitWidth)
        )

        return HarmonyChordLayout(textWidth: measuredTextWidth, hitWidth: hitWidth)
    }

    private static func textWidth(symbol: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: chordFont
        ]
        return NSAttributedString(string: symbol, attributes: attributes).size().width
    }

    static var chordFont: NSFont {
        NSFont.systemFont(
            ofSize: AppTheme.Timeline.chordSymbolFontSize,
            weight: .semibold
        )
    }
}

enum HarmonyChordMarkerRenderMode: Equatable {
    case label
    case tick
}

struct HarmonyChordRenderItem: Identifiable, Equatable {
    var event: HarmonyEvent
    var layout: HarmonyChordLayout
    var anchorX: CGFloat
    var labelFrame: CGRect?
    var tickFrame: CGRect
    var hitFrame: CGRect
    var mode: HarmonyChordMarkerRenderMode
    var isBarStart: Bool

    var id: HarmonyEvent.ID {
        event.id
    }
}

enum HarmonyChordCollisionLayout {
    private struct Candidate: Equatable {
        var sourceIndex: Int
        var event: HarmonyEvent
        var layout: HarmonyChordLayout
        var anchorX: CGFloat
        var labelFrame: CGRect?
        var tickFrame: CGRect
        var tickHitFrame: CGRect
        var isBarStart: Bool
    }

    static func renderItems(
        events: [HarmonyEvent],
        tempoMap: TempoMap,
        viewport: TimelineViewport,
        width: CGFloat,
        selectedEventID: HarmonyEvent.ID?,
        hoveredEventID: HarmonyEvent.ID?,
        editingEventID: HarmonyEvent.ID?
    ) -> [HarmonyChordRenderItem] {
        guard width > 0, viewport.visibleDuration > 0 else { return [] }

        let mapper = BeatCoordinateMapper(tempoMap: tempoMap)
        let candidates = events.enumerated().compactMap { index, event -> Candidate? in
            let time = mapper.time(for: event.startBeat)
            guard viewport.contains(time) else { return nil }

            return candidate(
                sourceIndex: index,
                event: event,
                time: time,
                tempoMap: tempoMap,
                viewport: viewport,
                width: width
            )
        }

        var labelIDs = Set<HarmonyEvent.ID>()
        var occupiedFrames: [CGRect] = []

        for candidate in candidates.sorted(by: {
            prioritySort(
                $0,
                $1,
                selectedEventID: selectedEventID,
                hoveredEventID: hoveredEventID,
                editingEventID: editingEventID
            )
        }) {
            guard let labelFrame = candidate.labelFrame else { continue }

            let collisionFrame = collisionFrame(labelFrame)
            guard !occupiedFrames.contains(where: { $0.intersects(collisionFrame) }) else { continue }

            labelIDs.insert(candidate.event.id)
            occupiedFrames.append(collisionFrame)
        }

        return candidates
            .sorted {
                if $0.event.startBeat != $1.event.startBeat {
                    return $0.event.startBeat < $1.event.startBeat
                }
                return $0.sourceIndex < $1.sourceIndex
            }
            .map { candidate in
                let showsLabel = labelIDs.contains(candidate.event.id)
                let mode: HarmonyChordMarkerRenderMode = showsLabel ? .label : .tick
                let hitFrame = hitFrame(
                    labelFrame: showsLabel ? candidate.labelFrame : nil,
                    tickHitFrame: candidate.tickHitFrame
                )

                return HarmonyChordRenderItem(
                    event: candidate.event,
                    layout: candidate.layout,
                    anchorX: candidate.anchorX,
                    labelFrame: showsLabel ? candidate.labelFrame : nil,
                    tickFrame: candidate.tickFrame,
                    hitFrame: hitFrame,
                    mode: mode,
                    isBarStart: candidate.isBarStart
                )
            }
    }

    private static func candidate(
        sourceIndex: Int,
        event: HarmonyEvent,
        time: TimeInterval,
        tempoMap: TempoMap,
        viewport: TimelineViewport,
        width: CGFloat
    ) -> Candidate {
        let layout = HarmonyChordLayout.layout(symbol: event.symbol)
        let anchorX = viewport.xPosition(for: time, width: width)
        let labelFrame = labelFrame(anchorX: anchorX, layout: layout, trackWidth: width)
        let tickFrame = tickFrame(anchorX: anchorX, trackWidth: width)

        return Candidate(
            sourceIndex: sourceIndex,
            event: event,
            layout: layout,
            anchorX: anchorX,
            labelFrame: labelFrame,
            tickFrame: tickFrame,
            tickHitFrame: tickHitFrame(anchorX: anchorX, trackWidth: width),
            isBarStart: isBarStart(time: time, tempoMap: tempoMap)
        )
    }

    private static func prioritySort(
        _ lhs: Candidate,
        _ rhs: Candidate,
        selectedEventID: HarmonyEvent.ID?,
        hoveredEventID: HarmonyEvent.ID?,
        editingEventID: HarmonyEvent.ID?
    ) -> Bool {
        let lhsPriority = priority(
            lhs,
            selectedEventID: selectedEventID,
            hoveredEventID: hoveredEventID,
            editingEventID: editingEventID
        )
        let rhsPriority = priority(
            rhs,
            selectedEventID: selectedEventID,
            hoveredEventID: hoveredEventID,
            editingEventID: editingEventID
        )

        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        if lhs.event.startBeat != rhs.event.startBeat {
            return lhs.event.startBeat < rhs.event.startBeat
        }
        return lhs.event.id.uuidString < rhs.event.id.uuidString
    }

    private static func priority(
        _ candidate: Candidate,
        selectedEventID: HarmonyEvent.ID?,
        hoveredEventID: HarmonyEvent.ID?,
        editingEventID: HarmonyEvent.ID?
    ) -> Int {
        if editingEventID == candidate.event.id {
            return 0
        }
        if selectedEventID == candidate.event.id {
            return 1
        }
        if hoveredEventID == candidate.event.id {
            return 2
        }
        if candidate.isBarStart {
            return 3
        }
        return 4
    }

    private static func labelFrame(
        anchorX: CGFloat,
        layout: HarmonyChordLayout,
        trackWidth: CGFloat
    ) -> CGRect? {
        guard trackWidth >= AppTheme.Timeline.chordSymbolMinHitWidth else { return nil }

        let width = min(layout.hitWidth, trackWidth)
        let x = min(max(anchorX, 0), max(0, trackWidth - width))
        return CGRect(
            x: x,
            y: AppTheme.Timeline.chordSymbolVerticalInset,
            width: width,
            height: AppTheme.Timeline.chordSymbolHitHeight
        )
    }

    private static func tickFrame(anchorX: CGFloat, trackWidth: CGFloat) -> CGRect {
        let tickWidth = min(AppTheme.Timeline.chordTickWidth, trackWidth)
        let x = min(max(anchorX - tickWidth / 2, 0), max(0, trackWidth - tickWidth))
        return CGRect(
            x: x,
            y: AppTheme.Timeline.chordTickTopInset,
            width: tickWidth,
            height: AppTheme.Timeline.chordTickHeight
        )
    }

    private static func tickHitFrame(anchorX: CGFloat, trackWidth: CGFloat) -> CGRect {
        let hitWidth = min(AppTheme.Timeline.chordTickHitWidth, trackWidth)
        let hitHeight = min(AppTheme.Timeline.chordTickHitHeight, AppTheme.Timeline.harmonyTrackHeight)
        let x = min(max(anchorX - hitWidth / 2, 0), max(0, trackWidth - hitWidth))
        let y = max(0, AppTheme.Timeline.chordTickTopInset - (hitHeight - AppTheme.Timeline.chordTickHeight) / 2)

        return CGRect(x: x, y: y, width: hitWidth, height: hitHeight)
    }

    private static func collisionFrame(_ frame: CGRect) -> CGRect {
        frame.insetBy(dx: -AppTheme.Timeline.chordSymbolCollisionGap / 2, dy: 0)
    }

    private static func hitFrame(labelFrame: CGRect?, tickHitFrame: CGRect) -> CGRect {
        guard let labelFrame else { return tickHitFrame }
        return labelFrame.union(tickHitFrame)
    }

    private static func isBarStart(time: TimeInterval, tempoMap: TempoMap) -> Bool {
        var settings = tempoMap.settings(at: time)
        if settings.bpm == nil {
            settings.bpm = AppDefaults.defaultTempoBPM
        }
        guard let beatDuration = settings.beatDuration, beatDuration > 0 else { return false }

        let rawIndex = (time - settings.firstBeatTime) / beatDuration
        let nearestIndex = Int(round(rawIndex))
        let nearestTime = settings.firstBeatTime + Double(nearestIndex) * beatDuration
        let tolerance = max(0.0001, beatDuration * 0.001)
        guard abs(nearestTime - time) <= tolerance else { return false }

        let beatsPerBar = max(1, settings.timeSignature.beatsPerBar)
        return nearestIndex == 0 || nearestIndex % beatsPerBar == 0
    }
}
